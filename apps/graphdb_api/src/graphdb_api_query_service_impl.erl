%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: grpcbox service implementation for graphdb_api.QueryService
%%              (graphdb_api_query_service_bhvr, generated from
%%              query_service.proto). find_path/3 only -- see design
%%              §3.1 for why general query execution is deferred. The
%%              {partial, BestSoFar, Cont} case discards Cont: resume/2
%%              is out of scope, so there is no RPC that could consume
%%              the continuation token.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: FindPath RPC.
%%---------------------------------------------------------------------
-module(graphdb_api_query_service_impl).
-behaviour(graphdb_api_query_service_bhvr).

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

-export([find_path/2]).

find_path(Ctx, #{from := From, to := To, max_depth := MaxDepth}) ->
    case graphdb_query:find_path(From, To, MaxDepth) of
        {ok, no_path}       -> {ok, #{found => false, path => []}, Ctx};
        {ok, Path}          -> {ok, #{found => true, path => path_edges_to_nrefs(From, Path)}, Ctx};
        {partial, Prefix, _Cont} -> {ok, #{found => false, path => path_edges_to_nrefs(From, Prefix)}, Ctx};
        Error                -> graphdb_api_error:to_status(Error)
    end.

%% path_edges_to_nrefs(From, Edges) -> [integer()]
%%
%% Edges is a list of edge maps: [#{from, via, to, kind}, ...].
%% Convert to a list of nrefs: [From, To1, To2, ..., ToN] where each ToI
%% is the target_nref of the corresponding edge. If Edges is empty,
%% return an empty list (no path traversed).
path_edges_to_nrefs(_From, []) ->
    [];
path_edges_to_nrefs(From, Edges) ->
    [From | [To || #{to := To} <- Edges]].
