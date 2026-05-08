# SeerStoneGraphDb — High-Severity Tasks

Single-statement bugs against spec semantics. Each one means the engine
silently produces a wrong answer for a case the spec calls out
explicitly.

Tasks are listed in execution order. H0, H1, H2, and H3 have all
landed (see RESOLVED markers below). H0 closed M1; H1+H2 closed M2.
H4 and H5 cover the remaining multi-class instance-membership work
(API surface and resolver disambiguation) and should land together.

---

## H0. Establish the "arcs authoritative; hierarchy lists cached" invariant — RESOLVED

**Status:** Landed across H0a–H0e. The full decision record is
`arcs-authoritative.md`; the architectural summary is in
`ARCHITECTURE.md` §3.

**Substeps:**
  - **H0a** (`d5a7244`) — charter + task plan landed.
  - **H0b** (`0b5fc43`) — node record retired `parent`, gained
    `parents :: [integer()]` and `classes :: [integer()]` caches.
    Read sites migrated; downward lookups switched to private
    `downward_children_by_arc/3` helpers reading `relationships`.
  - **H0c** (`ce07cb2`) — `graphdb_mgr:verify_caches/0` and
    `rebuild_caches/0` implemented and wired into every CT suite's
    `end_per_testcase`.  4 direct CT cases in `cache_audit` group.
  - **H0d** (`9e5d64a`) — `bootstrap.terms` to Option B (5-tuple node
    form); loader runs `rebuild_caches/0` + `verify_caches/0` after
    writing all rows.
  - **H0e** — this commit; doc fold + RESOLVED markers.

**Closes:** M1 (`TASKS-MEDIUM.md`).

---

## H1. `resolve_from_class` does not walk the class taxonomy — RESOLVED

**Status:** Fixed. `resolve_from_class` now reuses `do_class_of/1` to
locate the membership arc, then asks `graphdb_class:get_class/1` and
`graphdb_class:ancestors/1` for the nearest-first chain and returns
the first AVP match. Two CT cases cover the new behaviour
(`resolve_value_walks_class_taxonomy`,
`resolve_value_local_class_overrides_taxonomy_ancestor`). Subsumes
M2.

---

## H2. Priority 4 ("directly connected nodes") double-walks Priorities 2 and 3 — RESOLVED

**Status:** Fixed. `resolve_from_connected` now filters the outgoing
relationships to `R#relationship.kind =:= connection` before pulling
target nrefs, so instantiation (membership) and composition
(parent/child) arcs no longer feed Priority 4.  CT case
`resolve_value_p4_ignores_compositional_arc` reproduces the previous
leak (a value bound on the compositional parent's category surfacing
via the parent_arc) and now returns `not_found` as the spec requires.

---

## H3. Classes support only single inheritance — RESOLVED

**Status:** Fixed. New API `graphdb_class:add_superclass/2` writes a
25/26 taxonomy arc pair AND appends to the subject class's `parents`
cache in one transaction (idempotent, rejects self-references).
`do_walk_ancestors` rewritten as a BFS over the multi-parent DAG using
the `node.parents` cache; each ancestor is visited at most once
(diamond inheritance returns shared ancestors exactly once). 10 CT
cases under the new `multi_inheritance` group cover basic add, arc
shape, idempotency, validation, multi-parent BFS, diamond dedup,
multi-parent QC inheritance, and `class_in_ancestry` over added
parents. Composition remains a single-chain walk (compositional
hierarchy is a tree, not a DAG).

---

## H4. Instances support only single class membership

**Spec:** §5 Instantiation — *"A single instance may belong to multiple
classes simultaneously."*

**Evidence:** `graphdb_instance.erl:171, 313-386`. `create_instance/3`
takes one `ClassNref` and writes one 29/30 membership pair. No
`add_class_membership/2` after creation.

**Fix:**
- New API: `add_class_membership/2 :: (InstanceNref, ClassNref) -> ok`.
  Writes a second 29/30 arc pair.
- New API: `class_memberships/1 :: (InstanceNref) -> {ok, [ClassNref]}`.
  Reads all 29-characterized outgoing arcs.

**Dependencies:** none structurally; the resolver work is H5.

---

## H5. `resolve_from_class` silently picks the first class membership

**Spec:** §6 — *"Two parent classes may define the same attribute with
different bound values — resolution requires an explicit local value on
the instance."*

**Evidence:** `graphdb_instance.erl:564-587`. `lists:search/2` returns
the first match; whichever Mnesia hands back first wins. No ambiguity
detection, no error, no signal that two classes might conflict.

**Fix:** read *all* membership arcs. For each class (and its taxonomy
ancestors per H1), look up the AVP. If multiple distinct values are
found, return `{error, {ambiguous_class_value, AttrNref, [{ClassNref,
Value}]}}`. If exactly one value is found, return `{ok, Value}`. If
none, fall through to Priority 3.

**Dependencies:** H4 (so the multi-membership case is reachable), H1
(so ancestors are checked). The fix is naturally part of the same
rewrite.
