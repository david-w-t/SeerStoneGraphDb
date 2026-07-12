%%---------------------------------------------------------------------
%% Copyright (c) 2008 SeerStone, Inc.
%% Copyright (c) 2026 David W. Thomas
%% SPDX-License-Identifier: GPL-2.0-or-later
%%---------------------------------------------------------------------
%% Author: David W. Thomas
%% Created: 2026-07-08
%% Description: grpcbox service implementation for
%%              graphdb_api.LanguageService (graphdb_api_language_service_bhvr,
%%              generated from language_service.proto). Chain crosses the
%%              wire opaquely (Value term_binary) -- MakeChain produces
%%              it, ResolveLabel consumes it unchanged; the client never
%%              inspects it. Scope is hardcoded to `environment`.
%%
%%              `code`/`base_code` wire fields decode as binaries (gpb
%%              default for proto3 string fields in this codebase's
%%              config) but graphdb_language keys its internal language
%%              maps (lang_code_map/dialect_map) by atom -- overlay
%%              table names are built with atom_to_list/1 -- so this
%%              module mints atoms from them with binary_to_atom/2, the
%%              same pattern graphdb_api_attribute_service_impl uses for
%%              its `type` field. Accepted only under the internal-
%%              trusted-network threat model (see that module's note).
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: all 6 LanguageService RPCs.
%%---------------------------------------------------------------------
-module(graphdb_api_language_service_impl).
-behaviour(graphdb_api_language_service_bhvr).

-revision('Revision: PA1 ').
-created('Date: 2026-07-08').
-created_by('david@davidwt.com').

-define(NYI(X), (begin
    io:format("*** NYI ~p ~p ~p~n",[?MODULE, ?LINE, X]),
    exit(nyi)
end)).
-define(UEM(F, X), (begin
    io:format("*** UEM ~p:~p ~p ~p~n",[?MODULE, F, ?LINE, X]),
    exit(uem)
end)).

-export([register_language/2, register_dialect/2, lookup_language_nref/2,
         set_labels/2, make_chain/2, resolve_label/2]).

-define(SCOPE, environment).

register_language(Ctx, #{code := Code, name := Name}) ->
    case graphdb_language:register_language(code_to_atom(Code), Name) of
        {ok, Nref} -> {ok, #{nref => Nref}, Ctx};
        Error      -> graphdb_api_error:to_status(Error)
    end.

register_dialect(Ctx, #{code := Code, name := Name, base_code := BaseCode}) ->
    case graphdb_language:register_dialect(
            code_to_atom(Code), Name, code_to_atom(BaseCode)) of
        {ok, Nref} -> {ok, #{nref => Nref}, Ctx};
        Error      -> graphdb_api_error:to_status(Error)
    end.

lookup_language_nref(Ctx, #{code := Code}) ->
    case graphdb_language:lookup_language_nref(code_to_atom(Code)) of
        {ok, Nref} -> {ok, #{nref => Nref}, Ctx};
        Error      -> graphdb_api_error:to_status(Error)
    end.

set_labels(Ctx, #{nref := Nref, code := Code, labels := Labels}) ->
    Terms = [graphdb_api_value:pb_to_avp(A) || A <- Labels],
    case graphdb_language:set_labels(Nref, code_to_atom(Code), Terms) of
        ok    -> {ok, #{}, Ctx};
        Error -> graphdb_api_error:to_status(Error)
    end.

make_chain(Ctx, #{codes := Codes}) ->
    Chain = graphdb_language:make_chain([code_to_atom(C) || C <- Codes]),
    {ok, #{chain => graphdb_api_value:term_to_value(Chain)}, Ctx}.

resolve_label(Ctx, #{nref := Nref, attr_nref := AttrNref, chain := ChainPb}) ->
    Chain = graphdb_api_value:value_to_term(ChainPb),
    case graphdb_language:resolve_label(Nref, AttrNref, Chain, ?SCOPE) of
        {ok, Label} -> {ok, #{label => graphdb_api_value:term_to_value(Label)}, Ctx};
        Error       -> graphdb_api_error:to_status(Error)
    end.

%%-----------------------------------------------------------------------------
%% Internal
%%-----------------------------------------------------------------------------

%% code_to_atom(binary()) -> atom()
%%
%% graphdb_language's language codes are atoms (lang_code_map/dialect_map
%% keys, overlay_table_name/2's atom_to_list/1); the wire carries them as
%% strings (binaries). No catch-all needed: binary_to_atom/2 accepts any
%% binary, including the empty binary from an omitted proto3 string field
%% (mints the atom '') -- graphdb_language then reports it as
%% not_found/already_registered/base_not_found through the normal error
%% path, never an uncaught crash.
code_to_atom(Code) when is_binary(Code) ->
    binary_to_atom(Code, utf8).
