%%---------------------------------------------------------------------
%% Copyright SeerStone, Inc. 2008
%%
%% All rights reserved. No part of this computer programs(s) may be
%% used, reproduced,stored in any retrieval system, or transmitted,
%% in any form or by any means, electronic, mechanical, photocopying,
%% recording, or otherwise without prior written permission of
%% SeerStone, Inc.
%%---------------------------------------------------------------------
%% Author: Dallas Noyes
%% Created: *** 2008
%% Description: graphdb_instance manages graph node and edge instances.
%%				graphdb_instance is responsible for the creation, storage,
%%				retrieval, and deletion of individual graph nodes and edges.
%%				Graph nodes are identified by Nrefs (globally unique integers)
%%				allocated by the nref application.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Stub implementation.
%% Rev A Date: March 19, 2026 Author: AI
%% Full implementation of node and edge CRUD operations.
%%---------------------------------------------------------------------
-module(graphdb_instance).
-behaviour(gen_server).

%%---------------------------------------------------------------------
%% Module Attributes
%%---------------------------------------------------------------------
-revision('Revision: A ').
-created('Date: March 19, 2026').
-created_by('dallas.noyes@gmail.com').

%%---------------------------------------------------------------------
%% Include files
%%---------------------------------------------------------------------
-include_lib("kernel/include/logger.hrl").

%%---------------------------------------------------------------------
%% Macro Functions
%%---------------------------------------------------------------------
-define(NYI(F), (begin
					io:format("*** NYI ~p ~p ~p~n",[?MODULE, ?LINE, F]),
					exit(nyi)
				 end)).
-define(UEM(F, X), (begin
					io:format("*** UEM ~p:~p ~p ~p~n",[?MODULE, F, ?LINE, X]),
					exit(uem)
				 end)).

-define(TAB_NODES, graphdb_nodes).
-define(TAB_EDGES, graphdb_edges).
-define(TAB_EDGE_INDEX, graphdb_edge_index).

%%---------------------------------------------------------------------
%% Exported Functions
%%---------------------------------------------------------------------
%%---------------------------------------------------------------------
%% Exports External API
%%---------------------------------------------------------------------
-export([
		start_link/0,
		%% Node operations
		create_node/1,
		create_node/2,
		get_node/1,
		update_node/2,
		delete_node/1,
		all_nodes/0,
		node_count/0,
		%% Edge operations
		create_edge/3,
		create_edge/4,
		get_edge/1,
		get_edges_from/1,
		get_edges_to/1,
		get_edges/1,
		update_edge/2,
		delete_edge/1,
		all_edges/0,
		edge_count/0
		]).

%%---------------------------------------------------------------------
%% Exports Behaviour Callback for -behaviour(gen_server).
%%---------------------------------------------------------------------
-export([
		init/1,
		handle_call/3,
		handle_cast/2,
		handle_info/2,
		terminate/2,
		code_change/3
		]).

%%---------------------------------------------------------------------
%% Type Definitions
%%---------------------------------------------------------------------
-type graph_node() :: #{nref => integer(), class => term(), attrs => map(), created => integer()}.
-type graph_edge() :: #{id => integer(), from => integer(), to => integer(), type => term(), attrs => map(), created => integer()}.
-type edge_id() :: integer().
-export_type([graph_node/0, graph_edge/0, edge_id/0]).

