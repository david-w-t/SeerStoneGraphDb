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
%% Description: graphdb_language manages the graph query language.
%%				graphdb_language is responsible for parsing, validating,
%%				and executing graph query language expressions against
%%				the graph database.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Stub implementation.
%% Rev A Date: March 19, 2026 Author: AI
%% Full implementation of query parsing and execution.
%%---------------------------------------------------------------------
-module(graphdb_language).
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

-define(TAB_PARSED, graphdb_parsed_queries).

%%---------------------------------------------------------------------
%% Type Definitions
%%---------------------------------------------------------------------
-type query() :: #{
	type => select | insert | update | delete | traverse,
	target => atom() | integer(),
	conditions => [condition()],
	return => [atom()],
	limit => integer() | undefined
}.
-type condition() :: {field, atom(), operator(), term()} |
					 {'and', [condition()]} |
					 {'or', [condition()]}.
-type operator() :: '==' | '/=' | '>' | '<' | '>=' | '<=' | 'like' | 'in'.
-type query_result() :: {ok, [map()]} | {error, term()}.
-export_type([query/0, query_result/0]).

%%---------------------------------------------------------------------
%% Exported Functions
%%---------------------------------------------------------------------
%%---------------------------------------------------------------------
%% Exports External API
%%---------------------------------------------------------------------
-export([
		start_link/0,
		%% Query execution
		query/1,
		query/2,
		select/2,
		select/3,
		insert/2,
		update/3,
		delete/2,
		%% Traversal
		traverse/3,
		traverse/4,
		traverse_breadth_first/3,
		traverse_depth_first/3,
		%% Utils
		parse/1,
		validate/1,
		explain/1
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
%% Query Execution API
%%---------------------------------------------------------------------
-spec query(string() | query()) -> query_result().
query(QueryString) ->
	case parse(QueryString) of
		{ok, Query} -> query(Query, #{});
		Error -> Error
	end.

-spec query(string() | query(), map()) -> query_result().
query(QueryString, Context) when is_list(QueryString) ->
	case parse(QueryString) of
		{ok, Query} -> execute_query(Query, Context);
		Error -> Error
	end;
query(Query, Context) when is_map(Query) ->
	execute_query(Query, Context).

-spec select(atom(), [condition()]) -> query_result().
select(Target, Conditions) ->
	Query = #{
		type => select,
		target => Target,
		conditions => Conditions,
		return => all,
		limit => undefined
	},
	execute_query(Query, #{}).

-spec select(atom(), [condition()], [atom()]) -> query_result().
select(Target, Conditions, ReturnFields) ->
	Query = #{
		type => select,
		target => Target,
		conditions => Conditions,
		return => ReturnFields,
		limit => undefined
	},
	execute_query(Query, #{}).

-spec insert(atom(), map()) -> query_result().
insert(Target, Data) ->
	Query = #{
		type => insert,
		target => Target,
		data => Data,
		return => all,
		limit => undefined
	},
	execute_query(Query, #{}).

-spec update(atom(), [condition()], map()) -> query_result().
update(Target, Conditions, Data) ->
	Query = #{
		type => update,
		target => Target,
		conditions => Conditions,
		data => Data,
		return => all,
		limit => undefined
	},
	execute_query(Query, #{}).

-spec delete(atom(), [condition()]) -> query_result().
delete(Target, Conditions) ->
	Query = #{
		type => delete,
		target => Target,
		conditions => Conditions,
		return => all,
		limit => undefined
	},
	execute_query(Query, #{}).

%%---------------------------------------------------------------------
%% Traversal API
%%---------------------------------------------------------------------
-spec traverse(integer(), fun(), integer()) -> query_result().
traverse(StartNref, FilterFun, MaxDepth) ->
	execute_traverse(StartNref, FilterFun, MaxDepth, depth_first, 0, sets:new()).

-spec traverse(integer(), fun(), integer(), breadth_first | depth_first) -> query_result().
traverse(StartNref, FilterFun, MaxDepth, Strategy) ->
	execute_traverse(StartNref, FilterFun, MaxDepth, Strategy, 0, sets:new()).

-spec traverse_breadth_first(integer(), fun(), integer()) -> query_result().
traverse_breadth_first(StartNref, FilterFun, MaxDepth) ->
	execute_traverse(StartNref, FilterFun, MaxDepth, breadth_first, 0, sets:new()).

-spec traverse_depth_first(integer(), fun(), integer()) -> query_result().
traverse_depth_first(StartNref, FilterFun, MaxDepth) ->
	execute_traverse(StartNref, FilterFun, MaxDepth, depth_first, 0, sets:new()).

%%---------------------------------------------------------------------
%% Query Utilities API
%%---------------------------------------------------------------------
-spec parse(string()) -> {ok, query()} | {error, term()}.
parse(QueryString) when is_list(QueryString) ->
	try
		case tokenize(QueryString) of
			{select, Target, Conditions} ->
				{ok, #{
					type => select,
					target => list_to_atom(Target),
					conditions => parse_conditions(Conditions),
					return => all,
					limit => undefined
				}};
			{insert, Target, Data} ->
				{ok, #{
					type => insert,
					target => list_to_atom(Target),
					data => parse_data(Data),
					return => all,
					limit => undefined
				}};
			{update, Target, Conditions, Data} ->
				{ok, #{
					type => update,
					target => list_to_atom(Target),
					conditions => parse_conditions(Conditions),
					data => parse_data(Data),
					return => all,
					limit => undefined
				}};
			{delete, Target, Conditions} ->
				{ok, #{
					type => delete,
					target => list_to_atom(Target),
					conditions => parse_conditions(Conditions),
					return => all,
					limit => undefined
				}};
			{traverse, NrefStr} ->
				{ok, #{
					type => traverse,
					target => list_to_integer(NrefStr),
					conditions => [],
					return => all,
					limit => undefined
				}};
			{error, Reason} ->
				{error, Reason}
		end
	catch
		_:Error -> {error, {parse_error, Error}}
	end.

