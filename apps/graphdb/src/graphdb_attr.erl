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
%% Description: graphdb_attr manages the attribute library.
%%              The attribute library holds all named attribute concepts
%%              used as arc labels (characterizations) and as literal
%%              descriptors for scalar values stored directly on nodes.
%%
%%              Three attribute kinds are supported:
%%                name        - human-readable label for a class or instance
%%                literal     - scalar value descriptor (number, string, URL, …)
%%                relationship - arc label; always paired with a reciprocal
%%
%%              Relationship attributes may be grouped into relationship
%%              types (e.g., "location_of"/"located_in" grouped under
%%              "Location").
%%
%%              At bootstrap the server seeds a special literal attribute
%%              named <<"relationship_avp">> into the library.  Its Nref
%%              is stored in the primary DETS table under the key
%%              {bootstrap, relationship_avp_nref}.  Any attribute node
%%              that carries an AVP #{attribute=>RelAvpNref, value=>true}
%%              is thereby marked as intended for use on relationship arcs
%%              rather than on node records directly.
%%
%%              All three DETS tables are persisted to disk and survive
%%              node restarts.  On restart the tables are re-opened and
%%              bootstrap seeding is skipped (data already present).
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%% Stub implementation.
%%---------------------------------------------------------------------
%% Rev A Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%%
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

%%---------------------------------------------------------------------
%% DETS table names and file names
%%---------------------------------------------------------------------
%% graphdb_attr       — primary store keyed by Nref (integer) or
%%                      special bootstrap key tuple.
%%   Rows: {Nref, Record}
%%   Special rows:
%%     {{bootstrap, relationship_avp_nref}, Nref}
%%
%% graphdb_attr_index — secondary lookup keyed by {Kind, Name}
%%   Rows: {{Kind, Name}, Nref}
%%   where Kind = name | literal | relationship | relationship_type
%%
%% graphdb_attr_types — relationship-type membership
%%   Rows: {TypeNref, [MemberNref]}
%%
%% File names are relative to the node's working directory, consistent
%% with nref_allocator.dets and nref_server.dets.
%%---------------------------------------------------------------------
-define(TAB,        graphdb_attr).
-define(TAB_FILE,   "graphdb_attr.dets").
-define(IDX,        graphdb_attr_index).
-define(IDX_FILE,   "graphdb_attr_index.dets").
-define(TYPES,      graphdb_attr_types).
-define(TYPES_FILE, "graphdb_attr_types.dets").


