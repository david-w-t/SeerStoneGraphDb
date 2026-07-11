%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: grpcbox service implementation for
%%              graphdb_api.AttributeService (graphdb_api_attribute_service_bhvr,
%%              generated from attribute_service.proto). Thin
%%              wire-marshaling wrapper over graphdb_attr's public API.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: all 7 AttributeService RPCs.
%%---------------------------------------------------------------------
-module(graphdb_api_attribute_service_impl).
-behaviour(graphdb_api_attribute_service_bhvr).

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

-export([create_name_attribute/2, create_literal_attribute/2,
         create_relationship_attribute_pair/2, create_relationship_type/2,
         get_attribute/2, list_attributes/2, list_relationship_types/2]).

create_name_attribute(Ctx, #{name := Name, parent_nref := ParentNref}) ->
    Result = case ParentNref of
        0 -> graphdb_attr:create_name_attribute(Name);
        _ -> graphdb_attr:create_name_attribute(Name, ParentNref)
    end,
    case Result of
        {ok, Nref} -> {ok, #{nref => Nref}, Ctx};
        Error      -> graphdb_api_error:to_status(Error)
    end.

create_literal_attribute(Ctx, #{name := Name, type := TypeStr, parent_nref := ParentNref}) ->
    %% Wire `type` decodes as a binary (gpb default for proto3 string
    %% fields in this codebase's config, not a list) -- binary_to_atom/2,
    %% not list_to_atom/1, mints the atom from it. See brief note: this is
    %% the one place in the API that mints new atoms from client input;
    %% acceptable only under the internal-trusted-network threat model.
    Type = binary_to_atom(TypeStr, utf8),
    Result = case ParentNref of
        0 -> graphdb_attr:create_literal_attribute(Name, Type);
        _ -> graphdb_attr:create_literal_attribute(Name, Type, ParentNref)
    end,
    case Result of
        {ok, Nref} -> {ok, #{nref => Nref}, Ctx};
        Error      -> graphdb_api_error:to_status(Error)
    end.

create_relationship_attribute_pair(Ctx, #{name := Name, reciprocal_name := RevName,
                                           target_kind := TargetKind, parent_nref := ParentNref}) ->
    TargetKindAtom = graphdb_api_value:node_kind_to_atom(TargetKind),
    Result = case ParentNref of
        0 -> graphdb_attr:create_relationship_attribute_pair(Name, RevName, TargetKindAtom);
        _ -> graphdb_attr:create_relationship_attribute_pair(Name, RevName, TargetKindAtom, ParentNref)
    end,
    case Result of
        {ok, {FwdNref, RevNref}} -> {ok, #{forward_nref => FwdNref, reciprocal_nref => RevNref}, Ctx};
        Error                    -> graphdb_api_error:to_status(Error)
    end.

create_relationship_type(Ctx, #{name := Name, parent_nref := ParentNref}) ->
    Result = case ParentNref of
        0 -> graphdb_attr:create_relationship_type(Name);
        _ -> graphdb_attr:create_relationship_type(Name, ParentNref)
    end,
    case Result of
        {ok, Nref} -> {ok, #{nref => Nref}, Ctx};
        Error      -> graphdb_api_error:to_status(Error)
    end.

get_attribute(Ctx, #{nref := Nref}) ->
    case graphdb_attr:get_attribute(Nref) of
        {ok, Node} -> {ok, #{node => graphdb_api_value:node_to_pb(Node)}, Ctx};
        Error      -> graphdb_api_error:to_status(Error)
    end.

list_attributes(Ctx, _Req) ->
    case graphdb_attr:list_attributes() of
        {ok, Nodes} -> {ok, #{attributes => [graphdb_api_value:node_to_pb(N) || N <- Nodes]}, Ctx};
        Error       -> graphdb_api_error:to_status(Error)
    end.

list_relationship_types(Ctx, _Req) ->
    case graphdb_attr:list_relationship_types() of
        {ok, Nodes} -> {ok, #{relationship_types => [graphdb_api_value:node_to_pb(N) || N <- Nodes]}, Ctx};
        Error       -> graphdb_api_error:to_status(Error)
    end.
