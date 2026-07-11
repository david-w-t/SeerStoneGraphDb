%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: Common Test suite for graphdb_api.RulesService
%%              (graphdb_api_rules_service_impl), exercising the full
%%              stack + a real in-process grpcbox server via
%%              graphdb_api_test_helper.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: 4 test cases covering all 9 RPCs.
%%---------------------------------------------------------------------
%% Rev PA2 Date: 2026-07-10 Author: David W. Thomas
%% Add 2 test cases for Task 9 review fixes: name_pattern honored when
%% template_nref is unset (Finding 1), and an unspecified RuleMode enum
%% value returns a clean gRPC error instead of crashing the connection
%% (Finding 2).
%%---------------------------------------------------------------------
-module(graphdb_api_rules_service_SUITE).

-revision('Revision: PA1 ').
-created('Date: 2026-07-08').
-created_by('david@davidwt.com').

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0, suite/0]).
-export([init_per_testcase/2, end_per_testcase/2]).
-export([create_composition_rule_then_get_rule/1,
         create_connection_rule_returns_nref/1,
         effective_rules_for_class_returns_opaque_value/1,
         list_rules_includes_created_rule/1,
         create_composition_rule_unset_template_honors_name_pattern/1,
         create_composition_rule_unspecified_mode_returns_invalid_argument/1]).

suite() -> [{timetrap, {seconds, 30}}].

all() -> [create_composition_rule_then_get_rule,
          create_connection_rule_returns_nref,
          effective_rules_for_class_returns_opaque_value,
          list_rules_includes_created_rule,
          create_composition_rule_unset_template_honors_name_pattern,
          create_composition_rule_unspecified_mode_returns_invalid_argument].

