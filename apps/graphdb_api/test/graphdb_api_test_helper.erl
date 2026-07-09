%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: Shared Common Test helper for graphdb_api service
%%              suites. Boots an isolated-Mnesia-dir copy of the full
%%              graphdb worker stack (mirroring graphdb_sup's real
%%              child order — apps/graphdb/src/graphdb_sup.erl) plus a
%%              dynamically-started in-process grpcbox server, so every
%%              service suite exercises real Mnesia + a real HTTP/2
%%              round trip, never a mock.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: stack + grpcbox server lifecycle helpers.
%%---------------------------------------------------------------------
-module(graphdb_api_test_helper).

-export([start_stack/1, stop_stack/1,
         start_grpc/3, stop_grpc/1,
         start_client/2, stop_client/1,
         port_for/1]).

-define(SCRATCH_SENTINEL, "_build/test/ct_scratch/").
-define(DIR_PREFIX, "graphdb_api_").

%%-----------------------------------------------------------------------------
%% start_stack(Config) -> Config1
%%-----------------------------------------------------------------------------
start_stack(Config) ->
    {ok, OrigCwd} = file:get_cwd(),
    ok = ensure_loaded(graphdb),
    PrivDir = code:priv_dir(graphdb),
    BootstrapFile = filename:join(PrivDir, "bootstrap.terms"),
    true = filelib:is_file(BootstrapFile),

    Unique = integer_to_list(erlang:unique_integer([positive, monotonic])),
    TmpDir = filename:join([OrigCwd, "_build", "test", "ct_scratch",
        ?DIR_PREFIX ++ Unique]),
    MnesiaDir = filename:join(TmpDir, "mnesia"),
    ok = filelib:ensure_dir(filename:join(MnesiaDir, "x")),
    ok = file:set_cwd(TmpDir),
    application:set_env(mnesia, dir, MnesiaDir),
    application:set_env(seerstone_graph_db, bootstrap_file, BootstrapFile),
    {ok, _} = application:ensure_all_started(nref),

    {ok, _} = rel_id_server:start_link(),
    graphdb_nref:set_permanent_phase(),
    {ok, _} = graphdb_nref:start_link(),
    {ok, _} = graphdb_mgr:start_link(),
    {ok, _} = graphdb_attr:start_link(),
    {ok, _} = graphdb_class:start_link(),
    {ok, _} = graphdb_instance:start_link(),
    {ok, _} = graphdb_language:start_link(),
    {ok, _} = graphdb_query:start_link(),
    {ok, _} = graphdb_rules:start_link(),
    ok = graphdb_nref:set_runtime_phase(),

    [{orig_cwd, OrigCwd}, {tmp_dir, TmpDir}, {mnesia_dir, MnesiaDir} | Config].

%%-----------------------------------------------------------------------------
%% stop_stack(Config) -> ok
%%-----------------------------------------------------------------------------
stop_stack(Config) ->
    catch gen_server:stop(graphdb_rules),
    catch gen_server:stop(graphdb_query),
    catch gen_server:stop(graphdb_language),
    catch gen_server:stop(graphdb_instance),
    catch gen_server:stop(graphdb_class),
    catch gen_server:stop(graphdb_attr),
    catch gen_server:stop(graphdb_mgr),
    catch gen_server:stop(graphdb_nref),
    catch persistent_term:erase({graphdb_nref, phase}),
    catch gen_server:stop(rel_id_server),
    catch application:stop(nref),
    catch mnesia:stop(),
    catch dets:close(nref_server),
    catch dets:close(nref_allocator),
    catch dets:close(rel_id_server),

    OrigCwd = proplists:get_value(orig_cwd, Config),
    ok = file:set_cwd(OrigCwd),
    TmpDir = proplists:get_value(tmp_dir, Config),
    delete_dir_recursive(TmpDir),

    application:unset_env(seerstone_graph_db, bootstrap_file),
    application:unset_env(mnesia, dir),
    ok.

%%-----------------------------------------------------------------------------
%% start_grpc(Module, ServiceProtos, Services) -> {ok, ListenOpts}
%%
%% Module    :: atom()   -- the calling CT suite's ?MODULE, used to derive
%%                          a deterministic port (avoids collisions between
%%                          parallel CT suite OS processes).
%% ServiceProtos :: [module()] -- e.g. [node_service_pb]. NEVER include
%%                          common_pb (no service block -- see Global
%%                          Constraints).
%% Services  :: #{atom() => module()} -- e.g.
%%              #{'graphdb_api.NodeService' => graphdb_api_node_service_impl}
%%-----------------------------------------------------------------------------
start_grpc(Module, ServiceProtos, Services) ->
    {ok, _} = application:ensure_all_started(grpcbox),
    ListenOpts = #{port => port_for(Module), ip => {127, 0, 0, 1}},
    {ok, _Pid} = grpcbox:start_server(
        #{grpc_opts => #{service_protos => ServiceProtos,
                          services => Services},
          listen_opts => ListenOpts}),
    {ok, ListenOpts}.

%%-----------------------------------------------------------------------------
%% stop_grpc(ListenOpts) -> ok
%%-----------------------------------------------------------------------------
stop_grpc(ListenOpts) ->
    grpcbox_services_simple_sup:terminate_child(ListenOpts).

%%-----------------------------------------------------------------------------
%% start_client(Module, Port) -> {ok, Module}
%%
%% Starts a grpcbox_channel named `Module`, pointed at the local grpcbox
%% server on `Port`. Verified signature: start_link/3 takes a *list* of
%% {Transport, Host, Port, SslOpts} endpoint tuples, not positional
%% host/port arguments.
%%-----------------------------------------------------------------------------
start_client(Module, Port) ->
    {ok, _ChPid} = grpcbox_channel:start_link(
        Module, [{http, "127.0.0.1", Port, []}], #{}),
    {ok, Module}.

%%-----------------------------------------------------------------------------
%% stop_client(Module) -> ok
%%-----------------------------------------------------------------------------
stop_client(Module) ->
    catch grpcbox_channel:stop(Module),
    ok.

%%-----------------------------------------------------------------------------
%% port_for(Module) -> inet:port_number()
%%-----------------------------------------------------------------------------
port_for(Module) ->
    50000 + erlang:phash2(Module, 5000).

%%-----------------------------------------------------------------------------
%% Internal
%%-----------------------------------------------------------------------------
ensure_loaded(App) ->
    case application:load(App) of
        ok                             -> ok;
        {error, {already_loaded, App}} -> ok
    end.

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
