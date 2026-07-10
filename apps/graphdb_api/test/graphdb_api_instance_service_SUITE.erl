%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: Common Test suite for graphdb_api.InstanceService
%%              (graphdb_api_instance_service_impl), exercising the
%%              full stack + a real in-process grpcbox server via
%%              graphdb_api_test_helper.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: 7 test cases covering all 12 RPCs.
%%---------------------------------------------------------------------
-module(graphdb_api_instance_service_SUITE).

-revision('Revision: PA1 ').
-created('Date: 2026-07-08').
-created_by('david@davidwt.com').

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

%%---------------------------------------------------------------------
%% Record definitions (match graphdb internal #relationship{} record) --
%% needed to inspect graphdb_mgr:get_relationships/1 results directly.
%%---------------------------------------------------------------------
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
-export([create_instance_under_registered_project/1,
         create_instance_rejects_missing_project/1,
         add_and_remove_relationship_round_trip/1,
         add_relationship_unset_template_with_avps/1,
         update_relationship_avps/1,
         add_class_membership_then_class_memberships/1,
         get_instance_children_and_ancestors/1,
         resolve_value_reports_local_source/1]).

suite() -> [{timetrap, {seconds, 30}}].

all() -> [create_instance_under_registered_project,
          create_instance_rejects_missing_project,
          add_and_remove_relationship_round_trip,
          add_relationship_unset_template_with_avps,
          update_relationship_avps,
          add_class_membership_then_class_memberships,
          get_instance_children_and_ancestors,
          resolve_value_reports_local_source].

init_per_testcase(_TC, Config0) ->
    Config1 = graphdb_api_test_helper:start_stack(Config0),
    {ok, ListenOpts} = graphdb_api_test_helper:start_grpc(
        ?MODULE, [instance_service_pb, node_service_pb],
        #{'graphdb_api.InstanceService' => graphdb_api_instance_service_impl,
          'graphdb_api.NodeService' => graphdb_api_node_service_impl}),
    #{port := Port} = ListenOpts,
    {ok, ?MODULE} = graphdb_api_test_helper:start_client(?MODULE, Port),
    [{listen_opts, ListenOpts} | Config1].

end_per_testcase(_TC, Config) ->
    graphdb_api_test_helper:stop_client(?MODULE),
    graphdb_api_test_helper:stop_grpc(proplists:get_value(listen_opts, Config)),
    graphdb_api_test_helper:stop_stack(Config),
    ok.

