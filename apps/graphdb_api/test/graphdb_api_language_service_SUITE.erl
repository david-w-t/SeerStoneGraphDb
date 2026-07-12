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
%% Rev PA2 Date: 2026-07-11 Author: David W. Thomas
%% Task 10 review fix regression coverage: lookup/set_labels/make_chain
%% error paths for a never-registered code (binary_to_existing_atom/2
%% must reject cleanly, not mint an atom and not crash).
%%---------------------------------------------------------------------
-module(graphdb_api_language_service_SUITE).

-revision('Revision: PA2 ').
-created('Date: 2026-07-08').
-created_by('david@davidwt.com').

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0, suite/0]).
-export([init_per_testcase/2, end_per_testcase/2]).
-export([register_language_then_lookup/1,
         register_dialect_of_known_base/1,
         set_labels_then_resolve_via_chain/1,
         lookup_unregistered_code_returns_not_found/1,
         set_labels_unregistered_code_returns_unregistered_language/1,
         make_chain_drops_unregistered_code/1]).

suite() -> [{timetrap, {seconds, 30}}].

all() -> [register_language_then_lookup,
          register_dialect_of_known_base,
          set_labels_then_resolve_via_chain,
          lookup_unregistered_code_returns_not_found,
          set_labels_unregistered_code_returns_unregistered_language,
          make_chain_drops_unregistered_code].

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

%% Task 10 review fix: LookupLanguageNref must not mint an atom from
%% client input, including on a failed lookup of a code that was never
%% registered. existing_code_to_atom/1 rejects the binary via
%% binary_to_existing_atom/2 (no such atom exists) and the RPC returns
%% the same not_found error graphdb_language:lookup_language_nref/1
%% itself would return for a registered-but-atom code that isn't a
%% lang_code_map key -- routed through graphdb_api_error:to_status/1,
%% which curates `not_found` to gRPC NOT_FOUND (5). Must not crash.
lookup_unregistered_code_returns_not_found(_Config) ->
    {error, {Status, _Msg}, _Meta} =
        graphdb_api_language_service_client:lookup_language_nref(
            #{code => "zz-never-registered-lookup"}, #{channel => ?MODULE}),
    ?assertEqual(grpcbox_stream:code_to_status(5), Status).

%% Task 10 review fix: SetLabels must not mint an atom for its Code
%% argument either. A never-registered code returns the same
%% `unregistered_language` error graphdb_language:set_labels/3 itself
%% returns for it (State#state.lang_code_map without that key), routed
%% through the same to_status/1 chokepoint as every other error path.
%% `unregistered_language` is not a curated reason in
%% graphdb_api_error's status table, so it falls through to the
%% INTERNAL(13) catch-all -- this asserts the error routes cleanly (no
%% crash, no minted atom), not a specific curated status.
set_labels_unregistered_code_returns_unregistered_language(_Config) ->
    {ok, NameAttr} = graphdb_attr:create_name_attribute("labelTarget2"),
    Label = #{attribute => NameAttr, value => graphdb_api_value:term_to_value("hola")},
    {error, {Status, _Msg}, _Meta} = graphdb_api_language_service_client:set_labels(
        #{nref => NameAttr, code => "zz-never-registered-setlabels",
          labels => [Label]}, #{channel => ?MODULE}),
    ?assertEqual(grpcbox_stream:code_to_status(13), Status).

%% Task 10 review fix: MakeChain's `codes` field is `repeated string` --
%% a single call could otherwise mint an unbounded number of atoms
%% (batch amplification). A never-registered code must be silently
%% dropped from the chain, exactly like
%% graphdb_language:make_chain/1's own "drop unknown, don't crash"
%% contract for a code that's already an atom but not a lang_code_map
%% key -- not error the whole RPC. Confirmed by comparing the decoded
%% chain from a call mixing one registered and one never-registered
%% code against the chain from a call with only the registered code.
make_chain_drops_unregistered_code(_Config) ->
    {ok, _, _} = graphdb_api_language_service_client:register_language(
        #{code => "it", name => "Italian"}, #{channel => ?MODULE}),
    {ok, #{chain := MixedChainPb}, _} = graphdb_api_language_service_client:make_chain(
        #{codes => ["it", "zz-never-registered-makechain"]}, #{channel => ?MODULE}),
    {ok, #{chain := PureChainPb}, _} = graphdb_api_language_service_client:make_chain(
        #{codes => ["it"]}, #{channel => ?MODULE}),
    ?assertEqual(graphdb_api_value:value_to_term(PureChainPb),
                 graphdb_api_value:value_to_term(MixedChainPb)).
