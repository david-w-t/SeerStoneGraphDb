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
%% Description: graphdb_rules manages graph database rules.
%%				graphdb_rules is responsible for storing, evaluating,
%%				and enforcing rules applied to graph operations.
%%
%%				Rules are stored in an ETS table (persisted via tab2file).
%%				Each rule record has the form:
%%				  {RuleId::nref(), Name::binary(), Event::atom(), Condition::term(), Action::term()}
%%
%%				Event is the graph operation the rule fires on:
%%				  create_node | delete_node | create_edge | delete_edge | set_attr
%%
%%				Condition is an Erlang term matched against the operation context.
%%				  {class, ClassId}    — fires only for instances of ClassId
%%				  {attr, Name, Value} — fires when attribute Name = Value
%%				  any                 — fires for all events of the given type
%%
%%				Action is an Erlang term describing what to do when the rule fires:
%%				  {deny, Reason}      — abort the operation with Reason
%%				  {log, Message}      — log a message (no-op in this implementation)
%%				  allow               — explicitly permit (default when no deny fires)
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Stub implementation.
%%---------------------------------------------------------------------
%% Rev A Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Full implementation: ETS-backed rule store with evaluate/2.
%%---------------------------------------------------------------------
-module(graphdb_rules).
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

-define(TAB, graphdb_rules_tab).
-define(TAB_FILE, "graphdb_rules.ets").

%%---------------------------------------------------------------------
%% Exported Functions
%%---------------------------------------------------------------------
%%---------------------------------------------------------------------
%% Exports External API
%%---------------------------------------------------------------------
-export([
		start_link/0,
		add_rule/4,		%% add_rule(Name, Event, Condition, Action) -> {ok, RuleId} | {error, Reason}
		get_rule/1,		%% get_rule(RuleId) -> {ok, Rule} | {error, not_found}
		delete_rule/1,	%% delete_rule(RuleId) -> ok | {error, not_found}
		all_rules/0,	%% all_rules() -> [Rule]
		evaluate/2		%% evaluate(Event, Context) -> allow | {deny, Reason}
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
%% add_rule(Name, Event, Condition, Action) -> {ok, RuleId} | {error, Reason}
%%
%% Name      = binary()
%% Event     = create_node | delete_node | create_edge | delete_edge | set_attr
%% Condition = {class, ClassId} | {attr, Name, Value} | any
%% Action    = {deny, Reason} | {log, Message} | allow
%%-----------------------------------------------------------------------------
add_rule(Name, Event, Condition, Action) ->
	gen_server:call(?MODULE, {add_rule, Name, Event, Condition, Action}).

%%-----------------------------------------------------------------------------
%% get_rule(RuleId) -> {ok, {RuleId, Name, Event, Condition, Action}} | {error, not_found}
%%-----------------------------------------------------------------------------
get_rule(RuleId) ->
	gen_server:call(?MODULE, {get_rule, RuleId}).

%%-----------------------------------------------------------------------------
%% delete_rule(RuleId) -> ok | {error, not_found}
%%-----------------------------------------------------------------------------
delete_rule(RuleId) ->
	gen_server:call(?MODULE, {delete_rule, RuleId}).

%%-----------------------------------------------------------------------------
%% all_rules() -> [{RuleId, Name, Event, Condition, Action}]
%%-----------------------------------------------------------------------------
all_rules() ->
	gen_server:call(?MODULE, all_rules).

%%-----------------------------------------------------------------------------
%% evaluate(Event, Context) -> allow | {deny, Reason}
%%
%% Evaluates all rules matching Event against Context.
%% Returns {deny, Reason} if any deny rule fires; otherwise allow.
%%
%% Context is a proplist, e.g.:
%%   [{class, ClassId}, {attr, Name, Value}, ...]
%%-----------------------------------------------------------------------------
evaluate(Event, Context) ->
	gen_server:call(?MODULE, {evaluate, Event, Context}).


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
handle_call({add_rule, Name, Event, Condition, Action}, _From, Tab) ->
	RuleId = nref_server:get_nref(),
	ets:insert(Tab, {RuleId, Name, Event, Condition, Action}),
	{reply, {ok, RuleId}, Tab};
handle_call({get_rule, RuleId}, _From, Tab) ->
	Reply = case ets:lookup(Tab, RuleId) of
		[Rule] -> {ok, Rule};
		[]     -> {error, not_found}
	end,
	{reply, Reply, Tab};
handle_call({delete_rule, RuleId}, _From, Tab) ->
	Reply = case ets:lookup(Tab, RuleId) of
		[_] ->
			ets:delete(Tab, RuleId),
			ok;
		[] ->
			{error, not_found}
	end,
	{reply, Reply, Tab};
handle_call(all_rules, _From, Tab) ->
	{reply, ets:tab2list(Tab), Tab};
handle_call({evaluate, Event, Context}, _From, Tab) ->
	Reply = do_evaluate(Tab, Event, Context),
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
%%-----------------------------------------------------------------------------
open_tab() ->
	case filelib:is_file(?TAB_FILE) of
	true ->
		{ok, Tab} = ets:file2tab(?TAB_FILE),
		Tab;
	false ->
		ets:new(?TAB, [set, named_table, public])
	end.


%%-----------------------------------------------------------------------------
%% do_evaluate(Tab, Event, Context) -> allow | {deny, Reason}
%%
%% Iterates all rules for the given Event.  Returns {deny, Reason} on the first
%% matching deny rule; returns allow if no deny rule fires.
%%-----------------------------------------------------------------------------
do_evaluate(Tab, Event, Context) ->
	Rules = ets:match_object(Tab, {'_', '_', Event, '_', '_'}),
	eval_rules(Rules, Context).

eval_rules([], _Context) ->
	allow;
eval_rules([{_Id, _Name, _Event, Condition, Action} | Rest], Context) ->
	case condition_matches(Condition, Context) of
	true ->
		case Action of
		{deny, Reason} -> {deny, Reason};
		{log, _Msg}    -> eval_rules(Rest, Context);
		allow          -> eval_rules(Rest, Context)
		end;
	false ->
		eval_rules(Rest, Context)
	end.


%%-----------------------------------------------------------------------------
%% condition_matches(Condition, Context) -> boolean()
%%-----------------------------------------------------------------------------
condition_matches(any, _Context) ->
	true;
condition_matches({class, ClassId}, Context) ->
	proplists:get_value(class, Context) =:= ClassId;
condition_matches({attr, Name, Value}, Context) ->
	proplists:get_value({attr, Name}, Context) =:= Value;
condition_matches(_Unknown, _Context) ->
	false.