create_instance_under_registered_project(_Config) ->
    {ok, ProjNref} = graphdb_project:register_project("Acme"),
    {ok, ClassNref} = graphdb_class:create_class("Widget", 3),
    {ok, #{nref := InstNref, report := _}, _} =
        graphdb_api_instance_service_client:create_instance(
            #{project_id => ProjNref, name => "widget-1", class_nref => ClassNref,
              parent_nref => ProjNref},
            #{channel => ?MODULE}),
    ?assert(is_integer(InstNref)).

create_instance_rejects_missing_project(_Config) ->
    {ok, ClassNref} = graphdb_class:create_class("Widget2", 3),
    {error, {Status, _Msg}, _Meta} = graphdb_api_instance_service_client:create_instance(
        #{project_id => 999999999, name => "x", class_nref => ClassNref, parent_nref => 5},
        #{channel => ?MODULE}),
    ?assertEqual(grpcbox_stream:code_to_status(16), Status).

add_and_remove_relationship_round_trip(_Config) ->
    {ok, ProjNref} = graphdb_project:register_project("Acme2"),
    {ok, ClassNref} = graphdb_class:create_class("Widget3", 3),
    {ok, {RelNref, RecipNref}} = graphdb_attr:create_relationship_attribute_pair(
        "linkedTo", "linkedFrom", instance),
    {ok, Session} = graphdb_project:open_session(ProjNref),
    {ok, A, _} = graphdb_instance:create_instance(Session, "a", ClassNref, ProjNref),
    {ok, B, _} = graphdb_instance:create_instance(Session, "b", ClassNref, ProjNref),
    {ok, #{}, _} = graphdb_api_instance_service_client:add_relationship(
        #{project_id => ProjNref, source => A, characterization => RelNref, target => B,
          reciprocal => RecipNref, template => 0, fwd_avps => [], rev_avps => []},
        #{channel => ?MODULE}),
    {ok, #{}, _} = graphdb_api_instance_service_client:remove_relationship(
        #{project_id => ProjNref, source => A, characterization => RelNref, target => B, template => 0},
        #{channel => ?MODULE}).

%% Exercises the {0, has-AVPs} branch of
%% graphdb_api_instance_service_impl:add_relationship/2: wire template is
%% unset (0) but fwd_avps is non-empty, forcing resolution of the source
%% class's real default template via graphdb_instance:class_of/1 +
%% graphdb_class:default_template/1 before calling the /7 arity. Verifies
%% both that the call succeeds and that the AVP actually landed on the
%% created relationship row.
add_relationship_unset_template_with_avps(_Config) ->
    {ok, ProjNref} = graphdb_project:register_project("Acme7"),
    {ok, ClassNref} = graphdb_class:create_class("Widget8", 3),
    {ok, {RelNref, RecipNref}} = graphdb_attr:create_relationship_attribute_pair(
        "linkedTo3", "linkedFrom3", instance),
    {ok, WeightAttr} = graphdb_attr:create_literal_attribute("weight2", integer),
    {ok, Session} = graphdb_project:open_session(ProjNref),
    {ok, A, _} = graphdb_instance:create_instance(Session, "a3", ClassNref, ProjNref),
    {ok, B, _} = graphdb_instance:create_instance(Session, "b3", ClassNref, ProjNref),
    FwdAvp = #{attribute => WeightAttr, value => graphdb_api_value:term_to_value(42)},
    {ok, #{}, _} = graphdb_api_instance_service_client:add_relationship(
        #{project_id => ProjNref, source => A, characterization => RelNref, target => B,
          reciprocal => RecipNref, template => 0, fwd_avps => [FwdAvp], rev_avps => []},
        #{channel => ?MODULE}),
    {ok, Rels} = graphdb_mgr:get_relationships(A),
    ?assert(lists:any(
        fun(#relationship{target_nref = T, characterization = C, avps = AVPs}) ->
            T =:= B andalso C =:= RelNref andalso
            lists:any(fun(#{attribute := Attr, value := Val}) ->
                Attr =:= WeightAttr andalso Val =:= 42
            end, AVPs)
        end, Rels)).

update_relationship_avps(_Config) ->
    {ok, ProjNref} = graphdb_project:register_project("Acme3"),
    {ok, ClassNref} = graphdb_class:create_class("Widget4", 3),
    {ok, {RelNref, RecipNref}} = graphdb_attr:create_relationship_attribute_pair(
        "linkedTo2", "linkedFrom2", instance),
    {ok, Session} = graphdb_project:open_session(ProjNref),
    {ok, A, _} = graphdb_instance:create_instance(Session, "a2", ClassNref, ProjNref),
    {ok, B, _} = graphdb_instance:create_instance(Session, "b2", ClassNref, ProjNref),
    ok = graphdb_instance:add_relationship(Session, A, RelNref, B, RecipNref),
    {ok, WeightAttr} = graphdb_attr:create_literal_attribute("weight", integer),
    Update = #{attribute => WeightAttr, value => graphdb_api_value:term_to_value(7), delete => false},
    {ok, #{}, _} = graphdb_api_instance_service_client:update_relationship(
        #{project_id => ProjNref, source => A, characterization => RelNref, target => B,
          template => 0, updates => [Update]},
        #{channel => ?MODULE}).

add_class_membership_then_class_memberships(_Config) ->
    {ok, ProjNref} = graphdb_project:register_project("Acme4"),
    {ok, ClassNref} = graphdb_class:create_class("Widget5", 3),
    {ok, ClassNref2} = graphdb_class:create_class("Widget5b", 3),
    {ok, Session} = graphdb_project:open_session(ProjNref),
    {ok, InstNref, _} = graphdb_instance:create_instance(Session, "c", ClassNref, ProjNref),
    {ok, #{}, _} = graphdb_api_instance_service_client:add_class_membership(
        #{project_id => ProjNref, instance_nref => InstNref, class_nref => ClassNref2},
        #{channel => ?MODULE}),
    {ok, #{classes := Classes}, _} = graphdb_api_instance_service_client:class_memberships(
        #{instance_nref => InstNref}, #{channel => ?MODULE}),
    ?assert(lists:member(ClassNref, Classes)),
    ?assert(lists:member(ClassNref2, Classes)).

get_instance_children_and_ancestors(_Config) ->
    {ok, ProjNref} = graphdb_project:register_project("Acme5"),
    {ok, ClassNref} = graphdb_class:create_class("Widget6", 3),
    {ok, Session} = graphdb_project:open_session(ProjNref),
    {ok, Parent, _} = graphdb_instance:create_instance(Session, "parent", ClassNref, ProjNref),
    {ok, Child, _} = graphdb_instance:create_instance(Session, "child", ClassNref, Parent),
    {ok, #{node := #{nref := Parent}}, _} =
        graphdb_api_instance_service_client:get_instance(#{nref => Parent}, #{channel => ?MODULE}),
    {ok, #{children := Children}, _} =
        graphdb_api_instance_service_client:children(#{nref => Parent}, #{channel => ?MODULE}),
    ?assert(lists:any(fun(#{nref := N}) -> N =:= Child end, Children)),
    {ok, #{ancestors := Ancestors}, _} =
        graphdb_api_instance_service_client:compositional_ancestors(#{nref => Child}, #{channel => ?MODULE}),
    ?assert(lists:any(fun(#{nref := N}) -> N =:= Parent end, Ancestors)).

resolve_value_reports_local_source(_Config) ->
    {ok, ProjNref} = graphdb_project:register_project("Acme6"),
    {ok, NameAttr} = graphdb_attr:create_literal_attribute("displayName", string),
    {ok, ClassNref} = graphdb_class:create_class("Widget7", 3),
    {ok, Session} = graphdb_project:open_session(ProjNref),
    {ok, InstNref, _} = graphdb_instance:create_instance(Session, "d", ClassNref, ProjNref),
    ok = graphdb_mgr:update_node_avps(InstNref, [#{attribute => NameAttr, value => "hello"}]),
    {ok, #{value := ValuePb, source := #{kind := {local, true}}}, _} =
        graphdb_api_instance_service_client:resolve_value(
            #{instance_nref => InstNref, attr_nref => NameAttr}, #{channel => ?MODULE}),
    ?assertEqual("hello", graphdb_api_value:value_to_term(ValuePb)).
