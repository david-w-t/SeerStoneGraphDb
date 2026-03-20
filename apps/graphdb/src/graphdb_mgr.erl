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
%% Description: graphdb_mgr is the manager for the graph database.
%%				graphdb_mgr coordinates graph database operations and
%%				acts as the primary interface for the graphdb subsystem.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Stub implementation.
%% Rev A Date: March 19, 2026 Author: AI
%% Full implementation - coordinator for all graphdb workers.
%%---------------------------------------------------------------------
-module(graphdb_mgr).
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

%%---------------------------------------------------------------------
%% Exported Functions
%%---------------------------------------------------------------------
%%---------------------------------------------------------------------
%% Exports External API
%%---------------------------------------------------------------------
-export([
		start_link/0,
		%% Unified node API
		create_node/1,
		create_node/2,
		get_node/1,
		update_node/2,
		delete_node/1,
		all_nodes/0,
		node_count/0,
		%% Unified edge API
		create_edge/3,
		create_edge/4,
		get_edge/1,
		get_edges/1,
		delete_edge/1,
		all_edges/0,
		edge_count/0,
		%% Class API
		create_class/2,
		create_class/3,
		get_class/1,
		is_a/2,
		all_classes/0,
		%% Attribute API
		set_attr/4,
		get_attr/3,
		find_by_attr/2,
		%% Rule API
		create_rule/4,
		validate_operation/3,
		all_rules/0,
		%% Query API
		query/1,
		query/2,
		traverse/3,
		%% System API
		status/0,
		ping/0
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
%% Exported External API Functions
%%---------------------------------------------------------------------
start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%---------------------------------------------------------------------
%% Unified Node API
%%---------------------------------------------------------------------
-spec create_node(atom()) -> {ok, integer()} | {error, term()}.
create_node(Class) ->
	create_node(Class, #{}).

-spec create_node(atom(), map()) -> {ok, integer()} | {error, term()}.
create_node(Class, Attrs) ->
	graphdb_instance:create_node(Class, Attrs).

-spec get_node(integer()) -> {ok, map()} | {error, not_found}.
get_node(Nref) ->
	graphdb_instance:get_node(Nref).

-spec update_node(integer(), map()) -> ok | {error, not_found}.
update_node(Nref, Attrs) ->
	graphdb_instance:update_node(Nref, Attrs).

-spec delete_node(integer()) -> ok | {error, not_found}.
delete_node(Nref) ->
	graphdb_instance:delete_node(Nref).

-spec all_nodes() -> [integer()].
all_nodes() ->
	graphdb_instance:all_nodes().

-spec node_count() -> non_neg_integer().
node_count() ->
	graphdb_instance:node_count().

%%---------------------------------------------------------------------
%% Unified Edge API
%%---------------------------------------------------------------------
-spec create_edge(integer(), integer(), atom()) -> {ok, integer()} | {error, term()}.
create_edge(FromNref, ToNref, Type) ->
	create_edge(FromNref, ToNref, Type, #{}).

-spec create_edge(integer(), integer(), atom(), map()) -> {ok, integer()} | {error, term()}.
create_edge(FromNref, ToNref, Type, Attrs) ->
	graphdb_instance:create_edge(FromNref, ToNref, Type, Attrs).

-spec get_edge(integer()) -> {ok, map()} | {error, not_found}.
get_edge(EdgeId) ->
	graphdb_instance:get_edge(EdgeId).

-spec get_edges(integer()) -> [map()].
get_edges(Nref) ->
	graphdb_instance:get_edges(Nref).

-spec delete_edge(integer()) -> ok | {error, not_found}.
delete_edge(EdgeId) ->
	graphdb_instance:delete_edge(EdgeId).

-spec all_edges() -> [integer()].
all_edges() ->
	graphdb_instance:all_edges().

-spec edge_count() -> non_neg_integer().
edge_count() ->
	graphdb_instance:edge_count().

%%---------------------------------------------------------------------
%% Class API
%%---------------------------------------------------------------------
-spec create_class(atom(), map()) -> {ok, atom()} | {error, term()}.
create_class(Name, Attrs) ->
	create_class(Name, undefined, Attrs).

-spec create_class(atom(), atom() | undefined, map()) -> {ok, atom()} | {error, term()}.
create_class(Name, Parent, Attrs) ->
	graphdb_class:create_class(Name, Parent, Attrs).

-spec get_class(atom()) -> {ok, map()} | {error, not_found}.
get_class(Name) ->
	graphdb_class:get_class(Name).

-spec is_a(atom(), atom()) -> boolean().
is_a(Child, Parent) ->
	graphdb_class:is_a(Child, Parent).

-spec all_classes() -> [atom()].
all_classes() ->
	graphdb_class:all_classes().

%%---------------------------------------------------------------------
%% Attribute API
%%---------------------------------------------------------------------
-spec set_attr(node | edge, integer(), atom(), term()) -> ok.
set_attr(EntityType, EntityId, Key, Value) ->
	graphdb_attr:set_attr(EntityType, EntityId, Key, Value).

-spec get_attr(node | edge, integer(), atom()) -> {ok, term()} | undefined.
get_attr(EntityType, EntityId, Key) ->
	graphdb_attr:get_attr(EntityType, EntityId, Key).

-spec find_by_attr(atom(), term()) -> [{node | edge, integer()}].
find_by_attr(Key, Value) ->
	graphdb_attr:find_by_attr(Key, Value).

%%---------------------------------------------------------------------
%% Rule API
%%---------------------------------------------------------------------
-spec create_rule(atom(), atom(), atom(), fun()) -> {ok, atom()} | {error, term()}.
create_rule(Name, Type, Target, Condition) ->
	graphdb_rules:create_rule(Name, Type, Target, Condition).

-spec validate_operation(atom(), atom(), map()) -> ok | {error, [term()]}.
validate_operation(Operation, TargetType, Context) ->
	graphdb_rules:validate_operation(Operation, TargetType, Context).

-spec all_rules() -> [map()].
all_rules() ->
	graphdb_rules:all_rules().

%%---------------------------------------------------------------------
%% Query API
%%---------------------------------------------------------------------
-spec query(string()) -> {ok, [map()]} | {error, term()}.
query(QueryString) ->
	graphdb_language:query(QueryString).

-spec query(string() | map(), map()) -> {ok, [map()]} | {error, term()}.
query(QueryString, Context) ->
	graphdb_language:query(QueryString, Context).

-spec traverse(integer(), fun(), integer()) -> {ok, [map()]} | {error, term()}.
traverse(StartNref, FilterFun, MaxDepth) ->
	graphdb_language:traverse(StartNref, FilterFun, MaxDepth).

%%---------------------------------------------------------------------
%% System API
%%---------------------------------------------------------------------
-spec status() -> map().
status() ->
	#{
		nodes => node_count(),
		edges => edge_count(),
		classes => graphdb_class:class_count(),
		rules => graphdb_rules:rule_count(),
		attrs => graphdb_attr:attr_count()
	}.

-spec ping() -> pong.
ping() ->
	pong.

%%---------------------------------------------------------------------
%% gen_server Behaviour Callbacks
%%---------------------------------------------------------------------

init([]) ->
	?LOG_INFO("graphdb_mgr: initialized"),
	{ok, #{}}.

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
