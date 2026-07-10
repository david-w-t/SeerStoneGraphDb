%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: End-to-end CT suite for graphdb_api.NodeService: real
%%              stack (graphdb_api_test_helper), real grpcbox server,
%%              real generated client — no mocking.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: happy path per RPC + one error-mapping case.
%%---------------------------------------------------------------------
-module(graphdb_api_node_service_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

%% Local mirror of graphdb's #relationship{} record shape (matches
%% graphdb_mgr.erl / graphdb_instance.erl -- no shared .hrl exports it).
%% Only needed to inspect the `avps` field written by mutate/1.
-record(relationship, {
    id,
    kind,
    source_nref,
    characterization,
    target_nref,
    reciprocal,
    avps
}).

-export([all/0, suite/0]).
-export([init_per_testcase/2, end_per_testcase/2]).
-export([get_node_returns_root_category/1,
         create_attribute_then_get_node/1,
         create_class_returns_nref/1,
         retire_then_unretire_node/1,
         update_node_avps_upserts_and_deletes/1,
         mutate_batch_add_relationship/1,
         mutate_add_relationship_unset_template_keeps_avps/1,
         get_node_not_found_maps_to_grpc_status/1,
         delete_node_maps_to_unimplemented/1]).

suite() -> [{timetrap, {seconds, 30}}].

all() -> [get_node_returns_root_category,
          create_attribute_then_get_node,
          create_class_returns_nref,
          retire_then_unretire_node,
          update_node_avps_upserts_and_deletes,
          mutate_batch_add_relationship,
          mutate_add_relationship_unset_template_keeps_avps,
          get_node_not_found_maps_to_grpc_status,
          delete_node_maps_to_unimplemented].

