%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: grpcbox service implementation for graphdb_api.NodeService
%%              (graphdb_api_node_service_bhvr, generated from
%%              node_service.proto). Thin wire-marshaling wrapper over
%%              graphdb_mgr's public API — no business logic here.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: all 9 NodeService RPCs.
%%---------------------------------------------------------------------
-module(graphdb_api_node_service_impl).
-behaviour(graphdb_api_node_service_bhvr).

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

-export([get_node/2, get_relationships/2, create_attribute/2, create_class/2,
         retire_node/2, unretire_node/2, update_node_avps/2, delete_node/2,
         mutate/2]).

get_node(Ctx, #{nref := Nref}) ->
    case graphdb_mgr:get_node(Nref) of
        {ok, Node} -> {ok, #{node => graphdb_api_value:node_to_pb(Node)}, Ctx};
        Error      -> graphdb_api_error:to_status(Error)
    end.

get_relationships(Ctx, #{nref := Nref, direction := Direction}) ->
    case graphdb_mgr:get_relationships(Nref, direction_to_atom(Direction)) of
        {ok, Rels} ->
            {ok, #{relationships => [graphdb_api_value:relationship_to_pb(R) || R <- Rels]}, Ctx};
        Error ->
            graphdb_api_error:to_status(Error)
    end.

%% NOTE (see task-5-report.md "Concerns"): graphdb_mgr:create_attribute/3's
%% 3rd argument is NOT a graph-style AVP list -- it is a plain Erlang
%% *options* map with atom keys (`type` for a Literals-subtree attribute;
%% `reciprocal_name` + `target_kind` for a Relationships-subtree pair; see
%% apps/graphdb/src/graphdb_mgr.erl:1090 and graphdb_mgr_SUITE.erl:628-680).
%% The wire CreateAttributeRequest.avps field (repeated AVP, attribute an
%% int64 nref + a Value) cannot express those atom-keyed options, so it is
%% intentionally ignored here and an empty options map is always passed.
%% This means CreateAttribute over this RPC can only create name attributes
%% and relationship-type groupings (both take no options) -- it cannot yet
%% create typed literal attributes or reciprocal relationship-attribute
%% pairs. Flagging for the plan author: CreateAttributeRequest needs a
%% redesigned field (e.g. a dedicated oneof/map matching this options
%% shape) before those paths are reachable over gRPC.
create_attribute(Ctx, #{name := Name, parent_nref := ParentNref}) ->
    case graphdb_mgr:create_attribute(Name, ParentNref, #{}) of
        {ok, Nref} -> {ok, #{nref => Nref}, Ctx};
        Error      -> graphdb_api_error:to_status(Error)
    end.

create_class(Ctx, #{name := Name, parent_class_nref := ParentNref}) ->
    case graphdb_mgr:create_class(Name, ParentNref) of
        {ok, Nref} -> {ok, #{nref => Nref}, Ctx};
        Error      -> graphdb_api_error:to_status(Error)
    end.

retire_node(Ctx, #{nref := Nref}) ->
    case graphdb_mgr:retire_node(Nref) of
        ok    -> {ok, #{}, Ctx};
        Error -> graphdb_api_error:to_status(Error)
    end.

unretire_node(Ctx, #{nref := Nref}) ->
    case graphdb_mgr:unretire_node(Nref) of
        ok    -> {ok, #{}, Ctx};
        Error -> graphdb_api_error:to_status(Error)
    end.

update_node_avps(Ctx, #{nref := Nref, updates := Updates}) ->
    Terms = [graphdb_api_value:avp_update_to_term(U) || U <- Updates],
    case graphdb_mgr:update_node_avps(Nref, Terms) of
        ok    -> {ok, #{}, Ctx};
        Error -> graphdb_api_error:to_status(Error)
    end.

delete_node(Ctx, #{nref := Nref}) ->
    case graphdb_mgr:delete_node(Nref) of
        ok    -> {ok, #{}, Ctx};
        Error -> graphdb_api_error:to_status(Error)
    end.

mutate(Ctx, #{ops := Ops}) ->
    Terms = [mutation_op_to_term(Op) || Op <- Ops],
    case graphdb_mgr:mutate(Terms) of
        {ok, _Results} -> {ok, #{}, Ctx};
        Error          -> graphdb_api_error:to_status(Error)
    end.

%%-----------------------------------------------------------------------------
%% Internal
%%-----------------------------------------------------------------------------
direction_to_atom('OUTGOING') -> outgoing;
direction_to_atom('INCOMING') -> incoming;
direction_to_atom('BOTH')     -> both;
direction_to_atom(_)          -> outgoing.

mutation_op_to_term(#{op := {add_relationship, Op}}) ->
    #{source := S, characterization := C, target := T, reciprocal := R} = Op,
    FwdAVPs = [graphdb_api_value:pb_to_avp(A) || A <- maps:get(fwd_avps, Op, [])],
    RevAVPs = [graphdb_api_value:pb_to_avp(A) || A <- maps:get(rev_avps, Op, [])],
    %% graphdb_mgr:prepare/1 defaults an omitted Template to the atom
    %% `default` (apps/graphdb/src/graphdb_mgr.erl:445-447) and accepts it
    %% explicitly alongside an AVPSpec via the /6 grammar arity -- so
    %% "unset template" and "has AVPs" are independent, not mutually
    %% exclusive.
    Template = case maps:get(template, Op, 0) of
        0 -> default;
        T2 -> T2
    end,
    case {FwdAVPs, RevAVPs} of
        {[], []} when Template =:= default -> {add_relationship, S, C, T, R};
        {[], []}                           -> {add_relationship, S, C, T, R, Template};
        _                                  -> {add_relationship, S, C, T, R, Template, {FwdAVPs, RevAVPs}}
    end;
mutation_op_to_term(#{op := {retire_node, #{nref := Nref}}}) ->
    {retire_node, Nref};
mutation_op_to_term(#{op := {unretire_node, #{nref := Nref}}}) ->
    {unretire_node, Nref};
mutation_op_to_term(#{op := {update_node_avps, #{nref := Nref, updates := Updates}}}) ->
    {update_node_avps, Nref, [graphdb_api_value:avp_update_to_term(U) || U <- Updates]};
mutation_op_to_term(#{op := {remove_relationship, Op}}) ->
    #{source := S, characterization := C, target := T} = Op,
    case maps:get(template, Op, 0) of
        0        -> {remove_relationship, S, C, T};
        Template -> {remove_relationship, S, C, T, Template}
    end;
mutation_op_to_term(#{op := {update_relationship, Op}}) ->
    #{source := S, characterization := C, target := T, updates := Updates} = Op,
    Terms = [graphdb_api_value:avp_update_to_term(U) || U <- Updates],
    case maps:get(template, Op, 0) of
        0        -> {update_relationship, S, C, T, Terms};
        Template -> {update_relationship, S, C, T, Template, Terms}
    end;
mutation_op_to_term(#{op := {update_relationship_both, Op}}) ->
    #{source := S, characterization := C, target := T,
      fwd_updates := Fwd, rev_updates := Rev} = Op,
    FwdTerms = [graphdb_api_value:avp_update_to_term(U) || U <- Fwd],
    RevTerms = [graphdb_api_value:avp_update_to_term(U) || U <- Rev],
    case maps:get(template, Op, 0) of
        0        -> {update_relationship_both, S, C, T, {FwdTerms, RevTerms}};
        Template -> {update_relationship_both, S, C, T, Template, {FwdTerms, RevTerms}}
    end.