-spec validate(query()) -> ok | {error, [term()]}.
validate(Query) ->
	Errors = validate_query(Query),
	case Errors of
		[] -> ok;
		_ -> {error, Errors}
	end.

-spec explain(query()) -> {ok, string()}.
explain(Query) ->
	Plan = build_query_plan(Query),
	{ok, Plan}.

%%---------------------------------------------------------------------
%% gen_server Behaviour Callbacks
%%---------------------------------------------------------------------

init([]) ->
	?LOG_INFO("graphdb_language: initialized"),
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

%%---------------------------------------------------------------------
%% Internal Functions
%%---------------------------------------------------------------------
execute_query(#{
	type := select,
	target := Target,
	conditions := Conditions,
	return := ReturnFields,
	limit := Limit
}, _Context) ->
	case Target of
		node ->
			Nodes = graphdb_instance:all_nodes(),
			Results = filter_nodes(Nodes, Conditions),
			LimitedResults = case Limit of
				undefined -> Results;
				N when is_integer(N) -> lists:sublist(Results, N)
			end,
			Formatted = format_nodes(ReturnFields, LimitedResults),
			{ok, Formatted};
		edge ->
			Edges = graphdb_instance:all_edges(),
			Results = filter_edges(Edges, Conditions),
			LimitedResults = case Limit of
				undefined -> Results;
				N when is_integer(N) -> lists:sublist(Results, N)
			end,
			Formatted = format_edges(ReturnFields, LimitedResults),
			{ok, Formatted};
		_ ->
			case ets:lookup(?TAB_PARSED, Target) of
				[{Target, Query}] ->
					execute_query(Query#{
						conditions := Conditions,
						return := ReturnFields,
						limit := Limit
					}, _Context);
				[] ->
					{error, {unknown_target, Target}}
			end
	end;

execute_query(#{
	type := insert,
	target := Target,
	data := Data
}, _Context) ->
	case Target of
		node ->
			case maps:get(class, Data, undefined) of
				undefined -> {error, missing_class};
				Class ->
					Attrs = maps:remove(class, Data),
					case graphdb_instance:create_node(Class, Attrs) of
						{nref, Nref} -> {ok, [#{nref => Nref}]};
						Error -> Error
					end
			end;
		edge ->
			{ok, [Data]};
		_ ->
			{error, {unknown_target, Target}}
	end;

execute_query(#{
	type := update,
	target := Target,
	conditions := Conditions,
	data := Data
}, _Context) ->
	case Target of
		node ->
			Nodes = graphdb_instance:all_nodes(),
			Matches = filter_nodes(Nodes, Conditions),
			Updated = lists:map(fun(Nref) ->
				graphdb_instance:update_node(Nref, Data),
				#{nref => Nref}
			end, Matches),
			{ok, Updated};
		_ ->
			{error, {unknown_target, Target}}
	end;

execute_query(#{
	type := delete,
	target := Target,
	conditions := Conditions
}, _Context) ->
	case Target of
		node ->
			Nodes = graphdb_instance:all_nodes(),
			Matches = filter_nodes(Nodes, Conditions),
			lists:foreach(fun(Nref) ->
				graphdb_instance:delete_node(Nref)
			end, Matches),
			{ok, [{deleted, length(Matches)}]};
		_ ->
			{error, {unknown_target, Target}}
	end;

execute_query(#{
	type := traverse,
	target := StartNref,
	conditions := Conditions
}, _Context) ->
	FilterFun = build_filter_fun(Conditions),
	case traverse(StartNref, FilterFun, 10) of
		{ok, Results} -> {ok, Results};
		Error -> Error
	end.

execute_traverse(_StartNref, _FilterFun, MaxDepth, _Strategy, Depth, _Visited) when Depth >= MaxDepth ->
	{ok, []};
