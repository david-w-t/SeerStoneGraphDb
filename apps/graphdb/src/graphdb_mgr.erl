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
%%
%%				graphdb_mgr is a thin coordination layer.  It routes
%%				calls to the appropriate worker (graphdb_class,
%%				graphdb_attr, graphdb_rules, graphdb_instance) and
%%				enforces rules via graphdb_rules before mutating state.
%%
%%				All rule evaluation happens here, before delegating to
%%				graphdb_instance or graphdb_attr, so the workers
%%				themselves remain policy-free.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Stub implementation.
%%---------------------------------------------------------------------
%% Rev A Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Full implementation: coordinator/facade over graphdb worker modules.
%%---------------------------------------------------------------------
-module(graphdb_mgr).
-behaviour(gen_server).


%%---------------------------------------------------------------------
%% Module Attributes
%%---------------------------------------------------------------------
-revision('Revision: A ').
-created('Date: *** 2008').
-created_by('dallas.noyes@gmail.com').
%%-modified('Date: Month Day, Year 10:50:00').
%%-modified_by('dallas.noyes@gmail.com').


%%---------------------------------------------------------------------
%% Include files
%%---------------------------------------------------------------------

%%---------------------------------------------------------------------
%% Macro Functions
%%---------------------------------------------------------------------
%% NYI - Not Yet Implemented
%%	F = {fun,{Arg1,Arg2,...}}
%%
%% UEM - UnExpected Message
%%	F = {fun,{Arg1,Arg2,...}}
%%	X = Message
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
		%% --- Node operations ---
		create_node/2,			%% create_node(ClassId, Props) -> {ok, Nref} | {error, Reason}
		get_node/1,				%% get_node(Nref) -> {ok, Instance} | {error, not_found}
		delete_node/1,			%% delete_node(Nref) -> ok | {error, Reason}
		%% --- Edge operations ---
		create_edge/4,			%% create_edge(FromNref, ToNref, ClassId, Props) -> {ok, Nref} | {error, Reason}
		get_edge/1,				%% get_edge(Nref) -> {ok, Instance} | {error, not_found}
		delete_edge/1,			%% delete_edge(Nref) -> ok | {error, Reason}
		get_edges/1,			%% get_edges(Nref) -> [EdgeInstance]
		get_edges/2,			%% get_edges(FromNref, ToNref) -> [EdgeInstance]
		%% --- Attribute operations ---
		set_attr/3,				%% set_attr(Nref, Name, Value) -> ok | {error, Reason}
		get_attr/2,				%% get_attr(Nref, Name) -> {ok, Value} | {error, not_found}
		get_attrs/1,			%% get_attrs(Nref) -> [{Name, Value}]
		delete_attr/2,			%% delete_attr(Nref, Name) -> ok
		%% --- Class operations ---
		create_class/3,			%% create_class(Name, ParentId, AttrSpecs) -> {ok, ClassId} | {error, Reason}
		get_class/1,			%% get_class(ClassId) -> {ok, Class} | {error, not_found}
		get_class_by_name/1,	%% get_class_by_name(Name) -> {ok, Class} | {error, not_found}
		delete_class/1,			%% delete_class(ClassId) -> ok | {error, Reason}
		all_classes/0,			%% all_classes() -> [Class]
		%% --- Rule operations ---
		add_rule/4,				%% add_rule(Name, Event, Condition, Action) -> {ok, RuleId} | {error, Reason}
		get_rule/1,				%% get_rule(RuleId) -> {ok, Rule} | {error, not_found}
		delete_rule/1,			%% delete_rule(RuleId) -> ok | {error, not_found}
		all_rules/0				%% all_rules() -> [Rule]
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


%%=============================================================================
%% Exported External API Functions
%%=============================================================================

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% --- Node operations ---

create_node(ClassId, Props) ->
	gen_server:call(?MODULE, {create_node, ClassId, Props}).

get_node(Nref) ->
	gen_server:call(?MODULE, {get_node, Nref}).

delete_node(Nref) ->
	gen_server:call(?MODULE, {delete_node, Nref}).

%% --- Edge operations ---

create_edge(FromNref, ToNref, ClassId, Props) ->
	gen_server:call(?MODULE, {create_edge, FromNref, ToNref, ClassId, Props}).

get_edge(Nref) ->
	gen_server:call(?MODULE, {get_edge, Nref}).

delete_edge(Nref) ->
	gen_server:call(?MODULE, {delete_edge, Nref}).

get_edges(Nref) ->
	graphdb_instance:get_edges(Nref).

get_edges(FromNref, ToNref) ->
	graphdb_instance:get_edges(FromNref, ToNref).

%% --- Attribute operations ---

set_attr(Nref, Name, Value) ->
	gen_server:call(?MODULE, {set_attr, Nref, Name, Value}).

get_attr(Nref, Name) ->
	graphdb_attr:get_attr(Nref, Name).

