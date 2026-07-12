%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-12
%% Description: Proves the REAL config/sys.config `grpcbox` `servers`
%%              entry boots correctly via grpcbox's own application-start
%%              auto-start mechanism (grpcbox_app:start/2 reads
%%              application:get_env(grpcbox, servers) and calls
%%              grpcbox_services_simple_sup:start_child/1 per entry --
%%              see _build/default/lib/grpcbox/src/grpcbox_app.erl).
%%
%%              Every other suite in this app boots its grpcbox listener
%%              via the programmatic grpcbox:start_server/1 API
%%              (graphdb_api_test_helper:start_grpc/3), which never
%%              exercises this auto-start path -- a manual edit to
%%              config/sys.config that made it syntactically invalid, or
%%              a mismatched module name in its `servers` entry, would
%%              only surface at real release boot time. This suite reads
%%              the actual config/sys.config file, installs its `grpcbox`
%%              env exactly as a release's boot script would, and starts
%%              the `grpcbox` application for real so grpcbox_app:start/2
%%              runs its `maybe_start_server/1` against that real data.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-12 Author: David W. Thomas
%% Initial implementation: sys.config-driven grpcbox auto-start coverage
%% (Task 13 review finding fix).
%%---------------------------------------------------------------------
-module(graphdb_api_sys_config_boot_SUITE).

-revision('Revision: PA1 ').
-created('Date: 2026-07-12').
-created_by('david@davidwt.com').

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, suite/0]).
-export([init_per_testcase/2, end_per_testcase/2]).
-export([sys_config_grpcbox_servers_entry_boots_and_answers/1]).

-define(REPO_MARKER, "rebar.config").

suite() -> [{timetrap, {seconds, 30}}].

all() -> [sys_config_grpcbox_servers_entry_boots_and_answers].

%%-----------------------------------------------------------------------------
%% init_per_testcase/2
%%
%% Reads config/sys.config's real `grpcbox` `servers` entry (locating the
%% repo root via code:lib_dir/1 + an upward walk to the rebar.config
%% marker, since Common Test's own working directory during a run is its
%% log directory, not the invocation directory -- file:get_cwd/0 is not
%% reliable here), stops grpcbox if some earlier suite already started it
%% (its own start/2 was already run with a different -- typically empty
%% -- `servers` env, so a bare ensure_all_started/1 here would be a
%% silent no-op), installs the real config as the `grpcbox` application
%% env, then starts it for real so grpcbox_app:start/2 ->
%% maybe_start_server/1 runs against that real data.
%%-----------------------------------------------------------------------------
init_per_testcase(_TC, Config0) ->
    RepoRoot = find_repo_root(code:lib_dir(graphdb_api)),
    SysConfigPath = filename:join(RepoRoot, "config/sys.config"),
    {ok, [Terms]} = file:consult(SysConfigPath),
    {grpcbox, GrpcboxEnv} = lists:keyfind(grpcbox, 1, Terms),
    {servers, Servers} = lists:keyfind(servers, 1, GrpcboxEnv),
    [Server] = Servers,
    ListenOpts = maps:get(listen_opts, Server),

    catch application:stop(grpcbox),
    ok = application:set_env(grpcbox, servers, Servers),

    Config1 = graphdb_api_test_helper:start_stack(Config0),
    {ok, _} = application:ensure_all_started(grpcbox),

    #{port := Port} = ListenOpts,
    {ok, ?MODULE} = graphdb_api_test_helper:start_client(?MODULE, Port),
    [{listen_opts, ListenOpts} | Config1].

end_per_testcase(_TC, Config) ->
    graphdb_api_test_helper:stop_client(?MODULE),
    graphdb_api_test_helper:stop_grpc(proplists:get_value(listen_opts, Config)),
    application:unset_env(grpcbox, servers),
    graphdb_api_test_helper:stop_stack(Config),
    ok.

%%-----------------------------------------------------------------------------
%% grpcbox dispatches lazily at call-time, not eagerly at listener boot --
%% confirmed empirically: a deliberately typo'd module name in
%% config/sys.config's `services` map (e.g.
%% 'graphdb_api.NodeService' => graphdb_api_node_service_impl_TYPO) still
%% lets init_per_testcase's listener start and client connect; the RPC
%% only fails ("Method not found on server") when that specific service
%% is called. So a single call only behaviorally verifies ONE service's
%% sys.config module-name mapping. To actually close the review finding
%% ("a mismatched module name that testing missed") for all 8 registered
%% services, call all 8 -- one RPC per service, mirroring the proven call
%% sequence in graphdb_api_e2e_SUITE:all_eight_services_answer_on_one_listener/1,
%% just against the sys.config-auto-started listener instead of the
%% programmatic one.
%%-----------------------------------------------------------------------------
sys_config_grpcbox_servers_entry_boots_and_answers(_Config) ->
    Opts = #{channel => ?MODULE},

    {ok, #{node := #{nref := 1}}, _} =
        graphdb_api_node_service_client:get_node(#{nref => 1}, Opts),

    {ok, #{project_id := ProjId}, _} =
        graphdb_api_project_service_client:register_project(#{name => "SysCfgBoot"}, Opts),
    {ok, #{is_project := true}, _} =
        graphdb_api_project_service_client:is_project(#{nref => ProjId}, Opts),

    {ok, #{nref := ClassNref}, _} =
        graphdb_api_class_service_client:create_class(
            #{name => "SysCfgWidget", parent_class_nref => 3, avps => []}, Opts),

    {ok, #{nref := AttrNref}, _} =
        graphdb_api_attribute_service_client:create_name_attribute(
            #{name => "sysCfgName", parent_nref => 0}, Opts),
    ?assert(is_integer(AttrNref)),

    Mult = #{min => 0, max => 0, unbounded => true},
    {ok, #{rule_nref := _}, _} =
        graphdb_api_rules_service_client:create_composition_rule(
            #{name => "syscfg-rule", parent_class => ClassNref, child_class => ClassNref,
              mode => 'PROPOSE', multiplicity => Mult, template_nref => 0, name_pattern => ""},
            Opts),

    {ok, #{nref := LangNref}, _} =
        graphdb_api_language_service_client:register_language(
            #{code => "sc", name => "SysCfg Lang"}, Opts),
    ?assert(is_integer(LangNref)),

    {ok, #{nref := InstNref, report := _}, _} =
        graphdb_api_instance_service_client:create_instance(
            #{project_id => ProjId, name => "syscfg-inst", class_nref => ClassNref,
              parent_nref => ProjId},
            Opts),

    {ok, #{found := _}, _} =
        graphdb_api_query_service_client:find_path(
            #{from => ProjId, to => InstNref, max_depth => 5}, Opts).

%%-----------------------------------------------------------------------------
%% Internal
%%-----------------------------------------------------------------------------
find_repo_root(Dir) ->
    Marker = filename:join(Dir, ?REPO_MARKER),
    case filelib:is_file(Marker) of
        true ->
            Dir;
        false ->
            case filename:dirname(Dir) of
                Dir ->
                    error({repo_root_not_found, ?REPO_MARKER});
                Parent ->
                    find_repo_root(Parent)
            end
    end.
