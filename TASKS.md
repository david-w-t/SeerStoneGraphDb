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


## ~~3. graphdb worker modules~~ ✓ DONE (branch: graphdb_sonnet46)

All six graphdb workers implemented as inline gen_server modules.
See branch `graphdb_sonnet46` (commit `cefcf94`).

| Module | Storage | Role |
|---|---|---|
| `graphdb_class` | ETS + `tab2file` | Class/schema hierarchy; root class seeded at ClassId=0 |
| `graphdb_attr` | ETS + `tab2file` | Attribute store keyed by `{Nref, Name}` |
| `graphdb_rules` | ETS + `tab2file` | Rule store with `evaluate/2`; events: create/delete node/edge, set_attr |
| `graphdb_instance` | DETS | Node `{Nref, node, ClassId, Props}` and edge `{Nref, edge, From, To, ClassId, Props}` instances |
| `graphdb_mgr` | None (coordinator) | Facade over all workers; enforces rules before mutations |
| `graphdb_language` | None (interpreter) | Erlang-term DSL: `get`, `find_by_attr`, `match`, `traverse` (BFS), `and_query`, `or_query` |

Design decisions made:
- Nodes **and** edges are first-class — both receive Nrefs from `nref_server:get_nref/0`
- Classes are also identified by Nrefs (root = 0)
- Logic lives inline in each gen_server (no separate `_imp` modules)
- `graphdb_language` uses an Erlang-term DSL, not a text parser

### Comparison with `graphdb_minimax25`

A parallel implementation exists on branch `graphdb_minimax25`. Key differences:

| Dimension | `graphdb_sonnet46` | `graphdb_minimax25` |
|---|---|---|
| Edge identity | Nref (from `nref_server`) | Separate auto-increment integer — **not** a Nref |
| Class identity | Nref integer | Atom (e.g. `thing`, `entity`) |
| Durability | DETS (instances) + `tab2file` (others) | ETS only — **data lost on restart** |
| Attr index | Single table, scan on `find_by_attr` | Two-table with secondary `duplicate_bag` index — faster lookups |
| Class hierarchy | Scan-based subclass lookup | Eagerly maintained descendant lists (faster reads, complex delete) |
| Query language | Simple term DSL, BFS traversal | SQL-like string parser (`SELECT node WHERE ...`) + BFS/DFS, but parser is skeletal |
| Code style | Preserves Dallas's header conventions | More modern; adds `-spec`, `-type`, `logger.hrl` include; diverges from original style |

Advantages of `graphdb_minimax25` worth considering for a merge:
- Two-table attr index (secondary `duplicate_bag`) enables O(1) `find_by_attr` vs full scan
- Richer `graphdb_language` API surface (`select/insert/update/delete/traverse` as named functions)
- `-spec` annotations improve dialyzer coverage

Advantages of `graphdb_sonnet46`:
- All identifiers (nodes, edges, classes) are Nrefs — consistent with Dallas's design intent
- DETS persistence means instance data survives restarts
- Simpler, closer to the original codebase style


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

1. ~~**dictionary_server + term_server stubs**~~ ✓ DONE
2. ~~**dictionary_imp export_all**~~ ✓ DONE
3. ~~**nref_include clarification**~~ ✓ DONE
4. **graphdb worker implementations** — two competing branches; merge decision needed
5. **seerstone/nref start/2 non-normal clause** — low priority, distributed only
6. **code_change/3** — low priority, hot upgrades only
7. **Old directory cleanup** — housekeeping
