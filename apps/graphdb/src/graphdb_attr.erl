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
%%
%%				Attributes are stored in an ETS table (persisted via tab2file).
%%				Each attribute record has the form:
%%				  {{Nref::nref(), Name::binary()}, Value::term()}
%%
%%				Lookup is keyed by {Nref, Name} for O(1) access.
%%				Retrieval of all attributes for a node uses ets:match.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Stub implementation.
%%---------------------------------------------------------------------
%% Rev A Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Full implementation: ETS-backed attribute store with persistence.
%%---------------------------------------------------------------------
-module(graphdb_attr).
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

-define(TAB, graphdb_attr_tab).
-define(TAB_FILE, "graphdb_attr.ets").

%%---------------------------------------------------------------------
%% Exported Functions
%%---------------------------------------------------------------------
%%---------------------------------------------------------------------
%% Exports External API
%%---------------------------------------------------------------------
-export([
		start_link/0,
		set_attr/3,			%% set_attr(Nref, Name, Value) -> ok
		get_attr/2,			%% get_attr(Nref, Name) -> {ok, Value} | {error, not_found}
		get_attrs/1,		%% get_attrs(Nref) -> [{Name, Value}]
		delete_attr/2,		%% delete_attr(Nref, Name) -> ok
		delete_attrs/1		%% delete_attrs(Nref) -> ok  — removes all attrs for a node/edge
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

%%-----------------------------------------------------------------------------
%% set_attr(Nref, Name, Value) -> ok
%%
%% Inserts or replaces the attribute Name on the node/edge identified by Nref.
%%-----------------------------------------------------------------------------
set_attr(Nref, Name, Value) ->
	gen_server:call(?MODULE, {set_attr, Nref, Name, Value}).

%%-----------------------------------------------------------------------------
%% get_attr(Nref, Name) -> {ok, Value} | {error, not_found}
%%-----------------------------------------------------------------------------
get_attr(Nref, Name) ->
	gen_server:call(?MODULE, {get_attr, Nref, Name}).

%%-----------------------------------------------------------------------------
%% get_attrs(Nref) -> [{Name::binary(), Value::term()}]
%%
%% Returns all attributes stored for the given Nref.
%%-----------------------------------------------------------------------------
get_attrs(Nref) ->
	gen_server:call(?MODULE, {get_attrs, Nref}).

%%-----------------------------------------------------------------------------
%% delete_attr(Nref, Name) -> ok
%%-----------------------------------------------------------------------------
delete_attr(Nref, Name) ->
	gen_server:call(?MODULE, {delete_attr, Nref, Name}).

%%-----------------------------------------------------------------------------
%% delete_attrs(Nref) -> ok
%%
%% Removes all attributes for the given Nref. Called on node/edge deletion.
%%-----------------------------------------------------------------------------
delete_attrs(Nref) ->
	gen_server:call(?MODULE, {delete_attrs, Nref}).


%%=============================================================================
%% gen_server Behaviour Callbacks
%%=============================================================================

%%-----------------------------------------------------------------------------
%% init([]) -> {ok, Tab}
%%-----------------------------------------------------------------------------
init([]) ->
	Tab = open_tab(),
	{ok, Tab}.


%%-----------------------------------------------------------------------------
%% handle_call/3
%%-----------------------------------------------------------------------------
handle_call({set_attr, Nref, Name, Value}, _From, Tab) ->
	ets:insert(Tab, {{Nref, Name}, Value}),
	{reply, ok, Tab};
handle_call({get_attr, Nref, Name}, _From, Tab) ->
	Reply = case ets:lookup(Tab, {Nref, Name}) of
		[{_, V}] -> {ok, V};
		[]       -> {error, not_found}
	end,
	{reply, Reply, Tab};
handle_call({get_attrs, Nref}, _From, Tab) ->
	Pairs = ets:match(Tab, {{Nref, '$1'}, '$2'}),
	Reply = [{N, V} || [N, V] <- Pairs],
	{reply, Reply, Tab};
handle_call({delete_attr, Nref, Name}, _From, Tab) ->
	ets:delete(Tab, {Nref, Name}),
	{reply, ok, Tab};
handle_call({delete_attrs, Nref}, _From, Tab) ->
	ets:match_delete(Tab, {{Nref, '_'}, '_'}),
	{reply, ok, Tab};
handle_call(Request, From, Tab) ->
	?UEM(handle_call, {Request, From, Tab}),
	{noreply, Tab}.


%%-----------------------------------------------------------------------------
%% handle_cast/2
%%-----------------------------------------------------------------------------
handle_cast(Message, Tab) ->
	?UEM(handle_cast, {Message, Tab}),
	{noreply, Tab}.


%%-----------------------------------------------------------------------------
%% handle_info/2
%%-----------------------------------------------------------------------------
handle_info(Info, Tab) ->
	?UEM(handle_info, {Info, Tab}),
	{noreply, Tab}.


%%-----------------------------------------------------------------------------
%% terminate/2
%%
%% Persists the ETS table to disk before shutdown.
%%-----------------------------------------------------------------------------
terminate(_Reason, Tab) ->
	ets:tab2file(Tab, ?TAB_FILE),
	ok.


%%-----------------------------------------------------------------------------
%% code_change/3
%%-----------------------------------------------------------------------------
code_change(_OldVsn, Tab, _Extra) ->
	?NYI(code_change),
	{ok, Tab}.


%%=============================================================================
%% Internal Functions
%%=============================================================================

%%-----------------------------------------------------------------------------
%% open_tab() -> Tab
%%
%% Loads the ETS table from disk if the file exists; otherwise creates a new
%% empty table.
%%-----------------------------------------------------------------------------
open_tab() ->
	case filelib:is_file(?TAB_FILE) of
	true ->
		{ok, Tab} = ets:file2tab(?TAB_FILE),
		Tab;
	false ->
		ets:new(?TAB, [set, named_table, public])
	end.
