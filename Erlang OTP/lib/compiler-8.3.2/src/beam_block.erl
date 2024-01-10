%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 1999-2022. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%
%% Purpose: Partition BEAM instructions into basic blocks.

-module(beam_block).

-include("beam_asm.hrl").

-export([module/2]).
-import(lists, [keysort/2,member/2,reverse/1,reverse/2,
                splitwith/2,usort/1]).

-spec module(beam_utils:module_code(), [compile:option()]) ->
                    {'ok',beam_utils:module_code()}.

module({Mod,Exp,Attr,Fs0,Lc}, _Opts) ->
    Fs = [function(F) || F <- Fs0],
    {ok,{Mod,Exp,Attr,Fs,Lc}}.

function({function,Name,Arity,CLabel,Is0}) ->
    try
        Is1 = swap_opt(Is0),
        Is2 = blockify(Is1),
        Is3 = embed_lines(Is2),
        Is = opt_maps(Is3),
        {function,Name,Arity,CLabel,Is}
    catch
        Class:Error:Stack ->
	    io:fwrite("Function: ~w/~w\n", [Name,Arity]),
	    erlang:raise(Class, Error, Stack)
    end.

%%%
%%% Try to use a `swap` instruction instead of a sequence of moves.
%%%
%%% Note that beam_ssa_codegen generates `swap` instructions only for
%%% the moves within a single SSA instruction (such as `call`), not
%%% for the moves generated by a sequence of SSA instructions.
%%% Therefore, this optimization is needed.
%%%
%%% We'll need to handle non-consecutive sequences of moves, such
%%% as the following instruction sequence:
%%%
%%%     move y2, x2
%%%     move x0, y2
%%%     move y1, x1
%%%     init_yregs [y1]
%%%     move x2, x0
%%%
%%% The first two `move` instructions and the last `move` instruction
%%% should be combined to a `swap` instruction:
%%%
%%%     swap y2, x0
%%%     move y1, x1
%%%     init_yregs [y1]
%%%
%%% (Provided that x2 is killed in the code that follows.)
%%%

swap_opt([{move,Src,Dst},{swap,Dst,Other}|Is]) when Src =/= Other ->
    swap_opt([{move,Other,Dst},{move,Src,Other}|Is]);
swap_opt([{move,Src,Dst},{swap,Other,Dst}|Is]) when Src =/= Other ->
    swap_opt([{move,Other,Dst},{move,Src,Other}|Is]);
swap_opt([{move,Reg1,{x,_}=Temp}=Move1,
          {move,Reg2,Reg1}=Move2|Is0]) when Reg1 =/= Temp ->
    case swap_opt_end(Is0, Temp, Reg2, []) of
        {yes,Is} ->
            [{swap,Reg1,Reg2}|swap_opt(Is)];
        no ->
            [Move1|swap_opt([Move2|Is0])]
    end;
swap_opt([I|Is]) ->
    [I|swap_opt(Is)];
swap_opt([]) -> [].

swap_opt_end([{move,S,D}=I|Is], Temp, Dst, Acc) ->
    case {S,D} of
        {Temp,Dst} ->
            {x,X} = Temp,
            case is_unused(X, Is) of
                true -> {yes,reverse(Acc, Is)};
                false -> no
            end;
        {Temp,_} -> no;
        {Dst,_} -> no;
        {_,Temp} -> no;
        {_,Dst} -> no;
        {_,_} -> swap_opt_end(Is, Temp, Dst, [I|Acc])
    end;
swap_opt_end([{init_yregs,_}=I|Is], Temp, Dst, Acc) ->
    swap_opt_end(Is, Temp, Dst, [I|Acc]);
swap_opt_end(_, _, _, _) -> no.

is_unused(X, [{call,A,_}|_]) when A =< X -> true;
is_unused(X, [{call_ext,A,_}|_]) when A =< X -> true;
is_unused(X, [{make_fun2,_,_,_,A}|_]) when A =< X -> true;
is_unused(X, [{move,Src,Dst}|Is]) ->
    case {Src,Dst} of
        {{x,X},_} -> false;
        {_,{x,X}} -> true;
        {_,_} -> is_unused(X, Is)
    end;
