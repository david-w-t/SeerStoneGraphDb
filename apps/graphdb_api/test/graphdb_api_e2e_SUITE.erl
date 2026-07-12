%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: Registers all 8 graphdb_api services on one grpcbox
%%              listener (mirroring the real config/sys.config shape)
%%              and makes one real call per service. Every other suite
%%              in this app proves its service in isolation; this is the
%%              only one proving they coexist without name/routing
%%              collisions.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: combined-listener smoke test.
%%---------------------------------------------------------------------
-module(graphdb_api_e2e_SUITE).

-revision('Revision: PA1 ').
-created('Date: 2026-07-08').
-created_by('david@davidwt.com').

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, suite/0]).
-export([init_per_testcase/2, end_per_testcase/2]).
-export([all_eight_services_answer_on_one_listener/1]).

suite() -> [{timetrap, {seconds, 30}}].

all() -> [all_eight_services_answer_on_one_listener].

init_per_testcase(_TC, Config0) ->
    Config1 = graphdb_api_test_helper:start_stack(Config0),
    {ok, ListenOpts} = graphdb_api_test_helper:start_grpc(
        ?MODULE,
        [node_service_pb, instance_service_pb, class_service_pb,
         attribute_service_pb, rules_service_pb, language_service_pb,
         project_service_pb, query_service_pb],
        #{'graphdb_api.NodeService'      => graphdb_api_node_service_impl,
          'graphdb_api.InstanceService'  => graphdb_api_instance_service_impl,
          'graphdb_api.ClassService'     => graphdb_api_class_service_impl,
          'graphdb_api.AttributeService' => graphdb_api_attribute_service_impl,
          'graphdb_api.RulesService'     => graphdb_api_rules_service_impl,
          'graphdb_api.LanguageService'  => graphdb_api_language_service_impl,
          'graphdb_api.ProjectService'   => graphdb_api_project_service_impl,
          'graphdb_api.QueryService'     => graphdb_api_query_service_impl}),
    #{port := Port} = ListenOpts,
    {ok, ?MODULE} = graphdb_api_test_helper:start_client(?MODULE, Port),
    [{listen_opts, ListenOpts} | Config1].

end_per_testcase(_TC, Config) ->
    graphdb_api_test_helper:stop_client(?MODULE),
    graphdb_api_test_helper:stop_grpc(proplists:get_value(listen_opts, Config)),
    graphdb_api_test_helper:stop_stack(Config),
    ok.

all_eight_services_answer_on_one_listener(_Config) ->
    Opts = #{channel => ?MODULE},

    {ok, #{node := #{nref := 1}}, _} =
        graphdb_api_node_service_client:get_node(#{nref => 1}, Opts),

    {ok, #{project_id := ProjId}, _} =
        graphdb_api_project_service_client:register_project(#{name => "E2E"}, Opts),
    {ok, #{is_project := true}, _} =
        graphdb_api_project_service_client:is_project(#{nref => ProjId}, Opts),

    {ok, #{nref := ClassNref}, _} =
        graphdb_api_class_service_client:create_class(
            #{name => "E2EWidget", parent_class_nref => 3, avps => []}, Opts),

    {ok, #{nref := AttrNref}, _} =
        graphdb_api_attribute_service_client:create_name_attribute(
            #{name => "e2eName", parent_nref => 0}, Opts),

    Mult = #{min => 0, max => 0, unbounded => true},
    {ok, #{rule_nref := _}, _} =
        graphdb_api_rules_service_client:create_composition_rule(
            #{name => "e2e-rule", parent_class => ClassNref, child_class => ClassNref,
              mode => 'PROPOSE', multiplicity => Mult, template_nref => 0, name_pattern => ""},
            Opts),

    {ok, #{nref := LangNref}, _} =
        graphdb_api_language_service_client:register_language(
            #{code => "e2e", name => "E2E Lang"}, Opts),
    ?assert(is_integer(LangNref)),

    {ok, #{nref := InstNref, report := _}, _} =
        graphdb_api_instance_service_client:create_instance(
            #{project_id => ProjId, name => "e2e-inst", class_nref => ClassNref,
              parent_nref => ProjId},
            Opts),

    {ok, #{found := _}, _} =
        graphdb_api_query_service_client:find_path(
            #{from => ProjId, to => InstNref, max_depth => 5}, Opts),

    ?assert(is_integer(AttrNref)).
