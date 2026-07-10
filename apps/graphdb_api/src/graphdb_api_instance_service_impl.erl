%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: grpcbox service implementation for
%%              graphdb_api.InstanceService (graphdb_api_instance_service_bhvr,
%%              generated from instance_service.proto). Every write RPC
%%              carries a plain project_id field and reconstructs the
%%              graphdb_project session itself (design §2.1) — the wire
%%              never carries a serialized session term.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: all 12 InstanceService RPCs.
%%---------------------------------------------------------------------
-module(graphdb_api_instance_service_impl).
-behaviour(graphdb_api_instance_service_bhvr).

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

-export([create_instance/2, add_relationship/2, remove_relationship/2,
         update_relationship/2, update_relationship_both/2,
         add_class_membership/2, get_instance/2, children/2,
         compositional_ancestors/2, class_of/2, class_memberships/2,
         resolve_value/2]).

create_instance(Ctx, #{project_id := ProjId, name := Name, class_nref := ClassNref,
                        parent_nref := ParentNref}) ->
    with_session(ProjId, fun(Session) ->
        case graphdb_instance:create_instance(Session, Name, ClassNref, ParentNref) of
            {ok, Nref, Report} ->
                {ok, #{nref => Nref, report => graphdb_api_value:term_to_value(Report)}, Ctx};
            {error, Reason, _Report} ->
                graphdb_api_error:to_status(Reason);
            {error, _Reason} = Error ->
                graphdb_api_error:to_status(Error)
        end
    end).

add_relationship(Ctx, #{project_id := ProjId, source := S, characterization := C,
                         target := T, reciprocal := R} = Req) ->
    with_session(ProjId, fun(Session) ->
        FwdAVPs = [graphdb_api_value:pb_to_avp(A) || A <- maps:get(fwd_avps, Req, [])],
        RevAVPs = [graphdb_api_value:pb_to_avp(A) || A <- maps:get(rev_avps, Req, [])],
        %% Unlike graphdb_mgr:mutate/1's grammar (whose prepare/1 accepts the
        %% atom `default` as TemplateSpec even alongside an AVPSpec),
        %% graphdb_instance:add_relationship/7's public arity guards
        %% `is_integer(TemplateNref)` -- passing the atom `default` there
        %% raises function_clause. So "unset template" + "has AVPs" must
        %% resolve the real default template nref first via
        %% graphdb_class:default_template/1, then call the explicit-nref
        %% /7 arity. (Caught in this plan's Task 5 review: an earlier draft
        %% of the analogous NodeService.Mutate translation silently dropped
        %% AVPs whenever the wire template was unset -- fixed there by
        %% passing the graphdb_mgr-specific atom `default` through, which
        %% is NOT available on this direct graphdb_instance call path.)
        Result = case {maps:get(template, Req, 0), FwdAVPs, RevAVPs} of
            {0, [], []} ->
                graphdb_instance:add_relationship(Session, S, C, T, R);
            {0, _, _} ->
                case graphdb_instance:class_of(S) of
                    {ok, ClassNref} ->
                        case graphdb_class:default_template(ClassNref) of
                            {ok, TemplateNref} ->
                                graphdb_instance:add_relationship(Session, S, C, T, R, TemplateNref, {FwdAVPs, RevAVPs});
                            not_found ->
                                {error, {no_default_template, ClassNref}};
                            {error, _} = Err ->
                                Err
                        end;
                    not_found ->
                        {error, {no_class_membership, S}};
                    {error, _} = Err ->
                        Err
                end;
            {Template, [], []} ->
                graphdb_instance:add_relationship(Session, S, C, T, R, Template);
            {Template, _, _} ->
                graphdb_instance:add_relationship(Session, S, C, T, R, Template, {FwdAVPs, RevAVPs})
        end,
        reply_ok_or_status(Result, Ctx)
    end).

remove_relationship(Ctx, #{project_id := ProjId, source := S, characterization := C,
                            target := T} = Req) ->
    with_session(ProjId, fun(Session) ->
        Result = case maps:get(template, Req, 0) of
            0        -> graphdb_instance:remove_relationship(Session, S, C, T);
            Template -> graphdb_instance:remove_relationship(Session, S, C, T, Template)
        end,
        reply_ok_or_status(Result, Ctx)
    end).

update_relationship(Ctx, #{project_id := ProjId, source := S, characterization := C,
                            target := T, updates := Updates} = Req) ->
    with_session(ProjId, fun(Session) ->
        Terms = [graphdb_api_value:avp_update_to_term(U) || U <- Updates],
        Result = case maps:get(template, Req, 0) of
            0        -> graphdb_instance:update_relationship(Session, S, C, T, Terms);
            Template -> graphdb_instance:update_relationship(Session, S, C, T, Template, Terms)
        end,
        reply_ok_or_status(Result, Ctx)
    end).

