%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: Common Test suite for graphdb_api.ProjectService
%%              (graphdb_api_project_service_impl), exercising the full
%%              stack + a real in-process grpcbox server via
%%              graphdb_api_test_helper.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: 2 test cases covering both ProjectService RPCs.
%%---------------------------------------------------------------------
-module(graphdb_api_project_service_SUITE).

-revision('Revision: PA1 ').
-created('Date: 2026-07-08').
-created_by('david@davidwt.com').

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0, suite/0]).
-export([init_per_testcase/2, end_per_testcase/2]).
-export([register_project_then_is_project_true/1,
         is_project_false_for_unregistered_nref/1]).

suite() -> [{timetrap, {seconds, 30}}].

all() -> [register_project_then_is_project_true,
          is_project_false_for_unregistered_nref].

init_per_testcase(_TC, Config0) ->
    Config1 = graphdb_api_test_helper:start_stack(Config0),
    {ok, ListenOpts} = graphdb_api_test_helper:start_grpc(
        ?MODULE, [project_service_pb],
        #{'graphdb_api.ProjectService' => graphdb_api_project_service_impl}),
    #{port := Port} = ListenOpts,
    {ok, ?MODULE} = graphdb_api_test_helper:start_client(?MODULE, Port),
    [{listen_opts, ListenOpts} | Config1].

end_per_testcase(_TC, Config) ->
    graphdb_api_test_helper:stop_client(?MODULE),
    graphdb_api_test_helper:stop_grpc(proplists:get_value(listen_opts, Config)),
    graphdb_api_test_helper:stop_stack(Config),
    ok.

register_project_then_is_project_true(_Config) ->
    {ok, #{project_id := ProjId}, _} = graphdb_api_project_service_client:register_project(
        #{name => "Acme7"}, #{channel => ?MODULE}),
    {ok, #{is_project := true}, _} = graphdb_api_project_service_client:is_project(
        #{nref => ProjId}, #{channel => ?MODULE}).

is_project_false_for_unregistered_nref(_Config) ->
    {ok, #{is_project := false}, _} = graphdb_api_project_service_client:is_project(
        #{nref => 3}, #{channel => ?MODULE}).  %% nref 3 = Classes category, not a project