%%---------------------------------------------------------------------
%% Exported Functions
%%---------------------------------------------------------------------
%%---------------------------------------------------------------------
%% Exports External API
%%---------------------------------------------------------------------
-export([
		start_link/0,
		%% Attribute creation
		create_name_attribute/1,
		create_literal_attribute/2,
		create_literal_attribute/3,
		create_relationship_attribute/2,
		create_relationship_attribute/3,
		create_relationship_type/1,
		%% Attribute grouping
		add_to_relationship_type/2,
		%% Lookups
		get_attribute/1,
		find_attribute/2,
		list_attributes/0,
		list_attributes/1,
		list_relationship_types/0,
		%% Bootstrap helper
		relationship_avp_nref/0
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


%%=====================================================================
%% Exported External API Functions
%%=====================================================================

%%---------------------------------------------------------------------
%% start_link() -> {ok, Pid} | {error, Reason}
%%---------------------------------------------------------------------
start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).


%%---------------------------------------------------------------------
%% create_name_attribute(Name) -> {ok, Nref} | {error, Reason}
%%
%% Creates a name attribute in the library.
%% Name is a binary string (e.g. <<"instance_name">>).
%%---------------------------------------------------------------------
create_name_attribute(Name) when is_binary(Name) ->
	gen_server:call(?MODULE, {create_name_attribute, Name}).


%%---------------------------------------------------------------------
%% create_literal_attribute(Name, ValueType) -> {ok, Nref} | {error, Reason}
%%
%% Creates a literal attribute.
%% ValueType is an atom describing the expected value kind
%% (e.g. string, integer, float, boolean, binary, url, filename, any).
%%---------------------------------------------------------------------
create_literal_attribute(Name, ValueType)
		when is_binary(Name), is_atom(ValueType) ->
	gen_server:call(?MODULE, {create_literal_attribute, Name, ValueType, #{}}).


%%---------------------------------------------------------------------
%% create_literal_attribute(Name, ValueType, Opts) -> {ok, Nref} | {error, Reason}
%%
%% Like create_literal_attribute/2, but accepts an options map.
%% Supported option:
%%   relationship_avp => true   marks this attribute as a relationship-arc
%%                              metadata attribute (stored as an AVP on the
%%                              attribute node itself using the bootstrap
%%                              relationship_avp_nref).
%%---------------------------------------------------------------------
create_literal_attribute(Name, ValueType, Opts)
		when is_binary(Name), is_atom(ValueType), is_map(Opts) ->
	gen_server:call(?MODULE, {create_literal_attribute, Name, ValueType, Opts}).


%%---------------------------------------------------------------------
%% create_relationship_attribute(Name, ReciprocalName) -> {ok, Nref} | {error, duplicate}
%%
%% Creates a relationship attribute and its reciprocal counterpart.
%% Both must be new names; they are created together and each references
%% the other.
%%
%% Returns {ok, {ForwardNref, ReciprocalNref}}.
%%---------------------------------------------------------------------
create_relationship_attribute(Name, ReciprocalName)
		when is_binary(Name), is_binary(ReciprocalName) ->
	gen_server:call(?MODULE, {create_relationship_attribute, Name, ReciprocalName, #{}}).


%%---------------------------------------------------------------------
%% create_relationship_attribute(Name, ReciprocalName, Opts) -> {ok, {Nref, RecNref}}
%%
%% Like create_relationship_attribute/2 with an options map (reserved for future).
%%---------------------------------------------------------------------
create_relationship_attribute(Name, ReciprocalName, Opts)
		when is_binary(Name), is_binary(ReciprocalName), is_map(Opts) ->
	gen_server:call(?MODULE, {create_relationship_attribute, Name, ReciprocalName, Opts}).


%%---------------------------------------------------------------------
%% create_relationship_type(Name) -> {ok, Nref} | {error, duplicate}
%%
%% Creates a relationship type grouping node.
%% Members (relationship attribute Nrefs) are added via add_to_relationship_type/2.
%%---------------------------------------------------------------------
create_relationship_type(Name) when is_binary(Name) ->
	gen_server:call(?MODULE, {create_relationship_type, Name}).


%%---------------------------------------------------------------------
%% add_to_relationship_type(TypeNref, AttrNref) -> ok | {error, Reason}
%%
%% Adds a relationship attribute to a relationship type group.
%%---------------------------------------------------------------------
add_to_relationship_type(TypeNref, AttrNref)
		when is_integer(TypeNref), is_integer(AttrNref) ->
	gen_server:call(?MODULE, {add_to_relationship_type, TypeNref, AttrNref}).


%%---------------------------------------------------------------------
%% get_attribute(Nref) -> {ok, Record} | {error, not_found}
%%
%% Retrieves an attribute record by its Nref.
%%---------------------------------------------------------------------
get_attribute(Nref) when is_integer(Nref) ->
	gen_server:call(?MODULE, {get_attribute, Nref}).


%%---------------------------------------------------------------------
%% find_attribute(Kind, Name) -> {ok, Nref} | {error, not_found}
%%
%% Looks up an attribute by kind and name.
%% Kind = name | literal | relationship | relationship_type
%%---------------------------------------------------------------------
find_attribute(Kind, Name)
		when is_atom(Kind), is_binary(Name) ->
	gen_server:call(?MODULE, {find_attribute, Kind, Name}).


%%---------------------------------------------------------------------
%% list_attributes() -> [Record]
%%
%% Returns all attribute records in the library.
%%---------------------------------------------------------------------
list_attributes() ->
	gen_server:call(?MODULE, list_attributes).


%%---------------------------------------------------------------------
%% list_attributes(Kind) -> [Record]
%%
%% Returns all attribute records of the given kind.
%%---------------------------------------------------------------------
list_attributes(Kind) when is_atom(Kind) ->
	gen_server:call(?MODULE, {list_attributes, Kind}).


%%---------------------------------------------------------------------
%% list_relationship_types() -> [Record]
%%
%% Returns all relationship type records.
%%---------------------------------------------------------------------
list_relationship_types() ->
	gen_server:call(?MODULE, list_relationship_types).


%%---------------------------------------------------------------------
%% relationship_avp_nref() -> Nref
%%
%% Returns the Nref of the bootstrap relationship_avp flag attribute.
%% Crashes if called before the server has started.
%%---------------------------------------------------------------------
relationship_avp_nref() ->
	gen_server:call(?MODULE, relationship_avp_nref).


%%=====================================================================
%% gen_server Behaviour Callbacks
%%=====================================================================

%%---------------------------------------------------------------------
%% init([]) -> {ok, State}
%%
%% Opens the three DETS tables.  Seeds the bootstrap attribute library
%% only when the primary table is newly created (did not previously
%% exist on disk).
%%---------------------------------------------------------------------
init([]) ->
	TabNew   = open_dets(?TAB,   ?TAB_FILE),
	_IdxNew  = open_dets(?IDX,   ?IDX_FILE),
	_TypeNew = open_dets(?TYPES, ?TYPES_FILE),
	case TabNew of
	new ->
		ok = seed_bootstrap();
	existing ->
		ok
	end,
	{ok, #{}}.


%%---------------------------------------------------------------------
%% handle_call/3
%%---------------------------------------------------------------------
handle_call({create_name_attribute, Name}, _From, State) ->
	Reply = do_create_name_attribute(Name),
	{reply, Reply, State};

handle_call({create_literal_attribute, Name, ValueType, Opts}, _From, State) ->
	Reply = do_create_literal_attribute(Name, ValueType, Opts),
	{reply, Reply, State};

handle_call({create_relationship_attribute, Name, RecName, Opts}, _From, State) ->
	Reply = do_create_relationship_attribute(Name, RecName, Opts),
	{reply, Reply, State};

handle_call({create_relationship_type, Name}, _From, State) ->
	Reply = do_create_relationship_type(Name),
	{reply, Reply, State};

handle_call({add_to_relationship_type, TypeNref, AttrNref}, _From, State) ->
	Reply = do_add_to_relationship_type(TypeNref, AttrNref),
	{reply, Reply, State};

handle_call({get_attribute, Nref}, _From, State) ->
	Reply = do_get_attribute(Nref),
	{reply, Reply, State};

handle_call({find_attribute, Kind, Name}, _From, State) ->
	Reply = do_find_attribute(Kind, Name),
	{reply, Reply, State};

handle_call(list_attributes, _From, State) ->
	Reply = do_list_attributes(),
	{reply, Reply, State};

handle_call({list_attributes, Kind}, _From, State) ->
	Reply = do_list_attributes(Kind),
	{reply, Reply, State};

handle_call(list_relationship_types, _From, State) ->
	Reply = do_list_relationship_types(),
	{reply, Reply, State};

handle_call(relationship_avp_nref, _From, State) ->
	[{{bootstrap, relationship_avp_nref}, Nref}] =
		dets:lookup(?TAB, {bootstrap, relationship_avp_nref}),
	{reply, Nref, State};

handle_call(Request, From, State) ->
	?UEM(handle_call, {Request, From, State}),
	{noreply, State}.


%%---------------------------------------------------------------------
%% handle_cast/2
%%---------------------------------------------------------------------
handle_cast(Message, State) ->
	?UEM(handle_cast, {Message, State}),
	{noreply, State}.


%%---------------------------------------------------------------------
%% handle_info/2
%%---------------------------------------------------------------------
handle_info(Info, State) ->
	?UEM(handle_info, {Info, State}),
	{noreply, State}.


%%---------------------------------------------------------------------
%% terminate/2
%%---------------------------------------------------------------------
terminate(_Reason, _State) ->
	dets:close(?TAB),
	dets:close(?IDX),
	dets:close(?TYPES),
	ok.


%%---------------------------------------------------------------------
%% code_change/3
%%---------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
	?NYI(code_change),
	{ok, State}.


%%=====================================================================
%% Internal Functions
%%=====================================================================

%%---------------------------------------------------------------------
%% open_dets(Name, File) -> new | existing
%%
%% Opens a DETS table, creating the file if it does not yet exist.
%% Returns 'new' when the file was just created, 'existing' otherwise.
%% Exits with reason graphdb_attr_dets_open on failure.
%%---------------------------------------------------------------------
open_dets(Name, File) ->
	IsExisting = filelib:is_file(File),
	logger:info("opening dets file: ~p", [File]),
	case dets:open_file(Name, [{file, File}]) of
	{ok, Name} ->
		case IsExisting of
		true  -> existing;
		false -> new
		end;
	{error, Reason} ->
		logger:error("cannot open dets table ~p: ~p", [File, Reason]),
		exit(graphdb_attr_dets_open)
	end.


%%---------------------------------------------------------------------
%% seed_bootstrap() -> ok
%%
%% Seeds the minimum attribute library entries required at startup.
%% Called only when the primary DETS table is newly created.
%%
%%   1. A name attribute named <<"attr_name">> — used to attach a
%%      human-readable name to every attribute node.
%%   2. A literal attribute named <<"relationship_avp">> — the flag
%%      attribute used to mark other attributes as relationship-arc
%%      metadata attributes.  Its Nref is stored under the key
%%      {bootstrap, relationship_avp_nref} so that subsequent
%%      create_literal_attribute/3 calls can reference it.
%%---------------------------------------------------------------------
seed_bootstrap() ->
	%% 1. Seed the name attribute used to name all attribute nodes.
	%%    Its own AVP list is empty because attr_name cannot name itself
	%%    during bootstrapping.
	{ok, NameAttrNref} = raw_create_name_attribute(<<"attr_name">>),

	%% 2. Seed the relationship_avp flag literal attribute.
	%%    Its own AVP list carries its name (using NameAttrNref) but
	%%    cannot carry the relationship_avp flag on itself yet — that
	%%    would be circular.  The flag is identified by its reserved name.
	{ok, RelAvpNref} = raw_create_literal_attribute(
		<<"relationship_avp">>, boolean, NameAttrNref,
		[#{attribute => NameAttrNref, value => <<"relationship_avp">>}]),

	%% Store the well-known Nref for fast retrieval by
	%% relationship_avp_nref/0 and do_create_literal_attribute/3.
	dets:insert(?TAB, {{bootstrap, relationship_avp_nref}, RelAvpNref}),
	ok.


%%---------------------------------------------------------------------
%% raw_create_name_attribute(Name) -> {ok, Nref}
%%
%% Low-level name-attribute creation used during bootstrap.
%% Idempotent: returns the existing Nref if the name already exists.
%%---------------------------------------------------------------------
raw_create_name_attribute(Name) ->
	Key = {name, Name},
	case dets:lookup(?IDX, Key) of
	[{Key, ExistingNref}] ->
		{ok, ExistingNref};
	[] ->
		Nref = nref_server:get_nref(),
		Record = #{
			nref                 => Nref,
			type                 => name,
			name                 => Name,
			attribute_value_pairs => []
		},
		dets:insert(?TAB, {Nref, Record}),
		dets:insert(?IDX, {Key, Nref}),
		nref_server:confirm_nref(Nref),
		{ok, Nref}
	end.


%%---------------------------------------------------------------------
%% raw_create_literal_attribute(Name, ValueType, NameAttrNref, Avps)
%%   -> {ok, Nref}
%%
%% Low-level literal-attribute creation used during bootstrap.
%% Avps is the full attribute_value_pairs list to store on the record.
%% Idempotent: returns the existing Nref if the name already exists.
%%---------------------------------------------------------------------
raw_create_literal_attribute(Name, ValueType, _NameAttrNref, Avps) ->
	Key = {literal, Name},
	case dets:lookup(?IDX, Key) of
	[{Key, ExistingNref}] ->
		{ok, ExistingNref};
	[] ->
		Nref = nref_server:get_nref(),
		Record = #{
			nref                 => Nref,
			type                 => literal,
			name                 => Name,
			value_type           => ValueType,
			attribute_value_pairs => Avps
		},
		dets:insert(?TAB, {Nref, Record}),
		dets:insert(?IDX, {Key, Nref}),
		nref_server:confirm_nref(Nref),
		{ok, Nref}
	end.


%%---------------------------------------------------------------------
%% do_create_name_attribute(Name) -> {ok, Nref} | {error, duplicate}
%%---------------------------------------------------------------------
do_create_name_attribute(Name) ->
	Key = {name, Name},
	case dets:lookup(?IDX, Key) of
	[{Key, _Nref}] ->
		{error, duplicate};
	[] ->
		Nref = nref_server:get_nref(),
		NameAttrNref = bootstrap_name_attr_nref(),
		Record = #{
			nref                 => Nref,
			type                 => name,
			name                 => Name,
			attribute_value_pairs => [#{attribute => NameAttrNref, value => Name}]
		},
		dets:insert(?TAB, {Nref, Record}),
		dets:insert(?IDX, {Key, Nref}),
		nref_server:confirm_nref(Nref),
		{ok, Nref}
	end.


%%---------------------------------------------------------------------
%% do_create_literal_attribute(Name, ValueType, Opts)
%%   -> {ok, Nref} | {error, duplicate}
%%---------------------------------------------------------------------
do_create_literal_attribute(Name, ValueType, Opts) ->
	Key = {literal, Name},
	case dets:lookup(?IDX, Key) of
	[{Key, _Nref}] ->
		{error, duplicate};
	[] ->
		Nref = nref_server:get_nref(),
		NameAttrNref = bootstrap_name_attr_nref(),
		NameAvp = #{attribute => NameAttrNref, value => Name},
		%% If the relationship_avp option is set, attach the flag AVP.
		ExtraAvps = case maps:get(relationship_avp, Opts, false) of
			true ->
				RelAvpNref = bootstrap_relationship_avp_nref(),
				[#{attribute => RelAvpNref, value => true}];
			false ->
				[]
		end,
		Record = #{
			nref                 => Nref,
			type                 => literal,
			name                 => Name,
			value_type           => ValueType,
			attribute_value_pairs => [NameAvp | ExtraAvps]
		},
		dets:insert(?TAB, {Nref, Record}),
		dets:insert(?IDX, {Key, Nref}),
		nref_server:confirm_nref(Nref),
		{ok, Nref}
	end.


%%---------------------------------------------------------------------
%% do_create_relationship_attribute(Name, RecName, Opts)
%%   -> {ok, {ForwardNref, ReciprocalNref}} | {error, duplicate}
%%
%% Both sides are created atomically: either both succeed or neither
%% is stored.  If either name already exists the call returns
%% {error, duplicate} without creating anything.
%%---------------------------------------------------------------------
do_create_relationship_attribute(Name, RecName, _Opts) ->
	KeyFwd = {relationship, Name},
	KeyRec = {relationship, RecName},
	case {dets:lookup(?IDX, KeyFwd), dets:lookup(?IDX, KeyRec)} of
	{[], []} ->
		NrefFwd = nref_server:get_nref(),
		NrefRec = nref_server:get_nref(),
		NameAttrNref = bootstrap_name_attr_nref(),
		RecordFwd = #{
			nref                 => NrefFwd,
			type                 => relationship,
			name                 => Name,
			reciprocal           => NrefRec,
			attribute_value_pairs => [#{attribute => NameAttrNref, value => Name}]
		},
		RecordRec = #{
			nref                 => NrefRec,
			type                 => relationship,
			name                 => RecName,
			reciprocal           => NrefFwd,
			attribute_value_pairs => [#{attribute => NameAttrNref, value => RecName}]
		},
		dets:insert(?TAB, {NrefFwd, RecordFwd}),
		dets:insert(?TAB, {NrefRec, RecordRec}),
		dets:insert(?IDX, {KeyFwd, NrefFwd}),
		dets:insert(?IDX, {KeyRec, NrefRec}),
		nref_server:confirm_nrefs([NrefFwd, NrefRec]),
		{ok, {NrefFwd, NrefRec}};
	_ ->
		{error, duplicate}
	end.


%%---------------------------------------------------------------------
%% do_create_relationship_type(Name) -> {ok, Nref} | {error, duplicate}
%%---------------------------------------------------------------------
do_create_relationship_type(Name) ->
	Key = {relationship_type, Name},
	case dets:lookup(?IDX, Key) of
	[{Key, _Nref}] ->
		{error, duplicate};
	[] ->
		Nref = nref_server:get_nref(),
		NameAttrNref = bootstrap_name_attr_nref(),
		Record = #{
			nref                 => Nref,
			type                 => relationship_type,
			name                 => Name,
			members              => [],
			attribute_value_pairs => [#{attribute => NameAttrNref, value => Name}]
		},
		dets:insert(?TAB,   {Nref, Record}),
		dets:insert(?IDX,   {Key,  Nref}),
		dets:insert(?TYPES, {Nref, []}),
		nref_server:confirm_nref(Nref),
		{ok, Nref}
	end.


%%---------------------------------------------------------------------
%% do_add_to_relationship_type(TypeNref, AttrNref) -> ok | {error, Reason}
%%---------------------------------------------------------------------
do_add_to_relationship_type(TypeNref, AttrNref) ->
	case dets:lookup(?TAB, TypeNref) of
	[] ->
		{error, type_not_found};
	[{TypeNref, Record}] ->
		case maps:get(type, Record) of
		relationship_type ->
			Members0 = maps:get(members, Record),
			case lists:member(AttrNref, Members0) of
			true ->
				{error, already_member};
			false ->
				Members1 = [AttrNref | Members0],
				Updated  = Record#{members => Members1},
				dets:insert(?TAB,   {TypeNref, Updated}),
				dets:insert(?TYPES, {TypeNref, Members1}),
				ok
			end;
		_ ->
			{error, not_a_relationship_type}
		end
	end.


%%---------------------------------------------------------------------
%% do_get_attribute(Nref) -> {ok, Record} | {error, not_found}
%%---------------------------------------------------------------------
do_get_attribute(Nref) ->
	case dets:lookup(?TAB, Nref) of
	[{Nref, Record}] when is_map(Record) ->
		{ok, Record};
	_ ->
		{error, not_found}
	end.


%%---------------------------------------------------------------------
%% do_find_attribute(Kind, Name) -> {ok, Nref} | {error, not_found}
%%---------------------------------------------------------------------
do_find_attribute(Kind, Name) ->
	Key = {Kind, Name},
	case dets:lookup(?IDX, Key) of
	[{Key, Nref}] ->
		{ok, Nref};
	[] ->
		{error, not_found}
	end.


%%---------------------------------------------------------------------
%% do_list_attributes() -> [Record]
%%---------------------------------------------------------------------
do_list_attributes() ->
	Acc = dets:foldl(
		fun({_Key, Record}, A) when is_map(Record) -> [Record | A];
		   (_, A)                                  -> A
		end, [], ?TAB),
	Acc.


%%---------------------------------------------------------------------
%% do_list_attributes(Kind) -> [Record]
%%---------------------------------------------------------------------
do_list_attributes(Kind) ->
	dets:foldl(
		fun({_Key, Record}, A) when is_map(Record) ->
			case maps:get(type, Record, undefined) of
			Kind -> [Record | A];
			_    -> A
			end;
		   (_, A) -> A
		end, [], ?TAB).


%%---------------------------------------------------------------------
%% do_list_relationship_types() -> [Record]
%%---------------------------------------------------------------------
do_list_relationship_types() ->
	do_list_attributes(relationship_type).


%%---------------------------------------------------------------------
%% bootstrap_name_attr_nref() -> Nref
%%
%% Returns the Nref of the <<"attr_name">> seed attribute.
%%---------------------------------------------------------------------
bootstrap_name_attr_nref() ->
	[{{name, <<"attr_name">>}, Nref}] = dets:lookup(?IDX, {name, <<"attr_name">>}),
	Nref.


%%---------------------------------------------------------------------
%% bootstrap_relationship_avp_nref() -> Nref
%%
%% Returns the Nref of the <<"relationship_avp">> seed attribute.
%%---------------------------------------------------------------------
bootstrap_relationship_avp_nref() ->
	[{{bootstrap, relationship_avp_nref}, Nref}] =
		dets:lookup(?TAB, {bootstrap, relationship_avp_nref}),
	Nref.
