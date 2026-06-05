<!--
Copyright (c) 2026 David W. Thomas
SPDX-License-Identifier: GPL-2.0-or-later
-->

# F4 Phase B / Division B1 — `effective_rules_for_class/2` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one read-only function to `graphdb_rules`, `effective_rules_for_class/2`, that gathers every rule attached to a class **and to its taxonomy ancestors**, grouped by attachment class (nearest-first), each rule paired with its per-attachment deployment (`mode`/`multiplicity`/`template`).

**Architecture:** Pure read. Reuse `graphdb_class:ancestors/1` for the nearest-first ancestor walk; prepend the class itself as the distance-0 head. For each level, read its outgoing `applies_to` connection arcs and pair each target rule node with the deployment map decoded from that arc's AVPs. Resolve nothing — every level's rules survive (the firing engine B2/B5 decides additive-vs-shadow later). Environment scope only; `{project,_} -> {ok, []}`. No new seeds, records, state, or supervisor changes.

**Tech Stack:** Erlang/OTP 28, Mnesia (`disc_copies`, dirty reads), Common Test, rebar3. Invoke the build as plain `./rebar3 …` (kerl PATH is preconfigured — no `source ~/.bashrc` prefix).

**Design spec:** `docs/designs/f4-phase-b1-effective-rules-design.md` (B1-D1 … B1-D8). Parent design: `docs/designs/f4-graphdb-rules-design.md` (resolves its **OI-1**).

---

## File Structure

| File                                                  | Responsibility in B1                                                                                           |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `apps/graphdb/src/graphdb_rules.erl`                  | Add export, API wrapper, handler clauses, and read-path helpers (`effective_rules/2`, `ancestor_nrefs/1`, `attached_rules_with_deployment/2`, `decode_deployment/2`); refactor `attached_rules/2` onto a shared `applies_to_arcs/2` |
| `apps/graphdb/test/graphdb_rules_SUITE.erl`           | New CT group `effective` (11 cases) + local assertion helpers                                                  |
| `docs/designs/f4-graphdb-rules-design.md`             | Mark OI-1 resolved; **edit OI-1's code block in place** to the new return shape                                |
| `apps/graphdb/CLAUDE.md`                              | Add `effective_rules_for_class/2` to the `graphdb_rules` public API list                                       |
| `ARCHITECTURE.md`                                     | Update the `graphdb_rules` API contract line and the test count                                                |
| `TASKS.md`                                            | Record F4 Phase B / B1 status                                                                                  |

No `docs/diagrams/ontology-tree.md` change — B1 seeds nothing.

---

## Task 1: Refactor `attached_rules/2` onto a shared arc-read helper

Pure refactor — no behavior change. Extract the `applies_to` arc read so the new
deployment-bearing reader (Task 2) can share it. The existing `retrieval`,
`complex_scenarios`, and `cache_audit` CT groups are the safety net.

**Files:**
- Modify: `apps/graphdb/src/graphdb_rules.erl:678-688` (the `attached_rules/2` function in the "Rule read path" section)

- [ ] **Step 1: Run the existing rules suite to establish a green baseline**

