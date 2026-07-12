-module(graphdb_api_query_service_SUITE).

-revision('Revision: PA1 ').
-created('Date: 2026-07-08').
-created_by('david@davidwt.com').

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0, suite/0]).
-export([init_per_testcase/2, end_per_testcase/2]).
-export([find_path_between_composition_parent_and_child/1,
         find_path_reports_no_path_when_unreachable/1]).

suite() -> [{timetrap, {seconds, 30}}].

all() -> [find_path_between_composition_parent_and_child,
          find_path_reports_no_path_when_unreachable].

init_per_testcase(_TC, Config0) ->
    Config1 = graphdb_api_test_helper:start_stack(Config0),
    {ok, ListenOpts} = graphdb_api_test_helper:start_grpc(
        ?MODULE, [query_service_pb],
        #{'graphdb_api.QueryService' => graphdb_api_query_service_impl}),
    #{port := Port} = ListenOpts,
    {ok, ?MODULE} = graphdb_api_test_helper:start_client(?MODULE, Port),
    [{listen_opts, ListenOpts} | Config1].

end_per_testcase(_TC, Config) ->
    graphdb_api_test_helper:stop_client(?MODULE),
    graphdb_api_test_helper:stop_grpc(proplists:get_value(listen_opts, Config)),
    graphdb_api_test_helper:stop_stack(Config),
    ok.

find_path_between_composition_parent_and_child(_Config) ->
    {ok, ProjNref} = graphdb_project:register_project("Acme8"),
    {ok, ClassNref} = graphdb_class:create_class("Widget8", 3),
    {ok, Session} = graphdb_project:open_session(ProjNref),
    {ok, Parent, _} = graphdb_instance:create_instance(Session, "parent8", ClassNref, ProjNref),
    {ok, Child, _} = graphdb_instance:create_instance(Session, "child8", ClassNref, Parent),
    {ok, #{found := true, path := Path}, _} = graphdb_api_query_service_client:find_path(
        #{from => Parent, to => Child, max_depth => 5}, #{channel => ?MODULE}),
    ?assertEqual(Parent, hd(Path)),
    ?assertEqual(Child, lists:last(Path)).

%% Two instances in two DIFFERENT projects are genuinely BFS-disconnected:
%% each instance's only composition arc is to its own project anchor, and
%% the anchors' only further composition arc is to the shared `Projects`
%% category (nref 5), which is a scaffold node (is_scaffold_node/1) and is
%% never traversed (graphdb_query:expand_arcs/8). So the frontier empties
%% out after two hops, well within max_depth => 5, and bfs/8 hits its
%% first clause (frontier == []) -- the genuine {ok, no_path} branch --
%% rather than the depth-exhausted {partial, ...} branch.
find_path_reports_no_path_when_unreachable(_Config) ->
    {ok, ProjNrefA} = graphdb_project:register_project("Acme9a"),
    {ok, ProjNrefB} = graphdb_project:register_project("Acme9b"),
    {ok, ClassNref} = graphdb_class:create_class("Widget9", 3),
    {ok, SessionA} = graphdb_project:open_session(ProjNrefA),
    {ok, SessionB} = graphdb_project:open_session(ProjNrefB),
    {ok, A, _} = graphdb_instance:create_instance(SessionA, "a9", ClassNref, ProjNrefA),
    {ok, B, _} = graphdb_instance:create_instance(SessionB, "b9", ClassNref, ProjNrefB),
    {ok, #{found := false, path := []}, _} = graphdb_api_query_service_client:find_path(
        #{from => A, to => B, max_depth => 5}, #{channel => ?MODULE}).
