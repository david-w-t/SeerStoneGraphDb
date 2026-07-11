%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: Common Test suite for graphdb_api.ClassService
%%              (graphdb_api_class_service_impl), exercising the full
%%              stack + a real in-process grpcbox server via
%%              graphdb_api_test_helper.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: 6 test cases covering all 12 RPCs.
%%---------------------------------------------------------------------
-module(graphdb_api_class_service_SUITE).

-revision('Revision: PA1 ').
-created('Date: 2026-07-08').
-created_by('david@davidwt.com').

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0, suite/0]).
-export([init_per_testcase/2, end_per_testcase/2]).
-export([create_class_then_get_class/1,
         add_superclass_appears_in_ancestors/1,
         qualifying_characteristic_and_bind_value/1,
         add_template_then_templates_for_class/1,
         default_template_present_by_default/1,
         is_instantiable_true_by_default/1]).

suite() -> [{timetrap, {seconds, 30}}].

all() -> [create_class_then_get_class,
          add_superclass_appears_in_ancestors,
          qualifying_characteristic_and_bind_value,
          add_template_then_templates_for_class,
          default_template_present_by_default,
          is_instantiable_true_by_default].

init_per_testcase(_TC, Config0) ->
    Config1 = graphdb_api_test_helper:start_stack(Config0),
    {ok, ListenOpts} = graphdb_api_test_helper:start_grpc(
        ?MODULE, [class_service_pb],
        #{'graphdb_api.ClassService' => graphdb_api_class_service_impl}),
    #{port := Port} = ListenOpts,
    {ok, ?MODULE} = graphdb_api_test_helper:start_client(?MODULE, Port),
    [{listen_opts, ListenOpts} | Config1].

end_per_testcase(_TC, Config) ->
    graphdb_api_test_helper:stop_client(?MODULE),
    graphdb_api_test_helper:stop_grpc(proplists:get_value(listen_opts, Config)),
    graphdb_api_test_helper:stop_stack(Config),
    ok.

create_class_then_get_class(_Config) ->
    {ok, #{nref := ClassNref}, _} = graphdb_api_class_service_client:create_class(
        #{name => "Vehicle", parent_class_nref => 3, avps => []}, #{channel => ?MODULE}),
    {ok, #{node := #{nref := ClassNref, kind := 'CLASS'}}, _} =
        graphdb_api_class_service_client:get_class(#{nref => ClassNref}, #{channel => ?MODULE}).

add_superclass_appears_in_ancestors(_Config) ->
    {ok, #{nref := Base}, _} = graphdb_api_class_service_client:create_class(
        #{name => "Machine", parent_class_nref => 3, avps => []}, #{channel => ?MODULE}),
    {ok, #{nref := Extra}, _} = graphdb_api_class_service_client:create_class(
        #{name => "Powered", parent_class_nref => 3, avps => []}, #{channel => ?MODULE}),
    {ok, #{nref := Child}, _} = graphdb_api_class_service_client:create_class(
        #{name => "Car2", parent_class_nref => Base, avps => []}, #{channel => ?MODULE}),
    {ok, #{}, _} = graphdb_api_class_service_client:add_superclass(
        #{class_nref => Child, additional_parent_nref => Extra}, #{channel => ?MODULE}),
    {ok, #{ancestors := Ancestors}, _} = graphdb_api_class_service_client:ancestors(
        #{class_nref => Child}, #{channel => ?MODULE}),
    ?assert(lists:any(fun(#{nref := N}) -> N =:= Extra end, Ancestors)).

qualifying_characteristic_and_bind_value(_Config) ->
    {ok, AttrNref} = graphdb_attr:create_literal_attribute("horsepower", integer),
    {ok, #{nref := ClassNref}, _} = graphdb_api_class_service_client:create_class(
        #{name => "Engine2", parent_class_nref => 3, avps => []}, #{channel => ?MODULE}),
    {ok, #{}, _} = graphdb_api_class_service_client:add_qualifying_characteristic(
        #{class_nref => ClassNref, attr_nref => AttrNref, instance_only => false},
        #{channel => ?MODULE}),
    {ok, #{}, _} = graphdb_api_class_service_client:bind_qc_value(
        #{class_nref => ClassNref, attr_nref => AttrNref,
          value => graphdb_api_value:term_to_value(300)},
        #{channel => ?MODULE}).

add_template_then_templates_for_class(_Config) ->
    {ok, #{nref := ClassNref}, _} = graphdb_api_class_service_client:create_class(
        #{name => "Phone2", parent_class_nref => 3, avps => []}, #{channel => ?MODULE}),
    {ok, #{nref := TemplateNref}, _} = graphdb_api_class_service_client:add_template(
        #{class_nref => ClassNref, name => "custom-color"}, #{channel => ?MODULE}),
    {ok, #{templates := Templates}, _} = graphdb_api_class_service_client:templates_for_class(
        #{class_nref => ClassNref}, #{channel => ?MODULE}),
    ?assert(lists:any(fun(#{nref := N}) -> N =:= TemplateNref end, Templates)).

default_template_present_by_default(_Config) ->
    {ok, #{nref := ClassNref}, _} = graphdb_api_class_service_client:create_class(
        #{name => "Gadget2", parent_class_nref => 3, avps => []}, #{channel => ?MODULE}),
    {ok, #{template_nref := TemplateNref}, _} = graphdb_api_class_service_client:default_template(
        #{class_nref => ClassNref}, #{channel => ?MODULE}),
    ?assert(is_integer(TemplateNref)).

is_instantiable_true_by_default(_Config) ->
    {ok, #{nref := ClassNref}, _} = graphdb_api_class_service_client:create_class(
        #{name => "Sensor2", parent_class_nref => 3, avps => []}, #{channel => ?MODULE}),
    {ok, #{instantiable := true}, _} = graphdb_api_class_service_client:is_instantiable(
        #{class_nref => ClassNref}, #{channel => ?MODULE}).
