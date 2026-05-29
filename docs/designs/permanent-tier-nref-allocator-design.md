<!--
Copyright (c) 2026 David W. Thomas
SPDX-License-Identifier: GPL-2.0-or-later
-->

# Permanent-Tier Nref Allocator (init-seed nref tier)

**Status:** Draft — pending review
**Date:** 2026-05-28
**Topic origin:** `memory/project-init-seed-nref-tier.md` (first of two
pending topics flagged 2026-05-27)

## 1. Problem

Module `init/1` one-time seed creates currently allocate node nrefs
from the **runtime tier** (≥ `nref_start`), because they call
`nref_server:get_nref/0` after the bootstrap loader has already called
`nref_server:set_floor(nref_start)`.

Affected paths:

| Worker             | init/1 seed path                          | Seeded nodes                                                                                    |
| ------------------ | ----------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `graphdb_attr`     | `ensure_seed/2` → `do_create_attribute/3` | `Attribute Literals` group; `literal_type`, `target_kind`, `relationship_avp`, `attribute_type` |
| `graphdb_language` | `ensure_literal_seed/2`                   | `Language Literals` group; `base_language`, `project_language`                                  |

These seeds are bootstrap-equivalent scaffolding — one-time,
deterministic, structural — and belong in the **permanent tier**
`[label_start, nref_start)` alongside English (10000), `lang_code`, and
`lang_human`, not scattered into runtime space.

The bootstrap loader already allocates its atom-labeled nodes from the
permanent tier via a transient local counter in `build_symbol_table/4`,
but that counter dies when `do_load/0` returns. There is no persistent
"next available permanent nref" anywhere after bootstrap, so init/1
seeds (which run *after* bootstrap) have nothing to continue from.

## 2. Scope

**In scope:** a permanent-tier allocator; rewiring the two init/1 seed
paths to use it; promoting the tier boundaries to header macros;
removing the now-redundant `bootstrap.terms` directives; test and doc
updates.

**Out of scope (explicitly):**

- Runtime creates (`graphdb_instance:create_instance/3`,
  `add_relationship/*`, `graphdb_mgr` write ops, runtime
  `graphdb_language:register_language/2`) keep using
  `nref_server:get_nref/0` — they are genuine runtime data.
- **Cross-version / cross-environment seed identity.** A monotonic
  allocator (computed or persisted) gives collision-avoidance and
  within-a-single-DB-history determinism only. nref *values* remain
  dependent on allocation order/history: a fresh bootstrap of a future
  code version and an upgraded existing DB will assign different
  integers to the same logical seed. Content-addressed / stable
  identity is the job of the second pending topic
  (`memory/project-nref-identity-indirection.md`), not this work.

## 3. Approach: compute-from-DB

A single new gen_server, `graphdb_pnref` (working name — permanent
nref allocator), owns permanent-tier allocation. It derives its cursor
from the `nodes` table itself, so the database is the only source of
truth — no second persisted counter that can drift out of sync.

### 3.1 Tier boundaries become header macros

The fixed tier dividers move into `apps/graphdb/include/graphdb_nrefs.hrl`
as compile-time constants, read by the loader, the allocator, and the
tests:

```erlang
%% -- Permanent / runtime tier boundaries ------------------------------
-define(LABEL_START,    10001).    %% first permanent nref above English
-define(NREF_START,   1000000).    %% runtime tier floor; permanent < this
```

These are **system invariants, not per-bootstrap-file knobs.** The
`{nref_start, N}` / `{label_start, N}` directives added to
`bootstrap.terms` last session are therefore removed; `classify_terms/N`
reverts to returning `{Nodes, Rels}` (no directive parsing), and
`validate_label_start/2` plus its directive-parsing tests are deleted.
The `bootstrap.terms` header comment is updated to reference the macros.

### 3.2 Allocator behaviour

- **Supervision:** child of `graphdb_sup`, inserted *after*
  `graphdb_mgr` (which triggers the loader) and *before* the seeding
  workers (`graphdb_rules`, `graphdb_attr`, `graphdb_class`,
  `graphdb_instance`, `graphdb_language`). Consistent with
  `nref_server` / `rel_id_server` as dedicated allocators.

- **Lazy compute-from-DB, then cached cursor.** On the first
  `next_permanent_nref/0` call (which lands during `graphdb_attr:init`,
  after the loader has written its labeled nodes), the allocator scans
  the `nodes` table:

  ```
  Cursor = max(?LABEL_START, 1 + max{ N in nodes : N < ?NREF_START })
        %% or ?LABEL_START if no node satisfies the predicate
  ```

  The cursor is cached in gen_server state. The gen_server serializes
  all allocations, so concurrent callers cannot collide.

- **Scan invariant (load-bearing).** The compute correctness rests on:
  *every node in the `nodes` table with `nref < ?NREF_START` is a
  permanent seed.* This holds today by construction — all runtime
  creates (`graphdb_instance:do_create_instance` and every other path)
  allocate via `nref_server:get_nref/0`, whose floor is `?NREF_START`,
  so runtime nodes are always `>= ?NREF_START` even though they share
  the same `nodes` table. **Forward constraint:** the architecture's
  future per-project instance space (allocator starting at 1) must be a
  *physically separate* Mnesia table, never the shared `nodes` table —
  otherwise from-1 project nrefs would fall below `?NREF_START` and
  corrupt this scan. The allocator should assert this invariant cannot
  be silently violated (e.g. it only ever scans the ontology `nodes`
  table).

  Computing lazily (on first use) rather than at the allocator's own
  `init/1` avoids a first-boot ordering hazard: on first boot the
  `nodes` table does not exist until the loader creates it, but the
  first allocation request only arrives during `graphdb_attr:init`,
  well after `graphdb_mgr:init` has run the loader.

