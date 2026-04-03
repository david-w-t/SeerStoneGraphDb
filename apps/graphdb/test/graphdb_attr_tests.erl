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
%% Description: EUnit tests for graphdb_attr.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: *** 2008 Author: Dallas Noyes (dallas.noyes@gmail.com)
%%
%%---------------------------------------------------------------------
-module(graphdb_attr_tests).

-include_lib("eunit/include/eunit.hrl").


%%=====================================================================
%% Test fixture — start/stop nref + graphdb_attr for each test group
%%=====================================================================

setup() ->
    %% nref_allocator and nref_server write DETS files; use a temp dir.
    TmpDir = make_tmp_dir(),
    ok = file:set_cwd(TmpDir),
    {ok, _} = application:ensure_all_started(nref),
    {ok, _Pid} = graphdb_attr:start_link(),
    TmpDir.

teardown(TmpDir) ->
    gen_server:stop(graphdb_attr),
    application:stop(nref),
    %% Brief pause to let DETS close cleanly before deleting files.
    timer:sleep(50),
    os:cmd("rm -rf " ++ TmpDir),
    ok.

make_tmp_dir() ->
    Base = "/tmp/graphdb_attr_test_" ++
           integer_to_list(erlang:unique_integer([positive])),
    ok = file:make_dir(Base),
    Base.


%%=====================================================================
%% Test generator
%%=====================================================================

graphdb_attr_test_() ->
    {foreach,
     fun setup/0,
     fun teardown/1,
     [
      fun test_bootstrap_seeded/1,
      fun test_relationship_avp_nref/1,
      fun test_create_name_attribute/1,
      fun test_create_name_attribute_duplicate/1,
      fun test_create_literal_attribute/1,
      fun test_create_literal_attribute_duplicate/1,
      fun test_create_literal_attribute_with_relationship_avp_flag/1,
      fun test_create_relationship_attribute/1,
      fun test_create_relationship_attribute_duplicate/1,
      fun test_create_relationship_attribute_reciprocal_links/1,
      fun test_create_relationship_type/1,
      fun test_create_relationship_type_duplicate/1,
      fun test_add_to_relationship_type/1,
      fun test_add_to_relationship_type_already_member/1,
      fun test_add_to_relationship_type_not_found/1,
      fun test_get_attribute_not_found/1,
      fun test_find_attribute/1,
      fun test_find_attribute_not_found/1,
      fun test_list_attributes_all/1,
      fun test_list_attributes_by_kind/1,
      fun test_list_relationship_types/1,
      fun test_persistence_across_restart/1
     ]}.


%%=====================================================================
%% Individual tests
%%=====================================================================

%% Bootstrap seeds <<"attr_name">> (name) and <<"relationship_avp">> (literal).
test_bootstrap_seeded(_TmpDir) ->
    ?_test(begin
        {ok, _} = graphdb_attr:find_attribute(name,    <<"attr_name">>),
        {ok, _} = graphdb_attr:find_attribute(literal, <<"relationship_avp">>)
    end).

%% relationship_avp_nref/0 returns the Nref of the bootstrap flag attribute.
test_relationship_avp_nref(_TmpDir) ->
    ?_test(begin
        RelAvpNref = graphdb_attr:relationship_avp_nref(),
        ?assert(is_integer(RelAvpNref)),
        ?assert(RelAvpNref > 0),
        {ok, Record} = graphdb_attr:get_attribute(RelAvpNref),
        ?assertEqual(literal,              maps:get(type, Record)),
        ?assertEqual(<<"relationship_avp">>, maps:get(name, Record))
    end).

%% create_name_attribute/1 — happy path.
test_create_name_attribute(_TmpDir) ->
    ?_test(begin
        {ok, Nref} = graphdb_attr:create_name_attribute(<<"instance_name">>),
        ?assert(is_integer(Nref)),
        ?assert(Nref > 0),
        {ok, Record} = graphdb_attr:get_attribute(Nref),
        ?assertEqual(name,              maps:get(type,  Record)),
        ?assertEqual(<<"instance_name">>, maps:get(name,  Record)),
        ?assertEqual(Nref,              maps:get(nref,  Record))
    end).

%% create_name_attribute/1 — duplicate name returns error.
test_create_name_attribute_duplicate(_TmpDir) ->
    ?_test(begin
        {ok, _} = graphdb_attr:create_name_attribute(<<"dup_name">>),
        ?assertEqual({error, duplicate},
                     graphdb_attr:create_name_attribute(<<"dup_name">>))
    end).

%% create_literal_attribute/2 — happy path.
test_create_literal_attribute(_TmpDir) ->
    ?_test(begin
        {ok, Nref} = graphdb_attr:create_literal_attribute(<<"temperature">>, float),
        ?assert(is_integer(Nref)),
        {ok, Record} = graphdb_attr:get_attribute(Nref),
        ?assertEqual(literal,          maps:get(type,       Record)),
        ?assertEqual(<<"temperature">>, maps:get(name,       Record)),
        ?assertEqual(float,            maps:get(value_type, Record))
    end).

