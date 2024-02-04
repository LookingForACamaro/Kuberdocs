-module(rabbit_xml_interceptor).

-include_lib("rabbit_common/include/rabbit.hrl").
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
    create_ets_table(),
    fill_ets_table(),
    rabbit_channel:get_vhost(Ch).

description() ->
    [{description, <<"xml interceptor for channel methods">>}].

intercept(#'basic.publish'{} = Method, Content, _VHost) ->
    case validate(Content) of
        ok -> {Method, Content};
        _ -> drop
    end;

intercept(Method, Content, _VHost) ->
    {Method, Content}.

applies_to() ->
    ['basic.publish'].

%%----------------------------------------------------------------------------
create_ets_table() ->
    ets:new(xsds, [set,protected,named_table]).

fill_ets_table() ->
    % TODO
    ok.

validate(#content{ properties = #'P_basic'{ headers = Headers}, payload_fragments_rev = Payload } = _Content) ->
    logger:error("INTERCEPTED: ~p ~p", [Headers, Payload]),
    case get_schema_from_headers(Headers, Payload) of
        false -> false;
        Schema ->
            case validate_payload_structure(Payload) of
                false -> false;
                XmlElement -> validate_payload_against_schema(XmlElement, Schema)
            end
    end.

get_schema_from_headers(Headers, _Payload) ->
    SoughtHeaders = lists:filter(fun({HeaderName, _Type, _Protocol}) -> HeaderName =:= <<"RLX_HEADER">> end, Headers),
    case SoughtHeaders of
        [Header] ->
            case do_get_schema(Header) of
                false -> false;
                _Schema -> ok
            end;
        _ -> false
    end.

do_get_schema({_HeaderName, _Type, Protocol}) ->
    case ets:lookup(xsds, Protocol) of
        [] -> false;
        Schema -> Schema
    end.

validate_payload_structure(Payload) ->
    try xmerl_scan:string(binary_to_list(lists:nth(1, Payload))) of
        XmlElement -> XmlElement
    catch
        _ -> false
    end.

validate_payload_against_schema(XmlElement, XsdSchema) ->
    case xmerl_xsd:validate(XmlElement, XsdSchema) of
        {error, _} -> false;
        {_ValidElement, _} -> ok
    end.