%%---------------------------------------------------------------------
%% Exported External API Functions
%%---------------------------------------------------------------------
start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%---------------------------------------------------------------------
%% Node API
%%---------------------------------------------------------------------
create_node(Class) ->
	create_node(Class, #{}).

create_node(Class, Attrs) when is_map(Attrs) ->
	gen_server:call(?MODULE, {create_node, Class, Attrs}).

-spec get_node(integer()) -> {ok, graph_node()} | {error, not_found}.
get_node(Nref) ->
	gen_server:call(?MODULE, {get_node, Nref}).

-spec update_node(integer(), map()) -> ok | {error, not_found}.
update_node(Nref, Attrs) ->
	gen_server:call(?MODULE, {update_node, Nref, Attrs}).

-spec delete_node(integer()) -> ok | {error, not_found}.
delete_node(Nref) ->
	gen_server:call(?MODULE, {delete_node, Nref}).

-spec all_nodes() -> [integer()].
all_nodes() ->
	gen_server:call(?MODULE, all_nodes).

-spec node_count() -> non_neg_integer().
node_count() ->
	gen_server:call(?MODULE, node_count).

%%---------------------------------------------------------------------
%% Edge API
%%---------------------------------------------------------------------
-spec create_edge(integer(), integer(), term()) -> {ok, edge_id()} | {error, no_such_node}.
create_edge(FromNref, ToNref, Type) ->
	create_edge(FromNref, ToNref, Type, #{}).

-spec create_edge(integer(), integer(), term(), map()) -> {ok, edge_id()} | {error, no_such_node}.
create_edge(FromNref, ToNref, Type, Attrs) when is_integer(FromNref), is_integer(ToNref), is_map(Attrs) ->
	gen_server:call(?MODULE, {create_edge, FromNref, ToNref, Type, Attrs}).

-spec get_edge(edge_id()) -> {ok, graph_edge()} | {error, not_found}.
get_edge(EdgeId) ->
	gen_server:call(?MODULE, {get_edge, EdgeId}).

-spec get_edges_from(integer()) -> [graph_edge()].
get_edges_from(Nref) ->
	gen_server:call(?MODULE, {get_edges_from, Nref}).

-spec get_edges_to(integer()) -> [graph_edge()].
get_edges_to(Nref) ->
	gen_server:call(?MODULE, {get_edges_to, Nref}).

-spec get_edges(integer()) -> [graph_edge()].
get_edges(Nref) ->
	gen_server:call(?MODULE, {get_edges, Nref}).

-spec update_edge(edge_id(), map()) -> ok | {error, not_found}.
update_edge(EdgeId, Attrs) ->
	gen_server:call(?MODULE, {update_edge, EdgeId, Attrs}).

-spec delete_edge(edge_id()) -> ok | {error, not_found}.
delete_edge(EdgeId) ->
	gen_server:call(?MODULE, {delete_edge, EdgeId}).

-spec all_edges() -> [edge_id()].
all_edges() ->
	gen_server:call(?MODULE, all_edges).

-spec edge_count() -> non_neg_integer().
edge_count() ->
	gen_server:call(?MODULE, edge_count).

%%---------------------------------------------------------------------
%% gen_server Behaviour Callbacks
%%---------------------------------------------------------------------

init([]) ->
	?LOG_INFO("graphdb_instance: initializing ETS tables"),
	NodesTab = ets:new(?TAB_NODES, [set, named_table, {keypos, 1}, public]),
	EdgesTab = ets:new(?TAB_EDGES, [set, named_table, {keypos, 1}, public]),
	EdgeIndexTab = ets:new(?TAB_EDGE_INDEX, [duplicate_bag, named_table, public]),
	?LOG_INFO("graphdb_instance: ETS tables created"),
	{ok, #{nodes => NodesTab, edges => EdgesTab, edge_index => EdgeIndexTab}}.

handle_call({create_node, Class, Attrs}, _From, State) ->
	Reply = do_create_node(Class, Attrs),
	{reply, Reply, State};

handle_call({get_node, Nref}, _From, State) ->
	Reply = do_get_node(Nref),
	{reply, Reply, State};

handle_call({update_node, Nref, Attrs}, _From, State) ->
	Reply = do_update_node(Nref, Attrs),
	{reply, Reply, State};

handle_call({delete_node, Nref}, _From, State) ->
	Reply = do_delete_node(Nref),
	{reply, Reply, State};

handle_call(all_nodes, _From, State) ->
	Reply = do_all_nodes(),
	{reply, Reply, State};

handle_call(node_count, _From, State) ->
	Reply = ets:info(?TAB_NODES, size),
	{reply, Reply, State};

handle_call({create_edge, FromNref, ToNref, Type, Attrs}, _From, State) ->
	Reply = do_create_edge(FromNref, ToNref, Type, Attrs),
	{reply, Reply, State};

handle_call({get_edge, EdgeId}, _From, State) ->
	Reply = do_get_edge(EdgeId),
	{reply, Reply, State};

handle_call({get_edges_from, Nref}, _From, State) ->
	Reply = do_get_edges_from(Nref),
	{reply, Reply, State};

handle_call({get_edges_to, Nref}, _From, State) ->
	Reply = do_get_edges_to(Nref),
	{reply, Reply, State};

handle_call({get_edges, Nref}, _From, State) ->
	Reply = do_get_edges(Nref),
	{reply, Reply, State};

handle_call({update_edge, EdgeId, Attrs}, _From, State) ->
	Reply = do_update_edge(EdgeId, Attrs),
	{reply, Reply, State};

handle_call({delete_edge, EdgeId}, _From, State) ->
	Reply = do_delete_edge(EdgeId),
	{reply, Reply, State};

handle_call(all_edges, _From, State) ->
	Reply = do_all_edges(),
	{reply, Reply, State};

handle_call(edge_count, _From, State) ->
	Reply = ets:info(?TAB_EDGES, size),
	{reply, Reply, State};

handle_call(Request, From, State) ->
	?UEM(handle_call, {Request, From, State}),
	{noreply, State}.

handle_cast(Message, State) ->
	?UEM(handle_cast, {Message, State}),
	{noreply, State}.

handle_info(Info, State) ->
	?UEM(handle_info, {Info, State}),
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%%---------------------------------------------------------------------
%% Internal Functions - Nodes
%%---------------------------------------------------------------------
do_create_node(Class, Attrs) ->
	case catch nref_server:get_nref() of
		{'EXIT', _} ->
			{error, nref_unavailable};
		Nref when is_integer(Nref) ->
			Now = erlang:system_time(second),
			Node = #{nref => Nref, class => Class, attrs => Attrs, created => Now},
			true = ets:insert(?TAB_NODES, Node),
			?LOG_INFO("graphdb_instance: created node ~p with class ~p", [Nref, Class]),
			{nref, Nref}
	end.

do_get_node(Nref) ->
	case ets:lookup(?TAB_NODES, Nref) of
		[Node] -> {ok, Node};
		[] -> {error, not_found}
	end.

do_update_node(Nref, Attrs) ->
	case ets:lookup(?TAB_NODES, Nref) of
		[Node] ->
			UpdatedNode = maps:put(attrs, Attrs, Node),
			true = ets:insert(?TAB_NODES, UpdatedNode),
			ok;
		[] ->
			{error, not_found}
	end.

do_delete_node(Nref) ->
	case ets:lookup(?TAB_NODES, Nref) of
		[_Node] ->
			true = ets:delete(?TAB_NODES, Nref),
			delete_edges_for_node(Nref),
			ok;
		[] ->
			{error, not_found}
	end.

do_all_nodes() ->
	[ Nref || [Nref] <- ets:match(?TAB_NODES, {'$1', '_', '_', '_'}) ].

delete_edges_for_node(Nref) ->
	FromEdges = ets:match_object(?TAB_EDGE_INDEX, {Nref, '_', '_'}),
	ToEdges = ets:match_object(?TAB_EDGE_INDEX, {'_', Nref, '_'}),
	AllEdges = FromEdges ++ ToEdges,
	lists:foreach(fun(EdgeIndex) ->
		{_, _, EdgeId} = EdgeIndex,
		ets:delete(?TAB_EDGES, EdgeId)
	end, AllEdges),
	ets:delete_object(?TAB_EDGE_INDEX, {Nref, '_', '_'}),
	ets:delete_object(?TAB_EDGE_INDEX, {'_', Nref, '_'}).

%%---------------------------------------------------------------------
%% Internal Functions - Edges
%%---------------------------------------------------------------------
do_create_edge(FromNref, ToNref, Type, Attrs) ->
	case ets:lookup(?TAB_NODES, FromNref) of
		[_] ->
			case ets:lookup(?TAB_NODES, ToNref) of
				[_] ->
					create_edge_unsafe(FromNref, ToNref, Type, Attrs);
				[] ->
					{error, no_such_node}
			end;
		[] ->
			{error, no_such_node}
	end.

create_edge_unsafe(FromNref, ToNref, Type, Attrs) ->
	case catch nref_server:get_nref() of
		{'EXIT', _} ->
			{error, nref_unavailable};
		EdgeId when is_integer(EdgeId) ->
			Now = erlang:system_time(second),
			Edge = {EdgeId, FromNref, ToNref, Type, Attrs, Now},
			true = ets:insert(?TAB_EDGES, Edge),
			true = ets:insert(?TAB_EDGE_INDEX, {FromNref, ToNref, EdgeId}),
			?LOG_INFO("graphdb_instance: created edge ~p -> ~p type ~p",
					  [FromNref, ToNref, Type]),
			{edge_id, EdgeId}
	end.

do_get_edge(EdgeId) ->
	case ets:lookup(?TAB_EDGES, EdgeId) of
		[Edge] -> {ok, format_edge(Edge)};
		[] -> {error, not_found}
	end.

do_get_edges_from(Nref) ->
	EdgeIndices = ets:match_object(?TAB_EDGE_INDEX, {Nref, '_', '_'}),
	lists:foldl(fun({_, _, EdgeId}, Acc) ->
		case ets:lookup(?TAB_EDGES, EdgeId) of
			[Edge] -> [format_edge(Edge) | Acc];
			[] -> Acc
		end
	end, [], EdgeIndices).

do_get_edges_to(Nref) ->
	EdgeIndices = ets:match_object(?TAB_EDGE_INDEX, {'_', Nref, '_'}),
	lists:foldl(fun({_, _, EdgeId}, Acc) ->
		case ets:lookup(?TAB_EDGES, EdgeId) of
			[Edge] -> [format_edge(Edge) | Acc];
			[] -> Acc
		end
	end, [], EdgeIndices).

do_get_edges(Nref) ->
	do_get_edges_from(Nref) ++ do_get_edges_to(Nref).

do_update_edge(EdgeId, Attrs) ->
	case ets:lookup(?TAB_EDGES, EdgeId) of
		[{EdgeId, From, To, Type, _OldAttrs, Created}] ->
			Edge = {EdgeId, From, To, Type, Attrs, Created},
			true = ets:insert(?TAB_EDGES, Edge),
			ok;
		[] ->
			{error, not_found}
	end.

do_delete_edge(EdgeId) ->
	case ets:lookup(?TAB_EDGES, EdgeId) of
		[{EdgeId, From, To, _Type, _Attrs, _Created}] ->
			true = ets:delete(?TAB_EDGES, EdgeId),
			ets:delete_object(?TAB_EDGE_INDEX, {From, To, EdgeId}),
			ok;
		[] ->
			{error, not_found}
	end.

do_all_edges() ->
	ets:match(?TAB_EDGES, {'$1', '_', '_', '_', '_', '_'}).

format_edge({EdgeId, From, To, Type, Attrs, Created}) ->
	#{
		id => EdgeId,
		from => From,
		to => To,
		type => Type,
		attrs => Attrs,
		created => Created
	}.