init_per_testcase(_TC, Config0) ->
    Config1 = graphdb_api_test_helper:start_stack(Config0),
    {ok, ListenOpts} = graphdb_api_test_helper:start_grpc(
        ?MODULE, [rules_service_pb],
        #{'graphdb_api.RulesService' => graphdb_api_rules_service_impl}),
    #{port := Port} = ListenOpts,
    {ok, ?MODULE} = graphdb_api_test_helper:start_client(?MODULE, Port),
    [{listen_opts, ListenOpts} | Config1].

end_per_testcase(_TC, Config) ->
    graphdb_api_test_helper:stop_client(?MODULE),
    graphdb_api_test_helper:stop_grpc(proplists:get_value(listen_opts, Config)),
    graphdb_api_test_helper:stop_stack(Config),
    ok.

create_composition_rule_then_get_rule(_Config) ->
    {ok, ParentClass} = graphdb_class:create_class("Car3", 3),
    {ok, ChildClass} = graphdb_class:create_class("Engine3", 3),
    Mult = #{min => 1, max => 1, unbounded => false},
    {ok, #{rule_nref := RuleNref}, _} = graphdb_api_rules_service_client:create_composition_rule(
        #{name => "car-has-engine", parent_class => ParentClass, child_class => ChildClass,
          mode => 'MANDATORY', multiplicity => Mult, template_nref => 0, name_pattern => ""},
        #{channel => ?MODULE}),
    {ok, #{node := #{nref := RuleNref}}, _} =
        graphdb_api_rules_service_client:get_rule(#{rule_nref => RuleNref}, #{channel => ?MODULE}).

create_connection_rule_returns_nref(_Config) ->
    {ok, SourceClass} = graphdb_class:create_class("Driver3", 3),
    {ok, TargetClass} = graphdb_class:create_class("Car4", 3),
    {ok, {RelNref, _}} = graphdb_attr:create_relationship_attribute_pair("drives3", "drivenBy3", instance),
    Mult = #{min => 0, max => 0, unbounded => true},
    {ok, #{rule_nref := RuleNref}, _} = graphdb_api_rules_service_client:create_connection_rule(
        #{name => "driver-drives-car", source_class => SourceClass, characterization => RelNref,
          reciprocal => RelNref, target_class => TargetClass, mode => 'AUTO',
          multiplicity => Mult, template_nref => 0},
        #{channel => ?MODULE}),
    ?assert(is_integer(RuleNref)).

effective_rules_for_class_returns_opaque_value(_Config) ->
    {ok, ParentClass} = graphdb_class:create_class("Car5", 3),
    {ok, ChildClass} = graphdb_class:create_class("Engine5", 3),
    Mult = #{min => 1, max => 1, unbounded => false},
    {ok, _, _} = graphdb_api_rules_service_client:create_composition_rule(
        #{name => "car5-has-engine5", parent_class => ParentClass, child_class => ChildClass,
          mode => 'MANDATORY', multiplicity => Mult, template_nref => 0, name_pattern => ""},
        #{channel => ?MODULE}),
    {ok, #{rules := ValuePb}, _} = graphdb_api_rules_service_client:effective_rules_for_class(
        #{class_nref => ParentClass}, #{channel => ?MODULE}),
    Decoded = graphdb_api_value:value_to_term(ValuePb),
    ?assert(is_list(Decoded)),
    ?assertNotEqual([], Decoded).

list_rules_includes_created_rule(_Config) ->
    {ok, ParentClass} = graphdb_class:create_class("Car6", 3),
    {ok, ChildClass} = graphdb_class:create_class("Engine6", 3),
    Mult = #{min => 1, max => 1, unbounded => false},
    {ok, #{rule_nref := RuleNref}, _} = graphdb_api_rules_service_client:create_composition_rule(
        #{name => "car6-has-engine6", parent_class => ParentClass, child_class => ChildClass,
          mode => 'MANDATORY', multiplicity => Mult, template_nref => 0, name_pattern => ""},
        #{channel => ?MODULE}),
    {ok, #{rules := Rules}, _} = graphdb_api_rules_service_client:list_rules(#{}, #{channel => ?MODULE}),
    ?assert(lists:any(fun(#{nref := N}) -> N =:= RuleNref end, Rules)).

%% Task 9 review Finding 1: template_nref =:= 0 ("unset") previously
%% always routed to the 6-arity graphdb_rules:create_composition_rule/6,
%% which has no Opts parameter at all -- a non-empty name_pattern was
%% silently dropped, with no error, no signal to the caller. This exercises
%% exactly that combination (unset template + non-empty name_pattern) and
%% reads the created rule node back via GetRule to confirm the name_pattern
%% content AVP actually landed, rather than just asserting `ok`.
create_composition_rule_unset_template_honors_name_pattern(_Config) ->
    {ok, ParentClass} = graphdb_class:create_class("Car8", 3),
    {ok, ChildClass} = graphdb_class:create_class("Engine8", 3),
    {ok, Seeds} = graphdb_rules:seeded_nrefs(),
    NamePatternAttr = maps:get(name_pattern, Seeds),
    Mult = #{min => 1, max => 1, unbounded => false},
    {ok, #{rule_nref := RuleNref}, _} = graphdb_api_rules_service_client:create_composition_rule(
        #{name => "car8-has-engine8", parent_class => ParentClass, child_class => ChildClass,
          mode => 'MANDATORY', multiplicity => Mult, template_nref => 0,
          name_pattern => "Engine #"},
        #{channel => ?MODULE}),
    {ok, #{node := #{attribute_value_pairs := AVPs}}, _} =
        graphdb_api_rules_service_client:get_rule(#{rule_nref => RuleNref}, #{channel => ?MODULE}),
    ?assert(lists:any(
        fun(#{attribute := Attr, value := Value}) ->
            Attr =:= NamePatternAttr andalso
                graphdb_api_value:value_to_term(Value) =:= "Engine #"
        end, AVPs)).

%% Task 9 review Finding 2: mode_to_atom/1 had no catch-all clause, so
%% RuleMode's proto3 zero-value (RULE_MODE_UNSPECIFIED, what a client gets
%% by omitting `mode`, or sends explicitly here) hit function_clause --  an
%% uncaught crash instead of routing through graphdb_api_error:to_status/1.
%% Asserts a clean INVALID_ARGUMENT status comes back instead of a crash/
%% connection failure.
create_composition_rule_unspecified_mode_returns_invalid_argument(_Config) ->
    {ok, ParentClass} = graphdb_class:create_class("Car9", 3),
    {ok, ChildClass} = graphdb_class:create_class("Engine9", 3),
    Mult = #{min => 1, max => 1, unbounded => false},
    {error, {Status, _Msg}, _Meta} = graphdb_api_rules_service_client:create_composition_rule(
        #{name => "car9-has-engine9", parent_class => ParentClass, child_class => ChildClass,
          mode => 'RULE_MODE_UNSPECIFIED', multiplicity => Mult, template_nref => 0,
          name_pattern => ""},
        #{channel => ?MODULE}),
    ?assertEqual(grpcbox_stream:code_to_status(3), Status).