- **`next_permanent_nref/0`** returns the cursor, then increments it.

### 3.3 Spillover rule

Each allocation hands out `N = cursor` and then increments. If a
handed-out `N >= ?NREF_START`, the permanent tier is full and the
allocation has spilled into runtime space. The allocator then calls
`nref_server:set_floor(N + 1)` so the runtime floor floats up above the
spilled region — i.e. *nref_start becomes the next available nref*.
`set_floor/1` is monotonic (`max(current, Floor)`), so this only ever
raises the floor.

With ~990 000 permanent slots this regime is effectively unreachable;
it is defined and enforced for completeness. Sustained spillover that
interleaves permanent and runtime allocations across boots is an
unsupported corner that would be subsumed by the identity-indirection
topic; it is not engineered here.

### 3.4 Loader stays as-is

The bootstrap loader keeps its local fold counter for the labeled
batch. Because the allocator computes from the DB the loader produced,
the cursor naturally continues immediately past the labeled nodes —
there is no second-source-of-truth problem, and the loader's tested
two-pass behaviour is untouched (apart from sourcing `?LABEL_START` /
`?NREF_START` from macros instead of directives).

## 4. Init-path rewiring

| Call site                                | Change                                                      |
| ---------------------------------------- | ----------------------------------------------------------- |
| `graphdb_attr:do_create_attribute/3`     | seed allocations call `graphdb_pnref:next_permanent_nref/0` |
| `graphdb_language:ensure_literal_seed/2` | replace `nref_server:get_nref/0` with the permanent call    |

`do_create_attribute/3` is shared between init seeding and (future)
runtime attribute creation. Seeding must use the permanent allocator
while runtime creation keeps `nref_server:get_nref/0`. Resolve by
threading the allocator choice in — e.g. an internal arity that takes
the allocated nref, with the `init/1` path passing a permanent nref and
the runtime path passing a runtime nref. Exact factoring is an
implementation detail for the plan; the contract is: **init seeds →
permanent tier; runtime creates → runtime tier.**

Future seeding workers (F4 `graphdb_rules`) follow the same pattern.

## 5. Testing

- **New `graphdb_pnref_SUITE`** (or EUnit): compute-from-empty returns
  `?LABEL_START`; compute-from-populated resumes at `max+1`; sequential
  calls are unique and monotonic; spillover raises the runtime floor.
- **`graphdb_attr_SUITE` / `graphdb_language_SUITE`:** flip seed
  assertions from `>= 1000000` to permanent bounds
  (`> ?NREF_ENGLISH andalso < ?NREF_START`).
- **`graphdb_bootstrap_tests` / `graphdb_bootstrap_SUITE`:** remove
  the directive-parsing tests (`*_label_start_*`, `*_nref_start_*`,
  directive-order cases) and `validate_label_start` group; adjust
  `build_symbol_table` and `classify_terms` tests to the macro-sourced,
  directive-free shapes; fixtures drop the directive lines.

## 6. Documentation

- `bootstrap.terms` header comment — tiers reference the macros, not
  directives.
- `ARCHITECTURE.md` nref-tier section — init seeds now permanent;
  boundaries are header macros; describe the `graphdb_pnref` allocator.
- Root `CLAUDE.md` + `apps/graphdb/CLAUDE.md` — nref-spaces bullets and
  the supervision-tree / worker list.
- `docs/diagrams/ontology-tree.md` — unaffected (seed *shape*
  unchanged; only nref *values* move tier).

## 7. Open items deferred elsewhere (not part of this work)

- English `category 32 → instance 10000` composition-vs-connection arc
  (`bootstrap.terms` OPEN QUESTION block) — awaits connection-arc infra.
- `lang_code` / `lang_human` labeled-node design review
  (`bootstrap.terms` PROPOSAL block).
- Cross-version seed identity — second pending topic
  (`memory/project-nref-identity-indirection.md`).

## 8. Decision log

| ID  | Decision                                                                   | Rationale                                                                                                                                                                                                                     |
| --- | -------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D1  | Compute-from-DB allocator, not a persisted DETS counter                    | DB is single source of truth; resumes correctly when later workers seed; no drift                                                                                                                                             |
| D2  | Tier boundaries as `graphdb_nrefs.hrl` macros; drop bootstrap directives   | System invariants, not per-file knobs; one source for loader/allocator/tests                                                                                                                                                  |
| D3  | Dedicated `graphdb_pnref` gen_server, not a cursor hosted in `graphdb_mgr` | Consistent with `nref_server`/`rel_id_server`; one process serializes allocation                                                                                                                                              |
| D4  | Lazy compute on first use, not at allocator `init/1`                       | Sidesteps first-boot table-creation ordering hazard                                                                                                                                                                           |
| D5  | Spillover raises runtime floor via `set_floor(N+1)`                        | Matches "nref_start becomes the next available nref"; monotonic set_floor                                                                                                                                                     |
| D6  | This work does NOT deliver cross-version seed identity                     | That is the indirection topic's job; keeps the two topics' scopes crisp                                                                                                                                                       |
| D7  | Cursor recomputed per boot, never persisted across restarts                | Safe because init/1 keeps idempotent lookup-by-name first, allocating only on a miss — a fresh cursor is never consulted for already-seeded nodes. Answers the open persistence question in `project-init-seed-nref-tier.md`. |
