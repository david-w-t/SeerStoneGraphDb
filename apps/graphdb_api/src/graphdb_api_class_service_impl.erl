%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: grpcbox service implementation for graphdb_api.ClassService
%%              (graphdb_api_class_service_bhvr, generated from
%%              class_service.proto). Thin wire-marshaling wrapper over
%%              graphdb_class's public API.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: all 12 ClassService RPCs.
%%---------------------------------------------------------------------
-module(graphdb_api_class_service_impl).
-behaviour(graphdb_api_class_service_bhvr).

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

-export([create_class/2, add_superclass/2, add_qualifying_characteristic/2,
         bind_qc_value/2, add_template/2, get_class/2, subclasses/2,
         ancestors/2, get_template/2, templates_for_class/2,
         default_template/2, is_instantiable/2]).

create_class(Ctx, #{name := Name, parent_class_nref := ParentNref, avps := AVPs}) ->
    Terms = [graphdb_api_value:pb_to_avp(A) || A <- AVPs],
    case graphdb_class:create_class(Name, ParentNref, Terms) of
        {ok, Nref} -> {ok, #{nref => Nref}, Ctx};
        Error      -> graphdb_api_error:to_status(Error)
    end.

add_superclass(Ctx, #{class_nref := ClassNref, additional_parent_nref := ParentNref}) ->
    reply_ok_or_status(graphdb_class:add_superclass(ClassNref, ParentNref), Ctx).

add_qualifying_characteristic(Ctx, #{class_nref := ClassNref, attr_nref := AttrNref,
                                      instance_only := true}) ->
    reply_ok_or_status(
        graphdb_class:add_qualifying_characteristic(ClassNref, AttrNref, #{instance_only => true}),
        Ctx);
add_qualifying_characteristic(Ctx, #{class_nref := ClassNref, attr_nref := AttrNref}) ->
    reply_ok_or_status(
        graphdb_class:add_qualifying_characteristic(ClassNref, AttrNref), Ctx).

bind_qc_value(Ctx, #{class_nref := ClassNref, attr_nref := AttrNref, value := Value}) ->
    Term = graphdb_api_value:value_to_term(Value),
    reply_ok_or_status(graphdb_class:bind_qc_value(ClassNref, AttrNref, Term), Ctx).

add_template(Ctx, #{class_nref := ClassNref, name := Name}) ->
    case graphdb_class:add_template(ClassNref, Name) of
        {ok, Nref} -> {ok, #{nref => Nref}, Ctx};
        Error      -> graphdb_api_error:to_status(Error)
    end.

get_class(Ctx, #{nref := Nref}) ->
    case graphdb_class:get_class(Nref) of
        {ok, Node} -> {ok, #{node => graphdb_api_value:node_to_pb(Node)}, Ctx};
        Error      -> graphdb_api_error:to_status(Error)
    end.

subclasses(Ctx, #{class_nref := ClassNref}) ->
    case graphdb_class:subclasses(ClassNref) of
        {ok, Nodes} -> {ok, #{subclasses => [graphdb_api_value:node_to_pb(N) || N <- Nodes]}, Ctx};
        Error       -> graphdb_api_error:to_status(Error)
    end.

ancestors(Ctx, #{class_nref := ClassNref}) ->
    case graphdb_class:ancestors(ClassNref) of
        {ok, Nodes} -> {ok, #{ancestors => [graphdb_api_value:node_to_pb(N) || N <- Nodes]}, Ctx};
        Error       -> graphdb_api_error:to_status(Error)
    end.

get_template(Ctx, #{nref := Nref}) ->
    case graphdb_class:get_template(Nref) of
        {ok, Node} -> {ok, #{node => graphdb_api_value:node_to_pb(Node)}, Ctx};
        Error      -> graphdb_api_error:to_status(Error)
    end.

templates_for_class(Ctx, #{class_nref := ClassNref}) ->
    case graphdb_class:templates_for_class(ClassNref) of
        {ok, Nodes} -> {ok, #{templates => [graphdb_api_value:node_to_pb(N) || N <- Nodes]}, Ctx};
        Error       -> graphdb_api_error:to_status(Error)
    end.

default_template(Ctx, #{class_nref := ClassNref}) ->
    case graphdb_class:default_template(ClassNref) of
        {ok, TemplateNref} -> {ok, #{template_nref => TemplateNref}, Ctx};
        Error               -> graphdb_api_error:to_status(Error)
    end.

is_instantiable(Ctx, #{class_nref := ClassNref}) ->
    case graphdb_class:is_instantiable(ClassNref) of
        B when is_boolean(B) -> {ok, #{instantiable => B}, Ctx};
        Error                 -> graphdb_api_error:to_status(Error)
    end.

%%-----------------------------------------------------------------------------
%% Internal
%%-----------------------------------------------------------------------------
reply_ok_or_status(ok, Ctx)     -> {ok, #{}, Ctx};
reply_ok_or_status(Error, _Ctx) -> graphdb_api_error:to_status(Error).