update_relationship_both(Ctx, #{project_id := ProjId, source := S, characterization := C,
                                 target := T, fwd_updates := Fwd, rev_updates := Rev} = Req) ->
    with_session(ProjId, fun(Session) ->
        FwdTerms = [graphdb_api_value:avp_update_to_term(U) || U <- Fwd],
        RevTerms = [graphdb_api_value:avp_update_to_term(U) || U <- Rev],
        Result = case maps:get(template, Req, 0) of
            0        -> graphdb_instance:update_relationship_both(Session, S, C, T, {FwdTerms, RevTerms});
            Template -> graphdb_instance:update_relationship_both(Session, S, C, T, Template, {FwdTerms, RevTerms})
        end,
        reply_ok_or_status(Result, Ctx)
    end).

add_class_membership(Ctx, #{project_id := ProjId, instance_nref := InstNref,
                             class_nref := ClassNref}) ->
    with_session(ProjId, fun(Session) ->
        Result = graphdb_instance:add_class_membership(Session, InstNref, ClassNref),
        reply_ok_or_status(Result, Ctx)
    end).

get_instance(Ctx, #{nref := Nref}) ->
    case graphdb_instance:get_instance(Nref) of
        {ok, Node} -> {ok, #{node => graphdb_api_value:node_to_pb(Node)}, Ctx};
        Error      -> graphdb_api_error:to_status(Error)
    end.

children(Ctx, #{nref := Nref}) ->
    case graphdb_instance:children(Nref) of
        {ok, Nodes} -> {ok, #{children => [graphdb_api_value:node_to_pb(N) || N <- Nodes]}, Ctx};
        Error       -> graphdb_api_error:to_status(Error)
    end.

compositional_ancestors(Ctx, #{nref := Nref}) ->
    case graphdb_instance:compositional_ancestors(Nref) of
        {ok, Nodes} -> {ok, #{ancestors => [graphdb_api_value:node_to_pb(N) || N <- Nodes]}, Ctx};
        Error       -> graphdb_api_error:to_status(Error)
    end.

class_of(Ctx, #{instance_nref := Nref}) ->
    case graphdb_instance:class_of(Nref) of
        {ok, ClassNref} -> {ok, #{class_nref => ClassNref}, Ctx};
        Error           -> graphdb_api_error:to_status(Error)
    end.

class_memberships(Ctx, #{instance_nref := Nref}) ->
    case graphdb_instance:class_memberships(Nref) of
        {ok, Classes} -> {ok, #{classes => Classes}, Ctx};
        Error         -> graphdb_api_error:to_status(Error)
    end.

resolve_value(Ctx, #{instance_nref := Nref, attr_nref := AttrNref}) ->
    case graphdb_instance:resolve_value(Nref, AttrNref) of
        {ok, Value, Source} ->
            {ok, #{value => graphdb_api_value:term_to_value(Value),
                   source => source_to_pb(Source)}, Ctx};
        Error ->
            graphdb_api_error:to_status(Error)
    end.

%%-----------------------------------------------------------------------------
%% Internal
%%-----------------------------------------------------------------------------
with_session(ProjId, Fun) ->
    case graphdb_project:open_session(ProjId) of
        {ok, Session} ->
            Fun(Session);
        {error, not_a_project} ->
            %% project_id is effectively this RPC's write credential: a
            %% session that fails to open is an authentication failure
            %% from the wire's perspective (design §2.1's "reconstructs
            %% the session server-side"), not a generic graph-lookup
            %% miss -- so it is remapped to invalid_session (UNAUTHENTICATED,
            %% code 16) rather than surfacing graphdb_project:open_session/1's
            %% own not_a_project reason (which graphdb_api_error maps to
            %% NOT_FOUND, code 5, for other, non-session-establishment
            %% callers). See task-6-report.md "Self-review findings" for
            %% the plan-defect note this resolves.
            graphdb_api_error:to_status({error, invalid_session});
        {error, _} = Err ->
            graphdb_api_error:to_status(Err)
    end.

reply_ok_or_status(ok, Ctx)      -> {ok, #{}, Ctx};
reply_ok_or_status(Error, _Ctx)  -> graphdb_api_error:to_status(Error).

source_to_pb(local)                 -> #{kind => {local, true}};
source_to_pb({class, Nref})         -> #{kind => {class_nref, Nref}};
source_to_pb({compositional, Nref}) -> #{kind => {compositional_nref, Nref}};
source_to_pb({connected, Nref})     -> #{kind => {connected_nref, Nref}}.
