%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: grpcbox service implementation for graphdb_api.RulesService
%%              (graphdb_api_rules_service_bhvr, generated from
%%              rules_service.proto). Scope is hardcoded to `environment`
%%              (project-scoped rules are not yet supported -- see
%%              TASKS.md). The five read RPCs whose Erlang return shape is
%%              richer than a bare node list cross the wire opaquely via
%%              the Value term_binary escape hatch.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: all 9 RulesService RPCs.
%%---------------------------------------------------------------------
%% Rev PA2 Date: 2026-07-10 Author: David W. Thomas
%% Fix Task 9 review findings: (1) create_composition_rule no longer
%% silently drops a non-empty Opts (name_pattern) when template_nref is
%% unset -- always routes through the 8-arity graphdb_rules form with
%% `undefined` as the "no template" sentinel; (2) mode_to_atom/1 gained a
%% catch-all clause so an unspecified/unrecognized RuleMode enum value
%% routes through graphdb_api_error:to_status/1 instead of crashing
%% uncaught.
%%---------------------------------------------------------------------
-module(graphdb_api_rules_service_impl).
-behaviour(graphdb_api_rules_service_bhvr).

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

-export([create_composition_rule/2, create_connection_rule/2, get_rule/2,
         rules_for_class/2, composition_rules_for_class/2,
         connection_rules_for_class/2, effective_rules_for_class/2,
         effective_connection_rules/2, list_rules/2]).

-define(SCOPE, environment).

create_composition_rule(Ctx, #{name := Name, parent_class := ParentClass,
                                child_class := ChildClass, mode := Mode,
                                multiplicity := Mult} = Req) ->
    case mode_to_atom(Mode) of
        {invalid_mode, _} = Invalid ->
            graphdb_api_error:to_status(Invalid);
        ModeAtom ->
            MultTerm = multiplicity_to_term(Mult),
            Template = maps:get(template_nref, Req, 0),
            NamePattern = maps:get(name_pattern, Req, ""),
            Opts = case NamePattern of
                "" -> #{};
                P  -> #{name_pattern => P}
            end,
            %% Always route through the 8-arity form so a non-empty Opts
            %% (name_pattern) is never silently dropped when Template is
            %% unset -- undefined is the exact "no template" sentinel the
            %% 6/7-arity graphdb_rules:create_composition_rule/6,7 clauses
            %% default to internally.
            TemplateNref = case Template of
                0 -> undefined;
                T -> T
            end,
            Result = graphdb_rules:create_composition_rule(
                ?SCOPE, Name, ParentClass, ChildClass, ModeAtom, MultTerm,
                TemplateNref, Opts),
            case Result of
                {ok, RuleNref} -> {ok, #{rule_nref => RuleNref}, Ctx};
                Error          -> graphdb_api_error:to_status(Error)
            end
    end.

create_connection_rule(Ctx, #{name := Name, source_class := SourceClass,
                               characterization := Char, reciprocal := Recip,
                               target_class := TargetClass, mode := Mode,
                               multiplicity := Mult} = Req) ->
    case mode_to_atom(Mode) of
        {invalid_mode, _} = Invalid ->
            graphdb_api_error:to_status(Invalid);
        ModeAtom ->
            MultTerm = multiplicity_to_term(Mult),
            %% create_connection_rule/8,9 has no Opts parameter (no
            %% name_pattern on the wire for connection rules), so the
            %% Template-vs-Opts silent-drop risk from Finding 1 does not
            %% apply here -- this 0-vs-explicit-template branch is already
            %% complete.
            Result = case maps:get(template_nref, Req, 0) of
                0 -> graphdb_rules:create_connection_rule(?SCOPE, Name, SourceClass, Char, Recip, TargetClass, ModeAtom, MultTerm);
                T -> graphdb_rules:create_connection_rule(?SCOPE, Name, SourceClass, Char, Recip, TargetClass, ModeAtom, MultTerm, T)
            end,
            case Result of
                {ok, RuleNref} -> {ok, #{rule_nref => RuleNref}, Ctx};
                Error          -> graphdb_api_error:to_status(Error)
            end
    end.

get_rule(Ctx, #{rule_nref := RuleNref}) ->
    case graphdb_rules:get_rule(?SCOPE, RuleNref) of
        {ok, Node} -> {ok, #{node => graphdb_api_value:node_to_pb(Node)}, Ctx};
        Error      -> graphdb_api_error:to_status(Error)
    end.

rules_for_class(Ctx, #{class_nref := ClassNref}) ->
    opaque_reply(graphdb_rules:rules_for_class(?SCOPE, ClassNref), rules, Ctx).

composition_rules_for_class(Ctx, #{class_nref := ClassNref}) ->
    opaque_reply(graphdb_rules:composition_rules_for_class(?SCOPE, ClassNref), rules, Ctx).

connection_rules_for_class(Ctx, #{class_nref := ClassNref}) ->
    opaque_reply(graphdb_rules:connection_rules_for_class(?SCOPE, ClassNref), rules, Ctx).

effective_rules_for_class(Ctx, #{class_nref := ClassNref}) ->
    opaque_reply(graphdb_rules:effective_rules_for_class(?SCOPE, ClassNref), rules, Ctx).

effective_connection_rules(Ctx, #{class_nref := ClassNref}) ->
    opaque_reply(graphdb_rules:effective_connection_rules(?SCOPE, ClassNref), rules, Ctx).

list_rules(Ctx, _Req) ->
    case graphdb_rules:list_rules(?SCOPE) of
        {ok, Nodes} -> {ok, #{rules => [graphdb_api_value:node_to_pb(N) || N <- Nodes]}, Ctx};
        Error       -> graphdb_api_error:to_status(Error)
    end.

%%-----------------------------------------------------------------------------
%% Internal
%%-----------------------------------------------------------------------------
opaque_reply({ok, Term}, Key, Ctx) ->
    {ok, #{Key => graphdb_api_value:term_to_value(Term)}, Ctx};
opaque_reply(Error, _Key, _Ctx) ->
    graphdb_api_error:to_status(Error).

mode_to_atom('MANDATORY') -> mandatory;
mode_to_atom('AUTO')      -> auto;
mode_to_atom('PROPOSE')   -> propose;
%% Catch-all: covers the proto3 RuleMode zero-value ('RULE_MODE_UNSPECIFIED',
%% what gpb decodes to when a client omits `mode`) and any other
%% unrecognized wire value, routing through graphdb_api_error:to_status/1
%% (INVALID_ARGUMENT via the {invalid_mode, _} code_for/1 clause) instead of
%% an uncaught function_clause crash.
mode_to_atom(Other) -> {invalid_mode, Other}.

%% multiplicity_to_term/1 has no catch-all: verified by reading
%% rules_service_pb.erl's decode_msg_multiplicity/2 that a decoded
%% Multiplicity submessage always carries all three keys (min/max/unbounded,
%% defaulting to 0/0/false for any field absent on the wire), so the second
%% clause below is an unconditional catch-all in practice -- there is no
%% gpb-producible shape that falls through both clauses.
multiplicity_to_term(#{unbounded := true, min := Min}) ->
    {Min, unbounded};
multiplicity_to_term(#{min := Min, max := Max}) ->
    {Min, Max}.
