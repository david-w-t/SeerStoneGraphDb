# graphdb Implementation Branch Comparison

**Date:** March 19, 2026  
**Branches compared:** `graphdb_sonnet46` (claude-sonnet-4-6) vs `graphdb_minimax25` (minimax m2.5)  
**Base branch:** `develop` at commit `92c17fd`

---

## Overview

Two AI-generated implementations of the six graphdb worker modules were produced
independently on separate branches. Both implement the same six modules
(`graphdb_class`, `graphdb_attr`, `graphdb_rules`, `graphdb_instance`,
`graphdb_mgr`, `graphdb_language`) starting from the same gen_server stubs.
The branches diverge significantly in design decisions.

---

## 1. Nref Usage

This is the most fundamental difference.

**`graphdb_sonnet46`:**  
Nrefs are used as the identity for **nodes, edges, and classes**. Every entity
that needs a globally unique ID calls `nref_server:get_nref/0`. This is
consistent with Dallas's design intent, expressed in `graphdb_instance.erl`'s
original header comment:

> "Graph nodes are identified by Nrefs (globally unique integers) allocated
> by the nref application."

- Node record: `{Nref, node, ClassId::nref(), Props::map()}`
- Edge record: `{Nref, edge, FromNref::nref(), ToNref::nref(), ClassId::nref(), Props::map()}`
- Class record: `{ClassId::nref(), ParentId::nref()|undefined, Name::binary(), AttrSpecs}`
- Root class hardcoded as `ClassId = 0`

**`graphdb_minimax25`:**  
Nrefs are used only for **nodes**. Edges use a separate auto-increment integer
from `nref_server` (via `catch nref_server:get_nref/0` with a fallback), but the
return value is tagged `{edge_id, EdgeId}` rather than `{ok, Nref}`, treating
edge IDs as a distinct namespace. Classes are identified by **atoms** (e.g.
`thing`, `entity`, `person`) rather than integers.

Consequence: in `graphdb_minimax25`, edge IDs and class identifiers are not
interoperable with the nref allocation/recycling/confirmation machinery. A
deleted edge's ID is never returned to `nref_server` for reuse.

---

## 2. Data Persistence

**`graphdb_sonnet46`:**
- `graphdb_instance`: **DETS** — node and edge data is durable across restarts
- `graphdb_class`, `graphdb_attr`, `graphdb_rules`: **ETS with `ets:tab2file`
  on terminate** — persisted to disk on clean shutdown, reloaded on startup
- Data survives node restarts (assuming clean shutdown or DETS for instances)

**`graphdb_minimax25`:**
- All six modules use **ETS only** — no DETS, no `tab2file`
- All graph data is **lost on restart**
- No persistence mechanism of any kind is present

This is a significant omission for a database system.

---

## 3. Attribute Storage (`graphdb_attr`)

**`graphdb_sonnet46`:**  
Single ETS table, keyed by `{Nref, Name}`:
```erlang
{{Nref, AttrName::binary()}, Value::term()}
```
- `set_attr/3`, `get_attr/2`, `get_attrs/1`, `delete_attr/2`, `delete_attrs/1`
- `find_by_attr` requires a full table scan via `ets:match`

**`graphdb_minimax25`:**  
Two ETS tables:
- `graphdb_attrs`: primary store keyed by `{EntityType, EntityId, Key}`
- `graphdb_attr_index`: secondary `duplicate_bag` table keyed by `{Key, Value, EntityType, EntityId}`

The secondary index makes `find_by_attr/2` an O(1) lookup instead of a full
scan. This is a real performance advantage at scale.

Additional API in minimax25: `set_attrs/2` (bulk), `get_all_attrs/2` (returns
map), `has_attr/2`, `attr_count/0`, `unique_keys/0`, `find_by_attr/3`
(with limit). The API takes `(EntityType::node|edge, EntityId, Key, Value)` —
a more explicit signature than sonnet46's `(Nref, Name, Value)`.

Note: minimax25's `do_get_attrs` has a pattern match bug —
`ets:match_object(?TAB_ATTRS, {Pattern, '_'})` where `Pattern` is a tuple
`{EntityType, EntityId, '_'}` will not match correctly because the key is a
3-tuple stored as the ETS key, not nested inside another tuple.

---

## 4. Class Hierarchy (`graphdb_class`)

**`graphdb_sonnet46`:**
- Classes identified by Nref integers
- `create_class/3` takes `(Name::binary(), ParentId::nref()|undefined, AttrSpecs)`
- Subclass lookup: `ets:match_object(Tab, {'_', ClassId, '_', '_'})` — full scan
- `is_a/2` not implemented (not in API)
- `get_ancestors/1` not implemented

**`graphdb_minimax25`:**
- Classes identified by atoms
- `create_class/3` takes `(Name::atom(), Parent::atom()|undefined, Attrs::map())`
- Two ETS tables: `graphdb_classes` (class records) and `graphdb_class_hierarchy`
  (eagerly maintained descendant lists)
