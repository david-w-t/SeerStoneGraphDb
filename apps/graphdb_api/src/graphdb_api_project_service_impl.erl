%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: grpcbox service implementation for
%%              graphdb_api.ProjectService (graphdb_api_project_service_bhvr,
%%              generated from project_service.proto). Thin
%%              wire-marshaling wrapper over graphdb_project's public API.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: both ProjectService RPCs.
%%---------------------------------------------------------------------
-module(graphdb_api_project_service_impl).
-behaviour(graphdb_api_project_service_bhvr).

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

-export([register_project/2, is_project/2]).

register_project(Ctx, #{name := Name}) ->
    case graphdb_project:register_project(binary_to_list(Name)) of
        {ok, Nref} -> {ok, #{project_id => Nref}, Ctx};
        Error      -> graphdb_api_error:to_status(Error)
    end.

is_project(Ctx, #{nref := Nref}) ->
    {ok, #{is_project => graphdb_project:is_project(Nref)}, Ctx}.
