%% This Source Code Form is subject to the terms of the Mozilla Public
%% License, v. 2.0. If a copy of the MPL was not distributed with this
%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%
%% Copyright (c) 2007-2024 Broadcom. All Rights Reserved. The term “Broadcom” refers to Broadcom Inc. and/or its subsidiaries. All rights reserved.
%%

-module(rabbit_xml_interceptor).

-include_lib("rabbit_common/include/rabbit_framing.hrl").

-behaviour(rabbit_channel_interceptor).

-export([description/0, intercept/3, applies_to/0, init/1]).

-rabbit_boot_step({?MODULE,
                   [{description, "xml interceptor"},
                    {mfa, {rabbit_registry, register,
                           [channel_interceptor,
                            <<"xml interceptor">>, ?MODULE]}},
                    {cleanup, {rabbit_registry, unregister,
                               [channel_interceptor,
                                <<"xml interceptor">>]}},
                    {requires, rabbit_registry},
                    {enables, recovery}]}).

init(Ch) ->
    rabbit_channel:get_vhost(Ch).

description() ->
    [{description, <<"xml interceptor for channel methods">>}].

intercept(#'basic.publish'{} = Method, Content, _VHost) ->
    logger:error("INTERCEPTED: ~p", [Content]),
    {Method, Content};

intercept(Method, Content, _VHost) ->
    {Method, Content}.

applies_to() ->
    ['basic.consume', 'basic.get', 'queue.delete', 'queue.declare',
     'queue.bind', 'queue.unbind', 'queue.purge'].

%%----------------------------------------------------------------------------