is_unused(X, [{line,_}|Is]) -> is_unused(X, Is);
is_unused(_, _) -> false.

%% blockify(Instructions0) -> Instructions
%%  Collect sequences of instructions to basic blocks.
%%  Also do some simple optimations on instructions outside the blocks.

blockify(Is) ->
    blockify(Is, []).

blockify([I|Is0]=IsAll, Acc) ->
    case collect(I) of
	error -> blockify(Is0, [I|Acc]);
	Instr when is_tuple(Instr) ->
            {Block0,Is} = collect_block(IsAll),
            Block = sort_moves(Block0),
	    blockify(Is, [{block,Block}|Acc])
    end;
blockify([], Acc) -> reverse(Acc).

collect_block(Is) ->
    collect_block(Is, []).

collect_block([{allocate,N,R}|Is0], Acc) ->
    {Inits,Is} = splitwith(fun ({init,{y,_}}) -> true;
                               (_) -> false
                           end, Is0),
    collect_block(Is, [{set,[],[],{alloc,R,{nozero,N,0,Inits}}}|Acc]);
collect_block([I|Is]=Is0, Acc) ->
    case collect(I) of
	error -> {reverse(Acc),Is0};
	Instr -> collect_block(Is, [Instr|Acc])
    end;
collect_block([], Acc) ->
    {reverse(Acc),[]}.

collect({allocate,N,R})      -> {set,[],[],{alloc,R,{nozero,N,0,[]}}};
collect({allocate_heap,Ns,Nh,R}) -> {set,[],[],{alloc,R,{nozero,Ns,Nh,[]}}};
collect({test_heap,N,R})     -> {set,[],[],{alloc,R,{nozero,nostack,N,[]}}};
collect({bif,N,{f,0},As,D})  -> {set,[D],As,{bif,N,{f,0}}};
collect({gc_bif,N,{f,0},R,As,D}) ->   {set,[D],As,{alloc,R,{gc_bif,N,{f,0}}}};
collect({move,S,D})          -> {set,[D],[S],move};
collect({put_list,S1,S2,D})  -> {set,[D],[S1,S2],put_list};
collect({put_tuple2,D,{list,Els}}) -> {set,[D],Els,put_tuple2};
collect({get_tuple_element,S,I,D}) -> {set,[D],[S],{get_tuple_element,I}};
collect({set_tuple_element,S,D,I}) -> {set,[],[S,D],{set_tuple_element,I}};
collect({get_hd,S,D})  ->       {set,[D],[S],get_hd};
collect({get_tl,S,D})  ->       {set,[D],[S],get_tl};
collect(remove_message)      -> {set,[],[],remove_message};
collect({put_map,{f,0},Op,S,D,R,{list,Puts}}) ->
    {set,[D],[S|Puts],{alloc,R,{put_map,Op,{f,0}}}};
collect({fmove,S,D})         -> {set,[D],[S],fmove};
collect({fconv,S,D})         -> {set,[D],[S],fconv};
collect(_)                   -> error.

%% embed_lines([Instruction]) -> [Instruction]
%%  Combine blocks that would be split by line/1 instructions.
%%  Also move a line instruction before a block into the block,
%%  but leave the line/1 instruction after a block outside.

embed_lines(Is) ->
    embed_lines(reverse(Is), []).

embed_lines([{block,B2},{line,_}=Line,{block,B1}|T], Acc) ->
    B = {block,B1++[{set,[],[],Line}]++B2},
    embed_lines([B|T], Acc);
embed_lines([{block,B1},{line,_}=Line|T], Acc) ->
    B = {block,[{set,[],[],Line}|B1]},
    embed_lines([B|T], Acc);
embed_lines([I|Is], Acc) ->
    embed_lines(Is, [I|Acc]);
embed_lines([], Acc) -> Acc.

%% sort_moves([Instruction]) -> [Instruction].
%%  Sort move instructions on the Y register to give the loader
%%  more opportunities for combining instructions.

sort_moves([{set,[{x,_}],[{y,_}],move}=I|Is0]) ->
    {Moves,Is} = sort_moves_1(Is0, x, y, [I]),
    Moves ++ sort_moves(Is);
