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
%%
%%				This implementation uses an Erlang-term DSL — queries
%%				are expressed as Erlang tuples rather than a text syntax.
%%				This avoids the need for a lexer/parser at this stage and
%%				can be extended to a full text grammar later.
%%
%%				Supported query forms:
%%
%%				  {get, Nref}
%%				    — Retrieve a single node or edge by Nref.
%%				    — Returns {ok, Instance} | {error, not_found}
%%
%%				  {find_by_attr, Name::binary(), Value::term()}
%%				    — Find all nodes/edges that have attribute Name = Value.
%%				    — Returns [Nref]
%%
%%				  {match, ClassId::nref()}
%%				    — Find all node instances of the given ClassId.
%%				    — Returns [NodeInstance]
%%
%%				  {traverse, FromNref::nref(), ClassId::nref(), Depth::pos_integer()}
%%				    — Starting from FromNref, follow edges of ClassId up to Depth hops.
%%				    — Returns [{Depth::integer(), Nref::nref(), Instance}]
%%
%%				  {and_query, [Query]}
%%				    — Execute multiple queries and return the intersection of Nrefs.
%%
%%				  {or_query, [Query]}
%%				    — Execute multiple queries and return the union of Nrefs.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Stub implementation.
%%---------------------------------------------------------------------
%% Rev A Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Full implementation: Erlang-term DSL query interpreter.
%%---------------------------------------------------------------------
-module(graphdb_language).
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
		execute/1		%% execute(Query) -> Result
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
%% execute(Query) -> Result
%%
%% Executes a DSL query term against the graph database.
%% See module description for supported query forms.
%%-----------------------------------------------------------------------------
execute(Query) ->
	gen_server:call(?MODULE, {execute, Query}).


%%=============================================================================
%% gen_server Behaviour Callbacks
%%=============================================================================

%%-----------------------------------------------------------------------------
%% init([]) -> {ok, State}
%%
%% graphdb_language holds no persistent state.
%%-----------------------------------------------------------------------------
init([]) ->
	{ok, []}.


%%-----------------------------------------------------------------------------
%% handle_call/3
%%-----------------------------------------------------------------------------
handle_call({execute, Query}, _From, State) ->
	Reply = do_execute(Query),
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


%%=============================================================================
%% Internal Functions
%%=============================================================================

%%-----------------------------------------------------------------------------
%% do_execute(Query) -> Result
%%-----------------------------------------------------------------------------

%% {get, Nref} — retrieve a single node or edge by Nref
do_execute({get, Nref}) ->
	graphdb_instance:get(Nref);

%% {find_by_attr, Name, Value} — find all Nrefs with a given attribute value
do_execute({find_by_attr, Name, Value}) ->
	%% Scan all nodes and edges; collect those whose attribute Name = Value.
	Nodes = graphdb_instance:all_nodes(),
	Edges = graphdb_instance:all_edges(),
	All   = Nodes ++ Edges,
	[element(1, I) || I <- All,
		graphdb_attr:get_attr(element(1, I), Name) =:= {ok, Value}];

%% {match, ClassId} — find all node instances of ClassId
do_execute({match, ClassId}) ->
	All = graphdb_instance:all_nodes(),
	[I || I <- All, element(3, I) =:= ClassId];

%% {traverse, FromNref, ClassId, Depth} — follow edges of ClassId up to Depth hops
do_execute({traverse, FromNref, ClassId, Depth}) ->
	do_traverse([{0, FromNref}], ClassId, Depth, [], [FromNref]);

%% {and_query, Queries} — intersection of Nref results
do_execute({and_query, Queries}) ->
	Results = [nrefs_from(do_execute(Q)) || Q <- Queries],
	lists:foldl(fun(S, Acc) -> [N || N <- Acc, lists:member(N, S)] end,
				hd(Results), tl(Results));

%% {or_query, Queries} — union of Nref results
do_execute({or_query, Queries}) ->
	Results = [nrefs_from(do_execute(Q)) || Q <- Queries],
	lists:usort(lists:append(Results));

do_execute(Unknown) ->
	{error, {unknown_query, Unknown}}.


%%-----------------------------------------------------------------------------
%% do_traverse(Queue, ClassId, MaxDepth, Acc, Visited) -> [{Depth, Nref, Instance}]
%%
%% BFS traversal following edges of ClassId.
%%-----------------------------------------------------------------------------
do_traverse([], _ClassId, _MaxDepth, Acc, _Visited) ->
	lists:reverse(Acc);
do_traverse([{Depth, _Nref} | Rest], ClassId, MaxDepth, Acc, Visited)
		when Depth >= MaxDepth ->
	do_traverse(Rest, ClassId, MaxDepth, Acc, Visited);
do_traverse([{Depth, Nref} | Rest], ClassId, MaxDepth, Acc, Visited) ->
	Edges = graphdb_instance:get_edges(Nref),
	%% Filter to only edges of the requested ClassId.
	Matching = [E || E <- Edges, element(5, E) =:= ClassId],
	%% Collect destination Nrefs not yet visited.
	NewNrefs = [element(4, E) || E <- Matching,
					not lists:member(element(4, E), Visited)],
	NewQueue = Rest ++ [{Depth + 1, N} || N <- NewNrefs],
	NewVisited = Visited ++ NewNrefs,
	%% Fetch instances for new Nrefs and accumulate.
	NewAcc = lists:foldl(
		fun(N, A) ->
			case graphdb_instance:get(N) of
			{ok, Inst} -> [{Depth + 1, N, Inst} | A];
			_          -> A
			end
		end, Acc, NewNrefs),
	do_traverse(NewQueue, ClassId, MaxDepth, NewAcc, NewVisited).


%%-----------------------------------------------------------------------------
%% nrefs_from(Result) -> [Nref]
%%
%% Extracts a list of Nrefs from the various result shapes returned by do_execute.
%%-----------------------------------------------------------------------------
nrefs_from({ok, Instance}) when is_tuple(Instance) ->
	[element(1, Instance)];
nrefs_from(List) when is_list(List) ->
	%% Could be a list of Nrefs, instances, or traverse results.
	lists:map(fun
		({_Depth, Nref, _Inst}) -> Nref;
		(Inst) when is_tuple(Inst) -> element(1, Inst);
		(Nref) when is_integer(Nref) -> Nref
	end, List);
nrefs_from(_) ->
	[].
