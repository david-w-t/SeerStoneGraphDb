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
%%
%%				Instances are stored in a DETS table for durability.
%%
%%				Node record:
%%				  {Nref::nref(), node, ClassId::nref(), Props::map()}
%%
%%				Edge record:
%%				  {Nref::nref(), edge, FromNref::nref(), ToNref::nref(),
%%				   ClassId::nref(), Props::map()}
%%
%%				Props is a map of inline properties (distinct from the
%%				externally-managed attributes in graphdb_attr).
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Stub implementation.
%%---------------------------------------------------------------------
%% Rev A Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Full implementation: DETS-backed node/edge instance store.
%%---------------------------------------------------------------------
-module(graphdb_instance).
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

-define(TAB, graphdb_instance_tab).
-define(TAB_FILE, "graphdb_instance.dets").

%%---------------------------------------------------------------------
%% Exported Functions
%%---------------------------------------------------------------------
%%---------------------------------------------------------------------
%% Exports External API
%%---------------------------------------------------------------------
-export([
		start_link/0,
		create_node/2,		%% create_node(ClassId, Props) -> {ok, Nref} | {error, Reason}
		create_edge/4,		%% create_edge(FromNref, ToNref, ClassId, Props) -> {ok, Nref} | {error, Reason}
		get/1,				%% get(Nref) -> {ok, Instance} | {error, not_found}
		delete/1,			%% delete(Nref) -> ok | {error, not_found}
		get_edges/1,		%% get_edges(Nref) -> [EdgeInstance]  — all edges from Nref
		get_edges/2,		%% get_edges(FromNref, ToNref) -> [EdgeInstance]
		all_nodes/0,		%% all_nodes() -> [NodeInstance]
		all_edges/0			%% all_edges() -> [EdgeInstance]
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
%% create_node(ClassId, Props) -> {ok, Nref} | {error, Reason}
%%
%% ClassId = nref()  — the class this node is an instance of
%% Props   = map()   — inline properties
%%-----------------------------------------------------------------------------
create_node(ClassId, Props) ->
	gen_server:call(?MODULE, {create_node, ClassId, Props}).

%%-----------------------------------------------------------------------------
%% create_edge(FromNref, ToNref, ClassId, Props) -> {ok, Nref} | {error, Reason}
%%
%% Edges are first-class: they receive their own Nref from nref_server.
%%-----------------------------------------------------------------------------
create_edge(FromNref, ToNref, ClassId, Props) ->
	gen_server:call(?MODULE, {create_edge, FromNref, ToNref, ClassId, Props}).

%%-----------------------------------------------------------------------------
%% get(Nref) -> {ok, Instance} | {error, not_found}
%%
%% Returns the node or edge record for the given Nref.
%%-----------------------------------------------------------------------------
get(Nref) ->
	gen_server:call(?MODULE, {get, Nref}).

%%-----------------------------------------------------------------------------
%% delete(Nref) -> ok | {error, not_found}
%%
%% Deletes a node or edge.  Also releases the Nref back to nref_server for
%% reuse, and removes associated attributes via graphdb_attr.
%%-----------------------------------------------------------------------------
delete(Nref) ->
	gen_server:call(?MODULE, {delete, Nref}).

%%-----------------------------------------------------------------------------
%% get_edges(Nref) -> [EdgeInstance]
%%
%% Returns all edges whose FromNref = Nref.
%%-----------------------------------------------------------------------------
get_edges(Nref) ->
	gen_server:call(?MODULE, {get_edges, Nref}).

%%-----------------------------------------------------------------------------
%% get_edges(FromNref, ToNref) -> [EdgeInstance]
%%
%% Returns all edges between FromNref and ToNref.
%%-----------------------------------------------------------------------------
get_edges(FromNref, ToNref) ->
	gen_server:call(?MODULE, {get_edges, FromNref, ToNref}).

%%-----------------------------------------------------------------------------
%% all_nodes() -> [NodeInstance]
%%-----------------------------------------------------------------------------
all_nodes() ->
	gen_server:call(?MODULE, all_nodes).

%%-----------------------------------------------------------------------------
%% all_edges() -> [EdgeInstance]
%%-----------------------------------------------------------------------------
all_edges() ->
	gen_server:call(?MODULE, all_edges).


%%=============================================================================
%% gen_server Behaviour Callbacks
%%=============================================================================

%%-----------------------------------------------------------------------------
%% init([]) -> {ok, Tab}
%%
%% Opens or creates the DETS table for instance storage.
%%-----------------------------------------------------------------------------
init([]) ->
	ok = open_tab(),
	{ok, ?TAB}.


%%-----------------------------------------------------------------------------
%% handle_call/3
%%-----------------------------------------------------------------------------
handle_call({create_node, ClassId, Props}, _From, Tab) ->
	Nref = nref_server:get_nref(),
	ok = dets:insert(Tab, {Nref, node, ClassId, Props}),
	{reply, {ok, Nref}, Tab};
handle_call({create_edge, FromNref, ToNref, ClassId, Props}, _From, Tab) ->
	Nref = nref_server:get_nref(),
	ok = dets:insert(Tab, {Nref, edge, FromNref, ToNref, ClassId, Props}),
	{reply, {ok, Nref}, Tab};
handle_call({get, Nref}, _From, Tab) ->
	Reply = case dets:lookup(Tab, Nref) of
		[Instance] -> {ok, Instance};
		[]         -> {error, not_found}
	end,
	{reply, Reply, Tab};
handle_call({delete, Nref}, _From, Tab) ->
	Reply = case dets:lookup(Tab, Nref) of
		[_] ->
			ok = dets:delete(Tab, Nref),
			graphdb_attr:delete_attrs(Nref),
			nref_server:reuse_nref(Nref),
			ok;
		[] ->
			{error, not_found}
	end,
	{reply, Reply, Tab};
handle_call({get_edges, FromNref}, _From, Tab) ->
	Reply = dets:match_object(Tab, {'_', edge, FromNref, '_', '_', '_'}),
	{reply, Reply, Tab};
handle_call({get_edges, FromNref, ToNref}, _From, Tab) ->
	Reply = dets:match_object(Tab, {'_', edge, FromNref, ToNref, '_', '_'}),
	{reply, Reply, Tab};
handle_call(all_nodes, _From, Tab) ->
	Reply = dets:match_object(Tab, {'_', node, '_', '_'}),
	{reply, Reply, Tab};
handle_call(all_edges, _From, Tab) ->
	Reply = dets:match_object(Tab, {'_', edge, '_', '_', '_', '_'}),
	{reply, Reply, Tab};
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
%%-----------------------------------------------------------------------------
terminate(_Reason, _Tab) ->
	dets:close(?TAB),
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
%% open_tab() -> ok | exit(Reason)
%%
%% Opens the DETS file, creating and initializing it if it does not exist.
%%-----------------------------------------------------------------------------
open_tab() ->
	File = ?TAB_FILE,
	logger:info("opening dets file: ~p", [File]),
	case dets:open_file(?TAB, [{file, File}]) of
	{ok, ?TAB} ->
		ok;
	{error, Reason} ->
		logger:error("cannot open dets table ~p: ~p", [?TAB, Reason]),
		exit(Reason)
	end.