Run: `./rebar3 ct --suite apps/graphdb/test/graphdb_rules_SUITE`
Expected: PASS — all current cases green (this is the refactor's safety net).

- [ ] **Step 2: Replace `attached_rules/2` with a version built on a new `applies_to_arcs/2`**

In `apps/graphdb/src/graphdb_rules.erl`, find the current function (in the
"Rule read path" section):

```erlang
%% attached_rules(ClassNref, State) -> [#node{}]
%% Rules attached to ClassNref are the targets of the applies_to connection
%% arcs out of ClassNref.
attached_rules(ClassNref, State) ->
	AppliesTo = State#state.applies_to_nref,
	Arcs = mnesia:dirty_index_read(relationships, ClassNref,
								   #relationship.source_nref),
	RuleNrefs = [A#relationship.target_nref || A <- Arcs,
				 A#relationship.kind =:= connection,
				 A#relationship.characterization =:= AppliesTo],
	lists:flatmap(fun(N) -> mnesia:dirty_read(nodes, N) end, RuleNrefs).
```

Replace it with:

```erlang
%% applies_to_arcs(ClassNref, State) -> [#relationship{}]
%% The forward applies_to connection arcs out of ClassNref -- one per rule
%% attached directly to the class.  Shared by attached_rules/2 (bare nodes)
%% and attached_rules_with_deployment/2 (nodes + deployment map).
applies_to_arcs(ClassNref, State) ->
	AppliesTo = State#state.applies_to_nref,
	Arcs = mnesia:dirty_index_read(relationships, ClassNref,
								   #relationship.source_nref),
	[A || A <- Arcs,
	 A#relationship.kind =:= connection,
	 A#relationship.characterization =:= AppliesTo].

%% attached_rules(ClassNref, State) -> [#node{}]
%% Rules attached directly to ClassNref: the targets of its applies_to arcs.
attached_rules(ClassNref, State) ->
	RuleNrefs = [A#relationship.target_nref
				 || A <- applies_to_arcs(ClassNref, State)],
	lists:flatmap(fun(N) -> mnesia:dirty_read(nodes, N) end, RuleNrefs).
```

- [ ] **Step 3: Compile**

Run: `./rebar3 compile`
Expected: clean compile, zero warnings.

- [ ] **Step 4: Re-run the rules suite to confirm the refactor preserved behavior**

Run: `./rebar3 ct --suite apps/graphdb/test/graphdb_rules_SUITE`
Expected: PASS — identical green result to Step 1.

- [ ] **Step 5: Commit**

```bash
git add apps/graphdb/src/graphdb_rules.erl
git commit -m "F4 B1: extract applies_to_arcs/2 shared arc-read helper

Pure refactor ahead of effective_rules_for_class/2 -- attached_rules/2
now reads via applies_to_arcs/2 so the deployment-bearing reader can
share the arc filter.  No behavior change.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Implement `effective_rules_for_class/2` (TDD)

The whole new function: export, API wrapper, the two handler clauses, and the
read-path helpers. Test-first with the full `effective` CT group — one
implementation turns all 11 cases green.

**Files:**
- Modify: `apps/graphdb/test/graphdb_rules_SUITE.erl` (exports, `all/0`, `groups/0`, 11 cases, local helpers)
- Modify: `apps/graphdb/src/graphdb_rules.erl` (export list ~89-101; API wrapper after `connection_rules_for_class/2` ~235; handler clauses after the `rules_for_class` project clause ~364; read-path helpers in the "Rule read path" section ~674+)

- [ ] **Step 1: Register the `effective` group and its 11 cases in the suite**

In `apps/graphdb/test/graphdb_rules_SUITE.erl`, add `{group, effective}` to
`all/0` (append after `{group, complex_scenarios}`, before `{group, cache_audit}`):

```erlang
all() ->
	[{group, seeding}, {group, composition}, {group, connection},
	 {group, validation}, {group, retrieval}, {group, scope},
	 {group, complex_scenarios}, {group, effective}, {group, cache_audit}].
```

Add the group definition to `groups/0` (insert before the `{cache_audit, …}` entry):

```erlang
		{effective, [], [
			self_only_no_ancestors,
			linear_chain_nearest_first,
			diamond_dag_dedup,
			shared_rule_node_across_ancestors,
			deployment_avps_surfaced,
			additive_parent_and_child,
			empty_levels_skipped,
			mixed_kinds_returned,
			project_scope_empty,
			unknown_class_empty,
			non_class_nref_empty
		]},
```

Add the 11 case names to the test-case `-export([...])` block (append a new
`%% effective` section before `%% cache audit`):

```erlang
	%% effective (B1 taxonomy walk)
	self_only_no_ancestors/1,
	linear_chain_nearest_first/1,
	diamond_dag_dedup/1,
	shared_rule_node_across_ancestors/1,
	deployment_avps_surfaced/1,
	additive_parent_and_child/1,
	empty_levels_skipped/1,
	mixed_kinds_returned/1,
	project_scope_empty/1,
	unknown_class_empty/1,
	non_class_nref_empty/1,
```

- [ ] **Step 2: Write the 11 failing test cases**

In `apps/graphdb/test/graphdb_rules_SUITE.erl`, add a new section just before
the `%% Cache Audit Tests` banner:

```erlang
%%=============================================================================
%% Effective Rules Tests (B1 -- taxonomy walk)
%%=============================================================================
%% effective_rules_for_class/2 gathers rules from the class AND its taxonomy
%% ancestors, nearest-first, grouped by attaching class, each paired with that
%% attachment's deployment map.  It resolves nothing -- every level survives.

self_only_no_ancestors(_Config) ->
	Car = make_class("Car"),
	Eng = make_class("Engine"),
	{ok, R} = graphdb_rules:create_composition_rule(
		environment, "has-engine", Car, Eng, mandatory, 1),
	{ok, Levels} = graphdb_rules:effective_rules_for_class(environment, Car),
	?assertEqual([Car], level_nrefs(Levels)),
	?assertEqual([R], rule_nrefs_at(Car, Levels)).

linear_chain_nearest_first(_Config) ->
	Vehicle = make_class("Vehicle"),
	{ok, Car}    = graphdb_class:create_class("Car", Vehicle),
	{ok, Sports} = graphdb_class:create_class("SportsCar", Car),
	Eng   = make_class("Engine"),
	Wheel = make_class("SteeringWheel"),
	Spoil = make_class("Spoiler"),
	{ok, RV} = graphdb_rules:create_composition_rule(
		environment, "v-engine", Vehicle, Eng, mandatory, 1),
	{ok, RC} = graphdb_rules:create_composition_rule(
		environment, "c-wheel", Car, Wheel, mandatory, 1),
	{ok, RS} = graphdb_rules:create_composition_rule(
		environment, "s-spoiler", Sports, Spoil, auto, 1),
	{ok, Levels} = graphdb_rules:effective_rules_for_class(environment, Sports),
	%% nearest-first: SportsCar, then Car, then Vehicle
	?assertEqual([Sports, Car, Vehicle], level_nrefs(Levels)),
	?assertEqual([RS], rule_nrefs_at(Sports, Levels)),
	?assertEqual([RC], rule_nrefs_at(Car, Levels)),
	?assertEqual([RV], rule_nrefs_at(Vehicle, Levels)).

diamond_dag_dedup(_Config) ->
	Top  = make_class("Component"),
	{ok, Mid1} = graphdb_class:create_class("Electrical", Top),
	{ok, Mid2} = graphdb_class:create_class("Mechanical", Top),
	{ok, Bot}  = graphdb_class:create_class("Alternator", Mid1),
	ok = graphdb_class:add_superclass(Bot, Mid2),
	Wid = make_class("Winding"),
	Cas = make_class("Casing"),
	{ok, RT} = graphdb_rules:create_composition_rule(
		environment, "comp-winding", Top, Wid, mandatory, 1),
	{ok, RB} = graphdb_rules:create_composition_rule(
		environment, "alt-casing", Bot, Cas, auto, 1),
	{ok, Levels} = graphdb_rules:effective_rules_for_class(environment, Bot),
	Names = level_nrefs(Levels),
	%% Top appears exactly once despite being reachable via two parents.
	%% Mid1/Mid2 carry no rules and are omitted (empty levels).
	?assertEqual(1, length([L || L <- Names, L =:= Top])),
	?assertEqual([Bot, Top], Names),
	?assertEqual([RB], rule_nrefs_at(Bot, Levels)),
	?assertEqual([RT], rule_nrefs_at(Top, Levels)).

shared_rule_node_across_ancestors(_Config) ->
	%% A and B are two superclasses of Bot.  ONE rule node is attached to
	%% BOTH (F4 D12 reuse).  It must appear once per attaching ancestor, each
	%% occurrence carrying that ancestor's own deployment.
	A = make_class("Insurable"),
	B = make_class("Taxable"),
	{ok, Bot} = graphdb_class:create_class("Vehicle", A),
	ok = graphdb_class:add_superclass(Bot, B),
	Doc = make_class("Document"),
	{ok, R} = graphdb_rules:create_composition_rule(
		environment, "needs-document", A, Doc, mandatory, 1),
	ok = attach_existing_rule(B, R, mandatory, 3),
	{ok, Levels} = graphdb_rules:effective_rules_for_class(environment, Bot),
	?assertEqual([A, B], level_nrefs(Levels)),
	?assertMatch([{#node{nref = R}, #{multiplicity := 1}}], pairs_at(A, Levels)),
	?assertMatch([{#node{nref = R}, #{multiplicity := 3}}], pairs_at(B, Levels)).

deployment_avps_surfaced(_Config) ->
	Car = make_class("Car"),
	Whl = make_class("Wheel"),
	{ok, DT} = graphdb_class:default_template(Car),
	{ok, _R} = graphdb_rules:create_composition_rule(
		environment, "wheels", Car, Whl, auto, 4, DT),
	{ok, Levels} = graphdb_rules:effective_rules_for_class(environment, Car),
	[{_RuleNode, Deploy}] = pairs_at(Car, Levels),
	?assertEqual(auto, maps:get(mode, Deploy)),
	?assertEqual(4, maps:get(multiplicity, Deploy)),
	?assertEqual(DT, maps:get(template, Deploy)).

additive_parent_and_child(_Config) ->
	%% Parent mandates a wheel-group (mult 1); subclass adds more (mult 4) for
	%% the SAME child class.  B1 drops nothing -- both survive, each with its
	%% own deployment.  The firing engine (B2/B5) decides additive-vs-shadow.
	Vehicle = make_class("Vehicle"),
	{ok, Car} = graphdb_class:create_class("Car", Vehicle),
	Wheel = make_class("Wheel"),
	{ok, RV} = graphdb_rules:create_composition_rule(
		environment, "v-wheel", Vehicle, Wheel, mandatory, 1),
	{ok, RC} = graphdb_rules:create_composition_rule(
		environment, "c-wheel", Car, Wheel, mandatory, 4),
	{ok, Levels} = graphdb_rules:effective_rules_for_class(environment, Car),
	?assertEqual([Car, Vehicle], level_nrefs(Levels)),
	?assertEqual([RC], rule_nrefs_at(Car, Levels)),
	?assertEqual([RV], rule_nrefs_at(Vehicle, Levels)),
	[{_, DC}] = pairs_at(Car, Levels),
	[{_, DV}] = pairs_at(Vehicle, Levels),
	?assertEqual(4, maps:get(multiplicity, DC)),
	?assertEqual(1, maps:get(multiplicity, DV)).

empty_levels_skipped(_Config) ->
	Vehicle = make_class("Vehicle"),
	{ok, Car}    = graphdb_class:create_class("Car", Vehicle),
	{ok, Sports} = graphdb_class:create_class("SportsCar", Car),
	Spoil = make_class("Spoiler"),
	Eng   = make_class("Engine"),
	%% Rules on Sports and Vehicle only; the middle level (Car) has none.
	{ok, RS} = graphdb_rules:create_composition_rule(
		environment, "s-spoiler", Sports, Spoil, auto, 1),
	{ok, RV} = graphdb_rules:create_composition_rule(
		environment, "v-engine", Vehicle, Eng, mandatory, 1),
	{ok, Levels} = graphdb_rules:effective_rules_for_class(environment, Sports),
	%% Car omitted entirely; nearest-first order preserved.
	?assertEqual([Sports, Vehicle], level_nrefs(Levels)),
	?assertEqual([RS], rule_nrefs_at(Sports, Levels)),
	?assertEqual([RV], rule_nrefs_at(Vehicle, Levels)).

mixed_kinds_returned(_Config) ->
	Car   = make_class("Car"),
	Eng   = make_class("Engine"),
	Maker = make_class("Manufacturer"),
	Char  = make_rel_char("made_by", "makes"),
	{ok, RComp} = graphdb_rules:create_composition_rule(
		environment, "has-engine", Car, Eng, mandatory, 1),
	{ok, RConn} = graphdb_rules:create_connection_rule(
		environment, "made-by", Car, Char, Maker, mandatory, 1),
	{ok, Levels} = graphdb_rules:effective_rules_for_class(environment, Car),
	{ok, S} = graphdb_rules:seeded_nrefs(),
	Comp = maps:get(composition_rule, S),
	Conn = maps:get(connection_rule, S),
	Pairs = pairs_at(Car, Levels),
	%% B1-D4 consumer pattern: inline kind filter over the gathered pairs.
	CompNrefs = [N#node.nref || {N, _D} <- Pairs,
				 lists:member(Comp, N#node.classes)],
	ConnNrefs = [N#node.nref || {N, _D} <- Pairs,
				 lists:member(Conn, N#node.classes)],
	?assertEqual([RComp], CompNrefs),
	?assertEqual([RConn], ConnNrefs).

project_scope_empty(_Config) ->
	Car = make_class("Car"),
	?assertEqual({ok, []},
		graphdb_rules:effective_rules_for_class({project, 1}, Car)).

unknown_class_empty(_Config) ->
	%% Non-existent nref: ancestors/1 -> {error, not_found}, mapped to [].
	?assertEqual({ok, []},
		graphdb_rules:effective_rules_for_class(environment, 999999)).

non_class_nref_empty(_Config) ->
	%% nref 6 (Names) is an attribute node, not a class:
	%% ancestors/1 -> {error, not_a_class}, mapped to [].
	?assertEqual({ok, []},
		graphdb_rules:effective_rules_for_class(environment, ?NREF_NAMES)).
```

Then add the local assertion helpers to the `%% Local test helpers` section at
the bottom of the suite (after `make_rel_char/2`):

```erlang
%% level_nrefs(Levels) -> [integer()]
%% The ordered list of attaching-class nrefs in an effective_rules result.
level_nrefs(Levels) ->
	[L || {L, _Pairs} <- Levels].

%% pairs_at(LevelNref, Levels) -> [{#node{}, map()}]
%% The {RuleNode, Deployment} pairs grouped under LevelNref.
pairs_at(Level, Levels) ->
	{Level, Pairs} = lists:keyfind(Level, 1, Levels),
	Pairs.

%% rule_nrefs_at(LevelNref, Levels) -> [integer()]
%% The rule nrefs grouped under LevelNref.
rule_nrefs_at(Level, Levels) ->
	[N#node.nref || {N, _D} <- pairs_at(Level, Levels)].

%% attach_existing_rule(OwnerClass, RuleNref, Mode, Mult) -> ok
%% Writes a SECOND applies_to/applied_by connection arc pair from OwnerClass to
%% an already-existing rule node (F4 D12 reuse), stamped with OwnerClass's own
%% deployment.  Connection arcs are not part of the parents/classes caches, so
%% this does not disturb verify_caches/0.  Used by
%% shared_rule_node_across_ancestors to make one rule node reachable from two
%% ancestors.
attach_existing_rule(OwnerClass, RuleNref, Mode, Mult) ->
	{ok, S} = graphdb_rules:seeded_nrefs(),
	AppliesTo = maps:get(applies_to, S),
	AppliedBy = maps:get(applied_by, S),
	ModeAttr  = maps:get(mode_attr, S),
	MultAttr  = maps:get(multiplicity_attr, S),
	{ok, DT}  = graphdb_class:default_template(OwnerClass),
	{Id1, Id2} = rel_id_server:get_id_pair(),
	Deploy = [#{attribute => ?ARC_TEMPLATE, value => DT},
			  #{attribute => ModeAttr, value => Mode},
			  #{attribute => MultAttr, value => Mult}],
	Fwd = #relationship{id = Id1, kind = connection, source_nref = OwnerClass,
		characterization = AppliesTo, target_nref = RuleNref,
		reciprocal = AppliedBy, avps = Deploy},
	Rev = #relationship{id = Id2, kind = connection, source_nref = RuleNref,
		characterization = AppliedBy, target_nref = OwnerClass,
		reciprocal = AppliesTo, avps = []},
	{atomic, ok} = mnesia:transaction(fun() ->
		ok = mnesia:write(relationships, Fwd, write),
		ok = mnesia:write(relationships, Rev, write)
	end),
	ok.
```

- [ ] **Step 3: Run the new group to verify it fails**

Run: `./rebar3 ct --suite apps/graphdb/test/graphdb_rules_SUITE --group effective`
Expected: FAIL — compile/run error: `effective_rules_for_class/2` is undefined
(the function does not exist yet). Some cases may report
`undef`/`function_clause`. This confirms the tests exercise the not-yet-written
function.

- [ ] **Step 4: Export the new function**

In `apps/graphdb/src/graphdb_rules.erl`, add `effective_rules_for_class/2` to
the External API export list (insert after `connection_rules_for_class/2`):

```erlang
		create_connection_rule/8,
		get_rule/2,
		rules_for_class/2,
		composition_rules_for_class/2,
		connection_rules_for_class/2,
		effective_rules_for_class/2,
		list_rules/1
		]).
```

- [ ] **Step 5: Add the public API wrapper**

In `apps/graphdb/src/graphdb_rules.erl`, in the "Exported External API
Functions" section, add the wrapper after `connection_rules_for_class/2` (just
before the `list_rules/1` wrapper):

```erlang
%%-----------------------------------------------------------------------------
%% effective_rules_for_class(Scope, ClassNref) ->
%%     {ok, [{AncestorNref :: integer(),
%%            [{RuleNode :: #node{}, Deployment :: map()}]}]}
%%
%% Every rule attached to ClassNref AND to each of its taxonomy ancestors,
%% grouped by the class it is attached to, nearest-first (ClassNref itself
%% first), each rule paired with that attachment's deployment map
%% (#{mode, multiplicity, template}).  Both rule kinds are returned; callers
%% filter inline.  Levels contributing no rules are omitted.
%% {project, _} -> {ok, []}.
%%
%% Does NOT resolve override/shadow/conflict -- every level's rules are
%% present.  Resolution is the firing engine's job (Phase B2/B5).
%%-----------------------------------------------------------------------------
effective_rules_for_class(Scope, ClassNref) ->
	gen_server:call(?MODULE, {effective_rules_for_class, Scope, ClassNref}).
```

- [ ] **Step 6: Add the handler clauses**

In `apps/graphdb/src/graphdb_rules.erl`, add the two clauses immediately after
the existing `{rules_for_class, {project, _}, _}` clause (the one that returns
`{reply, {ok, []}, State}`):

```erlang
handle_call({effective_rules_for_class, environment, ClassNref}, _From, State) ->
	{reply, {ok, effective_rules(ClassNref, State)}, State};
handle_call({effective_rules_for_class, {project, _}, _}, _From, State) ->
	{reply, {ok, []}, State};
```

- [ ] **Step 7: Add the read-path helpers**

In `apps/graphdb/src/graphdb_rules.erl`, in the "Rule read path" section, add
these helpers after `attached_rules/2` (which Task 1 left reading via
`applies_to_arcs/2`):

```erlang
%% effective_rules(ClassNref, State) -> [{LevelNref, [{#node{}, map()}]}]
%% Self-first, nearest-first taxonomy gather: the class itself followed by its
%% ancestors (graphdb_class:ancestors/1 order).  Each level carries the rules
%% attached directly to it, paired with that attachment's deployment.  Levels
%% with no attached rules are dropped (B1-D7).  Resolves nothing (B1-D1).
effective_rules(ClassNref, State) ->
	Chain = [ClassNref | ancestor_nrefs(ClassNref)],
	[{Level, Pairs}
	 || Level <- Chain,
		Pairs <- [attached_rules_with_deployment(Level, State)],
		Pairs =/= []].

%% ancestor_nrefs(ClassNref) -> [integer()]
%% The taxonomy ancestors of ClassNref, nearest-first, via the canonical
%% graphdb_class:ancestors/1 walk.  A bad starting class (unknown nref or a
%% non-class node) makes ancestors/1 return {error, _}; B1 maps that to an
%% empty ancestor set (B1-D6).  The direct-attachment read on a bad nref is
%% likewise empty, so the overall effective result is {ok, []}.
ancestor_nrefs(ClassNref) ->
	case graphdb_class:ancestors(ClassNref) of
		{ok, Nodes} -> [N#node.nref || N <- Nodes];
		{error, _}  -> []
	end.

%% attached_rules_with_deployment(ClassNref, State) -> [{#node{}, map()}]
%% Deployment-preserving sibling of attached_rules/2: each rule attached
%% directly to ClassNref paired with the deployment map decoded from its
%% applies_to arc.
attached_rules_with_deployment(ClassNref, State) ->
	[ {RuleNode, decode_deployment(Arc#relationship.avps, State)}
	  || Arc <- applies_to_arcs(ClassNref, State),
		 RuleNode <- mnesia:dirty_read(nodes, Arc#relationship.target_nref) ].

%% decode_deployment(AVPs, State) -> map()
%% Decodes an applies_to arc's deployment AVPs into the symbolic Deployment map
%% #{mode, multiplicity, template}.  A key whose AVP is absent is omitted
%% (B1-D2).  The `template' key reads the arc Template scope marker
%% (?ARC_TEMPLATE, attr 31) -- NOT the template_nref content literal on the
%% rule node.
decode_deployment(AVPs, State) ->
	Pairs = [{mode,         State#state.mode_attr},
			 {multiplicity, State#state.multiplicity_attr},
			 {template,     ?ARC_TEMPLATE}],
	lists:foldl(fun({Key, AttrNref}, Acc) ->
		case lists:search(fun(#{attribute := A}) -> A =:= AttrNref end, AVPs) of
			{value, #{value := V}} -> Acc#{Key => V};
			false                  -> Acc
		end
	end, #{}, Pairs).
```

- [ ] **Step 8: Compile**

Run: `./rebar3 compile`
Expected: clean compile, zero warnings.

- [ ] **Step 9: Run the new group to verify it passes**

Run: `./rebar3 ct --suite apps/graphdb/test/graphdb_rules_SUITE --group effective`
Expected: PASS — all 11 cases green; `end_per_testcase` `verify_caches/0 = ok`.

- [ ] **Step 10: Run the whole rules suite (regression)**

Run: `./rebar3 ct --suite apps/graphdb/test/graphdb_rules_SUITE`
Expected: PASS — the prior groups plus the new `effective` group.

- [ ] **Step 11: Commit**

```bash
git add apps/graphdb/src/graphdb_rules.erl apps/graphdb/test/graphdb_rules_SUITE.erl
git commit -m "F4 B1: effective_rules_for_class/2 taxonomy-walking rule gather

Adds the read-only effective_rules_for_class/2: nearest-first gather of
every rule attached to a class and its taxonomy ancestors, grouped by
attaching class, each paired with that attachment's deployment map
(mode/multiplicity/template from the applies_to arc).  Resolves nothing
-- additive-vs-shadow is left to the firing engine (B2/B5).  Reuses
graphdb_class:ancestors/1; bad nref -> {ok, []}.  +11 CT cases.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Documentation updates + full-suite verification

Resolve OI-1 in the parent design (edit in place — no contradictory shapes left
behind), record the new API in `apps/graphdb/CLAUDE.md` and `ARCHITECTURE.md`,
note B1 status in `TASKS.md`, and confirm the whole project suite is green.

**Files:**
- Modify: `docs/designs/f4-graphdb-rules-design.md:736-747` (OI-1 block)
- Modify: `apps/graphdb/CLAUDE.md` (the `graphdb_rules` public API bullet list)
- Modify: `ARCHITECTURE.md` (the `graphdb_rules` API contract line + test count)
- Modify: `TASKS.md` (F4 status)

- [ ] **Step 1: Resolve OI-1 in the parent design (edit the code block in place)**

In `docs/designs/f4-graphdb-rules-design.md`, replace the OI-1 block:

```markdown
**OI-1. Effective rules (taxonomy walk).** `rules_for_class/2`
returns directly-attached rules only. Phase B will add an
`effective_rules_for_class/2` that walks class taxonomy ancestors so
subclass instances inherit superclass composition rules. The shape:

```erlang
effective_rules_for_class(Scope, ClassNref) ->
    {ok, [{AncestorNref, [#node{}]}]}.
```

Returns rules grouped by which ancestor they came from, so the engine
can apply override/shadow semantics.
```

with (note the **resolved** marker and the corrected return shape that pairs
each rule with its deployment):

```markdown
**OI-1. Effective rules (taxonomy walk). — RESOLVED (B1).**
`rules_for_class/2` returns directly-attached rules only.
`effective_rules_for_class/2` (Phase B / division B1) walks class
taxonomy ancestors so subclass instances inherit superclass rules. The
shape:

```erlang
effective_rules_for_class(Scope, ClassNref) ->
    {ok, [{AncestorNref, [{RuleNode :: #node{}, Deployment :: map()}]}]}.
```

Returns rules grouped by which ancestor they came from, nearest-first,
each paired with that attachment's deployment map
(`#{mode, multiplicity, template}`) read from the `applies_to` arc — the
bare `[#node{}]` element shape was insufficient because deployment lives
per-attachment on the arc, not on the rule node. B1 resolves nothing;
the firing engine (B2/B5) applies override/shadow/additive semantics.
See `docs/designs/f4-phase-b1-effective-rules-design.md`.
```

- [ ] **Step 2: Record the new API in `apps/graphdb/CLAUDE.md`**

In `apps/graphdb/CLAUDE.md`, in the `### graphdb_rules — Graph Rules` section,
add a bullet for the new function. Find the line:

```markdown
- `get_rule/2`, `rules_for_class/2`, `composition_rules_for_class/2`, `connection_rules_for_class/2`, `list_rules/1`
```

and replace it with:

```markdown
- `get_rule/2`, `rules_for_class/2`, `composition_rules_for_class/2`, `connection_rules_for_class/2`, `list_rules/1`
- `effective_rules_for_class/2` (F4 Phase B / B1) — taxonomy-walking read: every rule attached to a class **and its taxonomy ancestors**, grouped by attaching class nearest-first, each paired with its `applies_to`-arc deployment (`mode`/`multiplicity`/`template`). Resolves nothing; the B2+ firing engines consume it.
```

- [ ] **Step 3: Update `ARCHITECTURE.md` (API contract line + test count)**

In `ARCHITECTURE.md`, make three edits.

(a) The test-count summary row (`ARCHITECTURE.md:31`). B1 adds 11 CT cases and
no EUnit. Replace:

```markdown
| Tests               | 430 passing (329 Common Test + 101 EUnit)                                                                                                                                                                       |
```

with (keep the cell padding so the table stays aligned — re-pad with
`python3 ~/.claude/scripts/align_md_tables.py ARCHITECTURE.md` afterward if the
column width shifts):

```markdown
| Tests               | 441 passing (340 Common Test + 101 EUnit)                                                                                                                                                                       |
```

(b) The §12 attachment/retrieval bullet (`ARCHITECTURE.md:611-616`). Replace the
trailing two sentences:

```markdown
  rule. Retrieval is **direct-attachment only** — `rules_for_class/2`
  reads the owning class's outgoing `applies_to` arcs. Taxonomy-walking
  effective-rule resolution (`effective_rules_for_class/2`) is Phase B.
```

with:

```markdown
  rule. `rules_for_class/2` is **direct-attachment only** — it reads the
  owning class's outgoing `applies_to` arcs. `effective_rules_for_class/2`
  (Phase B / B1) additionally walks the class's taxonomy ancestors:
  a nearest-first, deployment-bearing gather of every rule attached to the
  class and its superclasses, grouped by attaching class. It resolves
  nothing — additive-vs-shadow is the firing engine's job (B2/B5).
```

(c) If the file carries a CT-count figure elsewhere that this edit missed,
reconcile it:

Run: `grep -n "329\|430\|Common Test" ARCHITECTURE.md`
Expected: only the row edited in (a) remains; if another stale figure surfaces,
bump it by 11 CT consistently.

- [ ] **Step 4: Record B1 status in `TASKS.md`**

In `TASKS.md`, in the `### F4 Phases B–F — Rule-firing engine — OUTSTANDING`
section (`TASKS.md:630`), insert a B1-done note. Replace the intro paragraph:

```markdown
The remaining phases build the engine that consumes the Phase A data
model. Taxonomy-walking `effective_rules_for_class/2`, the
instantiation engine, composition-rule firing at `create_instance`,
and reactive learning are all Phase B+ work.
```

with:

```markdown
The remaining phases build the engine that consumes the Phase A data
model: the instantiation engine, composition-rule firing at
`create_instance`, connection firing, conflict precedence, and reactive
learning.

**Phase B is divided B1–B5** (each with its own design + plan):

- **B1 — `effective_rules_for_class/2` (read-side taxonomy walk) — DONE.**
  Nearest-first gather of every rule attached to a class and its taxonomy
  ancestors, grouped by attaching class, each paired with its
  `applies_to`-arc deployment (`mode`/`multiplicity`/`template`). Resolves
  nothing — additive-vs-shadow is the firing engine's job. Design:
  `docs/designs/f4-phase-b1-effective-rules-design.md`.
- **B2** composition firing engine; **B3** `propose` mode + session flag;
  **B4** connection firing; **B5** horizontal conflict precedence —
  OUTSTANDING.
```

If the surrounding `TASKS.md` convention differs (heading level, bullet
style), follow the file rather than the literal text above.

- [ ] **Step 5: Run the whole graphdb test suite**

Run: `./rebar3 ct --dir apps/graphdb/test`
Expected: PASS — every graphdb suite green, including the new `effective`
cases.

- [ ] **Step 6: Run the full project suite (CT + EUnit) for a clean baseline**

Run: `./rebar3 do ct, eunit`
Expected: PASS — CT total up by 11 vs the pre-B1 baseline; EUnit unchanged;
clean compile, zero warnings.

- [ ] **Step 7: Commit**

```bash
git add docs/designs/f4-graphdb-rules-design.md apps/graphdb/CLAUDE.md ARCHITECTURE.md TASKS.md
git commit -m "F4 B1: docs -- resolve OI-1, record effective_rules_for_class/2

Edits OI-1 in the parent design in place to the deployment-bearing
return shape (no contradictory shapes left); adds the function to the
graphdb_rules API lists in apps/graphdb/CLAUDE.md and ARCHITECTURE.md;
bumps the CT count by 11; records F4 Phase B / B1 done in TASKS.md.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Notes for the Implementer

- **Build invocation:** plain `./rebar3 …` from the project root. The kerl
  OTP 28 PATH is preconfigured — do **not** prefix with `source ~/.bashrc`.
- **Tabs, not spaces:** every `.erl` file in this codebase indents with hard
  tabs. Match the surrounding file exactly (the code blocks above use tabs).
- **`lists:search/2`** returns `{value, Elem} | false` — that is the shape
  `decode_deployment/2` matches on. (Do not assume `{ok, _}`.)
- **`mnesia:dirty_read(nodes, N)`** returns `[#node{}] | []`; the list
  comprehension generator `RuleNode <- mnesia:dirty_read(...)` skips the empty
  (missing-node) case, mirroring the existing `lists:flatmap` idiom.
- **Cache invariant:** B1 writes nothing in production. The test helper
  `attach_existing_rule/4` writes only `connection` arcs, which are not part of
  the `parents`/`classes` caches, so `end_per_testcase`'s `verify_caches/0`
  assertion stays green.
- **`--group` fallback:** if `./rebar3 ct … --group effective` misbehaves on
  this rebar3, run the whole suite instead
  (`./rebar3 ct --suite apps/graphdb/test/graphdb_rules_SUITE`) — the
  FAIL-then-PASS expectations still hold, the other groups just run too.
- **Ordering is load-bearing:** `graphdb_class:ancestors/1` excludes self and
  the Classes category (nref 3) and is nearest-first BFS, diamond-deduped.
  `effective_rules/2` prepends the class as the distance-0 head; the result
  order is therefore `[Class | nearest-ancestor … farthest-ancestor]` with
  empty levels removed.

---

## Execution Handoff

Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task,
   review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session via executing-plans,
   batched with checkpoints.
