%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: Common Test suite for graphdb_api.LanguageService
%%              (graphdb_api_language_service_impl), exercising the full
%%              stack + a real in-process grpcbox server via
%%              graphdb_api_test_helper.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: 3 test cases covering all 6 RPCs.
%%---------------------------------------------------------------------
-module(graphdb_api_language_service_SUITE).

-revision('Revision: PA1 ').
-created('Date: 2026-07-08').
-created_by('david@davidwt.com').

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0, suite/0]).
-export([init_per_testcase/2, end_per_testcase/2]).
-export([register_language_then_lookup/1,
         register_dialect_of_known_base/1,
         set_labels_then_resolve_via_chain/1]).

suite() -> [{timetrap, {seconds, 30}}].

all() -> [register_language_then_lookup,
          register_dialect_of_known_base,
          set_labels_then_resolve_via_chain].

init_per_testcase(_TC, Config0) ->
    Config1 = graphdb_api_test_helper:start_stack(Config0),
    {ok, ListenOpts} = graphdb_api_test_helper:start_grpc(
        ?MODULE, [language_service_pb],
        #{'graphdb_api.LanguageService' => graphdb_api_language_service_impl}),
    #{port := Port} = ListenOpts,
    {ok, ?MODULE} = graphdb_api_test_helper:start_client(?MODULE, Port),
    [{listen_opts, ListenOpts} | Config1].

end_per_testcase(_TC, Config) ->
    graphdb_api_test_helper:stop_client(?MODULE),
    graphdb_api_test_helper:stop_grpc(proplists:get_value(listen_opts, Config)),
    graphdb_api_test_helper:stop_stack(Config),
    ok.

register_language_then_lookup(_Config) ->
    {ok, #{nref := Nref}, _} = graphdb_api_language_service_client:register_language(
        #{code => "de", name => "German"}, #{channel => ?MODULE}),
    {ok, #{nref := Nref}, _} = graphdb_api_language_service_client:lookup_language_nref(
        #{code => "de"}, #{channel => ?MODULE}).

register_dialect_of_known_base(_Config) ->
    {ok, _, _} = graphdb_api_language_service_client:register_language(
        #{code => "fr", name => "French"}, #{channel => ?MODULE}),
    {ok, #{nref := DialectNref}, _} = graphdb_api_language_service_client:register_dialect(
        #{code => "fr-CA", name => "Canadian French", base_code => "fr"}, #{channel => ?MODULE}),
    ?assert(is_integer(DialectNref)).

set_labels_then_resolve_via_chain(_Config) ->
    {ok, #{nref := LangNref}, _} = graphdb_api_language_service_client:register_language(
        #{code => "es", name => "Spanish"}, #{channel => ?MODULE}),
    {ok, NameAttr} = graphdb_attr:create_name_attribute("labelTarget"),
    Label = #{attribute => NameAttr, value => graphdb_api_value:term_to_value("hola")},
    {ok, #{}, _} = graphdb_api_language_service_client:set_labels(
        #{nref => NameAttr, code => "es", labels => [Label]}, #{channel => ?MODULE}),
    {ok, #{chain := ChainPb}, _} = graphdb_api_language_service_client:make_chain(
        #{codes => ["es"]}, #{channel => ?MODULE}),
    {ok, #{label := LabelPb}, _} = graphdb_api_language_service_client:resolve_label(
        #{nref => NameAttr, attr_nref => NameAttr, chain => ChainPb}, #{channel => ?MODULE}),
    ?assertEqual("hola", graphdb_api_value:value_to_term(LabelPb)),
    LangNref =/= undefined orelse ct:fail(language_registration_failed).