- `is_a/2`, `get_ancestors/1`, `get_descendants/1` implemented
- `update_class/2` implemented (sonnet46 has no update)
- On `create_class`, descendant lists are propagated up **all ancestors** —
  reads are O(1) but writes are O(depth)

Potential bug in minimax25: `delete_class_hierarchy/1` re-parents descendants
to the deleted class's parent, but does not update the `graphdb_class_hierarchy`
table for those re-parented descendants or their ancestors. Hierarchy table
can become stale after a delete.

---

## 5. Instance Storage (`graphdb_instance`)

**`graphdb_sonnet46`:**
- DETS-backed, single table for both nodes and edges
- `create_node/2` returns `{ok, Nref}`
- `create_edge/4` returns `{ok, Nref}` — edge is first-class with its own Nref
- `delete/1` cleans up attrs via `graphdb_attr:delete_attrs/1` and returns the
  Nref to `nref_server:reuse_nref/1`
- `all_nodes/0`, `all_edges/0` via `dets:match_object`

**`graphdb_minimax25`:**
- ETS-backed, three tables: `graphdb_nodes`, `graphdb_edges`, `graphdb_edge_index`
- `create_node/2` returns `{nref, Nref}` — inconsistent return tag vs. standard `{ok, ...}`
- `create_edge/4` returns `{edge_id, EdgeId}` — edge ID is not a Nref
- Separate `get_edges_from/1` and `get_edges_to/1` (sonnet46 only has `get_edges/1`
  for outbound)
- `update_node/2` and `update_edge/2` implemented (sonnet46 has no update)
- `node_count/0`, `edge_count/0` via `ets:info`
- `delete_node` cascades to delete all incident edges — sonnet46 does not cascade

---

## 6. Rules (`graphdb_rules`)

**`graphdb_sonnet46`:**
- Rule record: `{RuleId::nref(), Name::binary(), Event::atom(), Condition::term(), Action::term()}`
- Events: `create_node | delete_node | create_edge | delete_edge | set_attr`
- Conditions: `{class, ClassId}`, `{attr, Name, Value}`, `any`
- Actions: `{deny, Reason}`, `{log, Message}`, `allow`
- `evaluate/2` returns `allow | {deny, Reason}` — called by `graphdb_mgr` before mutations
- Persisted via `tab2file`

**`graphdb_minimax25`:**
- Rules module is a stub — `graphdb_rules` has no real implementation beyond
  the gen_server skeleton. The `handle_call` catchall fires `?UEM` on any call.
- No rule storage, no evaluate, no API beyond `start_link/0`

This is a significant gap in minimax25.

---

## 7. Manager / Coordinator (`graphdb_mgr`)

**`graphdb_sonnet46`:**
- Full facade: all node/edge/attr/class/rule operations exposed
- Mutation operations (create node/edge, delete node/edge, set attr) pass through
  `graphdb_rules:evaluate/2` before delegating — workers are policy-free
- Read operations delegate directly without going through the gen_server
  (e.g. `get_attr`, `get_attrs`, `get_class` call workers directly)

**`graphdb_minimax25`:**
- Full facade with similar coverage
- No rule evaluation — mutations go directly to workers
- Additional operations: `query/1`, `query/2` (delegates to `graphdb_language`)
- `stats/0` returns aggregate counts across all workers
- `get_node_with_attrs/1` — convenience function that fetches node + all attrs in one call

---

## 8. Query Language (`graphdb_language`)

**`graphdb_sonnet46`:**  
Erlang-term DSL — queries are Erlang tuples passed directly to `execute/1`:

```erlang
graphdb_language:execute({get, Nref})
graphdb_language:execute({match, ClassId})
graphdb_language:execute({find_by_attr, <<"name">>, <<"Alice">>})
graphdb_language:execute({traverse, FromNref, EdgeClassId, 3})
graphdb_language:execute({and_query, [Q1, Q2]})
graphdb_language:execute({or_query, [Q1, Q2]})
```

No parser needed. Simple, reliable, easily extended. BFS traversal implemented.

**`graphdb_minimax25`:**  
More ambitious: a string-based SQL-like query parser plus a structured query map API:

```erlang
graphdb_language:query("SELECT node WHERE name == Alice")
graphdb_language:select(node, [{field, name, '==', <<"Alice">>}])
graphdb_language:insert(node, #{class => person, name => <<"Alice">>})
graphdb_language:update(node, Conditions, NewAttrs)
graphdb_language:delete(node, Conditions)
graphdb_language:traverse(StartNref, FilterFun, MaxDepth)
graphdb_language:traverse_breadth_first(StartNref, FilterFun, MaxDepth)
graphdb_language:traverse_depth_first(StartNref, FilterFun, MaxDepth)
```

The string parser (`tokenize/parse_tokens`) is extremely rudimentary — it
splits on spaces and keywords (`SELECT`, `INSERT`, etc.) but cannot parse
`WHERE` clauses, quoted strings, or any real query syntax. `parse_conditions`
and `parse_data` are skeletal. In practice, the string query path would fail
on anything beyond trivial inputs.

