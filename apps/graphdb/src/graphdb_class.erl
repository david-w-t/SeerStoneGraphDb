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
%% Description: graphdb_class manages graph class (type/schema) definitions.
%%				graphdb_class is responsible for storing and enforcing
%%				the class hierarchy and type system for graph nodes and edges.
%%
%%				Classes are stored in an ETS table (persisted via tab2file).
%%				Each class record has the form:
%%				  {ClassId::nref(), ParentId::nref()|undefined,
%%				   Name::binary(), AttrSpecs::[{Name::binary(), Type::atom(), Required::boolean()}]}
%%
%%				The built-in root class has ClassId = 0 and no parent.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Stub implementation.
%%---------------------------------------------------------------------
%% Rev A Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Full implementation: ETS-backed class/schema store with persistence.
%%---------------------------------------------------------------------
-module(graphdb_class).
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

-define(TAB, graphdb_class_tab).
-define(TAB_FILE, "graphdb_class.ets").

%%---------------------------------------------------------------------
%% Exported Functions
%%---------------------------------------------------------------------
%%---------------------------------------------------------------------
%% Exports External API
%%---------------------------------------------------------------------
-export([
		start_link/0,
		create_class/3,			%% create_class(Name, ParentId, AttrSpecs) -> {ok, ClassId} | {error, Reason}
		get_class/1,			%% get_class(ClassId) -> {ok, Class} | {error, not_found}
		get_class_by_name/1,	%% get_class_by_name(Name) -> {ok, Class} | {error, not_found}
		delete_class/1,			%% delete_class(ClassId) -> ok | {error, Reason}
		get_subclasses/1,		%% get_subclasses(ClassId) -> [Class]
		all_classes/0			%% all_classes() -> [Class]
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
%% create_class(Name, ParentId, AttrSpecs) -> {ok, ClassId} | {error, Reason}
%%
%% Name      = binary()
%% ParentId  = nref() | undefined
%% AttrSpecs = [{Name::binary(), Type::atom(), Required::boolean()}]
%%-----------------------------------------------------------------------------
create_class(Name, ParentId, AttrSpecs) ->
	gen_server:call(?MODULE, {create_class, Name, ParentId, AttrSpecs}).

%%-----------------------------------------------------------------------------
%% get_class(ClassId) -> {ok, {ClassId, ParentId, Name, AttrSpecs}} | {error, not_found}
%%-----------------------------------------------------------------------------
get_class(ClassId) ->
	gen_server:call(?MODULE, {get_class, ClassId}).

%%-----------------------------------------------------------------------------
%% get_class_by_name(Name) -> {ok, {ClassId, ParentId, Name, AttrSpecs}} | {error, not_found}
%%-----------------------------------------------------------------------------
get_class_by_name(Name) ->
	gen_server:call(?MODULE, {get_class_by_name, Name}).

%%-----------------------------------------------------------------------------
%% delete_class(ClassId) -> ok | {error, has_subclasses} | {error, not_found}
%%-----------------------------------------------------------------------------
delete_class(ClassId) ->
	gen_server:call(?MODULE, {delete_class, ClassId}).

%%-----------------------------------------------------------------------------
%% get_subclasses(ClassId) -> [{ClassId, ParentId, Name, AttrSpecs}]
%%-----------------------------------------------------------------------------
get_subclasses(ClassId) ->
	gen_server:call(?MODULE, {get_subclasses, ClassId}).

%%-----------------------------------------------------------------------------
%% all_classes() -> [{ClassId, ParentId, Name, AttrSpecs}]
%%-----------------------------------------------------------------------------
all_classes() ->
	gen_server:call(?MODULE, all_classes).


%%=============================================================================
%% gen_server Behaviour Callbacks
%%=============================================================================

%%-----------------------------------------------------------------------------
%% init([]) -> {ok, State}
%%
%% Opens or creates the ETS table for class storage.
%% Seeds the built-in root class (ClassId=0) if the table is new.
%%-----------------------------------------------------------------------------
init([]) ->
	Tab = open_tab(),
	{ok, Tab}.


%%-----------------------------------------------------------------------------
%% handle_call/3
%%-----------------------------------------------------------------------------
handle_call({create_class, Name, ParentId, AttrSpecs}, _From, Tab) ->
	Reply = do_create_class(Tab, Name, ParentId, AttrSpecs),
	{reply, Reply, Tab};
handle_call({get_class, ClassId}, _From, Tab) ->
	Reply = do_get_class(Tab, ClassId),
	{reply, Reply, Tab};
handle_call({get_class_by_name, Name}, _From, Tab) ->
	Reply = do_get_class_by_name(Tab, Name),
	{reply, Reply, Tab};
handle_call({delete_class, ClassId}, _From, Tab) ->
	Reply = do_delete_class(Tab, ClassId),
	{reply, Reply, Tab};
handle_call({get_subclasses, ClassId}, _From, Tab) ->
	Reply = do_get_subclasses(Tab, ClassId),
	{reply, Reply, Tab};
handle_call(all_classes, _From, Tab) ->
	Reply = ets:tab2list(Tab),
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
%% table and seeds the built-in root class (ClassId = 0).
%%-----------------------------------------------------------------------------
open_tab() ->
	case filelib:is_file(?TAB_FILE) of
	true ->
		{ok, Tab} = ets:file2tab(?TAB_FILE),
		Tab;
	false ->
		Tab = ets:new(?TAB, [set, named_table, public]),
		%% Seed the built-in root class: all user classes descend from this.
		ets:insert(Tab, {0, undefined, <<"root">>, []}),
		Tab
	end.


%%-----------------------------------------------------------------------------
%% do_create_class(Tab, Name, ParentId, AttrSpecs) -> {ok, ClassId} | {error, Reason}
%%-----------------------------------------------------------------------------
do_create_class(Tab, Name, ParentId, AttrSpecs) ->
	%% Validate parent exists (or is undefined = root).
	case ParentId =:= undefined orelse do_get_class(Tab, ParentId) =/= {error, not_found} of
	false ->
		{error, {parent_not_found, ParentId}};
	true ->
		ClassId = nref_server:get_nref(),
		ets:insert(Tab, {ClassId, ParentId, Name, AttrSpecs}),
		{ok, ClassId}
	end.


%%-----------------------------------------------------------------------------
%% do_get_class(Tab, ClassId) -> {ok, Class} | {error, not_found}
%%-----------------------------------------------------------------------------
do_get_class(Tab, ClassId) ->
	case ets:lookup(Tab, ClassId) of
	[Class] -> {ok, Class};
	[]      -> {error, not_found}
	end.


%%-----------------------------------------------------------------------------
%% do_get_class_by_name(Tab, Name) -> {ok, Class} | {error, not_found}
%%-----------------------------------------------------------------------------
do_get_class_by_name(Tab, Name) ->
	case ets:match_object(Tab, {'_', '_', Name, '_'}) of
	[Class|_] -> {ok, Class};
	[]        -> {error, not_found}
	end.


%%-----------------------------------------------------------------------------
%% do_delete_class(Tab, ClassId) -> ok | {error, Reason}
%%-----------------------------------------------------------------------------
do_delete_class(Tab, ClassId) ->
	case do_get_subclasses(Tab, ClassId) of
	[] ->
		case ets:lookup(Tab, ClassId) of
		[_] ->
			ets:delete(Tab, ClassId),
			ok;
		[] ->
			{error, not_found}
		end;
	_ ->
		{error, has_subclasses}
	end.


%%-----------------------------------------------------------------------------
%% do_get_subclasses(Tab, ClassId) -> [Class]
%%-----------------------------------------------------------------------------
do_get_subclasses(Tab, ClassId) ->
	ets:match_object(Tab, {'_', ClassId, '_', '_'}).
