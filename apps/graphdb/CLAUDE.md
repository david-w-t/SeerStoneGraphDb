# graphdb — Graph Database OTP Application

## Purpose

`graphdb` is the core **graph database** OTP application within the SeerStone system. It is supervised by `database_sup` (see `Database/`) and itself manages graph data through `graphdb_sup`.

## Files

| File | Description |
|---|---|
| `graphdb.erl` | OTP `application` behaviour callback module |
| `graphdb_sup.erl` | OTP `supervisor` — supervises all six worker gen_servers |
| `graphdb_mgr.erl` | Primary coordinator; public API facade; enforces rules before mutations |
| `graphdb_class.erl` | Class/schema hierarchy; ETS-backed; persisted via `tab2file` |
| `graphdb_attr.erl` | Node/edge attribute store; ETS-backed; persisted via `tab2file` |
| `graphdb_rules.erl` | Rule store with `evaluate/2`; ETS-backed; persisted via `tab2file` |
| `graphdb_instance.erl` | Node and edge instance store; DETS-backed (durable) |
| `graphdb_language.erl` | Erlang-term DSL query interpreter; no storage |

## Application Lifecycle

`graphdb` is started by calling `application:start(graphdb)` or indirectly via the `database` application supervisor. The call chain is:

```
database_sup -> graphdb_sup:start_link(StartArgs) -> graphdb_sup:init/1
```

`graphdb:start/2` delegates immediately to `graphdb_sup:start_link/1`.

## Supervisor (`graphdb_sup`)

`graphdb_sup` uses `one_for_one` strategy and supervises all six workers as
`permanent` children with `brutal_kill` shutdown. Workers start in this order:
`graphdb_mgr`, `graphdb_rules`, `graphdb_attr`, `graphdb_class`,
`graphdb_instance`, `graphdb_language`.

## Worker Module Summary

### `graphdb_class`
- ETS table, persisted to `graphdb_class.ets` on shutdown
- Record: `{ClassId::nref(), ParentId::nref()|undefined, Name::binary(), AttrSpecs}`
- Built-in root class seeded at `ClassId = 0` on first startup
- API: `create_class/3`, `get_class/1`, `get_class_by_name/1`, `delete_class/1`,
  `get_subclasses/1`, `all_classes/0`

### `graphdb_attr`
- ETS table keyed by `{Nref, AttrName::binary()}`, persisted to `graphdb_attr.ets`
- API: `set_attr/3`, `get_attr/2`, `get_attrs/1`, `delete_attr/2`, `delete_attrs/1`

### `graphdb_rules`
- ETS table, persisted to `graphdb_rules.ets` on shutdown
- Record: `{RuleId::nref(), Name::binary(), Event::atom(), Condition::term(), Action::term()}`
- Events: `create_node | delete_node | create_edge | delete_edge | set_attr`
- Conditions: `{class, ClassId}`, `{attr, Name, Value}`, `any`
- Actions: `{deny, Reason}`, `{log, Message}`, `allow`
- API: `add_rule/4`, `get_rule/1`, `delete_rule/1`, `all_rules/0`, `evaluate/2`

### `graphdb_instance`
- DETS table (`graphdb_instance.dets`) — data is durable across restarts
- Node record: `{Nref, node, ClassId::nref(), Props::map()}`
- Edge record: `{Nref, edge, FromNref::nref(), ToNref::nref(), ClassId::nref(), Props::map()}`
- Both nodes and edges are first-class: each gets its own Nref from `nref_server`
- `delete/1` removes attrs via `graphdb_attr:delete_attrs/1` and returns the
  Nref to `nref_server:reuse_nref/1`
- API: `create_node/2`, `create_edge/4`, `get/1`, `delete/1`,
  `get_edges/1`, `get_edges/2`, `all_nodes/0`, `all_edges/0`

### `graphdb_mgr`
- No storage; pure coordinator
- All mutation operations (`create_node`, `delete_node`, `create_edge`,
  `delete_edge`, `set_attr`) pass through `graphdb_rules:evaluate/2` first
- Read operations delegate directly to workers without going through the gen_server
- API: full union of all worker APIs

### `graphdb_language`
- No storage; pure interpreter
- Erlang-term DSL — queries are Erlang tuples passed to `execute/1`:
  ```erlang
  {get, Nref}
  {match, ClassId}
  {find_by_attr, Name::binary(), Value::term()}
  {traverse, FromNref, EdgeClassId, Depth::pos_integer()}  %% BFS
  {and_query, [Query]}
  {or_query, [Query]}
  ```

## Key Design Notes

- **All identifiers are Nrefs** — nodes, edges, and classes are all identified
  by plain positive integers allocated by `nref_server:get_nref/0`. No wrapper
  types. This is consistent with Dallas's original design intent.
- `graphdb_sup` receives `StartArgs` from `database:start/2`
- The UEM macro in `graphdb:start/2` catches unexpected return values from
  `graphdb_sup:start_link/1`

## NYI / Remaining Stubs

The following callbacks in `graphdb.erl` return `ok` (no-op) and are correct
for the current deployment model:
- `start_phase/3`, `prep_stop/1`, `stop/1`, `config_change/3`

`code_change/3` in all six worker gen_servers calls `?NYI` — only relevant
for hot code upgrades (see TASKS.md item 6).

## Branch Comparison

A second independent implementation exists on branch `graphdb_minimax25`.
A detailed comparison of both branches, including known bugs and a recommended
merge strategy, is in `docs/graphdb_branch_comparison.md`.

## Compile

```sh
# from project root:
./rebar3 compile
```
