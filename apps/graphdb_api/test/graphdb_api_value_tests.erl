-module(graphdb_api_value_tests).
-include_lib("eunit/include/eunit.hrl").

string_value_round_trips_test() ->
    V = graphdb_api_value:term_to_value("Acme"),
    ?assertEqual(#{kind => {str, "Acme"}}, V),
    ?assertEqual("Acme", graphdb_api_value:value_to_term(V)).

binary_string_value_round_trips_test() ->
    V = graphdb_api_value:term_to_value(<<"Acme">>),
    ?assertMatch(#{kind := {str, _}}, V),
    ?assertEqual("Acme", graphdb_api_value:value_to_term(V)).

integer_value_round_trips_test() ->
    V = graphdb_api_value:term_to_value(42),
    ?assertEqual(#{kind => {i, 42}}, V),
    ?assertEqual(42, graphdb_api_value:value_to_term(V)).

float_value_round_trips_test() ->
    V = graphdb_api_value:term_to_value(3.5),
    ?assertEqual(#{kind => {d, 3.5}}, V),
    ?assertEqual(3.5, graphdb_api_value:value_to_term(V)).

bool_value_round_trips_test() ->
    V = graphdb_api_value:term_to_value(true),
    ?assertEqual(#{kind => {b, true}}, V),
    ?assertEqual(true, graphdb_api_value:value_to_term(V)).

undefined_value_round_trips_as_null_test() ->
    V = graphdb_api_value:term_to_value(undefined),
    ?assertEqual(#{kind => {null_value, #{}}}, V),
    ?assertEqual(undefined, graphdb_api_value:value_to_term(V)).

opaque_term_falls_back_to_term_binary_test() ->
    Term = {some, ["nested", 1, 2.0], #{a => b}},
    V = graphdb_api_value:term_to_value(Term),
    ?assertMatch(#{kind := {term_binary, _}}, V),
    ?assertEqual(Term, graphdb_api_value:value_to_term(V)).

non_printable_list_falls_back_to_term_binary_test() ->
    Term = [1, 2, 3, 999999],
    V = graphdb_api_value:term_to_value(Term),
    ?assertMatch(#{kind := {term_binary, _}}, V),
    ?assertEqual(Term, graphdb_api_value:value_to_term(V)).

avp_round_trips_test() ->
    AVP = #{attribute => 12345, value => "Ford"},
    Pb = graphdb_api_value:avp_to_pb(AVP),
    ?assertEqual(AVP, graphdb_api_value:pb_to_avp(Pb)).

avp_update_upsert_round_trips_test() ->
    Update = #{attribute => 12345, value => graphdb_api_value:term_to_value(7), delete => false},
    ?assertEqual(#{attribute => 12345, value => 7},
                 graphdb_api_value:avp_update_to_term(Update)).

avp_update_delete_has_no_value_key_test() ->
    Update = #{attribute => 12345, delete => true},
    Result = graphdb_api_value:avp_update_to_term(Update),
    ?assertEqual(#{attribute => 12345}, Result),
    ?assertNot(maps:is_key(value, Result)).

node_kind_round_trips_test() ->
    lists:foreach(
      fun(Atom) ->
          Enum = graphdb_api_value:atom_to_node_kind(Atom),
          ?assertEqual(Atom, graphdb_api_value:node_kind_to_atom(Enum))
      end,
      [category, attribute, class, instance, template]).

relationship_kind_round_trips_test() ->
    lists:foreach(
      fun(Atom) ->
          Enum = graphdb_api_value:atom_to_relationship_kind(Atom),
          ?assertEqual(Atom, graphdb_api_value:relationship_kind_to_atom(Enum))
      end,
      [taxonomy, composition, connection, instantiation]).
