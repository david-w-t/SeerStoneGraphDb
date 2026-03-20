# SeerStoneGraphDb — Remaining Tasks

Generated: 2026-03-15. All modernization work is complete and the project
compiles clean with zero warnings (OTP 27 / rebar3 3.24.0). What follows
is implementation work — completing Dallas's unfinished NYI stubs.

---

## ~~1. dictionary subsystem — missing worker modules~~ ✓ DONE

`dictionary_server` and `term_server` created as gen_server stubs in
`apps/dictionary/src/`. The `dictionary` application now starts cleanly.

Related reference files (not compiled, kept for design context):
- `Dictionary/dict_wkr.erl` — Dallas's earlier worker sketch
- `Dictionary/dictionary_draft.erl` — early draft of the `dictionary` module


## ~~2. dictionary_imp — export_all flag~~ ✓ DONE

`-compile(export_all).` removed. The explicit `-export([...])` list was
already present; the compiler now warns about unused functions normally.


## 3. graphdb worker modules — all are empty stubs

All six graphdb workers exist as gen_server stubs that start cleanly but
do nothing:

| Module | Intended role |
|---|---|
| `graphdb_mgr` | Primary coordinator for graphdb operations |
| `graphdb_rules` | Storage and enforcement of graph rules |
| `graphdb_attr` | Node/edge attribute management |
| `graphdb_class` | Class/type/schema definitions |
| `graphdb_instance` | Creation and retrieval of graph node/edge instances |
| `graphdb_language` | Graph query language parsing and execution |

Each needs its API designed and implemented. Graph nodes are identified by
**Nrefs** (plain `integer()`, allocated by `nref_server:get_nref/0`).

Location: `apps/graphdb/src/graphdb_*.erl`


## ~~4. nref_include — purpose unclear~~ ✓ DONE

`apps/nref/src/nref_include.erl` was Dallas's earlier unsupervised,
plain-function predecessor to `nref_server`. It was fully superseded by
`nref_server` (a proper gen_server supervised by `nref_sup`) and was
never referenced from anywhere in the compiled codebase. The file has
been deleted.


## 5. seerstone:start/2 — non-normal start types NYI

`apps/seerstone/src/seerstone.erl` line 152–153:
```erlang
start(Type, StartArgs) ->
    ?NYI({start, {Type, StartArgs}}),
```
The second clause handles takeover and failover starts
(`{takeover, Node}`, `{failover, Node}`). These are only relevant in a
distributed/failover OTP deployment. Low priority, but the `?NYI` will
crash the application master if a non-normal start is ever attempted.
Same pattern exists in `apps/nref/src/nref.erl`.


## 6. code_change/3 — NYI in all gen_server modules

The following gen_server modules have `?NYI(code_change)` in their
`code_change/3` callback:

- `apps/nref/src/nref_allocator.erl`
- `apps/nref/src/nref_server.erl`
- `apps/graphdb/src/graphdb_mgr.erl` (and the other 5 graphdb workers)

`code_change/3` is only invoked during a hot code upgrade. It can remain
NYI until hot upgrades are a real deployment concern. Low priority.


## 7. Old Directory/ top-level source files

The following files in the old pre-rebar3 locations are **not compiled**
by rebar3 and are not part of the active build:

| File | Status |
|---|---|
| `Dictionary/dict_wkr.erl` | Design reference; not in `apps/`; not compiled |
| `Dictionary/dictionary_draft.erl` | Early draft; not in `apps/`; not compiled |
| `Database/`, `graphdb/` top-level dirs | Old source locations; rebar3 uses `apps/` |
| `*.beam` files at project root | Stale; built from old flat layout |

Decision needed: delete the old directories and root-level `.beam` files,
or keep them as historical reference. They do not interfere with the build.


## 8. seerstone.app.src — start_phases not defined

None of the `.app.src` files define a `start_phases` key, so
`start_phase/3` will never be called by OTP. If phased startup is desired
in the future, `start_phases` must be added to the relevant `.app.src` and
the `start_phase/3` implementations in the app modules filled in.
Currently the callbacks return `ok` (no-op) which is correct for the
present configuration.


## Priority Order

1. **dictionary_server + term_server stubs** — blocks `dictionary` app startup
2. **graphdb worker implementations** — core graph database functionality
3. **dictionary_imp export_all** — code quality / hygiene
4. **nref_include clarification** — design decision needed
5. **seerstone/nref start/2 non-normal clause** — low priority, distributed only
6. **code_change/3** — low priority, hot upgrades only
7. **Old directory cleanup** — housekeeping