get_attrs(Nref) ->
	graphdb_attr:get_attrs(Nref).

delete_attr(Nref, Name) ->
	graphdb_attr:delete_attr(Nref, Name).

%% --- Class operations ---

create_class(Name, ParentId, AttrSpecs) ->
	graphdb_class:create_class(Name, ParentId, AttrSpecs).

get_class(ClassId) ->
	graphdb_class:get_class(ClassId).

get_class_by_name(Name) ->
	graphdb_class:get_class_by_name(Name).

delete_class(ClassId) ->
	graphdb_class:delete_class(ClassId).

all_classes() ->
	graphdb_class:all_classes().

%% --- Rule operations ---

add_rule(Name, Event, Condition, Action) ->
	graphdb_rules:add_rule(Name, Event, Condition, Action).

get_rule(RuleId) ->
	graphdb_rules:get_rule(RuleId).

delete_rule(RuleId) ->
	graphdb_rules:delete_rule(RuleId).

all_rules() ->
	graphdb_rules:all_rules().


%%=============================================================================
%% gen_server Behaviour Callbacks
%%=============================================================================

%%-----------------------------------------------------------------------------
%% init([]) -> {ok, State}
%%
%% graphdb_mgr holds no persistent state; all state lives in the workers.
%%-----------------------------------------------------------------------------
init([]) ->
	{ok, []}.


%%-----------------------------------------------------------------------------
%% handle_call/3
%%
%% Mutation operations pass through rule evaluation before delegating.
%%-----------------------------------------------------------------------------
handle_call({create_node, ClassId, Props}, _From, State) ->
	Context = [{class, ClassId}],
	Reply = case graphdb_rules:evaluate(create_node, Context) of
		{deny, Reason} -> {error, {denied, Reason}};
		allow          -> graphdb_instance:create_node(ClassId, Props)
	end,
	{reply, Reply, State};
handle_call({get_node, Nref}, _From, State) ->
	Reply = case graphdb_instance:get(Nref) of
		{ok, {_, node, _, _} = Instance} -> {ok, Instance};
		{ok, _}                           -> {error, not_a_node};
		{error, not_found}                -> {error, not_found}
	end,
	{reply, Reply, State};
handle_call({delete_node, Nref}, _From, State) ->
	Context = [{nref, Nref}],
	Reply = case graphdb_rules:evaluate(delete_node, Context) of
		{deny, Reason} -> {error, {denied, Reason}};
		allow          -> graphdb_instance:delete(Nref)
	end,
	{reply, Reply, State};
handle_call({create_edge, FromNref, ToNref, ClassId, Props}, _From, State) ->
	Context = [{class, ClassId}, {from, FromNref}, {to, ToNref}],
	Reply = case graphdb_rules:evaluate(create_edge, Context) of
		{deny, Reason} -> {error, {denied, Reason}};
		allow          -> graphdb_instance:create_edge(FromNref, ToNref, ClassId, Props)
	end,
	{reply, Reply, State};
handle_call({get_edge, Nref}, _From, State) ->
	Reply = case graphdb_instance:get(Nref) of
		{ok, {_, edge, _, _, _, _} = Instance} -> {ok, Instance};
		{ok, _}                                 -> {error, not_an_edge};
		{error, not_found}                      -> {error, not_found}
	end,
	{reply, Reply, State};
handle_call({delete_edge, Nref}, _From, State) ->
	Context = [{nref, Nref}],
	Reply = case graphdb_rules:evaluate(delete_edge, Context) of
		{deny, Reason} -> {error, {denied, Reason}};
		allow          -> graphdb_instance:delete(Nref)
	end,
	{reply, Reply, State};
handle_call({set_attr, Nref, Name, Value}, _From, State) ->
	Context = [{nref, Nref}, {{attr, Name}, Value}],
	Reply = case graphdb_rules:evaluate(set_attr, Context) of
		{deny, Reason} -> {error, {denied, Reason}};
		allow          -> graphdb_attr:set_attr(Nref, Name, Value)
	end,
	{reply, Reply, State};
handle_call(Request, From, State) ->
	?UEM(handle_call, {Request, From, State}),
	{noreply, State}.


%%-----------------------------------------------------------------------------
%% handle_cast/2
%%-----------------------------------------------------------------------------
handle_cast(Message, State) ->
	?UEM(handle_cast, {Message, State}),
	{noreply, State}.


%%-----------------------------------------------------------------------------
%% handle_info/2
%%-----------------------------------------------------------------------------
handle_info(Info, State) ->
	?UEM(handle_info, {Info, State}),
	{noreply, State}.


%%-----------------------------------------------------------------------------
%% terminate/2
%%-----------------------------------------------------------------------------
terminate(_Reason, _State) ->
	ok.


%%-----------------------------------------------------------------------------
%% code_change/3
%%-----------------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
	?NYI(code_change),
	{ok, State}.
