%%---------------------------------------------------------------------
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: Top supervisor for graphdb_api. No children: the gRPC
%%              listener is owned by the grpcbox application (see
%%              graphdb_api.erl). Reserved for future workers (e.g. an
%%              auth interceptor's state process).
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: empty supervisor.
%%---------------------------------------------------------------------
-module(graphdb_api_sup).
-behaviour(supervisor).

-revision('Revision: PA1 ').
-created('Date: 2026-07-08').
-created_by('david@davidwt.com').

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 5, period => 5000},
    {ok, {SupFlags, []}}.