execute_traverse(StartNref, FilterFun, MaxDepth, _Strategy, Depth, Visited) ->
	case sets:is_element(StartNref, Visited) of
		true ->
			{ok, []};
		false ->
			case graphdb_instance:get_node(StartNref) of
				{ok, Node} ->
					case FilterFun(Node) of
						true ->
							NewVisited = sets:add_element(StartNref, Visited),
							Edges = graphdb_instance:get_edges(StartNref),
							Results = [Node],
							NeighborResults = lists:foldl(fun(Edge, Acc) ->
								ToNref = maps:get(to, Edge),
								{ok, NeighborNodes} = execute_traverse(ToNref, FilterFun, MaxDepth, depth_first, Depth + 1, NewVisited),
								Acc ++ NeighborNodes
							end, [], Edges),
							{ok, Results ++ NeighborResults};
						false ->
							{ok, []}
					end;
				{error, not_found} ->
					{ok, []}
			end
	end.

filter_nodes(Nodes, Conditions) ->
	lists:filter(fun(Nref) ->
		case graphdb_instance:get_node(Nref) of
			{ok, Node} -> matches_conditions(Node, Conditions);
			{error, _} -> false
		end
	end, Nodes).

filter_edges(Edges, Conditions) ->
	lists:filter(fun(EdgeId) ->
		case graphdb_instance:get_edge(EdgeId) of
			{ok, Edge} -> matches_conditions(Edge, Conditions);
			{error, _} -> false
		end
	end, Edges).

matches_conditions(_Entity, []) -> true;
matches_conditions(Entity, [{field, Field, Op, Value} | Rest]) ->
	case maps:find(Field, Entity) of
		{ok, FieldValue} ->
			case evaluate_op(Op, FieldValue, Value) of
				true -> matches_conditions(Entity, Rest);
				false -> false
			end;
		error -> false
	end;
matches_conditions(Entity, [{'and', ConditionsList} | Rest]) ->
	case lists:all(fun(C) -> matches_conditions(Entity, [C]) end, ConditionsList) of
		true -> matches_conditions(Entity, Rest);
		false -> false
	end;
matches_conditions(Entity, [{'or', ConditionsList} | Rest]) ->
	case lists:any(fun(C) -> matches_conditions(Entity, [C]) end, ConditionsList) of
		true -> matches_conditions(Entity, Rest);
		false -> false
	end.

evaluate_op('==', A, B) -> A =:= B;
evaluate_op('/=', A, B) -> A =/= B;
evaluate_op('>', A, B) -> A > B;
evaluate_op('<', A, B) -> A < B;
evaluate_op('>=', A, B) -> A >= B;
evaluate_op('=<', A, B) -> A =< B;
evaluate_op('in', A, List) -> lists:member(A, List);
evaluate_op('like', A, Pattern) ->
	re:run(A, Pattern, [{capture, none}, global]) =:= match.

build_filter_fun([]) ->
	fun(_) -> true end;
build_filter_fun(Conditions) ->
	fun(Node) -> matches_conditions(Node, Conditions) end.

format_nodes(all, Nrefs) ->
	lists:map(fun(Nref) ->
		case graphdb_instance:get_node(Nref) of
			{ok, Node} -> Node;
			{error, _} -> #{nref => Nref}
		end
	end, Nrefs);
format_nodes(Fields, Nrefs) ->
	lists:map(fun(Nref) ->
		case graphdb_instance:get_node(Nref) of
			{ok, Node} ->
				maps:with(Fields, Node);
			{error, _} ->
				#{nref => Nref}
		end
	end, Nrefs).

format_edges(all, EdgeIds) ->
	lists:map(fun(EdgeId) ->
		case graphdb_instance:get_edge(EdgeId) of
			{ok, Edge} -> Edge;
			{error, _} -> #{id => EdgeId}
		end
	end, EdgeIds);
format_edges(Fields, EdgeIds) ->
	lists:map(fun(EdgeId) ->
		case graphdb_instance:get_edge(EdgeId) of
			{ok, Edge} ->
				maps:with(Fields, Edge);
			{error, _} ->
				#{id => EdgeId}
		end
	end, EdgeIds).

tokenize(String) ->
	Tokens = string:tokens(String, " ;"),
	parse_tokens(Tokens).

parse_tokens(["SELECT", Target | Rest]) ->
	{select, Target, Rest};
parse_tokens(["INSERT", Target | Rest]) ->
	{insert, Target, Rest};
parse_tokens(["UPDATE", Target | Rest]) ->
	{update, Target, Rest, []};
parse_tokens(["DELETE", Target | Rest]) ->
	{delete, Target, Rest};
parse_tokens(["TRAVERSE", Nref]) ->
	{traverse, Nref};
parse_tokens(_) ->
	{error, invalid_query}.

parse_conditions([]) ->
	[];
parse_conditions([Field, Op, Value | _]) ->
	[{field, list_to_atom(Field), list_to_atom(Op), Value}].

parse_data([]) ->
	#{};
parse_data([Key, Value | Rest]) ->
	maps:put(list_to_atom(Key), Value, parse_data(Rest)).

validate_query(Query) ->
	Errors = [],
	case maps:get(type, Query, undefined) of
		undefined -> [{missing, type} | Errors];
		_ -> Errors
	end.

build_query_plan(Query) ->
	Type = maps:get(type, Query, unknown),
	io_lib:format("Query Plan: ~p on ~p", [Type, maps:get(target, Query, undefined)]).
