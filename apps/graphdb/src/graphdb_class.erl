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
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Stub implementation.
%% Rev A Date: March 19, 2026 Author: AI
%% Full implementation of class hierarchy and type system.
%%---------------------------------------------------------------------
-module(graphdb_class).
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

-define(TAB_CLASSES, graphdb_classes).
-define(TAB_HIERARCHY, graphdb_class_hierarchy).

%%---------------------------------------------------------------------
%% Type Definitions
%%---------------------------------------------------------------------
-type class_def() :: #{
	name => atom(),
	parent => atom() | undefined,
	attrs => map(),
	created => integer()
}.
-export_type([class_def/0]).

%%---------------------------------------------------------------------
%% Exported Functions
%%---------------------------------------------------------------------
%%---------------------------------------------------------------------
%% Exports External API
%%---------------------------------------------------------------------
-export([
		start_link/0,
		%% Class CRUD
		create_class/2,
		create_class/3,
		get_class/1,
		update_class/2,
		delete_class/1,
		all_classes/0,
		class_count/0,
		%% Hierarchy operations
		get_parent/1,
		get_subclasses/1,
		is_a/2,
		get_ancestors/1,
		get_descendants/1
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
%% Class API
%%---------------------------------------------------------------------
-spec create_class(atom(), map()) -> {ok, atom()} | {error, class_exists}.
create_class(Name, Attrs) ->
	create_class(Name, undefined, Attrs).

-spec create_class(atom(), atom() | undefined, map()) -> {ok, atom()} | {error, class_exists}.
create_class(Name, Parent, Attrs) when is_atom(Name), is_map(Attrs) ->
	gen_server:call(?MODULE, {create_class, Name, Parent, Attrs}).

-spec get_class(atom()) -> {ok, class_def()} | {error, not_found}.
get_class(Name) ->
	gen_server:call(?MODULE, {get_class, Name}).

-spec update_class(atom(), map()) -> ok | {error, not_found}.
update_class(Name, Attrs) ->
	gen_server:call(?MODULE, {update_class, Name, Attrs}).

-spec delete_class(atom()) -> ok | {error, not_found}.
delete_class(Name) ->
	gen_server:call(?MODULE, {delete_class, Name}).

-spec all_classes() -> [atom()].
all_classes() ->
	gen_server:call(?MODULE, all_classes).

-spec class_count() -> non_neg_integer().
class_count() ->
	gen_server:call(?MODULE, class_count).

%%---------------------------------------------------------------------
%% Hierarchy API
%%---------------------------------------------------------------------
-spec get_parent(atom()) -> {ok, atom()} | undefined | {error, not_found}.
get_parent(Name) ->
	gen_server:call(?MODULE, {get_parent, Name}).

-spec get_subclasses(atom()) -> [atom()].
get_subclasses(Name) ->
	gen_server:call(?MODULE, {get_subclasses, Name}).

-spec is_a(atom(), atom()) -> boolean().
is_a(Child, Parent) ->
	gen_server:call(?MODULE, {is_a, Child, Parent}).

-spec get_ancestors(atom()) -> [atom()].
get_ancestors(Name) ->
	gen_server:call(?MODULE, {get_ancestors, Name}).

-spec get_descendants(atom()) -> [atom()].
get_descendants(Name) ->
	gen_server:call(?MODULE, {get_descendants, Name}).

%%---------------------------------------------------------------------
%% gen_server Behaviour Callbacks
%%---------------------------------------------------------------------

init([]) ->
	?LOG_INFO("graphdb_class: initializing ETS tables"),
	ClassesTab = ets:new(?TAB_CLASSES, [set, named_table, {keypos, 1}, public]),
	HierarchyTab = ets:new(?TAB_HIERARCHY, [set, named_table, {keypos, 1}, public]),
	create_builtin_classes(ClassesTab, HierarchyTab),
	?LOG_INFO("graphdb_class: initialized with builtin classes"),
	{ok, #{classes => ClassesTab, hierarchy => HierarchyTab}}.

handle_call({create_class, Name, Parent, Attrs}, _From, State) ->
	Reply = do_create_class(Name, Parent, Attrs),
	{reply, Reply, State};

handle_call({get_class, Name}, _From, State) ->
	Reply = do_get_class(Name),
	{reply, Reply, State};

handle_call({update_class, Name, Attrs}, _From, State) ->
	Reply = do_update_class(Name, Attrs),
	{reply, Reply, State};

handle_call({delete_class, Name}, _From, State) ->
	Reply = do_delete_class(Name),
	{reply, Reply, State};

handle_call(all_classes, _From, State) ->
	Reply = do_all_classes(),
	{reply, Reply, State};

handle_call(class_count, _From, State) ->
	Reply = ets:info(?TAB_CLASSES, size),
	{reply, Reply, State};

handle_call({get_parent, Name}, _From, State) ->
	Reply = do_get_parent(Name),
	{reply, Reply, State};

handle_call({get_subclasses, Name}, _From, State) ->
	Reply = do_get_subclasses(Name),
	{reply, Reply, State};

handle_call({is_a, Child, Parent}, _From, State) ->
	Reply = do_is_a(Child, Parent),
	{reply, Reply, State};

handle_call({get_ancestors, Name}, _From, State) ->
	Reply = do_get_ancestors(Name),
	{reply, Reply, State};

handle_call({get_descendants, Name}, _From, State) ->
	Reply = do_get_descendants(Name),
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
create_builtin_classes(ClassesTab, HierarchyTab) ->
	Now = erlang:system_time(second),
	ets:insert(ClassesTab, {thing, undefined, #{}, Now}),
	ets:insert(ClassesTab, {entity, thing, #{}, Now}),
	_ = ClassesTab,
	ets:insert(HierarchyTab, {thing, []}),
	ets:insert(HierarchyTab, {entity, [thing]}),
	ok.

do_create_class(Name, Parent, Attrs) ->
	case ets:lookup(?TAB_CLASSES, Name) of
		[_] ->
			{error, class_exists};
		[] ->
			Now = erlang:system_time(second),
			Class = {Name, Parent, Attrs, Now},
			true = ets:insert(?TAB_CLASSES, Class),
			update_hierarchy(Name, Parent),
			?LOG_INFO("graphdb_class: created class ~p", [Name]),
			{ok, Name}
	end.

do_get_class(Name) ->
	case ets:lookup(?TAB_CLASSES, Name) of
		[Class] -> {ok, format_class(Class)};
		[] -> {error, not_found}
	end.

do_update_class(Name, Attrs) ->
	case ets:lookup(?TAB_CLASSES, Name) of
		[{Name, Parent, _OldAttrs, Created}] ->
			Class = {Name, Parent, Attrs, Created},
			true = ets:insert(?TAB_CLASSES, Class),
			ok;
		[] ->
			{error, not_found}
	end.

do_delete_class(Name) ->
	case ets:lookup(?TAB_CLASSES, Name) of
		[_] ->
			delete_class_hierarchy(Name),
			true = ets:delete(?TAB_CLASSES, Name),
			ok;
		[] ->
			{error, not_found}
	end.

do_all_classes() ->
	ets:match(?TAB_CLASSES, {'$1', '_', '_', '_'}).

do_get_parent(Name) ->
	case ets:lookup(?TAB_CLASSES, Name) of
		[{Name, Parent, _Attrs, _Created}] -> {ok, Parent};
		[] -> {error, not_found}
	end.

do_get_subclasses(Name) ->
	case ets:lookup(?TAB_HIERARCHY, Name) of
		[{Name, Descendants}] -> Descendants;
		[] -> []
	end.

do_is_a(_Child, undefined) -> true;
do_is_a(thing, thing) -> true;
do_is_a(Child, Parent) ->
	Ancestors = do_get_ancestors(Child),
	lists:member(Parent, Ancestors).

do_get_ancestors(Name) ->
	case ets:lookup(?TAB_CLASSES, Name) of
		[{Name, undefined, _Attrs, _Created}] -> [];
		[{Name, Parent, _Attrs, _Created}] ->
			[Parent | do_get_ancestors(Parent)];
		[] -> []
	end.

do_get_descendants(Name) ->
	case ets:lookup(?TAB_HIERARCHY, Name) of
		[{Name, Descendants}] -> Descendants;
		[] -> []
	end.

update_hierarchy(Name, undefined) ->
	ets:insert(?TAB_HIERARCHY, {Name, []});
update_hierarchy(Name, Parent) ->
	ParentDescendants = case ets:lookup(?TAB_HIERARCHY, Parent) of
		[{Parent, Desc}] -> Desc;
		[] -> []
	end,
	NewDescendants = [Name | ParentDescendants],
	ets:insert(?TAB_HIERARCHY, {Parent, NewDescendants}),
	AllAncestors = do_get_ancestors(Parent),
	lists:foreach(fun(Ancestor) ->
		AncestorDescendants = case ets:lookup(?TAB_HIERARCHY, Ancestor) of
			[{Ancestor, AD}] -> AD;
			[] -> []
		end,
		ets:insert(?TAB_HIERARCHY, {Ancestor, [Name | AncestorDescendants]})
	end, AllAncestors).

delete_class_hierarchy(Name) ->
	case ets:lookup(?TAB_CLASSES, Name) of
		[{Name, Parent, _Attrs, _Created}] ->
			Descendants = do_get_descendants(Name),
			lists:foreach(fun(Desc) ->
				case ets:lookup(?TAB_CLASSES, Desc) of
					[{Desc, DescParent, DescAttrs, DescCreated}] ->
						NewParent = case DescParent of
							Name -> Parent;
							_ -> DescParent
						end,
						ets:insert(?TAB_CLASSES, {Desc, NewParent, DescAttrs, DescCreated});
					[] -> ok
				end
			end, Descendants),
			case Parent of
				undefined -> ok;
				_ ->
					case ets:lookup(?TAB_HIERARCHY, Parent) of
						[{Parent, ParentDescendants}] ->
							NewParentDescendants = lists:delete(Name, ParentDescendants),
							ets:insert(?TAB_HIERARCHY, {Parent, NewParentDescendants});
						[] -> ok
					end
			end;
		[] -> ok
	end.

format_class({Name, Parent, Attrs, Created}) ->
	#{
		name => Name,
		parent => Parent,
		attrs => Attrs,
		created => Created
	}.
