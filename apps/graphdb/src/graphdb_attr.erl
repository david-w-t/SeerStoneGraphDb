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
%% Description: graphdb_attr manages graph node and edge attributes.
%%				graphdb_attr is responsible for storing and retrieving
%%				attribute data associated with graph nodes and edges.
%%				Provides indexed attribute lookups for efficient querying.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Stub implementation.
%% Rev A Date: March 19, 2026 Author: AI
%% Full implementation of attribute storage with indexing.
%%---------------------------------------------------------------------
-module(graphdb_attr).
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

-define(TAB_ATTRS, graphdb_attrs).
-define(TAB_INDEX, graphdb_attr_index).

%%---------------------------------------------------------------------
%% Type Definitions
%%---------------------------------------------------------------------
-type entity_type() :: node | edge.
-type attr_key() :: atom().
-type attr_value() :: term().
-export_type([entity_type/0, attr_key/0, attr_value/0]).

%%---------------------------------------------------------------------
%% Exported Functions
%%---------------------------------------------------------------------
%%---------------------------------------------------------------------
%% Exports External API
%%---------------------------------------------------------------------
-export([
		start_link/0,
		%% Single attribute operations
		set_attr/3,
		set_attr/4,
		get_attr/3,
		get_attrs/2,
		delete_attr/3,
		%% Bulk operations
		set_attrs/2,
		get_all_attrs/2,
		delete_all_attrs/2,
		%% Index operations
		find_by_attr/2,
		find_by_attr/3,
		has_attr/2,
		%% Stats
		attr_count/0,
		unique_keys/0
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
%% Single Attribute API
%%---------------------------------------------------------------------
-spec set_attr(entity_type(), integer(), {atom(), term()}) -> ok.
set_attr(EntityType, EntityId, {Key, Value}) ->
	set_attr(EntityType, EntityId, Key, Value).

-spec set_attr(entity_type(), integer(), atom(), term()) -> ok.
set_attr(EntityType, EntityId, Key, Value) when is_atom(EntityType), is_integer(EntityId) ->
	gen_server:call(?MODULE, {set_attr, EntityType, EntityId, Key, Value}).

-spec get_attr(entity_type(), integer(), atom()) -> {ok, term()} | undefined.
get_attr(EntityType, EntityId, Key) ->
	gen_server:call(?MODULE, {get_attr, EntityType, EntityId, Key}).

-spec get_attrs(entity_type(), integer()) -> [{atom(), term()}].
get_attrs(EntityType, EntityId) ->
	gen_server:call(?MODULE, {get_attrs, EntityType, EntityId}).

-spec delete_attr(entity_type(), integer(), atom()) -> ok.
delete_attr(EntityType, EntityId, Key) ->
	gen_server:call(?MODULE, {delete_attr, EntityType, EntityId, Key}).

%%---------------------------------------------------------------------
%% Bulk Operations API
%%---------------------------------------------------------------------
-spec set_attrs(entity_type(), [{integer(), [{atom(), term()}]}]) -> ok.
set_attrs(EntityType, EntityAttrsList) ->
	gen_server:call(?MODULE, {set_attrs, EntityType, EntityAttrsList}).

-spec get_all_attrs(entity_type(), integer()) -> map().
get_all_attrs(EntityType, EntityId) ->
	gen_server:call(?MODULE, {get_all_attrs, EntityType, EntityId}).

-spec delete_all_attrs(entity_type(), integer()) -> ok.
delete_all_attrs(EntityType, EntityId) ->
	gen_server:call(?MODULE, {delete_all_attrs, EntityType, EntityId}).

%%---------------------------------------------------------------------
%% Index Operations API
%%---------------------------------------------------------------------
-spec find_by_attr(atom(), term()) -> [{entity_type(), integer()}].
find_by_attr(Key, Value) ->
	gen_server:call(?MODULE, {find_by_attr, Key, Value}).

-spec find_by_attr(atom(), term(), integer()) -> [{entity_type(), integer()}].
find_by_attr(Key, Value, Limit) ->
	gen_server:call(?MODULE, {find_by_attr, Key, Value, Limit}).

-spec has_attr(atom(), term()) -> boolean().
has_attr(Key, Value) ->
	gen_server:call(?MODULE, {has_attr, Key, Value}).

%%---------------------------------------------------------------------
%% Stats API
%%---------------------------------------------------------------------
-spec attr_count() -> non_neg_integer().
attr_count() ->
	gen_server:call(?MODULE, attr_count).

-spec unique_keys() -> [atom()].
unique_keys() ->
	gen_server:call(?MODULE, unique_keys).

%%---------------------------------------------------------------------
%% gen_server Behaviour Callbacks
%%---------------------------------------------------------------------

init([]) ->
	?LOG_INFO("graphdb_attr: initializing ETS tables"),
	AttrsTab = ets:new(?TAB_ATTRS, [set, named_table, {keypos, 1}, public]),
	IndexTab = ets:new(?TAB_INDEX, [duplicate_bag, named_table, {keypos, 1}, public]),
	?LOG_INFO("graphdb_attr: ETS tables created"),
	{ok, #{attrs => AttrsTab, index => IndexTab}}.

handle_call({set_attr, EntityType, EntityId, Key, Value}, _From, State) ->
	Reply = do_set_attr(EntityType, EntityId, Key, Value),
	{reply, Reply, State};

handle_call({get_attr, EntityType, EntityId, Key}, _From, State) ->
	Reply = do_get_attr(EntityType, EntityId, Key),
	{reply, Reply, State};

handle_call({get_attrs, EntityType, EntityId}, _From, State) ->
	Reply = do_get_attrs(EntityType, EntityId),
	{reply, Reply, State};

handle_call({delete_attr, EntityType, EntityId, Key}, _From, State) ->
	Reply = do_delete_attr(EntityType, EntityId, Key),
	{reply, Reply, State};

handle_call({set_attrs, EntityType, EntityAttrsList}, _From, State) ->
	Reply = do_set_attrs(EntityType, EntityAttrsList),
	{reply, Reply, State};

handle_call({get_all_attrs, EntityType, EntityId}, _From, State) ->
	Reply = do_get_all_attrs(EntityType, EntityId),
	{reply, Reply, State};

handle_call({delete_all_attrs, EntityType, EntityId}, _From, State) ->
	Reply = do_delete_all_attrs(EntityType, EntityId),
	{reply, Reply, State};

handle_call({find_by_attr, Key, Value}, _From, State) ->
	Reply = do_find_by_attr(Key, Value),
	{reply, Reply, State};

handle_call({find_by_attr, Key, Value, Limit}, _From, State) ->
	Reply = do_find_by_attr(Key, Value, Limit),
	{reply, Reply, State};

handle_call({has_attr, Key, Value}, _From, State) ->
	Reply = do_has_attr(Key, Value),
	{reply, Reply, State};

handle_call(attr_count, _From, State) ->
	Reply = ets:info(?TAB_ATTRS, size),
	{reply, Reply, State};

handle_call(unique_keys, _From, State) ->
	Reply = do_unique_keys(),
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
%% Internal Functions
%%---------------------------------------------------------------------
do_set_attr(EntityType, EntityId, Key, Value) ->
	Key2 = {EntityType, EntityId, Key},
	true = ets:insert(?TAB_ATTRS, {Key2, Value}),
	true = ets:insert(?TAB_INDEX, {Key, Value, EntityType, EntityId}),
	ok.

do_get_attr(EntityType, EntityId, Key) ->
	Key2 = {EntityType, EntityId, Key},
	case ets:lookup(?TAB_ATTRS, Key2) of
		[{_, Value}] -> {ok, Value};
		[] -> undefined
	end.

do_get_attrs(EntityType, EntityId) ->
	Pattern = {EntityType, EntityId, '_'},
	[ {AttrKey, Value} || {_, AttrKey, Value} <- ets:match_object(?TAB_ATTRS, {Pattern, '_'}) ].

do_delete_attr(EntityType, EntityId, Key) ->
	Key2 = {EntityType, EntityId, Key},
	true = ets:delete(?TAB_ATTRS, Key2),
	ets:match_delete(?TAB_INDEX, {Key, '_', EntityType, EntityId}),
	ok.

do_set_attrs(_EntityType, []) ->
	ok;
do_set_attrs(EntityType, [{EntityId, Attrs} | Rest]) ->
	lists:foreach(fun({Key, Value}) ->
		do_set_attr(EntityType, EntityId, Key, Value)
	end, Attrs),
	do_set_attrs(EntityType, Rest).

do_get_all_attrs(EntityType, EntityId) ->
	Pattern = {EntityType, EntityId, '_'},
	maps:from_list([ {AttrKey, Value} || {_, AttrKey, Value} <- ets:match_object(?TAB_ATTRS, {Pattern, '_'}) ]).

do_delete_all_attrs(EntityType, EntityId) ->
	Pattern = {EntityType, EntityId, '_'},
	Attrs = ets:match_object(?TAB_ATTRS, {Pattern, '_'}),
	lists:foreach(fun({Key, _Value}) ->
		ets:delete(?TAB_ATTRS, Key)
	end, Attrs),
	ets:match_delete(?TAB_INDEX, {'_', '_', EntityType, EntityId}),
	ok.

do_find_by_attr(Key, Value) ->
	ets:match(?TAB_INDEX, {Key, Value, '$1', '$2'}).

do_find_by_attr(Key, Value, Limit) ->
	Results = do_find_by_attr(Key, Value),
	lists:sublist(Results, Limit).

do_has_attr(Key, Value) ->
	case ets:match(?TAB_INDEX, {Key, Value, '_', '_'}) of
		[] -> false;
		[_|_] -> true
	end.

do_unique_keys() ->
	AllKeys = ets:match(?TAB_INDEX, {'$1', '_', '_', '_'}),
	lists:usort([ K || [K] <- AllKeys ]).
