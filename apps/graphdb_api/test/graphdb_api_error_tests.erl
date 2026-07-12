-module(graphdb_api_error_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("grpcbox/include/grpcbox.hrl").

not_found_maps_to_grpc_not_found_test() ->
    {grpc_extended_error, #{status := Status}} =
        graphdb_api_error:to_status({error, not_found}),
    ?assertEqual(grpcbox_stream:code_to_status(5), Status).

invalid_session_maps_to_unauthenticated_test() ->
    {grpc_extended_error, #{status := Status}} =
        graphdb_api_error:to_status({error, invalid_session}),
    ?assertEqual(grpcbox_stream:code_to_status(16), Status).

category_nodes_are_immutable_maps_to_invalid_argument_test() ->
    {grpc_extended_error, #{status := Status}} =
        graphdb_api_error:to_status({error, category_nodes_are_immutable}),
    ?assertEqual(grpcbox_stream:code_to_status(3), Status).

instance_only_attribute_tuple_maps_to_invalid_argument_test() ->
    {grpc_extended_error, #{status := Status}} =
        graphdb_api_error:to_status({error, {instance_only_attribute, 999}}),
    ?assertEqual(grpcbox_stream:code_to_status(3), Status).

not_implemented_maps_to_unimplemented_test() ->
    {grpc_extended_error, #{status := Status}} =
        graphdb_api_error:to_status({error, not_implemented}),
    ?assertEqual(grpcbox_stream:code_to_status(12), Status).

no_default_template_tuple_maps_to_failed_precondition_test() ->
    {grpc_extended_error, #{status := Status}} =
        graphdb_api_error:to_status({error, {no_default_template, 123}}),
    ?assertEqual(grpcbox_stream:code_to_status(9), Status).

no_class_membership_tuple_maps_to_failed_precondition_test() ->
    {grpc_extended_error, #{status := Status}} =
        graphdb_api_error:to_status({error, {no_class_membership, 456}}),
    ?assertEqual(grpcbox_stream:code_to_status(9), Status).

unknown_reason_falls_back_to_internal_test() ->
    {grpc_extended_error, #{status := Status}} =
        graphdb_api_error:to_status({error, {something_nobody_curated, 42}}),
    ?assertEqual(grpcbox_stream:code_to_status(13), Status).

bare_reason_without_error_wrapper_works_test() ->
    {grpc_extended_error, #{status := Status}} =
        graphdb_api_error:to_status(not_found),
    ?assertEqual(grpcbox_stream:code_to_status(5), Status).

raw_reason_survives_in_trailer_test() ->
    Reason = {instance_only_attribute, 999},
    {grpc_extended_error, #{trailers := Trailers}} =
        graphdb_api_error:to_status({error, Reason}),
    Encoded = maps:get(<<"x-erlang-reason-bin">>, Trailers),
    ?assertEqual(Reason, binary_to_term(base64:decode(Encoded), [safe])).

message_is_human_readable_test() ->
    {grpc_extended_error, #{message := Msg}} =
        graphdb_api_error:to_status({error, {ambiguous_relationship, [1, 2]}}),
    ?assert(is_binary(Msg)),
    ?assert(binary:match(Msg, <<"ambiguous_relationship">>) =/= nomatch).
