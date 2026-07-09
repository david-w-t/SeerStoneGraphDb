%%---------------------------------------------------------------------
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: graphdb_api is the top application for the internal gRPC
%%              API exposed to the external REST proxy (see
%%              docs/designs/grpc-proxy-api-design.md). The gRPC listener
%%              itself is owned and started by the `grpcbox` application
%%              (sys.config-driven, per the design's §6.1) — this
%%              application's supervisor is deliberately near-empty; it
%%              is the attachment point for future interceptor/auth
%%              state (out of scope for v1).
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: app skeleton.
%%---------------------------------------------------------------------
-module(graphdb_api).
-behaviour(application).

-revision('Revision: PA1 ').
-created('Date: 2026-07-08').
-created_by('david@davidwt.com').

-export([start/2, stop/1]).

start(_Type, _StartArgs) ->
    graphdb_api_sup:start_link().

stop(_State) ->
    ok.
