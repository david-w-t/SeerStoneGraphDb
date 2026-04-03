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
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Stub implementation.
%%---------------------------------------------------------------------
%% Rev A Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Implementation completed.
%%---------------------------------------------------------------------
-module(graphdb_attr).
-behaviour(gen_server).


%%---------------------------------------------------------------------
%% Module Attributes
%%---------------------------------------------------------------------
-revision('Revision: A ').
-created('Date: *** 2008').
-created_by('dallas.noyes@gmail.com').
-modified('Date: April 2026').
-modified_by('claude').

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
		create_name_attribute/1,
		create_literal_attribute/1,
		create_literal_attribute/2,
		create_relationship_attribute/2,
		create_relationship_type/1,
		add_attribute_to_type/2,
		relationship_avp_flag/0,
		get_attribute/1,
		list_attributes/0,
		list_relationship_types/0
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
%% create_name_attribute(Name) -> {ok, Nref} | {error, Reason}
%%
%% Creates a name attribute. Used for class names, instance names,
%% and any attribute whose value is a label used for naming.
%%---------------------------------------------------------------------
create_name_attribute(Name) ->
	gen_server:call(?MODULE, {create_name_attribute, Name}).


%%---------------------------------------------------------------------
%% create_literal_attribute(#{name => Name, type => Type})
%%   -> {ok, Nref} | {error, Reason}
%% create_literal_attribute(Name, Type)
%%   -> {ok, Nref} | {error, Reason}
%%
%% Creates a literal attribute for scalar/external values (numbers,
%% strings, URLs, filenames).
%% Optional key relationship_avp => true marks this as an attribute
%% intended for use on relationship arcs rather than node records.
%%---------------------------------------------------------------------
create_literal_attribute(#{name := Name, type := Type} = AttrMap) ->
	gen_server:call(?MODULE, {create_literal_attribute, Name, Type, AttrMap}).
create_literal_attribute(Name, Type) ->
	gen_server:call(?MODULE, {create_literal_attribute, Name, Type, #{}}).


%%---------------------------------------------------------------------
%% create_relationship_attribute(AttrNref, ReciprocalNref)
%%   -> {ok, AttrNref, ReciprocalNref} | {error, Reason}
%%
%% Creates a reciprocal pair of relationship attributes grouped under
%% a relationship type.
%%---------------------------------------------------------------------
create_relationship_attribute(AttrNref, ReciprocalNref) ->
	gen_server:call(?MODULE, {create_relationship_attribute, AttrNref, ReciprocalNref}).


%%---------------------------------------------------------------------
%% create_relationship_type(Name) -> {ok, Nref} | {error, Reason}
%%
%% Creates a named relationship type (e.g., "Location", "Family")
%% under which relationship attributes are grouped.
%%---------------------------------------------------------------------
create_relationship_type(Name) ->
	gen_server:call(?MODULE, {create_relationship_type, Name}).


%%---------------------------------------------------------------------
%% add_attribute_to_type(TypeNref, AttrNref) -> ok | {error, Reason}
%%
%% Adds an existing attribute to a relationship type.
%%---------------------------------------------------------------------
add_attribute_to_type(TypeNref, AttrNref) ->
	gen_server:call(?MODULE, {add_attribute_to_type, TypeNref, AttrNref}).


%%---------------------------------------------------------------------
%% relationship_avp_flag() -> {ok, Nref}
%%
%% Returns the Nref of the relationship_avp flag attribute.
%%---------------------------------------------------------------------
relationship_avp_flag() ->
	gen_server:call(?MODULE, relationship_avp_flag).


%%---------------------------------------------------------------------
%% get_attribute(Nref) -> {ok, AttrMap} | {error, not_found}
%%
%% Retrieves a single attribute record by Nref.
%%---------------------------------------------------------------------
get_attribute(Nref) ->
	gen_server:call(?MODULE, {get_attribute, Nref}).


%%---------------------------------------------------------------------
%% list_attributes() -> [AttrMap]
%%
%% Returns all attribute records.
%%---------------------------------------------------------------------
list_attributes() ->
	gen_server:call(?MODULE, list_attributes).


%%---------------------------------------------------------------------
%% list_relationship_types() -> [{TypeNref, TypeMap}]
%%
%% Returns all relationship type records.
%%---------------------------------------------------------------------
list_relationship_types() ->
	gen_server:call(?MODULE, list_relationship_types).


%%---------------------------------------------------------------------
%% gen_server Behaviour Callbacks
%%---------------------------------------------------------------------

init([]) ->
	ok = open_dets(),
	AttrTab = ets:new(?MODULE, [set, private, named_table]),
	RtypesTab = ets:new(graphdb_attr_rtypes, [set, private, named_table]),
	State0 = #{attr_tab => AttrTab, rtypes_tab => RtypesTab},
	State1 = load_from_dets(State0),
	State2 = seed_relationship_avp_flag(State1),
	{ok, State2}.

handle_call({create_name_attribute, Name}, _From, State0) ->
	{Reply, State1} = do_create_attribute(#{name => Name, attribute_type => name}, State0),
	{reply, Reply, State1};
handle_call({create_literal_attribute, Name, Type, AttrMap}, _From, State0) ->
	Record0 = maps:without([name, type], AttrMap),
	Record = Record0#{name => Name, attribute_type => literal, value_type => Type},
	{Reply, State1} = do_create_attribute(Record, State0),
	{reply, Reply, State1};
handle_call({create_relationship_attribute, AttrNref, ReciprocalNref}, _From, State0) ->
	{Reply, State1} = do_create_relationship_attribute(AttrNref, ReciprocalNref, State0),
	{reply, Reply, State1};
handle_call({create_relationship_type, Name}, _From, State0) ->
	{Reply, State1} = do_create_relationship_type(Name, State0),
	{reply, Reply, State1};
handle_call({add_attribute_to_type, TypeNref, AttrNref}, _From, State) ->
	Reply = do_add_attribute_to_type(TypeNref, AttrNref, State),
	{reply, Reply, State};
handle_call(relationship_avp_flag, _From, #{rel_avp_flag := FlagNref} = State) ->
	{reply, {ok, FlagNref}, State};
handle_call(relationship_avp_flag, _From, State) ->
	{reply, {error, relationship_avp_flag_not_seeded}, State};
handle_call({get_attribute, Nref}, _From, #{attr_tab := Tab} = State) ->
	Reply = case ets:lookup(Tab, Nref) of
		[{Nref, Record}] -> {ok, Record};
		[] -> {error, not_found}
	end,
	{reply, Reply, State};
handle_call(list_attributes, _From, #{attr_tab := Tab} = State) ->
	Records = [Record || {_Nref, Record} <- ets:tab2list(Tab)],
	{reply, Records, State};
handle_call(list_relationship_types, _From, #{rtypes_tab := Tab} = State) ->
	Types = [{Nref, Record} || {Nref, Record} <- ets:tab2list(Tab)],
	{reply, Types, State};
handle_call(Request, From, State) ->
	?UEM(handle_call, {Request, From, State}),
	{noreply, State}.

handle_cast(Message, State) ->
	?UEM(handle_cast, {Message, State}),
	{noreply, State}.

handle_info(Info, State) ->
	?UEM(handle_info, {Info, State}),
	{noreply, State}.

terminate(_Reason, #{attr_tab := Tab, rtypes_tab := RTab}) ->
	save_to_dets(Tab, RTab),
	ok;
terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	?NYI(code_change),
	{ok, State}.


%%=====================================================================
%% Internal Functions
%%=====================================================================

open_dets() ->
	File = "graphdb_attr.dets",
	Exists = filelib:is_file(File),
	logger:info("opening dets file: ~p", [File]),
	case dets:open_file(graphdb_attr_dets, [{file, File}]) of
		{ok, graphdb_attr_dets} ->
			case Exists of
				true -> ok;
				false ->
					dets:insert(graphdb_attr_dets,
						[{next_nref, 1},
						 {attributes, []},
						 {relationship_types, []}]),
					ok
			end;
		{error, Reason} ->
			logger:error("cannot open dets table: ~p", [Reason]),
			exit(Reason),
			{error, Reason}
	end.

save_to_dets(Tab, RTab) ->
	AttrList = [{Nref, Record} || {Nref, Record} <- ets:tab2list(Tab)],
	TypeList = [{Nref, Record} || {Nref, Record} <- ets:tab2list(RTab)],
	Next = max_nref(Tab) + 1,
	dets:insert(graphdb_attr_dets,
		[{attributes, AttrList},
		 {relationship_types, TypeList},
		 {next_nref, Next}]).

max_nref(Tab) ->
	case ets:last(Tab) of
		'$end_of_table' -> 0;
		K -> K
	end.

load_from_dets(#{attr_tab := Tab, rtypes_tab := RTab} = State0) ->
	case dets:lookup(graphdb_attr_dets, attributes) of
		[{attributes, AttrList}] ->
			true = ets:insert(Tab, AttrList);
		[] -> ok
	end,
	case dets:lookup(graphdb_attr_dets, relationship_types) of
		[{relationship_types, TypeList}] ->
			true = ets:insert(RTab, TypeList);
		[] -> ok
	end,
	Next = case dets:lookup(graphdb_attr_dets, next_nref) of
		[{next_nref, N}] -> N;
		[] -> 1
	end,
	State0#{next_nref => Next}.

alloc_nref(#{next_nref := Next} = State) ->
	{Next, State#{next_nref => Next + 1}}.

%%---------------------------------------------------------------------
%% do_create_attribute(AttrMap, State) -> {{ok, Nref}, NewState}
%%
%% Allocates a new Nref and stores the attribute record in ETS.
%%---------------------------------------------------------------------
do_create_attribute(AttrMap0, #{attr_tab := Tab} = State) ->
	{Nref, State1} = alloc_nref(State),
	AttrMap = AttrMap0#{
		nref => Nref,
		attribute_value_pairs => maps:get(attribute_value_pairs, AttrMap0, [])
	},
	true = ets:insert(Tab, {Nref, AttrMap}),
	{{ok, Nref}, State1}.

%%---------------------------------------------------------------------
%% do_create_relationship_attribute(AttrNref, ReciprocalNref, State)
%%   -> {{ok, AttrNref, ReciprocalNref}, NewState}
%%
%% Links two existing attributes as reciprocal relationship attributes.
%%---------------------------------------------------------------------
do_create_relationship_attribute(AttrNref, ReciprocalNref,
		#{attr_tab := Tab} = State) ->
	case {ets:lookup(Tab, AttrNref), ets:lookup(Tab, ReciprocalNref)} of
		{[{AttrNref, AttrRec}], [{ReciprocalNref, RecRec}]} ->
			AttrRel = AttrRec#{relationship_reciprocal => ReciprocalNref},
			RecRel = RecRec#{relationship_reciprocal => AttrNref},
			true = ets:insert(Tab, {AttrNref, AttrRel}),
			true = ets:insert(Tab, {ReciprocalNref, RecRel}),
			{{ok, AttrNref, ReciprocalNref}, State};
		_ -> {{error, attribute_not_found}, State}
	end.

%%---------------------------------------------------------------------
%% do_create_relationship_type(Name, State) -> {{ok, Nref}, NewState}
%%---------------------------------------------------------------------
do_create_relationship_type(Name, #{rtypes_tab := RTab} = State) ->
	{Nref, State1} = alloc_nref(State),
	TypeRecord = #{
		nref => Nref,
		name => Name,
		attribute_type => relationship_type,
		attributes => []
	},
	true = ets:insert(RTab, {Nref, TypeRecord}),
	{{ok, Nref}, State1}.

%%---------------------------------------------------------------------
%% do_add_attribute_to_type(TypeNref, AttrNref, State) -> ok | {error, Reason}
%%---------------------------------------------------------------------
do_add_attribute_to_type(TypeNref, AttrNref,
		#{rtypes_tab := RTab, attr_tab := AttrTab}) ->
	case ets:lookup(RTab, TypeNref) of
		[{TypeNref, TypeRec}] ->
			case ets:lookup(AttrTab, AttrNref) of
				[{AttrNref, _Rec}] ->
					Attrs = maps:get(attributes, TypeRec, []),
					Updated = TypeRec#{attributes => Attrs ++ [AttrNref]},
					true = ets:insert(RTab, {TypeNref, Updated}),
					ok;
				[] -> {error, attribute_not_found}
			end;
		[] -> {error, relationship_type_not_found}
	end.

%%---------------------------------------------------------------------
%% seed_relationship_avp_flag(State) -> NewState
%%
%% At bootstrap, ensures a literal attribute named "relationship_avp"
%% exists. Its presence (value true) on another attribute's record
%% marks it as intended for relationship arc metadata.
%%---------------------------------------------------------------------
seed_relationship_avp_flag(#{attr_tab := Tab} = State0) ->
    %% Scan existing attributes for one named "relationship_avp"
    Existing = [Nref || {Nref, #{name := "relationship_avp"}} <- ets:tab2list(Tab)],
    case Existing of
        [Nref | _] ->
            State0#{rel_avp_flag => Nref};
        [] ->
            {Nref, State1} = alloc_nref(State0),
            FlagRecord = #{
                nref => Nref,
                name => "relationship_avp",
                attribute_type => literal,
                value_type => boolean,
                description => "Flag marking attributes intended for use on relationship arcs",
                attribute_value_pairs => []
            },
            true = ets:insert(Tab, {Nref, FlagRecord}),
            State1#{rel_avp_flag => Nref}
    end.