sort_moves([{set,[{y,_}],[{x,_}],move}=I|Is0]) ->
    {Moves,Is} = sort_moves_1(Is0, y, x, [I]),
    Moves ++ sort_moves(Is);
sort_moves([I|Is]) ->
    [I|sort_moves(Is)];
sort_moves([]) -> [].

sort_moves_1([{set,[{x,0}],[_],move}=I|Is], _DTag, _STag, Acc) ->
    %% The loader sometimes combines a move to x0 with the
    %% instruction that follows, producing, for example, a move_call
    %% instruction. Therefore, we don't want include this move
    %% instruction in the sorting.
    {sort_on_yreg(Acc)++[I],Is};
sort_moves_1([{set,[{DTag,_}],[{STag,_}],move}=I|Is], DTag, STag, Acc) ->
    sort_moves_1(Is, DTag, STag, [I|Acc]);
sort_moves_1(Is, _DTag, _STag, Acc) ->
    {sort_on_yreg(Acc),Is}.

sort_on_yreg([{set,[Dst],[Src],move}|_]=Moves) ->
    case {Dst,Src} of
        {{y,_},{x,_}} ->
            keysort(2, Moves);
        {{x,_},{y,_}} ->
            keysort(3, Moves)
    end.

%%%
%%% Coalesce adjacent get_map_elements and has_map_fields instructions.
%%%

opt_maps(Is) ->
    opt_maps(Is, []).

opt_maps([{get_map_elements,Fail,Src,List}=I|Is], Acc0) ->
    case simplify_get_map_elements(Fail, Src, List, Acc0) of
        {ok,Acc} ->
            opt_maps(Is, Acc);
        error ->
            opt_maps(Is, [I|Acc0])
    end;
opt_maps([{test,has_map_fields,Fail,Ops}=I|Is], Acc0) ->
    case simplify_has_map_fields(Fail, Ops, Acc0) of
        {ok,Acc} ->
            opt_maps(Is, Acc);
        error ->
            opt_maps(Is, [I|Acc0])
    end;
opt_maps([I|Is], Acc) ->
    opt_maps(Is, [I|Acc]);
opt_maps([], Acc) -> reverse(Acc).

simplify_get_map_elements(Fail, Src, {list,[Key,Dst]},
                          [{get_map_elements,Fail,Src,{list,List1}}|Acc]) ->
    case are_keys_literals([Key]) andalso are_keys_literals(List1) andalso
        not is_reg_overwritten(Src, List1) andalso
        not is_reg_overwritten(Dst, List1) of
        true ->
            case member(Key, List1) of
                true ->
                    %% The key is already in the other list. That is
                    %% very unusual, because there are optimizations to get
                    %% rid of duplicate keys. Therefore, don't try to
                    %% do anything smart here; just keep the
                    %% get_map_elements instructions separate.
                    error;
                false ->
                    List = [Key,Dst|List1],
                    {ok,[{get_map_elements,Fail,Src,{list,List}}|Acc]}
            end;
        false ->
            %% A destination is used more than once. That should only
            %% happen if some optimizations are disabled, so we
            %% will not attempt do anything smart here.
            error
    end;
simplify_get_map_elements(_, _, _, _) -> error.

simplify_has_map_fields(Fail, [Src|Keys0],
                        [{test,has_map_fields,Fail,[Src|Keys1]}|Acc]) ->
    case are_keys_literals(Keys0) andalso are_keys_literals(Keys1) of
        true ->
            Keys = usort(Keys0 ++ Keys1),
            {ok,[{test,has_map_fields,Fail,[Src|Keys]}|Acc]};
        false ->
            error
    end;
simplify_has_map_fields(_, _, _) -> error.

are_keys_literals([#tr{}|_]) -> false;
are_keys_literals([{x,_}|_]) -> false;
are_keys_literals([{y,_}|_]) -> false;
are_keys_literals([_|_]) -> true.

is_reg_overwritten(Src, [_Key,Src|_]) ->
    true;
is_reg_overwritten(Src, [_Key,_Src|T]) ->
    is_reg_overwritten(Src, T);
is_reg_overwritten(_, []) ->
    false.
