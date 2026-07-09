%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: Single chokepoint mapping an Erlang {error, Reason} (or
%%              bare Reason) into a grpcbox_stream:grpc_error_response().
%%              A curated table maps known reasons to the closest gRPC
%%              status code (design §5); anything uncurated falls back
%%              to INTERNAL. The raw Erlang reason always also survives,
%%              base64(term_to_binary(Reason))-encoded, in the
%%              x-erlang-reason-bin trailer, so no caller ever loses
%%              precision to the coarse status-code enum.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: curated status table + trailer passthrough.
%%---------------------------------------------------------------------
-module(graphdb_api_error).

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

-export([to_status/1]).

%%-----------------------------------------------------------------------------
%% to_status({error, Reason} | Reason) -> grpcbox_stream:grpc_error_response()
%%-----------------------------------------------------------------------------
to_status({error, Reason}) ->
    build(Reason);
to_status(Reason) ->
    build(Reason).

build(Reason) ->
    Status = grpcbox_stream:code_to_status(code_for(Reason)),
    Message = unicode:characters_to_binary(io_lib:format("~p", [Reason])),
    TrailerVal = base64:encode(term_to_binary(Reason)),
    {error, {Status, Message},
     #{trailers => #{<<"x-erlang-reason-bin">> => TrailerVal}}}.

%%-----------------------------------------------------------------------------
%% code_for(Reason) -> 0..16  (standard gRPC status codes)
%%-----------------------------------------------------------------------------
code_for(not_found)                        -> 5;  % NOT_FOUND
code_for(not_a_project)                    -> 5;
code_for(relationship_not_found)           -> 5;
code_for(template_not_found)               -> 5;
code_for(invalid_session)                  -> 16; % UNAUTHENTICATED
code_for(category_nodes_are_immutable)     -> 3;  % INVALID_ARGUMENT
code_for(permanent_node_immutable)         -> 3;
code_for({instance_only_attribute, _})     -> 3;
code_for({invalid_direction, _})           -> 3;
code_for({class_not_instantiable, _})      -> 9;  % FAILED_PRECONDITION
code_for({ambiguous_relationship, _})      -> 9;
code_for({dangling_half_edge, _})          -> 13; % INTERNAL
code_for(not_implemented)                  -> 12; % UNIMPLEMENTED
code_for(_)                                -> 13. % INTERNAL (catch-all)
