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
%%              table names are built with atom_to_list/1. Atom-minting
%%              is scoped to registration only: RegisterLanguage and
%%              RegisterDialect legitimately create a code that has
%%              never existed before, so they use binary_to_atom/2
%%              (code_to_atom/1), the same pattern
%%              graphdb_api_attribute_service_impl uses for its `type`
%%              field -- accepted only under the internal-trusted-
%%              network threat model (see that module's note). Every
%%              other RPC (LookupLanguageNref, SetLabels, MakeChain)
%%              only ever operates on an already-registered code, so
%%              they use binary_to_existing_atom/2
%%              (existing_code_to_atom/1) and never mint: an unknown
%%              code surfaces as the same error graphdb_language itself
%%              would return for it (not_found / unregistered_language),
%%              or for MakeChain is silently dropped, mirroring
%%              graphdb_language:make_chain/1's own "drop unknown,
%%              don't crash" contract. Task 10 review fix: the original
%%              revision used binary_to_atom/2 at all 5 call sites,
%%              which let a client mint an unbounded number of atoms
%%              (MakeChain's `codes` is `repeated string`) including on
%%              pure-read/failed-lookup paths.
%%---------------------------------------------------------------------
%% Revision History
%%---------------------------------------------------------------------
%% Rev PA1 Date: 2026-07-08 Author: David W. Thomas
%% Initial implementation: all 6 LanguageService RPCs.
%%---------------------------------------------------------------------
%% Rev PA2 Date: 2026-07-11 Author: David W. Thomas
%% Task 10 review fix: scope atom-minting to RegisterLanguage/
%% RegisterDialect only. LookupLanguageNref, SetLabels, and MakeChain
%% now use binary_to_existing_atom/2 via a new existing_code_to_atom/1
%% helper, translating badarg (code never registered) into the same
%% error graphdb_language itself returns for an unregistered code
%% (LookupLanguageNref -> not_found, SetLabels -> unregistered_language),
%% or, for MakeChain, filtering the code out of the list before calling
%% graphdb_language:make_chain/1 (matching that function's own
%% drop-unknown-codes contract instead of erroring the whole RPC).
%%---------------------------------------------------------------------
-module(graphdb_api_language_service_impl).
-behaviour(graphdb_api_language_service_bhvr).

-revision('Revision: PA2 ').
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
    case existing_code_to_atom(Code) of
        {ok, Atom} ->
            case graphdb_language:lookup_language_nref(Atom) of
                {ok, Nref} -> {ok, #{nref => Nref}, Ctx};
                Error      -> graphdb_api_error:to_status(Error)
            end;
        error ->
            %% Code was never registered -- no such atom exists. Same
            %% error graphdb_language:lookup_language_nref/1 itself
            %% returns for an unknown (already-atom) code; routed
            %% through the same chokepoint as every other error path.
            graphdb_api_error:to_status({error, not_found})
    end.

set_labels(Ctx, #{nref := Nref, code := Code, labels := Labels}) ->
    Terms = [graphdb_api_value:pb_to_avp(A) || A <- Labels],
    case existing_code_to_atom(Code) of
        {ok, Atom} ->
            case graphdb_language:set_labels(Nref, Atom, Terms) of
                ok    -> {ok, #{}, Ctx};
                Error -> graphdb_api_error:to_status(Error)
            end;
        error ->
            %% Same error graphdb_language:set_labels/3 itself returns
            %% for an unregistered (already-atom) code.
            graphdb_api_error:to_status({error, unregistered_language})
    end.

make_chain(Ctx, #{codes := Codes}) ->
    %% graphdb_language:make_chain/1 silently drops codes that are not
    %% keys of lang_code_map; mirror that contract here rather than
    %% erroring the whole RPC over one never-registered code.  A code
    %% that was never registered can't be a binary_to_existing_atom/2
    %% hit at all, so filter it out before calling through.
    Atoms = lists:filtermap(
        fun(C) ->
            case existing_code_to_atom(C) of
                {ok, Atom} -> {true, Atom};
                error      -> false
            end
        end, Codes),
    Chain = graphdb_language:make_chain(Atoms),
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
%% Registration only (RegisterLanguage, RegisterDialect's Code and
%% BaseCode): graphdb_language's language codes are atoms
%% (lang_code_map/dialect_map keys, overlay_table_name/2's
%% atom_to_list/1); the wire carries them as strings (binaries).
%% binary_to_atom/2 mints a new atom -- correct here because these two
%% RPCs legitimately create a code that has never existed before. No
%% catch-all needed: binary_to_atom/2 accepts any binary, including the
%% empty binary from an omitted proto3 string field (mints the atom '')
%% -- graphdb_language then reports it as already_registered/
%% base_not_found through the normal error path, never an uncaught
%% crash.
code_to_atom(Code) when is_binary(Code) ->
    binary_to_atom(Code, utf8).

%% existing_code_to_atom(binary()) -> {ok, atom()} | error
%%
%% Lookup-only call sites (LookupLanguageNref, SetLabels's Code,
%% MakeChain's codes): these only ever operate on an already-registered
%% code, and a registered code was necessarily minted as an atom by
%% code_to_atom/1 during RegisterLanguage/RegisterDialect already --
%% so binary_to_existing_atom/2 either finds it or the code was never
%% registered. Never mints. Returns `error' (not an exception) on
%% badarg so call sites can map "never registered" onto whatever error
%% graphdb_language itself would return for that case, without an
%% uncaught crash reaching the client.
existing_code_to_atom(Code) when is_binary(Code) ->
    try
        {ok, binary_to_existing_atom(Code, utf8)}
    catch
        error:badarg -> error
    end.
