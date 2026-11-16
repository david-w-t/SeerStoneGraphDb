%%---------------------------------------------------------------------
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-11-16
%% Description: Common Test suite for graphdb_startup, the boot-time
%%				profile logged by graphdb:start/2.  Each case boots the
%%				real graphdb application on an isolated empty data
%%				directory and captures the profile line with a logger
%%				handler (this module's log/2).
%%---------------------------------------------------------------------
-module(graphdb_startup_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([
	all/0,
	suite/0,
	init_per_suite/1,
	end_per_suite/1,
	init_per_testcase/2,
	end_per_testcase/2
]).

-export([
	boot_logs_one_profile_line/1,
	slow_boot_logs_a_warning/1,
	warm_restart_profiles_without_bootstrap_load/1,
	timed_outside_a_boot_only_runs_the_fun/1
]).

%% logger handler callback
-export([log/2]).

-define(HANDLER, graphdb_startup_probe).

%% Every graphdb_sup child, in start order.
-define(CHILDREN, [graphdb_nref, rel_id_server, graphdb_mgr, graphdb_attr,
	graphdb_class, graphdb_instance, graphdb_language, graphdb_query,
	graphdb_rules]).

suite() ->
	[{timetrap, {seconds, 60}}].

all() ->
	[boot_logs_one_profile_line,
	 slow_boot_logs_a_warning,
	 warm_restart_profiles_without_bootstrap_load,
	 timed_outside_a_boot_only_runs_the_fun].


%%-----------------------------------------------------------------------------
%% init_per_suite/1
%%-----------------------------------------------------------------------------
init_per_suite(Config) ->
	{ok, OrigCwd} = file:get_cwd(),
	ok = ensure_loaded(graphdb),
	BootstrapFile = filename:join(code:priv_dir(graphdb), "bootstrap.terms"),
	true = filelib:is_file(BootstrapFile),
	[{orig_cwd, OrigCwd}, {bootstrap_file, BootstrapFile} | Config].

end_per_suite(_Config) ->
	ok.


%%-----------------------------------------------------------------------------
%% init_per_testcase/2
%%-----------------------------------------------------------------------------
init_per_testcase(timed_outside_a_boot_only_runs_the_fun, Config) ->
	Config;
init_per_testcase(_TC, Config) ->
	OrigCwd = proplists:get_value(orig_cwd, Config),
	Unique = integer_to_list(erlang:unique_integer([positive, monotonic])),
	TmpDir = filename:join([OrigCwd, "_build", "test", "ct_scratch",
		"startup_" ++ Unique]),
	MnesiaDir = filename:join(TmpDir, "mnesia"),
	ok = filelib:ensure_dir(filename:join(MnesiaDir, "x")),
	%% nref and rel_id_server keep their DETS files in the cwd.
	ok = file:set_cwd(TmpDir),
	application:set_env(mnesia, dir, MnesiaDir),
	application:set_env(graphdb, bootstrap_file,
		proplists:get_value(bootstrap_file, Config)),
	%% A boot under CT load may approach the 2000 ms default; cases that
	%% expect info set a threshold no boot here reaches.
	application:set_env(graphdb, startup_warn_ms, 60000),
	#{level := PrimaryLevel} = logger:get_primary_config(),
	ok = logger:set_primary_config(level, info),
	ok = logger:add_handler(?HANDLER, ?MODULE,
		#{level => all, config => #{pid => self()}}),
	[{tmp_dir, TmpDir}, {primary_level, PrimaryLevel} | Config].


%%-----------------------------------------------------------------------------
%% end_per_testcase/2
%%-----------------------------------------------------------------------------
end_per_testcase(timed_outside_a_boot_only_runs_the_fun, _Config) ->
	ok;
end_per_testcase(_TC, Config) ->
	catch logger:remove_handler(?HANDLER),
	catch logger:set_primary_config(level,
		proplists:get_value(primary_level, Config)),
	catch application:stop(graphdb),
	catch graphdb_seeds:erase(),
	catch application:stop(mnesia),
	catch application:stop(nref),
	catch dets:close(nref_server),
	catch dets:close(nref_allocator),
	catch dets:close(rel_id_server),
	ok = file:set_cwd(proplists:get_value(orig_cwd, Config)),
	delete_dir_recursive(proplists:get_value(tmp_dir, Config)),
	application:unset_env(graphdb, bootstrap_file),
	application:unset_env(graphdb, startup_warn_ms),
	application:unset_env(mnesia, dir),
	ok.


%%=============================================================================
%% Test cases
%%=============================================================================

%% A first boot logs exactly one profile line, at info, naming every
%% phase in the order it finished, and closes the profile.
boot_logs_one_profile_line(_Config) ->
	{ok, _} = application:ensure_all_started(graphdb),
	{info, Profile} = next_profile(),
	?assertEqual(none, next_profile(0)),
	#{total_ms := Total, phases := Phases, nodes := Nodes,
	  relationships := Rels, vm_uptime_ms := Uptime,
	  warn_ms := WarnMs} = Profile,
	?assertEqual(60000, WarnMs),
	?assert(Uptime >= Total),
	?assertEqual(Nodes, mnesia:table_info(nodes, size)),
	?assertEqual(Rels, mnesia:table_info(relationships, size)),
	?assert(Nodes > 0),
	Names = [P || {P, _} <- Phases],
	%% The bootstrap steps run inside graphdb_mgr's init/1, so they
	%% finish just before it.
	Expected = [graphdb_nref, rel_id_server,
		ensure_mnesia, create_tables, wait_for_tables, bootstrap_load,
		graphdb_mgr, graphdb_attr, graphdb_class, graphdb_instance,
		graphdb_language, graphdb_query, graphdb_rules,
		runtime_flip, seed_cache],
	?assertEqual(Expected, Names),
	lists:foreach(fun({_, Ms}) -> ?assert(Ms >= 0) end, Phases),
	TopLevel = lists:sum([Ms || {P, Ms} <- Phases,
		lists:member(P, ?CHILDREN ++ [runtime_flip, seed_cache])]),
	?assert(Total >= TopLevel),
	?assertEqual(undefined, ets:whereis(graphdb_startup_profile)).

%% A boot longer than startup_warn_ms logs the same line as a warning.
slow_boot_logs_a_warning(_Config) ->
	application:set_env(graphdb, startup_warn_ms, 0),
	{ok, _} = application:ensure_all_started(graphdb),
	{warning, #{warn_ms := 0, total_ms := Total}} = next_profile(),
	?assert(Total > 0).

%% A second boot on the same data skips the bootstrap load and runs the
%% stale-data check instead; the profile opened by the first boot does not
%% leak into the second.
warm_restart_profiles_without_bootstrap_load(_Config) ->
	{ok, _} = application:ensure_all_started(graphdb),
	{info, #{nodes := Nodes}} = next_profile(),
	ok = application:stop(graphdb),
	{ok, _} = application:ensure_all_started(graphdb),
	{info, #{nodes := Nodes2, phases := Phases}} = next_profile(),
	?assertEqual(Nodes, Nodes2),
	Names = [P || {P, _} <- Phases],
	?assertNot(lists:member(bootstrap_load, Names)),
	?assert(lists:member(wait_for_tables, Names)),
	%% The warm boot checks the stored data against the bootstrap file.
	?assert(lists:member(stale_data_check, Names)),
	?assertEqual(1, length([P || P <- Names, P =:= graphdb_mgr])).

%% With no profile open (a worker restart, a test starting workers
%% directly), timed/2 runs the fun and passes its result or exception
%% through; finish/0 logs nothing.
timed_outside_a_boot_only_runs_the_fun(_Config) ->
	?assertEqual(undefined, ets:whereis(graphdb_startup_profile)),
	?assertEqual(42, graphdb_startup:timed(anything, fun() -> 42 end)),
	?assertError(boom,
		graphdb_startup:timed(anything, fun() -> error(boom) end)),
	?assertEqual(ok, graphdb_startup:finish()),
	?assertEqual(undefined, ets:whereis(graphdb_startup_profile)).


%%=============================================================================
%% logger handler: forwards profile lines to the test case process
%%=============================================================================

log(#{level := Level, meta := #{startup_profile := Profile}},
		#{config := #{pid := Pid}}) ->
	Pid ! {startup_profile, Level, Profile},
	ok;
log(_Event, _Config) ->
	ok.

next_profile() ->
	case next_profile(5000) of
		none  -> ct:fail(no_startup_profile_logged);
		Found -> Found
	end.

next_profile(Timeout) ->
	receive
		{startup_profile, Level, Profile} -> {Level, Profile}
	after Timeout ->
		none
	end.


%%=============================================================================
%% Helpers
%%=============================================================================

ensure_loaded(App) ->
	case application:load(App) of
		ok                             -> ok;
		{error, {already_loaded, App}} -> ok
	end.

-define(SCRATCH_SENTINEL, "_build/test/ct_scratch/").
-define(DIR_PREFIX, "startup_").

delete_dir_recursive(Dir) ->
	case is_safe_scratch_dir(Dir) of
		true  -> do_delete_dir(Dir);
		false -> error({unsafe_delete, Dir})
	end.

is_safe_scratch_dir(Dir) ->
	Abs = filename:absname(Dir),
	IsAbsolute = (Abs =:= Dir),
	ContainsSentinel = (string:find(Dir, ?SCRATCH_SENTINEL) =/= nomatch),
	Leaf = filename:basename(Dir),
	HasPrefix = lists:prefix(?DIR_PREFIX, Leaf),
	IsAbsolute andalso ContainsSentinel andalso HasPrefix.

do_delete_dir(Dir) ->
	case filelib:is_dir(Dir) of
		true ->
			{ok, Entries} = file:list_dir(Dir),
			lists:foreach(fun(E) ->
				Path = filename:join(Dir, E),
				case filelib:is_dir(Path) of
					true  -> do_delete_dir(Path);
					false -> file:delete(Path)
				end
			end, Entries),
			file:del_dir(Dir);
		false ->
			ok
	end.
