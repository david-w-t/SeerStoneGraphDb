%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: Proves graphdb_api_test_helper boots the stack and a
%%              grpcbox listener, and tears both down cleanly, before
%%              any real service is built on top of it.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: helper smoke test.
%%---------------------------------------------------------------------
-module(graphdb_api_test_helper_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, suite/0]).
-export([init_per_testcase/2, end_per_testcase/2]).
-export([stack_boots_and_mgr_responds/1,
         grpc_listener_binds_and_accepts_tcp/1]).

suite() -> [{timetrap, {seconds, 30}}].

all() -> [stack_boots_and_mgr_responds,
          grpc_listener_binds_and_accepts_tcp].

init_per_testcase(_TC, Config) ->
    graphdb_api_test_helper:start_stack(Config).

end_per_testcase(_TC, Config) ->
    graphdb_api_test_helper:stop_stack(Config),
    ok.

stack_boots_and_mgr_responds(_Config) ->
    {ok, _Node} = graphdb_mgr:get_node(1),  %% nref 1 = Root category
    ok.

grpc_listener_binds_and_accepts_tcp(_Config) ->
    {ok, ListenOpts} = graphdb_api_test_helper:start_grpc(?MODULE, [], #{}),
    #{port := Port, ip := Ip} = ListenOpts,
    {ok, Sock} = gen_tcp:connect(Ip, Port, [], 2000),
    ok = gen_tcp:close(Sock),
    ok = graphdb_api_test_helper:stop_grpc(ListenOpts).
