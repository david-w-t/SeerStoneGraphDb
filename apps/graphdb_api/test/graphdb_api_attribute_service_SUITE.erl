%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: Common Test suite for graphdb_api.AttributeService
%%              (graphdb_api_attribute_service_impl), exercising the full
%%              stack + a real in-process grpcbox server via
%%              graphdb_api_test_helper.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: 5 test cases covering all 7 RPCs.
%%---------------------------------------------------------------------
-module(graphdb_api_attribute_service_SUITE).

-revision('Revision: PA1 ').
-created('Date: 2026-07-08').
-created_by('david@davidwt.com').

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0, suite/0]).
-export([init_per_testcase/2, end_per_testcase/2]).
-export([create_name_attribute_then_get/1,
         create_literal_attribute_with_free_form_type/1,
         create_relationship_attribute_pair_returns_both_nrefs/1,
         create_relationship_type_then_list/1,
         list_attributes_includes_bootstrap_names/1]).

suite() -> [{timetrap, {seconds, 30}}].

all() -> [create_name_attribute_then_get,
          create_literal_attribute_with_free_form_type,
          create_relationship_attribute_pair_returns_both_nrefs,
          create_relationship_type_then_list,
          list_attributes_includes_bootstrap_names].

init_per_testcase(_TC, Config0) ->
    Config1 = graphdb_api_test_helper:start_stack(Config0),
    {ok, ListenOpts} = graphdb_api_test_helper:start_grpc(
        ?MODULE, [attribute_service_pb],
        #{'graphdb_api.AttributeService' => graphdb_api_attribute_service_impl}),
    #{port := Port} = ListenOpts,
    {ok, ?MODULE} = graphdb_api_test_helper:start_client(?MODULE, Port),
    [{listen_opts, ListenOpts} | Config1].

end_per_testcase(_TC, Config) ->
    graphdb_api_test_helper:stop_client(?MODULE),
    graphdb_api_test_helper:stop_grpc(proplists:get_value(listen_opts, Config)),
    graphdb_api_test_helper:stop_stack(Config),
    ok.

create_name_attribute_then_get(_Config) ->
    {ok, #{nref := Nref}, _} = graphdb_api_attribute_service_client:create_name_attribute(
        #{name => "codeName", parent_nref => 0}, #{channel => ?MODULE}),
    {ok, #{node := #{nref := Nref, kind := 'ATTRIBUTE'}}, _} =
        graphdb_api_attribute_service_client:get_attribute(#{nref => Nref}, #{channel => ?MODULE}).

create_literal_attribute_with_free_form_type(_Config) ->
    {ok, #{nref := Nref}, _} = graphdb_api_attribute_service_client:create_literal_attribute(
        #{name => "torque", type => "newton-meters", parent_nref => 0}, #{channel => ?MODULE}),
    ?assert(is_integer(Nref)).

create_relationship_attribute_pair_returns_both_nrefs(_Config) ->
    {ok, #{forward_nref := Fwd, reciprocal_nref := Rev}, _} =
        graphdb_api_attribute_service_client:create_relationship_attribute_pair(
            #{name => "ownedBy", reciprocal_name => "owns",
              target_kind => 'INSTANCE', parent_nref => 0},
            #{channel => ?MODULE}),
    ?assert(is_integer(Fwd)),
    ?assert(is_integer(Rev)),
    ?assertNotEqual(Fwd, Rev).

create_relationship_type_then_list(_Config) ->
    {ok, #{nref := Nref}, _} = graphdb_api_attribute_service_client:create_relationship_type(
        #{name => "bucket-test", parent_nref => 0}, #{channel => ?MODULE}),
    {ok, #{relationship_types := Types}, _} =
        graphdb_api_attribute_service_client:list_relationship_types(#{}, #{channel => ?MODULE}),
    ?assert(lists:any(fun(#{nref := N}) -> N =:= Nref end, Types)).

list_attributes_includes_bootstrap_names(_Config) ->
    {ok, #{attributes := Attrs}, _} =
        graphdb_api_attribute_service_client:list_attributes(#{}, #{channel => ?MODULE}),
    ?assert(lists:any(fun(#{nref := N}) -> N =:= 6 end, Attrs)).  %% nref 6 = Names