%% create_literal_attribute/2 — duplicate name returns error.
test_create_literal_attribute_duplicate(_TmpDir) ->
    ?_test(begin
        {ok, _} = graphdb_attr:create_literal_attribute(<<"weight">>, float),
        ?assertEqual({error, duplicate},
                     graphdb_attr:create_literal_attribute(<<"weight">>, float))
    end).

%% create_literal_attribute/3 with relationship_avp => true flag.
test_create_literal_attribute_with_relationship_avp_flag(_TmpDir) ->
    ?_test(begin
        {ok, Nref} = graphdb_attr:create_literal_attribute(
                         <<"relationship_weight">>, float,
                         #{relationship_avp => true}),
        {ok, Record} = graphdb_attr:get_attribute(Nref),
        RelAvpNref = graphdb_attr:relationship_avp_nref(),
        Avps = maps:get(attribute_value_pairs, Record),
        %% The AVP list must contain an entry with the flag attribute.
        HasFlag = lists:any(
            fun(#{attribute := A, value := V}) ->
                A =:= RelAvpNref andalso V =:= true;
               (_) -> false
            end, Avps),
        ?assert(HasFlag)
    end).

%% create_relationship_attribute/2 — happy path; returns two Nrefs.
test_create_relationship_attribute(_TmpDir) ->
    ?_test(begin
        {ok, {FwdNref, RecNref}} =
            graphdb_attr:create_relationship_attribute(
                <<"location_of">>, <<"located_in">>),
        ?assert(is_integer(FwdNref)),
        ?assert(is_integer(RecNref)),
        ?assert(FwdNref =/= RecNref),
        {ok, FwdRec} = graphdb_attr:get_attribute(FwdNref),
        {ok, RecRec} = graphdb_attr:get_attribute(RecNref),
        ?assertEqual(relationship,     maps:get(type, FwdRec)),
        ?assertEqual(<<"location_of">>, maps:get(name, FwdRec)),
        ?assertEqual(relationship,     maps:get(type, RecRec)),
        ?assertEqual(<<"located_in">>, maps:get(name, RecRec))
    end).

%% create_relationship_attribute/2 — duplicate either side returns error.
test_create_relationship_attribute_duplicate(_TmpDir) ->
    ?_test(begin
        {ok, _} = graphdb_attr:create_relationship_attribute(
                      <<"makes">>, <<"made_by">>),
        ?assertEqual({error, duplicate},
                     graphdb_attr:create_relationship_attribute(
                         <<"makes">>, <<"produced_by">>)),
        ?assertEqual({error, duplicate},
                     graphdb_attr:create_relationship_attribute(
                         <<"produces">>, <<"made_by">>))
    end).

%% Each side of a relationship attribute references the other as its reciprocal.
test_create_relationship_attribute_reciprocal_links(_TmpDir) ->
    ?_test(begin
        {ok, {FwdNref, RecNref}} =
            graphdb_attr:create_relationship_attribute(
                <<"parent_of">>, <<"child_of">>),
        {ok, FwdRec} = graphdb_attr:get_attribute(FwdNref),
        {ok, RecRec} = graphdb_attr:get_attribute(RecNref),
        ?assertEqual(RecNref, maps:get(reciprocal, FwdRec)),
        ?assertEqual(FwdNref, maps:get(reciprocal, RecRec))
    end).

%% create_relationship_type/1 — happy path.
test_create_relationship_type(_TmpDir) ->
    ?_test(begin
        {ok, Nref} = graphdb_attr:create_relationship_type(<<"Location">>),
        ?assert(is_integer(Nref)),
        {ok, Record} = graphdb_attr:get_attribute(Nref),
        ?assertEqual(relationship_type, maps:get(type,    Record)),
        ?assertEqual(<<"Location">>,    maps:get(name,    Record)),
        ?assertEqual([],                maps:get(members, Record))
    end).

%% create_relationship_type/1 — duplicate returns error.
test_create_relationship_type_duplicate(_TmpDir) ->
    ?_test(begin
        {ok, _} = graphdb_attr:create_relationship_type(<<"Family">>),
        ?assertEqual({error, duplicate},
                     graphdb_attr:create_relationship_type(<<"Family">>))
    end).

%% add_to_relationship_type/2 — happy path; member list grows.
test_add_to_relationship_type(_TmpDir) ->
    ?_test(begin
        {ok, TypeNref} = graphdb_attr:create_relationship_type(<<"Pipe">>),
        {ok, {InletNref, OutletNref}} =
            graphdb_attr:create_relationship_attribute(<<"inlet">>, <<"feeds_into">>),
        ok = graphdb_attr:add_to_relationship_type(TypeNref, InletNref),
        ok = graphdb_attr:add_to_relationship_type(TypeNref, OutletNref),
        {ok, Record} = graphdb_attr:get_attribute(TypeNref),
        Members = maps:get(members, Record),
        ?assert(lists:member(InletNref,  Members)),
        ?assert(lists:member(OutletNref, Members))
    end).

%% add_to_relationship_type/2 — adding same member twice returns error.
test_add_to_relationship_type_already_member(_TmpDir) ->
    ?_test(begin
        {ok, TypeNref} = graphdb_attr:create_relationship_type(<<"Dup">>),
        {ok, {AttrNref, _}} =
            graphdb_attr:create_relationship_attribute(<<"a">>, <<"b">>),
        ok = graphdb_attr:add_to_relationship_type(TypeNref, AttrNref),
        ?assertEqual({error, already_member},
                     graphdb_attr:add_to_relationship_type(TypeNref, AttrNref))
    end).

%% add_to_relationship_type/2 — non-existent type returns error.
test_add_to_relationship_type_not_found(_TmpDir) ->
    ?_test(begin
        ?assertEqual({error, type_not_found},
                     graphdb_attr:add_to_relationship_type(999999, 1))
    end).

%% get_attribute/1 — non-existent Nref returns error.
test_get_attribute_not_found(_TmpDir) ->
    ?_test(begin
        ?assertEqual({error, not_found}, graphdb_attr:get_attribute(999999))
    end).

%% find_attribute/2 — happy path.
test_find_attribute(_TmpDir) ->
    ?_test(begin
        {ok, Nref} = graphdb_attr:create_name_attribute(<<"class_name">>),
        {ok, Found} = graphdb_attr:find_attribute(name, <<"class_name">>),
        ?assertEqual(Nref, Found)
    end).

%% find_attribute/2 — missing name returns error.
test_find_attribute_not_found(_TmpDir) ->
    ?_test(begin
        ?assertEqual({error, not_found},
                     graphdb_attr:find_attribute(name, <<"no_such_attr">>))
    end).

%% list_attributes/0 — returns at least the bootstrap entries.
test_list_attributes_all(_TmpDir) ->
    ?_test(begin
        All = graphdb_attr:list_attributes(),
        ?assert(length(All) >= 2)
    end).

%% list_attributes/1 — filters correctly by kind.
test_list_attributes_by_kind(_TmpDir) ->
    ?_test(begin
        {ok, _} = graphdb_attr:create_name_attribute(<<"kind_test_name">>),
        {ok, _} = graphdb_attr:create_literal_attribute(<<"kind_test_lit">>, string),
        Names    = graphdb_attr:list_attributes(name),
        Literals = graphdb_attr:list_attributes(literal),
        ?assert(lists:any(fun(R) -> maps:get(name, R) =:= <<"kind_test_name">> end, Names)),
        ?assert(lists:any(fun(R) -> maps:get(name, R) =:= <<"kind_test_lit">>  end, Literals)),
        %% name entries must not appear in literals list and vice-versa.
        ?assertNot(lists:any(fun(R) -> maps:get(type, R) =/= name    end, Names)),
        ?assertNot(lists:any(fun(R) -> maps:get(type, R) =/= literal end, Literals))
    end).

%% list_relationship_types/0 — returns only relationship_type records.
test_list_relationship_types(_TmpDir) ->
    ?_test(begin
        {ok, _} = graphdb_attr:create_relationship_type(<<"TestType">>),
        Types = graphdb_attr:list_relationship_types(),
        ?assert(length(Types) >= 1),
        ?assert(lists:all(
            fun(R) -> maps:get(type, R) =:= relationship_type end,
            Types))
    end).

%% Attributes survive a server stop and restart (DETS persistence).
test_persistence_across_restart(_TmpDir) ->
    ?_test(begin
        %% Write some attributes.
        {ok, Nref1} = graphdb_attr:create_name_attribute(<<"persist_name">>),
        {ok, Nref2} = graphdb_attr:create_literal_attribute(<<"persist_lit">>, integer),
        {ok, {Nref3, _Nref4}} =
            graphdb_attr:create_relationship_attribute(
                <<"persist_fwd">>, <<"persist_rec">>),
        %% Stop the server (closes DETS files).
        ok = gen_server:stop(graphdb_attr),
        %% Restart the server against the same DETS files.
        {ok, _Pid} = graphdb_attr:start_link(),
        %% All previously written records must still be present.
        ?assertMatch({ok, _}, graphdb_attr:get_attribute(Nref1)),
        ?assertMatch({ok, _}, graphdb_attr:get_attribute(Nref2)),
        ?assertMatch({ok, _}, graphdb_attr:get_attribute(Nref3)),
        %% Index lookups must also work.
        ?assertMatch({ok, Nref1}, graphdb_attr:find_attribute(name,         <<"persist_name">>)),
        ?assertMatch({ok, Nref2}, graphdb_attr:find_attribute(literal,      <<"persist_lit">>)),
        ?assertMatch({ok, Nref3}, graphdb_attr:find_attribute(relationship,  <<"persist_fwd">>)),
        %% Bootstrap records still accessible.
        ?assertMatch({ok, _}, graphdb_attr:find_attribute(name,    <<"attr_name">>)),
        ?assertMatch({ok, _}, graphdb_attr:find_attribute(literal, <<"relationship_avp">>))
    end).
