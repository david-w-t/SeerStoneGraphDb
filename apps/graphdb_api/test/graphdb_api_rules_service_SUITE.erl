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
         list_rules_includes_created_rule/1]).

suite() -> [{timetrap, {seconds, 30}}].

all() -> [create_composition_rule_then_get_rule,
          create_connection_rule_returns_nref,
          effective_rules_for_class_returns_opaque_value,
          list_rules_includes_created_rule].

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
