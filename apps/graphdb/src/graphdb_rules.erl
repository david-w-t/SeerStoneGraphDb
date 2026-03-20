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
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Stub implementation.
%% Rev A Date: March 19, 2026 Author: AI
%% Full implementation of rule storage and evaluation.
%%---------------------------------------------------------------------
-module(graphdb_rules).
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

-define(TAB_RULES, graphdb_rules).

%%---------------------------------------------------------------------
%% Type Definitions
%%---------------------------------------------------------------------
-type rule() :: #{
	name => atom(),
	type => validation | constraint | trigger,
	target => atom(),
	condition => fun(),
	action => fun() | undefined,
	enabled => boolean(),
	created => integer()
}.
-type rule_result() :: {ok} | {error, Reason :: term()}.
-export_type([rule/0, rule_result/0]).

%%---------------------------------------------------------------------
%% Exported Functions
%%---------------------------------------------------------------------
%%---------------------------------------------------------------------
%% Exports External API
%%---------------------------------------------------------------------
-export([
		start_link/0,
		%% Rule CRUD
		create_rule/4,
		create_rule/5,
		get_rule/1,
		update_rule/2,
		delete_rule/1,
		enable_rule/1,
		disable_rule/1,
		all_rules/0,
		all_enabled_rules/0,
		rule_count/0,
		%% Rule evaluation
		evaluate/2,
		validate_operation/3
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
%% Rule CRUD API
%%---------------------------------------------------------------------
-spec create_rule(atom(), atom(), atom(), fun()) -> {ok, atom()} | {error, rule_exists}.
create_rule(Name, Type, Target, Condition) ->
	create_rule(Name, Type, Target, Condition, undefined).

-spec create_rule(atom(), atom(), atom(), fun(), fun() | undefined) -> {ok, atom()} | {error, rule_exists}.
create_rule(Name, Type, Target, Condition, Action) when is_atom(Name), is_atom(Type), is_atom(Target), is_function(Condition) ->
	gen_server:call(?MODULE, {create_rule, Name, Type, Target, Condition, Action}).

-spec get_rule(atom()) -> {ok, rule()} | {error, not_found}.
get_rule(Name) ->
	gen_server:call(?MODULE, {get_rule, Name}).

-spec update_rule(atom(), map()) -> ok | {error, not_found}.
update_rule(Name, Updates) ->
	gen_server:call(?MODULE, {update_rule, Name, Updates}).

-spec delete_rule(atom()) -> ok | {error, not_found}.
delete_rule(Name) ->
	gen_server:call(?MODULE, {delete_rule, Name}).

-spec enable_rule(atom()) -> ok | {error, not_found}.
enable_rule(Name) ->
	gen_server:call(?MODULE, {enable_rule, Name}).

-spec disable_rule(atom()) -> ok | {error, not_found}.
disable_rule(Name) ->
	gen_server:call(?MODULE, {disable_rule, Name}).

-spec all_rules() -> [rule()].
all_rules() ->
	gen_server:call(?MODULE, all_rules).

-spec all_enabled_rules() -> [rule()].
all_enabled_rules() ->
	gen_server:call(?MODULE, all_enabled_rules).

-spec rule_count() -> non_neg_integer().
rule_count() ->
	gen_server:call(?MODULE, rule_count).

%%---------------------------------------------------------------------
%% Rule Evaluation API
%%---------------------------------------------------------------------
-spec evaluate(atom() | rule(), term()) -> rule_result().
evaluate(RuleName, Context) when is_atom(RuleName) ->
	gen_server:call(?MODULE, {evaluate, RuleName, Context});
evaluate(Rule, Context) when is_map(Rule) ->
	do_evaluate(Rule, Context).

-spec validate_operation(atom(), term(), term()) -> ok | {error, [term()]}.
validate_operation(_Operation, TargetType, Context) ->
	gen_server:call(?MODULE, {validate_operation, TargetType, Context}).

%%---------------------------------------------------------------------
%% gen_server Behaviour Callbacks
%%---------------------------------------------------------------------

init([]) ->
	?LOG_INFO("graphdb_rules: initializing ETS tables"),
	RulesTab = ets:new(?TAB_RULES, [set, named_table, {keypos, 1}, public]),
	?LOG_INFO("graphdb_rules: ETS tables created"),
	{ok, #{rules => RulesTab}}.

handle_call({create_rule, Name, Type, Target, Condition, Action}, _From, State) ->
	Reply = do_create_rule(Name, Type, Target, Condition, Action),
	{reply, Reply, State};

handle_call({get_rule, Name}, _From, State) ->
	Reply = do_get_rule(Name),
	{reply, Reply, State};

handle_call({update_rule, Name, Updates}, _From, State) ->
	Reply = do_update_rule(Name, Updates),
	{reply, Reply, State};

handle_call({delete_rule, Name}, _From, State) ->
	Reply = do_delete_rule(Name),
	{reply, Reply, State};

handle_call({enable_rule, Name}, _From, State) ->
	Reply = do_enable_rule(Name),
	{reply, Reply, State};

handle_call({disable_rule, Name}, _From, State) ->
	Reply = do_disable_rule(Name),
	{reply, Reply, State};

handle_call(all_rules, _From, State) ->
	Reply = do_all_rules(),
	{reply, Reply, State};

handle_call(all_enabled_rules, _From, State) ->
	Reply = do_all_enabled_rules(),
	{reply, Reply, State};

handle_call(rule_count, _From, State) ->
	Reply = ets:info(?TAB_RULES, size),
	{reply, Reply, State};

handle_call({evaluate, RuleName, Context}, _From, State) ->
	Reply = do_evaluate_rule(RuleName, Context),
	{reply, Reply, State};

handle_call({validate_operation, TargetType, Context}, _From, State) ->
	Reply = do_validate_operation(TargetType, Context),
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
do_create_rule(Name, Type, Target, Condition, Action) ->
	case ets:lookup(?TAB_RULES, Name) of
		[_] ->
			{error, rule_exists};
		[] ->
			Now = erlang:system_time(second),
			Rule = #{
				name => Name,
				type => Type,
				target => Target,
				condition => Condition,
				action => Action,
				enabled => true,
				created => Now
			},
			true = ets:insert(?TAB_RULES, {Name, Rule}),
			?LOG_INFO("graphdb_rules: created rule ~p type ~p target ~p", [Name, Type, Target]),
			{ok, Name}
	end.

do_get_rule(Name) ->
	case ets:lookup(?TAB_RULES, Name) of
		[{_, Rule}] -> {ok, Rule};
		[] -> {error, not_found}
	end.

do_update_rule(Name, Updates) ->
	case ets:lookup(?TAB_RULES, Name) of
		[{_, OldRule}] ->
			NewRule = maps:merge(OldRule, Updates),
			true = ets:insert(?TAB_RULES, {Name, NewRule}),
			ok;
		[] ->
			{error, not_found}
	end.

do_delete_rule(Name) ->
	case ets:lookup(?TAB_RULES, Name) of
		[{_, _}] ->
			true = ets:delete(?TAB_RULES, Name),
			ok;
		[] ->
			{error, not_found}
	end.

do_enable_rule(Name) ->
	do_update_rule(Name, #{enabled => true}).

do_disable_rule(Name) ->
	do_update_rule(Name, #{enabled => false}).

do_all_rules() ->
	[ Rule || {_, Rule} <- ets:tab2list(?TAB_RULES) ].

do_all_enabled_rules() ->
	[ Rule || {_, Rule} <- ets:tab2list(?TAB_RULES), maps:get(enabled, Rule, false) =:= true ].

do_evaluate(Rule, Context) ->
	case maps:get(enabled, Rule, false) of
		false -> {ok};
		true ->
			Condition = maps:get(condition, Rule),
			try Condition(Context) of
				true -> {ok};
				false -> {error, rule_failed};
				{error, Reason} -> {error, Reason};
				Other -> {error, {invalid_return, Other}}
			catch
				_:Error -> {error, Error}
			end
	end.

do_evaluate_rule(RuleName, Context) ->
	case do_get_rule(RuleName) of
		{ok, Rule} -> do_evaluate(Rule, Context);
		{error, not_found} -> {error, not_found}
	end.

do_validate_operation(TargetType, Context) ->
	EnabledRules = do_all_enabled_rules(),
	MatchingRules = [ R || R <- EnabledRules, maps:get(target, R) =:= TargetType ],
	ValidationResults = [ {maps:get(name, Rule), do_evaluate(Rule, Context)} || Rule <- MatchingRules ],
	case [ Name || {Name, Result} <- ValidationResults, element(1, Result) =:= error ] of
		[] -> ok;
		Failed -> {error, Failed}
	end.
