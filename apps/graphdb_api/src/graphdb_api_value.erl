%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: Codec between graphdb's AVP term() values and the
%%              common.proto Value/AVP/AVPUpdate wire messages (design
%%              §2.2). Also converts the Node/Relationship kind atoms
%%              to/from their proto enum integers.
%%
%%              Encoding rule: binaries and printable-unicode lists are
%%              `str`; integers are `i`; floats are `d`; booleans are
%%              `b`; `undefined` is `null_value`; everything else
%%              (opaque terms, non-printable lists, other atoms, tuples,
%%              maps) falls back to `term_binary` via
%%              erlang:term_to_binary/1, decoded back with the `safe`
%%              option to avoid unbounded atom-table growth from
%%              untrusted input.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: Value/AVP/AVPUpdate codec.
%%---------------------------------------------------------------------
-module(graphdb_api_value).

-revision('Revision: PA1 ').
-created('Date: 2026-07-08').
-created_by('david@davidwt.com').

-define(NYI(X), (begin
    io:format("*** NYI ~p ~p ~p~n",[?MODULE, ?LINE, X]),
    exit(nyi)
end)).
-define(UEM(F, X), (begin
    io:format("*** UEM ~p:~p ~p ~p~n",[?MODULE, F, ?LINE, X]),
    exit(uem)
end)).

-export([term_to_value/1, value_to_term/1,
         avp_to_pb/1, pb_to_avp/1,
         avp_update_to_term/1,
         node_kind_to_atom/1, atom_to_node_kind/1,
         relationship_kind_to_atom/1, atom_to_relationship_kind/1]).

%%-----------------------------------------------------------------------------
%% term_to_value(term()) -> common_pb:value()
%%-----------------------------------------------------------------------------
term_to_value(undefined) ->
    #{kind => {null_value, #{}}};
term_to_value(V) when is_binary(V) ->
    #{kind => {str, unicode:characters_to_list(V)}};
term_to_value(V) when is_integer(V) ->
    #{kind => {i, V}};
term_to_value(V) when is_float(V) ->
    #{kind => {d, V}};
term_to_value(V) when is_boolean(V) ->
    #{kind => {b, V}};
term_to_value(V) when is_list(V) ->
    case io_lib:printable_unicode_list(V) of
        true  -> #{kind => {str, V}};
        false -> #{kind => {term_binary, term_to_binary(V)}}
    end;
term_to_value(V) ->
    #{kind => {term_binary, term_to_binary(V)}}.

%%-----------------------------------------------------------------------------
%% value_to_term(common_pb:value()) -> term()
%%-----------------------------------------------------------------------------
value_to_term(#{kind := {str, Bin}}) ->
    unicode:characters_to_list(Bin);
value_to_term(#{kind := {i, I}}) ->
    I;
value_to_term(#{kind := {d, D}}) ->
    D;
value_to_term(#{kind := {b, B}}) ->
    B =:= true orelse B =:= 1;
value_to_term(#{kind := {term_binary, Bin}}) ->
    binary_to_term(Bin, [safe]);
value_to_term(#{kind := {null_value, _}}) ->
    undefined;
value_to_term(_) ->
    undefined.

%%-----------------------------------------------------------------------------
%% avp_to_pb(#{attribute := integer(), value := term()}) -> common_pb:avp()
%%-----------------------------------------------------------------------------
avp_to_pb(#{attribute := Attr, value := Value}) ->
    #{attribute => Attr, value => term_to_value(Value)}.

%%-----------------------------------------------------------------------------
%% pb_to_avp(common_pb:avp()) -> #{attribute := integer(), value := term()}
%%-----------------------------------------------------------------------------
pb_to_avp(#{attribute := Attr, value := Value}) ->
    #{attribute => Attr, value => value_to_term(Value)}.

%%-----------------------------------------------------------------------------
%% avp_update_to_term(common_pb:avp_update()) ->
%%     #{attribute := integer(), value => term()}
%%
%% Mirrors graphdb_mgr:update_node_avps/2's well-formedness contract: the
%% `value` key is present only for an upsert; a delete update carries no
%% `value` key at all.
%%-----------------------------------------------------------------------------
avp_update_to_term(#{attribute := Attr, delete := true}) ->
    #{attribute => Attr};
avp_update_to_term(#{attribute := Attr, value := Value} = Update) ->
    case maps:get(delete, Update, false) of
        true  -> #{attribute => Attr};
        false -> #{attribute => Attr, value => value_to_term(Value)}
    end.

%%-----------------------------------------------------------------------------
%% Node/Relationship kind <-> proto enum
%%-----------------------------------------------------------------------------
node_kind_to_atom('CATEGORY')  -> category;
node_kind_to_atom('ATTRIBUTE') -> attribute;
node_kind_to_atom('CLASS')     -> class;
node_kind_to_atom('INSTANCE')  -> instance;
node_kind_to_atom('TEMPLATE')  -> template.

atom_to_node_kind(category)  -> 'CATEGORY';
atom_to_node_kind(attribute) -> 'ATTRIBUTE';
atom_to_node_kind(class)     -> 'CLASS';
atom_to_node_kind(instance)  -> 'INSTANCE';
atom_to_node_kind(template)  -> 'TEMPLATE'.

relationship_kind_to_atom('TAXONOMY')      -> taxonomy;
relationship_kind_to_atom('COMPOSITION')   -> composition;
relationship_kind_to_atom('CONNECTION')    -> connection;
relationship_kind_to_atom('INSTANTIATION') -> instantiation.

atom_to_relationship_kind(taxonomy)      -> 'TAXONOMY';
atom_to_relationship_kind(composition)   -> 'COMPOSITION';
atom_to_relationship_kind(connection)    -> 'CONNECTION';
atom_to_relationship_kind(instantiation) -> 'INSTANTIATION'.