The structured map query path (`select/2,3`, `insert/2`, `update/3`, `delete/2`)
is more usable and does real work via `filter_nodes`/`matches_conditions`. The
condition DSL `{field, Field, Op, Value}` with `'and'`/`'or'` combinators and
operators `==`, `/=`, `>`, `<`, `>=`, `=<`, `in`, `like` (regex) is well-designed.

The `graphdb_language` gen_server callbacks are never used — all API functions
bypass the gen_server and call internal functions directly, making `graphdb_language`
effectively a plain module that happens to run a gen_server process for no purpose.

Also: `execute_traverse` passes `_Context` as a variable name but references it
as `_Context` in a guard position in a later clause, which will produce a compiler
warning.

---

## 9. Code Style and Conventions

**`graphdb_sonnet46`:**
- Preserves Dallas's header format: copyright block, revision history, `%%-modified`
  commented out, `Rev PA1` / `Rev A` pattern, `*** 2008` dates
- NYI/UEM macro comment blocks retained
- No `-spec` or `-type` annotations
- Uses `logger:info/2`, `logger:error/2` (module-qualified)
- State variable named `Tab` where appropriate (matches the stored value)

**`graphdb_minimax25`:**
- Strips comment blocks around NYI/UEM macros
- Removes `%%-modified` lines
- Adds `-include_lib("kernel/include/logger.hrl")` and uses `?LOG_INFO` macro
- Adds `-spec` and `-type` annotations throughout — better for dialyzer
- Adds `-export_type` declarations
- Sets `-created` to `March 19, 2026` (accurate) rather than `*** 2008`
- Uses maps (`#{}`) as gen_server state rather than `[]`
- `code_change/3` silently returns `{ok, State}` instead of `?NYI` — correct
  behaviour but removes the crash signal if hot upgrades are attempted unexpectedly

---

## 10. `database_sup` change

**`graphdb_minimax25`** adds `start_link/1` to `apps/database/src/database_sup.erl`:

```erlang
start_link(StartArgs) ->
    supervisor:start_link(database_sup, StartArgs).
```

**`graphdb_sonnet46`** does not touch `database_sup`.

The existing `database_sup:init/1` only handles `[]` as its argument (the
`?UEM` fires on anything else), so this new `start_link/1` would crash the
supervisor on any non-empty `StartArgs`. The addition appears incomplete.

---

## Summary Table

| Dimension | `graphdb_sonnet46` | `graphdb_minimax25` |
|---|---|---|
| Node identity | Nref | Nref |
| Edge identity | **Nref** (first-class) | Auto-int, not a Nref |
| Class identity | **Nref** (integer) | Atom |
| Instance persistence | **DETS** | ETS only — lost on restart |
| Attr persistence | ETS + tab2file | ETS only — lost on restart |
| Attr index | Single table (scan) | **Two-table secondary index** |
| `find_by_attr` | Full scan | **O(1) index lookup** |
| Class hierarchy | Scan-based | **Eager descendant lists** |
| `is_a` / ancestors | Not implemented | **Implemented** |
| `update_node/edge` | Not implemented | **Implemented** |
| Node delete cascade | Not implemented | **Implemented** (deletes edges) |
| Rules (`graphdb_rules`) | **Fully implemented** | Stub only |
| Rule enforcement | **In `graphdb_mgr`** | Not present |
| Query language | Erlang-term DSL | SQL-like string + structured map API |
| String query parser | N/A | Present but skeletal |
| Structured query API | Minimal | **Richer (`select/insert/update/delete`)** |
| BFS/DFS traversal | BFS only | **Both** |
| `-spec` annotations | None | **Present** |
| Code style | **Preserves Dallas's conventions** | Modern, diverges from original |
| `code_change/3` | `?NYI` (crashes on hot upgrade) | Silent `{ok, State}` |
| Known bugs | None identified | `do_get_attrs` pattern bug; hierarchy stale on delete; language gen_server unused |

---

## Recommended Merge Strategy

Neither branch is complete on its own. A merged implementation would take:

**From `graphdb_sonnet46`:**
- Nrefs for edges and classes (consistent with Dallas's design)
- DETS persistence for `graphdb_instance`
- `tab2file` persistence for `graphdb_class`, `graphdb_attr`, `graphdb_rules`
- Fully implemented `graphdb_rules` with `evaluate/2` and rule enforcement in `graphdb_mgr`

**From `graphdb_minimax25`:**
- Two-table secondary index in `graphdb_attr` (fix the pattern bug)
- `is_a/2`, `get_ancestors/1`, `get_descendants/1` in `graphdb_class`
- `update_node/2`, `update_edge/2` in `graphdb_instance`
- Node delete cascade to edges in `graphdb_instance`
- Structured query API in `graphdb_language` (`select/insert/update/delete` with condition DSL)
- `-spec` and `-type` annotations
