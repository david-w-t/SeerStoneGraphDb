%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: Single chokepoint mapping an Erlang {error, Reason} (or
%%              bare Reason) into a grpcbox_stream:grpc_extended_error_response().
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
%% Rev PA2 Date: 2026-07-09 Author: David W. Thomas
%% Fix return shape: grpcbox 0.17.1's grpcbox_stream:handle_unary/3 only
%% recognizes a service callback's returned error as {grpc_error, _} or
%% {grpc_extended_error, _} (thrown from there); a bare {error, {Status,
%% Msg}, Meta} 3-tuple (the shape this module previously returned, matching
%% the -type grpc_error_response()/grpc_callback_error() spec in
%% grpcbox_stream.erl -- which does not match that module's own runtime
%% handle_unary/3 logic in this version) falls through handle_unary/3's
%% case clauses uncaught, crashing to a generic UNKNOWN(2) and losing both
%% the curated status and the x-erlang-reason-bin trailer. Discovered via
%% graphdb_api_node_service_SUITE's error-mapping CT cases (first real
%% wire-level exercise of this module -- Task 3's EUnit coverage only
%% checked to_status/1's return shape, never a live grpcbox round trip).
%% Now returns {grpc_extended_error, #{status, message, trailers}}, the
%% one shape handle_unary/3 both recognizes AND carries trailers with
%% (grpcbox_stream:add_trailers_from_error_data/2).
%%---------------------------------------------------------------------
%% Rev PA3 Date: 2026-07-10 Author: David W. Thomas
%% Add {invalid_mode, _} -> INVALID_ARGUMENT (3), mirroring the existing
%% {invalid_direction, _} clause. Task 9 review fix: RulesService's
%% mode_to_atom/1 now routes an unrecognized/unspecified RuleMode enum
%% value through this chokepoint instead of crashing uncaught.
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
%% to_status({error, Reason} | Reason) ->
%%     grpcbox_stream:grpc_extended_error_response()
%%-----------------------------------------------------------------------------
to_status({error, Reason}) ->
    build(Reason);
to_status(Reason) ->
    build(Reason).

build(Reason) ->
    Status = grpcbox_stream:code_to_status(code_for(Reason)),
    Message = unicode:characters_to_binary(io_lib:format("~p", [Reason])),
    TrailerVal = base64:encode(term_to_binary(Reason)),
    {grpc_extended_error,
     #{status => Status, message => Message,
       trailers => #{<<"x-erlang-reason-bin">> => TrailerVal}}}.

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
code_for({invalid_mode, _})                -> 3;
code_for({class_not_instantiable, _})      -> 9;  % FAILED_PRECONDITION
code_for({ambiguous_relationship, _})      -> 9;
code_for({dangling_half_edge, _})          -> 13; % INTERNAL
code_for(not_implemented)                  -> 12; % UNIMPLEMENTED
code_for(_)                                -> 13. % INTERNAL (catch-all)
