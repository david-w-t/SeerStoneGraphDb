%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-11-16
%% Description: Startup profile for the graphdb application.  begin_profile/0
%%				opens a profile at the top of graphdb:start/2; timed/2
%%				and start_child/1 record how long each boot phase took
%%				(Mnesia table load, each worker's init/1, the runtime
%%				flip, the seed cache load); finish/0 logs one summary
%%				line with every phase, the total and the environment
%%				table sizes.  The line is a warning when the total
%%				exceeds the startup_warn_ms setting of the
%%				seerstone_graph_db application (default 2000 ms),
%%				otherwise info.  Outside a profiled boot (a worker
%%				restart, a test that starts workers directly) timed/2
%%				and start_child/1 only run their work.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-11-16 Author: David W. Thomas
%% Initial implementation.
%%---------------------------------------------------------------------

-module(graphdb_startup).

-revision('Rev PA1').
-created('2026-11-16').
-created_by('David W. Thomas').

-export([begin_profile/0, timed/2, start_child/1, finish/0, discard/0]).

%%---------------------------------------------------------------------
%% NYI / UEM Macros
%%---------------------------------------------------------------------
-define(NYI(X), (begin
	io:format("*** NYI ~p ~p ~p~n",[?MODULE, ?LINE, X]),
	exit(nyi)
end)).
-define(UEM(F, X), (begin
	io:format("*** UEM ~p:~p ~p ~p~n",[?MODULE, F, ?LINE, X]),
	exit(uem)
end)).

%% Public named ETS table: phases are recorded from several processes
%% (graphdb_sup starts the children; graphdb_mgr's init/1 runs the
%% bootstrap).  It is owned by the process running graphdb:start/2 and
%% exists only between begin_profile/0 and finish/0 or discard/0.
-define(TAB, graphdb_startup_profile).
-define(DEFAULT_WARN_MS, 2000).


%%---------------------------------------------------------------------
%% begin_profile() -> ok
%%
%% Opens a fresh profile, dropping any left by an earlier failed start.
%%---------------------------------------------------------------------
begin_profile() ->
	ok = discard(),
	_ = ets:new(?TAB, [named_table, public, ordered_set]),
	true = ets:insert(?TAB, {start, now_us()}),
	ok.


%%---------------------------------------------------------------------
%% timed(Phase, Fun) -> Fun()
%%
%% Runs Fun and, inside a profiled boot, records its duration under
%% Phase (an atom).  Fun's result, or exception, passes through.
%%---------------------------------------------------------------------
timed(Phase, Fun) when is_atom(Phase), is_function(Fun, 0) ->
	T0 = now_us(),
	try Fun()
	after
		record(Phase, now_us() - T0)
	end.


%%---------------------------------------------------------------------
%% start_child(Module) -> Module:start_link()
%%
%% Supervisor start function for graphdb_sup's children: the duration
%% recorded is the child's whole init/1.
%%---------------------------------------------------------------------
start_child(Module) when is_atom(Module) ->
	timed(Module, fun() -> Module:start_link() end).


%%---------------------------------------------------------------------
%% finish() -> ok
%%
%% Logs the summary line and closes the profile.  The line carries the
%% figures as metadata (startup_profile => #{total_ms, phases, nodes,
%% relationships, vm_uptime_ms, warn_ms}) for tools and tests.
%% vm_uptime_ms is how long the VM had been running when graphdb became
%% ready: it also covers what happened before graphdb:start/2, such as
%% Mnesia starting up.
%%---------------------------------------------------------------------
finish() ->
	case profile() of
		undefined ->
			ok;
		{StartUs, Phases} ->
			TotalMs = to_ms(now_us() - StartUs),
			ok = discard(),
			WarnMs = warn_ms(),
			Nodes = table_size(nodes),
			Rels = table_size(relationships),
			{UptimeMs, _} = erlang:statistics(wall_clock),
			Profile = #{total_ms => TotalMs, phases => Phases,
				nodes => Nodes, relationships => Rels,
				vm_uptime_ms => UptimeMs, warn_ms => WarnMs},
			{Level, Suffix} = case TotalMs > WarnMs of
				true  -> {warning, io_lib:format(
					" -- over the ~p ms startup_warn_ms threshold", [WarnMs])};
				false -> {info, ""}
			end,
			logger:log(Level,
				"graphdb startup: ~.1f ms total (nodes ~p, relationships ~p,"
				" VM up ~p ms); phases (ms): ~ts~ts",
				[TotalMs, Nodes, Rels, UptimeMs, format_phases(Phases), Suffix],
				#{startup_profile => Profile}),
			ok
	end.


%%---------------------------------------------------------------------
%% discard() -> ok
%%
%% Closes the profile without logging (a failed start).
%%---------------------------------------------------------------------
discard() ->
	case ets:whereis(?TAB) of
		undefined -> ok;
		_ ->
			catch ets:delete(?TAB),
			ok
	end.


%%=====================================================================
%% Internal Functions
%%=====================================================================

%% Phase rows are keyed by a monotonic integer, so they read back in the
%% order the phases finished: a phase nested inside another (bootstrap
%% steps inside graphdb_mgr) is listed just before it, and the outer
%% phase's duration includes it.
record(Phase, Us) ->
	case ets:whereis(?TAB) of
		undefined -> ok;
		_ ->
			Key = {phase, erlang:unique_integer([monotonic])},
			catch ets:insert(?TAB, {Key, Phase, to_ms(Us)}),
			ok
	end.

profile() ->
	case ets:whereis(?TAB) of
		undefined -> undefined;
		_ ->
			[{start, StartUs}] = ets:lookup(?TAB, start),
			Phases = [{Phase, Ms} ||
				{{phase, _}, Phase, Ms} <- ets:tab2list(?TAB)],
			{StartUs, Phases}
	end.

format_phases(Phases) ->
	lists:join(", ",
		[io_lib:format("~p ~.1f", [Phase, Ms]) || {Phase, Ms} <- Phases]).

warn_ms() ->
	case application:get_env(seerstone_graph_db, startup_warn_ms) of
		{ok, Ms} when is_integer(Ms), Ms >= 0 -> Ms;
		_                                     -> ?DEFAULT_WARN_MS
	end.

table_size(Tab) ->
	case catch mnesia:table_info(Tab, size) of
		N when is_integer(N) -> N;
		_                    -> unknown
	end.

now_us() ->
	erlang:monotonic_time(microsecond).

to_ms(Us) ->
	Us / 1000.