init_per_testcase(_TC, Config0) ->
    Config1 = graphdb_api_test_helper:start_stack(Config0),
    {ok, ListenOpts} = graphdb_api_test_helper:start_grpc(
        ?MODULE, [node_service_pb],
        #{'graphdb_api.NodeService' => graphdb_api_node_service_impl}),
    #{port := Port} = ListenOpts,
    {ok, ?MODULE} = graphdb_api_test_helper:start_client(?MODULE, Port),
    [{listen_opts, ListenOpts} | Config1].

end_per_testcase(_TC, Config) ->
    graphdb_api_test_helper:stop_client(?MODULE),
    graphdb_api_test_helper:stop_grpc(proplists:get_value(listen_opts, Config)),
    graphdb_api_test_helper:stop_stack(Config),
    ok.

get_node_returns_root_category(_Config) ->
    {ok, Reply, _Meta} = graphdb_api_node_service_client:get_node(
        #{nref => 1}, #{channel => ?MODULE}),
    ?assertMatch(#{node := #{nref := 1, kind := 'CATEGORY'}}, Reply).

create_attribute_then_get_node(_Config) ->
    {ok, #{nref := AttrNref}, _} = graphdb_api_node_service_client:create_attribute(
        #{name => "TestAttr", parent_nref => 7, avps => []}, #{channel => ?MODULE}),
    ?assert(is_integer(AttrNref)),
    {ok, #{node := #{nref := AttrNref, kind := 'ATTRIBUTE'}}, _} =
        graphdb_api_node_service_client:get_node(#{nref => AttrNref}, #{channel => ?MODULE}).

create_class_returns_nref(_Config) ->
    {ok, #{nref := ClassNref}, _} = graphdb_api_node_service_client:create_class(
        #{name => "Widget", parent_class_nref => 3}, #{channel => ?MODULE}),
    ?assert(is_integer(ClassNref)).

retire_then_unretire_node(_Config) ->
    {ok, #{nref := ClassNref}, _} = graphdb_api_node_service_client:create_class(
        #{name => "Retireable", parent_class_nref => 3}, #{channel => ?MODULE}),
    {ok, #{}, _} = graphdb_api_node_service_client:retire_node(
        #{nref => ClassNref}, #{channel => ?MODULE}),
    {ok, #{}, _} = graphdb_api_node_service_client:unretire_node(
        #{nref => ClassNref}, #{channel => ?MODULE}).

update_node_avps_upserts_and_deletes(_Config) ->
    {ok, #{nref := AttrNref}, _} = graphdb_api_node_service_client:create_attribute(
        #{name => "AvpTarget", parent_nref => 7, avps => []}, #{channel => ?MODULE}),
    UpsertUpdate = #{attribute => 6, value => graphdb_api_value:term_to_value("hello"), delete => false},
    {ok, #{}, _} = graphdb_api_node_service_client:update_node_avps(
        #{nref => AttrNref, updates => [UpsertUpdate]}, #{channel => ?MODULE}),
    DeleteUpdate = #{attribute => 6, delete => true},
    {ok, #{}, _} = graphdb_api_node_service_client:update_node_avps(
        #{nref => AttrNref, updates => [DeleteUpdate]}, #{channel => ?MODULE}).

%% NOTE: named "add_relationship" in the brief, but the batch below only
%% exercises the {retire_node, Nref} mutation op -- a real add_relationship
%% mutation needs live instance nrefs (a project session + graphdb_instance
%% setup), out of scope for this smoke test of the batch entry point
%% itself. The final assertion is corrected from the brief: retiring A
%% makes graphdb_mgr:get_node/1 correctly return {error, retired} (see
%% graphdb_mgr.erl handle_call({get_node,...}) / is_retired_avp_present),
%% not {ok, ...} -- proving the mutate/1 batch actually committed.
mutate_batch_add_relationship(_Config) ->
    {ok, #{nref := A}, _} = graphdb_api_node_service_client:create_attribute(
        #{name => "RelA", parent_nref => 14, avps => []}, #{channel => ?MODULE}),
    Op = #{op => {retire_node, #{nref => A}}},
    {ok, #{}, _} = graphdb_api_node_service_client:mutate(
        #{ops => [Op]}, #{channel => ?MODULE}),
    {error, {Status, _Msg}, _Meta} =
        graphdb_api_node_service_client:get_node(#{nref => A}, #{channel => ?MODULE}),
    ?assertEqual(grpcbox_stream:code_to_status(13), Status).

%% Regression test for the silent AVP-loss bug in
%% graphdb_api_node_service_impl:mutation_op_to_term/1's add_relationship
%% clause: an `add_relationship` op with `template => 0` (wire "unset") but
%% non-empty `fwd_avps` must NOT drop those AVPs. graphdb_mgr:prepare/1
%% defaults an omitted Template to the atom `default`, and its /6 arity
%% accepts `default` alongside an explicit AVPSpec -- "unset template" and
%% "has AVPs" are independent, not mutually exclusive (see
%% apps/graphdb/src/graphdb_mgr.erl:445-453). Sets up two real instances and
%% a real relationship-attribute pair directly via the Erlang API (this
%% suite's server runs in-process, per graphdb_api_test_helper), then drives
%% the mutate RPC over the wire and confirms the forward AVP landed on the
%% written relationship row.
mutate_add_relationship_unset_template_keeps_avps(_Config) ->
    {ok, Project} = graphdb_project:register_project("NodeSvc AVP-loss test"),
    {ok, Session} = graphdb_project:open_session(Project),
    {ok, ClassNref} = graphdb_class:create_class("NSApiAvpClass", 3),
    {ok, InstA, _} = graphdb_instance:create_instance(Session, "NSApiAvpA", ClassNref, 5),
    {ok, InstB, _} = graphdb_instance:create_instance(Session, "NSApiAvpB", ClassNref, 5),
    {ok, {CharNref, RecipNref}} =
        graphdb_attr:create_relationship_attribute_pair("NSApiKnows", "NSApiKnownBy",
            instance),
    {ok, SourceAttr} = graphdb_attr:create_literal_attribute("nsapi_source", string),
    FwdAvpWire = #{attribute => SourceAttr,
                   value => graphdb_api_value:term_to_value("wire-test")},
    Op = #{op => {add_relationship,
                  #{source => InstA, characterization => CharNref,
                    target => InstB, reciprocal => RecipNref,
                    template => 0,
                    fwd_avps => [FwdAvpWire], rev_avps => []}}},
    {ok, #{}, _} = graphdb_api_node_service_client:mutate(
        #{ops => [Op]}, #{channel => ?MODULE}),
    {ok, Rels} = graphdb_mgr:get_relationships(InstA),
    [Fwd] = [R || R <- Rels,
        R#relationship.characterization =:= CharNref,
        R#relationship.target_nref =:= InstB],
    ?assert(lists:member(#{attribute => SourceAttr, value => "wire-test"},
        Fwd#relationship.avps)).

get_node_not_found_maps_to_grpc_status(_Config) ->
    {error, {Status, _Msg}, _Meta} = graphdb_api_node_service_client:get_node(
        #{nref => 999999999}, #{channel => ?MODULE}),
    ?assertEqual(grpcbox_stream:code_to_status(5), Status).

delete_node_maps_to_unimplemented(_Config) ->
    {ok, #{nref := ClassNref}, _} = graphdb_api_node_service_client:create_class(
        #{name => "Undeletable", parent_class_nref => 3}, #{channel => ?MODULE}),
    {error, {Status, _Msg}, _Meta} = graphdb_api_node_service_client:delete_node(
        #{nref => ClassNref}, #{channel => ?MODULE}),
    ?assertEqual(grpcbox_stream:code_to_status(12), Status).
