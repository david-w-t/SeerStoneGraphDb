# graphdb_api gRPC Reference

This document is the practical wire-contract reference for **`graphdb_api`**,
SeerStoneGraphDb's internal gRPC service. It is written for the engineer
building the external REST proxy — the **only** client this service is
designed for. It documents what exists in the actual `.proto` files and
`_impl.erl` handlers as of this writing, not the design's aspirational or
deferred scope.

Sources of truth used to write this document:

- `docs/designs/grpc-proxy-api-design.md` — design rationale (the "why").
- `apps/graphdb_api/priv/protos/*.proto` — the actual wire contract.
- `apps/graphdb_api/src/*_impl.erl` — actual per-RPC behavior, error paths,
  and quirks.
- `apps/graphdb_api/src/graphdb_api_value.erl` /
  `graphdb_api_error.erl` — the two codec/chokepoint modules every RPC
  routes through.
- `config/sys.config` — the real listener configuration.
- `apps/graphdb_api/test/*_SUITE.erl` — real, passing example calls.

If something here conflicts with `apps/graphdb_api/CLAUDE.md`, this document
was checked directly against source; see the note at the end of this file.

## 1. Overview

`graphdb_api` exposes SeerStoneGraphDb's existing Erlang public API
(`graphdb_mgr`, `graphdb_instance`, `graphdb_class`, `graphdb_attr`,
`graphdb_rules`, `graphdb_language`, `graphdb_project`, `graphdb_query`)
over gRPC (protobuf over HTTP/2), for consumption by a single non-Erlang REST
proxy running on the same internal network.

**Threat model:** this is an internal-trusted-network API, not a
public-facing one. There is no authentication, no TLS, and no per-request
authorization beyond the project-session check described in §2.1. The proxy
is expected to be the only caller, reachable only from inside the trusted
network boundary. A `grpcbox` server-interceptor hook point is reserved for
a future shared-secret or mTLS layer but is **not implemented**.

### 1.1 The 8 services at a glance

| Service            | Backing Erlang module                  | Purpose                                                                                              |
| ------------------ | -------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `NodeService`      | `graphdb_mgr`                          | Generic node CRUD, retire/unretire, batch mutation (`Mutate`)                                        |
| `InstanceService`  | `graphdb_instance` / `graphdb_project` | Instance creation, relationship writes (project-session-gated), compositional/class-membership reads |
| `ClassService`     | `graphdb_class`                        | Taxonomic class hierarchy, qualifying characteristics, templates                                     |
| `AttributeService` | `graphdb_attr`                         | Attribute library: name/literal/relationship attribute creation and lookup                           |
| `RulesService`     | `graphdb_rules`                        | Composition/connection rule creation and retrieval (environment scope only)                          |
| `LanguageService`  | `graphdb_language`                     | Multilingual label registration and resolution                                                       |
| `ProjectService`   | `graphdb_project`                      | Project registration and lookup                                                                      |
| `QueryService`     | `graphdb_query`                        | `FindPath` only — general query execution is deferred (§4)                                           |

### 1.2 Connection info

| Field        | Value                                                                             |
| ------------ | --------------------------------------------------------------------------------- |
| Protocol     | gRPC (protobuf over HTTP/2), via `grpcbox`                                        |
| Port         | `8081` (from `config/sys.config`'s `{grpcbox, [{servers, [...]}]}` entry)         |
| Bind address | `0.0.0.0` (all interfaces) — internal-network-only, no external exposure intended |
| TLS          | **None.** `listen_opts` in `sys.config` carries no SSL options — plaintext HTTP/2 |
| Auth         | **None.** No credentials, tokens, or interceptors are wired in v1                 |
| Streaming    | **None.** Every RPC in every service is unary request/response — see §5           |

The listener starts as part of the `grpcbox` OTP application, which is
placed after `database` in the release's application-start order — so the
port only accepts connections once the full graph stack (bootstrap included)
has finished starting.

## 2. Cross-cutting conventions

Read this section before any per-service section — these rules apply
uniformly across every RPC.

### 2.1 Session / project model

A "session" is **not** a token or capability the wire ever carries. Every
project-scoped write RPC carries a plain `int64 project_id` field; the
server reconstructs a `graphdb_project` session from it on every call by
calling `graphdb_project:open_session(ProjectId)` server-side. There is no
session creation RPC, no session expiry, and nothing for the proxy to cache
beyond the `project_id` value itself (obtained once from
`ProjectService.RegisterProject`).

**RPCs that require `project_id`** (all on `InstanceService`):
`CreateInstance`, `AddRelationship`, `RemoveRelationship`,
`UpdateRelationship`, `UpdateRelationshipBoth`, `AddClassMembership`.

**RPCs that do NOT require a project_id** — every read on `InstanceService`
(`GetInstance`, `Children`, `CompositionalAncestors`, `ClassOf`,
`ClassMemberships`, `ResolveValue`) and every RPC on every other service.
Reads are not project-session-gated.

**What happens on an invalid `project_id`:** the session-establishing RPCs
map a failed session open specifically to `invalid_session`
(`UNAUTHENTICATED`, gRPC code 16) — **not** the generic `not_a_project`
mapping (which elsewhere maps to `NOT_FOUND`, code 5). This is a deliberate
choice in `graphdb_api_instance_service_impl:with_session/2`: from the
wire's perspective, `project_id` functions as this RPC's write credential,
so a session that fails to open reads as an authentication failure, not a
generic lookup miss. `ProjectService.IsProject` is unaffected by this —
it's a plain boolean-returning read, never an error, even for a
non-project nref.

### 2.2 The `Value` oneof

Every AVP value (attribute-value-pair values, QC bound values, rule-firing
reports, resolved values, language labels, and the opaque `Chain` token)
crosses the wire as a `Value` message:

```proto
message Value {
  oneof kind {
    string    str         = 1;
    int64     i           = 2;
    double    d           = 3;
    bool      b           = 4;
    bytes     term_binary = 5;
    NullValue null_value  = 6;
  }
}
```

Encoding rules, from `graphdb_api_value:term_to_value/1`:

| Erlang term                                                  | Wire variant                                  |
| ------------------------------------------------------------ | --------------------------------------------- |
| `binary()` or a printable-unicode `list()`                   | `str`                                         |
| `integer()`                                                  | `i`                                           |
| `float()`                                                    | `d`                                           |
| `boolean()`                                                  | `b`                                           |
| `undefined`                                                  | `null_value`                                  |
| Any other list (non-printable, e.g. `[1,2,999999]`)          | `term_binary` (via `erlang:term_to_binary/1`) |
| Anything else (tuples, maps, other atoms, nested structures) | `term_binary`                                 |

Decoding (`value_to_term/1`) is the mirror: `term_binary` is decoded with
`binary_to_term(Bin, [safe])` (guards against unbounded atom-table growth
from decoding malicious input), and `null_value` decodes back to
`undefined`. `b` accepts either the wire boolean `true`/`false` or a
raw `1` and treats `1` as `true`; anything else is `false`.

**Practical implication for a non-Erlang client:** `str`/`i`/`d`/`b` are the
only variants you can meaningfully construct or read yourself. Several RPCs
*always* return `term_binary` for a field — `InstanceService.CreateInstance`'s
`report`, all five `RulesService` "rules" reply fields, and
`LanguageService.MakeChain`'s `chain` / the `chain` you pass back into
`ResolveLabel` — because the underlying Erlang value is an opaque nested
structure with no stable schema (a rule-firing report, a list of rule
records, an internal label-chain token). Treat these as **opaque bytes**:
store and round-trip them unchanged (e.g. base64 them into your REST
response, then base64-decode and pass back verbatim on the next call). Do
not attempt to parse `term_binary` payloads — they are Erlang's
`term_to_binary/1` external term format and are not designed to be decoded
outside an Erlang runtime.

### 2.3 `AVP` vs `AVPUpdate`

```proto
message AVP {
  int64 attribute = 1;
  Value value = 2;
}

message AVPUpdate {
  int64 attribute = 1;
  Value value = 2;   // ignored when delete = true
  bool  delete = 3;
}
```

`AVP` is used for **reads** (`Node.attribute_value_pairs`,
`Relationship.avps`) and for AVPs supplied **at creation time**
(`ClassService.CreateClass.avps`, `NodeService.Mutate`'s
`AddRelationshipOp.fwd_avps`/`rev_avps`, etc.) — `value` is always
meaningful there.

`AVPUpdate` is used only in update contexts
(`NodeService.UpdateNodeAvps`, `InstanceService.UpdateRelationship`/
`UpdateRelationshipBoth`, and the corresponding `Mutate` batch ops), and its
upsert-vs-delete semantics are governed by the **explicit `delete` boolean
field**, not by the presence or absence of `value` on the wire:

- `delete = true` → the attribute is **removed** from the node/relationship
  entirely. Whatever is in `value` on the wire is ignored (you don't need to
  set it at all).
- `delete = false` (the default when omitted) → **upsert**: the AVP's value
  is set to whatever `value` decodes to, *including* an explicit
  `null_value` (which upserts a bound-but-null value — this is distinct from
  deleting the AVP outright).

This is not the "presence of a field implies one thing, absence implies
another" pattern you might expect from a proto3 `optional` design — it's an
explicit flag, deliberately avoiding proto3's field-presence ambiguity for
singular scalar/message fields.

### 2.4 Error contract

Every RPC error surfaces as a real gRPC status **plus** a custom trailer,
built by the single chokepoint `graphdb_api_error:to_status/1`:

- **gRPC status code** — coarse, drives generic control flow (retry logic,
  broad error categories). See the curated table below.
- **status message** — a human-readable Erlang term dump
  (`io_lib:format("~p", [Reason])`, e.g. `<<"{instance_only_attribute,999}">>`).
  This is directly usable for logging without decoding anything — it's
  already a readable string, just not a machine-parseable one.
- **`x-erlang-reason-bin` trailer** — `base64(erlang:term_to_binary(Reason))`,
  the raw Erlang error reason, always present, always lossless. A
  non-Erlang client cannot generally decode this (it's Erlang's binary term
  format) — treat it as an opaque diagnostic blob to capture in logs for
  engineers with Erlang tooling, not something to branch on. If you need a
  human-readable version of the same information, use the status message
  instead.

**Curated status table** (from `graphdb_api_error:code_for/1` — every reason
not listed here falls through to `INTERNAL`):

| Erlang reason                         | gRPC status           | Code |
| ------------------------------------- | --------------------- | ---- |
| `not_found`                           | `NOT_FOUND`           | 5    |
| `not_a_project`                       | `NOT_FOUND`           | 5    |
| `relationship_not_found`              | `NOT_FOUND`           | 5    |
| `template_not_found`                  | `NOT_FOUND`           | 5    |
| `invalid_session`                     | `UNAUTHENTICATED`     | 16   |
| `category_nodes_are_immutable`        | `INVALID_ARGUMENT`    | 3    |
| `permanent_node_immutable`            | `INVALID_ARGUMENT`    | 3    |
| `{instance_only_attribute, Attr}`     | `INVALID_ARGUMENT`    | 3    |
| `{invalid_direction, Dir}`            | `INVALID_ARGUMENT`    | 3    |
| `{invalid_mode, Mode}`                | `INVALID_ARGUMENT`    | 3    |
| `{class_not_instantiable, Class}`     | `FAILED_PRECONDITION` | 9    |
| `{ambiguous_relationship, Templates}` | `FAILED_PRECONDITION` | 9    |
| `{dangling_half_edge, ...}`           | `INTERNAL`            | 13   |
| `not_implemented`                     | `UNIMPLEMENTED`       | 12   |
| *(anything else — catch-all)*         | `INTERNAL`            | 13   |

**Gotcha — `INTERNAL` is broader than it sounds.** A retired node's
`GetNode`/`GetInstance` lookup returns the Erlang reason `retired`, which is
**not** in the curated table — it falls to `INTERNAL` (13), not something
more specific like `NOT_FOUND`. Similarly, `unregistered_language`
(`LanguageService.SetLabels` on a never-registered code) also falls to
`INTERNAL`. Don't assume `INTERNAL` always means "something is genuinely
broken" — check the status message string for these cases.

### 2.5 The `0`-as-unset sentinel

Every optional `int64` field that identifies a nref (template nrefs, parent
nrefs) uses `0` as the "not supplied" sentinel — proto3 field-presence
tracking for singular scalars requires the `optional` keyword per field,
which this design deliberately avoided. `0` is never a valid nref (nref
allocation starts at 1), so it's a safe, unambiguous sentinel.

Where this applies: `AddRelationshipOp.template` / `RemoveRelationshipOp.template`
/ `UpdateRelationshipOp.template` / `UpdateRelationshipBothOp.template` (all
in `NodeService.Mutate`'s grammar and their `InstanceService` equivalents),
`RulesService`'s `template_nref` fields, and
`AttributeService`'s `parent_nref` fields (`0` = the documented default
parent: nref 6 `Names` for name attributes, nref 7 `Literals` for literal
attributes, nref 8 `Relationships` for relationship attribute pairs and
relationship types).

The one string analog: `RulesService.CreateCompositionRuleRequest.name_pattern`
uses `""` (empty string) the same way — "unset", not "set to the empty
string".

### 2.6 No streaming in v1

Every RPC across all 8 services is unary. List-returning RPCs
(`ListAttributes`, `Subclasses`, `Ancestors`, `ListRules`, etc.) return a
fully materialized `repeated` field in one response — there is no
pagination and no server-streaming. These are ontology-scale collections
(hundreds of rows, not millions); if a future RPC needs to return an
unbounded collection, it will be split into a streaming RPC at that point,
not before.

## 3. Per-service reference

### 3.1 NodeService

Mirrors `graphdb_mgr` — the generic node-level coordinator. Covers
node reads, attribute/class creation pass-throughs, retire/unretire, AVP
updates, and the batch mutation entry point.

| RPC                | Purpose                                                                                          |
| ------------------ | ------------------------------------------------------------------------------------------------ |
| `GetNode`          | Fetch one node by nref                                                                           |
| `GetRelationships` | Fetch a node's relationships, filtered by direction                                              |
| `CreateAttribute`  | Create a name attribute or relationship-type grouping (see gotcha below)                         |
| `CreateClass`      | Create a class (thin pass-through; no AVPs — see `ClassService.CreateClass` for the fuller form) |
| `RetireNode`       | Soft-retire a node                                                                               |
| `UnretireNode`     | Reverse a soft-retire                                                                            |
| `UpdateNodeAvps`   | Upsert/delete AVPs on a node                                                                     |
| `DeleteNode`       | **Not yet implemented** — always returns `UNIMPLEMENTED`                                         |
| `Mutate`           | Atomic batch of mutation ops                                                                     |

#### GetNode

```proto
message GetNodeRequest { int64 nref = 1; }
message GetNodeReply { Node node = 1; }
```

`Node` (from `common.proto`) carries `nref`, `kind` (`NodeKind` enum),
`parents`, `classes`, and `attribute_value_pairs` (`repeated AVP`). Returns
`NOT_FOUND` for an unknown nref; returns `INTERNAL` (uncurated `retired`
reason) for a retired node — see §2.4.

#### GetRelationships

```proto
enum Direction {
  DIRECTION_UNSPECIFIED = 0;
  OUTGOING = 1;
  INCOMING = 2;
  BOTH = 3;
}
message GetRelationshipsRequest { int64 nref = 1; Direction direction = 2; }
message GetRelationshipsReply { repeated Relationship relationships = 1; }
```

**Gotcha:** an unrecognized or omitted `Direction` (the zero value
`DIRECTION_UNSPECIFIED`) silently defaults to `OUTGOING` — it does **not**
raise `INVALID_ARGUMENT` the way an unrecognized `RuleMode` does on
`RulesService`. Always set `direction` explicitly.

#### CreateAttribute

```proto
message CreateAttributeRequest {
  string name = 1;
  int64 parent_nref = 2;
  repeated AVP avps = 3;
}
message CreateAttributeReply { int64 nref = 1; }
```

**Gotcha — `avps` is currently ignored.** `graphdb_mgr:create_attribute/3`'s
third argument is an atom-keyed Erlang *options* map (`type`,
`reciprocal_name`, `target_kind`), not a graph-style AVP list. The wire's
`avps` field cannot express that shape, so the handler always passes an
empty options map. In practice this means `NodeService.CreateAttribute` can
only create plain name attributes and relationship-type groupings — it
**cannot** create typed literal attributes or relationship-attribute pairs
over this RPC. Use `AttributeService.CreateLiteralAttribute` and
`AttributeService.CreateRelationshipAttributePair` for those.

#### CreateClass (NodeService)

```proto
message CreateClassRequest {
  string name = 1;
  int64 parent_class_nref = 2;
}
message CreateClassReply { int64 nref = 1; }
```

**Gotcha — message-name collision across services.** `ClassService` also
defines a message literally named `CreateClassRequest`/`CreateClassReply`,
but with a **different shape** — it adds a `repeated AVP avps = 3` field.
These are two distinct generated types belonging to two distinct proto
files (`node_service.proto` vs `class_service.proto`); do not assume the
same request shape works against both services' `CreateClass` RPC. Use
`ClassService.CreateClass` if you need to set AVPs at creation time.

#### RetireNode / UnretireNode

```proto
message RetireNodeRequest { int64 nref = 1; }
message RetireNodeReply {}
message UnretireNodeRequest { int64 nref = 1; }
message UnretireNodeReply {}
```

Empty replies on success; standard error mapping otherwise.

#### UpdateNodeAvps

```proto
message UpdateNodeAvpsRequest {
  int64 nref = 1;
  repeated AVPUpdate updates = 2;
}
message UpdateNodeAvpsReply {}
```

See §2.3 for `AVPUpdate` semantics. `category_nodes_are_immutable` /
`permanent_node_immutable` (`INVALID_ARGUMENT`) fire if you target a
bootstrap-scaffold node.

#### DeleteNode

```proto
message DeleteNodeRequest { int64 nref = 1; }
message DeleteNodeReply {}
```

**Always returns `UNIMPLEMENTED` (12) today** — `graphdb_mgr:delete_node/1`
itself returns `{error, not_implemented}`. The RPC exists on the wire so
that when hard-delete lands server-side, no wire-contract change is needed
— but there is no working delete path yet. Don't build proxy logic that
depends on this succeeding.

#### Mutate

The batch mutation entry point — an ordered list of ops, applied
atomically as one unit.

```proto
message MutationOp {
  oneof op {
    AddRelationshipOp add_relationship = 1;
    RetireNodeOp retire_node = 2;
    UnretireNodeOp unretire_node = 3;
    UpdateNodeAvpsOp update_node_avps = 4;
    RemoveRelationshipOp remove_relationship = 5;
    UpdateRelationshipOp update_relationship = 6;
    UpdateRelationshipBothOp update_relationship_both = 7;
  }
}
message MutateRequest { repeated MutationOp ops = 1; }
message MutateReply {}
```

`AddRelationshipOp`:

```proto
message AddRelationshipOp {
  int64 source = 1;
  int64 characterization = 2;
  int64 target = 3;
  int64 reciprocal = 4;
  int64 template = 5;         // 0 = unset (use source class's default template)
  repeated AVP fwd_avps = 6;  // empty = no per-direction AVPs
  repeated AVP rev_avps = 7;
}
```

The other five op message shapes (`RetireNodeOp`, `UnretireNodeOp`,
`UpdateNodeAvpsOp`, `RemoveRelationshipOp`, `UpdateRelationshipOp`,
`UpdateRelationshipBothOp`) mirror their single-RPC counterparts' request
fields one-for-one (minus `project_id` — `Mutate` operates in the
environment/`graphdb_mgr` context, not a project session).

**Gotcha — `MutateReply` is empty; no per-op results.** The batch either
succeeds as a whole (empty reply) or fails as a whole (one gRPC error for
the entire batch) — there is no per-op success/failure breakdown on the
wire, even though the underlying Erlang call (`graphdb_mgr:mutate/1`)
returns a results list internally; the handler discards it.

**Gotcha — `template = 0` alongside AVPs.** For `Mutate`'s
`AddRelationshipOp`, `template = 0` maps to the Erlang atom `default`
internally, and `graphdb_mgr`'s backend accepts `default` alongside a
non-empty AVP spec directly — "unset template" and "has AVPs" are
independent on this path. (Contrast with `InstanceService.AddRelationship`
below, where the equivalent situation requires an extra resolution step.)

Example: retire a node as part of a batch.

```json
{
  "ops": [
    { "op": { "retire_node": { "nref": 4210001 } } }
  ]
}
```

### 3.2 InstanceService

Mirrors `graphdb_instance`, with writes additionally gated by a
`graphdb_project` session (§2.1). Covers instance creation, relationship
mutation, class membership, and inheritance-resolution reads.

| RPC                      | Purpose                                                                 | Requires `project_id`? |
| ------------------------ | ----------------------------------------------------------------------- | ---------------------- |
| `CreateInstance`         | Create an instance under a class and compositional parent               | Yes                    |
| `AddRelationship`        | Add a bidirectional relationship (connection arc)                       | Yes                    |
| `RemoveRelationship`     | Remove a relationship edge                                              | Yes                    |
| `UpdateRelationship`     | Edit AVPs on the forward direction of a relationship                    | Yes                    |
| `UpdateRelationshipBoth` | Edit AVPs on both directions of a relationship                          | Yes                    |
| `AddClassMembership`     | Add an additional class membership to an instance                       | Yes                    |
| `GetInstance`            | Fetch one instance node                                                 | No                     |
| `Children`               | Compositional children of an instance                                   | No                     |
| `CompositionalAncestors` | Compositional ancestor chain                                            | No                     |
| `ClassOf`                | Primary class of an instance                                            | No                     |
| `ClassMemberships`       | All class memberships of an instance                                    | No                     |
| `ResolveValue`           | Resolve an attribute's effective value via the 4-tier inheritance rules | No                     |

#### CreateInstance

```proto
message CreateInstanceRequest {
  int64 project_id = 1;
  string name = 2;
  int64 class_nref = 3;
  int64 parent_nref = 4;
}
message CreateInstanceReply {
  int64 nref = 1;
  Value report = 2;  // opaque (term_binary) — rule-firing report
}
```

`report` is always `term_binary` — round-trip it opaquely (§2.2); it is a
rule-firing report from the composition rule engine, with no stable
external schema. An invalid `project_id` returns `UNAUTHENTICATED` (16),
not `NOT_FOUND` (§2.1).

Example (from the CT suite):

```json
{ "project_id": 1000042, "name": "widget-1", "class_nref": 1000010, "parent_nref": 1000042 }
```

```json
{ "nref": 1000055, "report": { "term_binary": "<opaque bytes>" } }
```

#### AddRelationship

```proto
message AddRelationshipRequest {
  int64 project_id = 1;
  int64 source = 2;
  int64 characterization = 3;
  int64 target = 4;
  int64 reciprocal = 5;
  int64 template = 6;         // 0 = unset (source class's default template)
  repeated AVP fwd_avps = 7;
  repeated AVP rev_avps = 8;
}
message AddRelationshipReply {}
```

**Gotcha — `template = 0` with non-empty AVPs is more expensive and more
failure-prone than the equivalent `Mutate` op.** Unlike `NodeService.Mutate`
(where the backend accepts the atom `default` directly, even alongside
AVPs), `graphdb_instance:add_relationship/7`'s public arity requires an
**explicit integer** template nref — it does not accept a `default` sentinel.
So when `template = 0` and either `fwd_avps` or `rev_avps` is non-empty, the
handler must first resolve the real default template itself:
`graphdb_instance:class_of(source)` → `graphdb_class:default_template(ClassNref)`
→ then call the explicit-template arity. This means:

- If `source` has no class membership, you get `{no_class_membership, S}`
  (uncurated → `INTERNAL`).
- If the source's class has no default template, you get
  `{no_default_template, ClassNref}` (uncurated → `INTERNAL`).
- If `template = 0` **and both AVP lists are empty**, none of this
  resolution happens — the plain no-AVP arity is called directly, which
  does accept unset-template implicitly.

If you already know the class's default template nref (via
`ClassService.DefaultTemplate`), pass it explicitly to skip this risk
entirely.

#### RemoveRelationship / UpdateRelationship / UpdateRelationshipBoth

```proto
message RemoveRelationshipRequest {
  int64 project_id = 1;
  int64 source = 2;
  int64 characterization = 3;
  int64 target = 4;
  int64 template = 5;         // 0 = unset (match any template)
}
message RemoveRelationshipReply {}

message UpdateRelationshipRequest {
  int64 project_id = 1;
  int64 source = 2;
  int64 characterization = 3;
  int64 target = 4;
  int64 template = 5;         // 0 = unset
  repeated AVPUpdate updates = 6;
}
message UpdateRelationshipReply {}

message UpdateRelationshipBothRequest {
  int64 project_id = 1;
  int64 source = 2;
  int64 characterization = 3;
  int64 target = 4;
  int64 template = 5;         // 0 = unset
  repeated AVPUpdate fwd_updates = 6;
  repeated AVPUpdate rev_updates = 7;
}
message UpdateRelationshipBothReply {}
```

`UpdateRelationship` edits only the forward-direction AVPs; use
`UpdateRelationshipBoth` to edit both directions in one call. See §2.3 for
`AVPUpdate` upsert/delete semantics.

#### AddClassMembership

```proto
message AddClassMembershipRequest {
  int64 project_id = 1;
  int64 instance_nref = 2;
  int64 class_nref = 3;
}
message AddClassMembershipReply {}
```

#### GetInstance / Children / CompositionalAncestors / ClassOf / ClassMemberships

```proto
message GetInstanceRequest { int64 nref = 1; }
message GetInstanceReply { Node node = 1; }

message ChildrenRequest { int64 nref = 1; }
message ChildrenReply { repeated Node children = 1; }

message CompositionalAncestorsRequest { int64 nref = 1; }
message CompositionalAncestorsReply { repeated Node ancestors = 1; }

message ClassOfRequest { int64 instance_nref = 1; }
message ClassOfReply { int64 class_nref = 1; }

message ClassMembershipsRequest { int64 instance_nref = 1; }
message ClassMembershipsReply { repeated int64 classes = 1; }
```

Plain, unauthenticated reads. No `project_id` needed.

#### ResolveValue

```proto
message ResolveSource {
  oneof kind {
    bool  local               = 1;  // true iff Source = local
    int64 class_nref          = 2;  // Source = {class, Nref}
    int64 compositional_nref  = 3;  // Source = {compositional, Nref}
    int64 connected_nref      = 4;  // Source = {connected, Nref}
  }
}
message ResolveValueRequest { int64 instance_nref = 1; int64 attr_nref = 2; }
message ResolveValueReply { Value value = 1; ResolveSource source = 2; }
```

Runs the 4-tier inheritance resolution (local → class-bound → compositional
ancestors → directly-connected nodes) and reports *which* tier the value
came from via `source`. `source.kind.local = true` means the value is
locally bound on the instance itself; the other three variants carry the
nref of the class/ancestor/connected node the value was inherited from.

### 3.3 ClassService

Mirrors `graphdb_class` — the taxonomic hierarchy, qualifying
characteristics, and template management.

| RPC                           | Purpose                                                |
| ----------------------------- | ------------------------------------------------------ |
| `CreateClass`                 | Create a class, optionally with initial AVPs           |
| `AddSuperclass`               | Add an additional taxonomic parent (multi-inheritance) |
| `AddQualifyingCharacteristic` | Declare a QC attribute on a class                      |
| `BindQcValue`                 | Bind a class-level value for a QC attribute            |
| `AddTemplate`                 | Add a named connection-scoping template to a class     |
| `GetClass`                    | Fetch one class node                                   |
| `Subclasses`                  | Direct subclasses of a class                           |
| `Ancestors`                   | Full taxonomic ancestor chain                          |
| `GetTemplate`                 | Fetch one template node                                |
| `TemplatesForClass`           | All templates defined on a class                       |
| `DefaultTemplate`             | The class's default template nref                      |
| `IsInstantiable`              | Whether the class is concrete (not abstract)           |

#### CreateClass (ClassService)

```proto
message CreateClassRequest {
  string name = 1;
  int64 parent_class_nref = 2;
  repeated AVP avps = 3;
}
message CreateClassReply { int64 nref = 1; }
```

Note the `avps` field here — this is the fuller form. See the collision
gotcha under `NodeService.CreateClass` above: the two `CreateClassRequest`
message types are not interchangeable despite the identical name.

#### AddSuperclass / AddQualifyingCharacteristic / BindQcValue / AddTemplate

```proto
message AddSuperclassRequest { int64 class_nref = 1; int64 additional_parent_nref = 2; }
message AddSuperclassReply {}

message AddQualifyingCharacteristicRequest {
  int64 class_nref = 1;
  int64 attr_nref = 2;
  bool instance_only = 3;
}
message AddQualifyingCharacteristicReply {}

message BindQcValueRequest { int64 class_nref = 1; int64 attr_nref = 2; Value value = 3; }
message BindQcValueReply {}

message AddTemplateRequest { int64 class_nref = 1; string name = 2; }
message AddTemplateReply { int64 nref = 1; }
```

`instance_only = true` marks the QC as bindable only at the instance level,
never at the class level (rejects a subsequent `BindQcValue` on that
attribute for that class).

#### GetClass / Subclasses / Ancestors / GetTemplate / TemplatesForClass

```proto
message GetClassRequest { int64 nref = 1; }
message GetClassReply { Node node = 1; }

message SubclassesRequest { int64 class_nref = 1; }
message SubclassesReply { repeated Node subclasses = 1; }

message AncestorsRequest { int64 class_nref = 1; }
message AncestorsReply { repeated Node ancestors = 1; }

message GetTemplateRequest { int64 nref = 1; }
message GetTemplateReply { Node node = 1; }

message TemplatesForClassRequest { int64 class_nref = 1; }
message TemplatesForClassReply { repeated Node templates = 1; }
```

#### DefaultTemplate / IsInstantiable

```proto
message DefaultTemplateRequest { int64 class_nref = 1; }
message DefaultTemplateReply { int64 template_nref = 1; }

message IsInstantiableRequest { int64 class_nref = 1; }
message IsInstantiableReply { bool instantiable = 1; }
```

`DefaultTemplate`'s reply field is a real nref on success — `0` never
appears in the *reply* (the sentinel convention is only for optional
*request* fields).

### 3.4 AttributeService

Mirrors `graphdb_attr` — the attribute library (name attributes, literal
attributes, relationship attribute pairs, relationship-type groupings).

| RPC                               | Purpose                                                 |
| --------------------------------- | ------------------------------------------------------- |
| `CreateNameAttribute`             | Create a name attribute                                 |
| `CreateLiteralAttribute`          | Create a typed literal attribute                        |
| `CreateRelationshipAttributePair` | Create a forward/reciprocal relationship attribute pair |
| `CreateRelationshipType`          | Create a relationship-type grouping node                |
| `GetAttribute`                    | Fetch one attribute node                                |
| `ListAttributes`                  | List every attribute in the library                     |
| `ListRelationshipTypes`           | List every relationship-type grouping node              |

#### CreateNameAttribute / CreateLiteralAttribute

```proto
message CreateNameAttributeRequest {
  string name = 1;
  int64 parent_nref = 2;   // 0 = unset (default parent, nref 6 Names)
}
message CreateNameAttributeReply { int64 nref = 1; }

message CreateLiteralAttributeRequest {
  string name = 1;
  string type = 2;         // free-form literal type label, e.g. "string", "kilogram"
  int64 parent_nref = 3;   // 0 = unset (default parent, nref 7 Literals)
}
message CreateLiteralAttributeReply { int64 nref = 1; }
```

**Gotcha — `type` mints a new Erlang atom from client input.** The handler
converts the `type` string to an atom via `binary_to_atom/2` (not
`list_to_atom/1` — the wire field decodes as a binary), because
`graphdb_attr:create_literal_attribute/2,3`'s type parameter is an atom.
This is the one place in `AttributeService` where arbitrary client-supplied
text mints a new, permanent Erlang atom — acceptable only under this API's
internal-trusted-network assumption (unbounded atom creation from
untrusted input would be a real concern on a public-facing service).

#### CreateRelationshipAttributePair

```proto
message CreateRelationshipAttributePairRequest {
  string name = 1;
  string reciprocal_name = 2;
  NodeKind target_kind = 3;
  int64 parent_nref = 4;   // 0 = unset (default parent, nref 8 Relationships)
}
message CreateRelationshipAttributePairReply {
  int64 forward_nref = 1;
  int64 reciprocal_nref = 2;
}
```

**Gotcha — `target_kind` is effectively mandatory despite being a plain
enum field.** The codec's `node_kind_to_atom/1` has clauses only for
`CATEGORY`/`ATTRIBUTE`/`CLASS`/`INSTANCE`/`TEMPLATE` — there is **no
catch-all clause** for the enum's zero value (`NODE_KIND_UNSPECIFIED`, what
you get by omitting `target_kind`). Omitting or explicitly sending
`NODE_KIND_UNSPECIFIED` crashes the handler with an uncaught
`function_clause` error rather than a clean `INVALID_ARGUMENT` — this does
not go through the curated error chokepoint. **Always set `target_kind`
explicitly** to one of the five real values.

#### CreateRelationshipType

```proto
message CreateRelationshipTypeRequest {
  string name = 1;
  int64 parent_nref = 2;   // 0 = unset (default parent, nref 8 Relationships)
}
message CreateRelationshipTypeReply { int64 nref = 1; }
```

#### GetAttribute / ListAttributes / ListRelationshipTypes

```proto
message GetAttributeRequest { int64 nref = 1; }
message GetAttributeReply { Node node = 1; }

message ListAttributesRequest {}
message ListAttributesReply { repeated Node attributes = 1; }

message ListRelationshipTypesRequest {}
message ListRelationshipTypesReply { repeated Node relationship_types = 1; }
```

`ListAttributes` returns the entire attribute library, including bootstrap
attributes (e.g. nref 6 `Names` is always present).

### 3.5 RulesService

Mirrors `graphdb_rules`. **Scope is hardcoded to `environment`** on every
RPC — project-scoped rules do not exist yet (deferred, see §4). Five of the
nine RPCs return an opaque `term_binary` "rules" payload rather than a
structured list, because their underlying Erlang return shape (rule
records with resolved precedence/conflict metadata) has no stable proto
schema yet.

| RPC                        | Purpose                                                    | Reply shape                  |
| -------------------------- | ---------------------------------------------------------- | ---------------------------- |
| `CreateCompositionRule`    | Create a part-of cardinality/mode rule between two classes | structured (`rule_nref`)     |
| `CreateConnectionRule`     | Create a lateral connection-arc cardinality/mode rule      | structured (`rule_nref`)     |
| `GetRule`                  | Fetch one rule node                                        | structured (`Node`)          |
| `RulesForClass`            | All rules (composition + connection) declared on a class   | opaque (`Value`)             |
| `CompositionRulesForClass` | Composition rules only                                     | opaque (`Value`)             |
| `ConnectionRulesForClass`  | Connection rules only                                      | opaque (`Value`)             |
| `EffectiveRulesForClass`   | Rules including taxonomic inheritance, precedence-resolved | opaque (`Value`)             |
| `EffectiveConnectionRules` | Connection-only effective rules                            | opaque (`Value`)             |
| `ListRules`                | Every rule in the environment scope                        | structured (`repeated Node`) |

#### CreateCompositionRule

```proto
enum RuleMode {
  RULE_MODE_UNSPECIFIED = 0;
  MANDATORY = 1;
  AUTO = 2;
  PROPOSE = 3;
}
message Multiplicity {
  int64 min = 1;
  int64 max = 2;        // ignored when unbounded = true
  bool unbounded = 3;
}
message CreateCompositionRuleRequest {
  string name = 1;
  int64 parent_class = 2;
  int64 child_class = 3;
  RuleMode mode = 4;
  Multiplicity multiplicity = 5;
  int64 template_nref = 6;   // 0 = unset
  string name_pattern = 7;   // "" = unset
}
message CreateCompositionRuleReply { int64 rule_nref = 1; }
```

**`mode` is validated, not defaulted.** Unlike `GetRelationships`'
`Direction`, an unrecognized or omitted `RuleMode` (the zero value
`RULE_MODE_UNSPECIFIED`) is explicitly caught and mapped to
`{invalid_mode, Mode}` → `INVALID_ARGUMENT` (3). Always set `mode`
explicitly to `MANDATORY`, `AUTO`, or `PROPOSE`.

Example (from the CT suite — a mandatory 1:1 composition rule):

```json
{
  "name": "car-has-engine",
  "parent_class": 1000010,
  "child_class": 1000011,
  "mode": "MANDATORY",
  "multiplicity": { "min": 1, "max": 1, "unbounded": false },
  "template_nref": 0,
  "name_pattern": ""
}
```

Example (unbounded cardinality — `max` is ignored when `unbounded: true`):

```json
{ "min": 0, "max": 0, "unbounded": true }
```

#### CreateConnectionRule

```proto
message CreateConnectionRuleRequest {
  string name = 1;
  int64 source_class = 2;
  int64 characterization = 3;
  int64 reciprocal = 4;
  int64 target_class = 5;
  RuleMode mode = 6;
  Multiplicity multiplicity = 7;
  int64 template_nref = 8;   // 0 = unset
}
message CreateConnectionRuleReply { int64 rule_nref = 1; }
```

No `name_pattern` field here — connection rules have no analogous
option. Same `mode` validation as `CreateCompositionRule`.

#### GetRule / ListRules

```proto
message GetRuleRequest { int64 rule_nref = 1; }
message GetRuleReply { Node node = 1; }

message ListRulesRequest {}
message ListRulesReply { repeated Node rules = 1; }
```

#### The five opaque-reply RPCs

```proto
message RulesForClassRequest { int64 class_nref = 1; }
message RulesForClassReply { Value rules = 1; }             // opaque
message CompositionRulesForClassRequest { int64 class_nref = 1; }
message CompositionRulesForClassReply { Value rules = 1; }  // opaque
message ConnectionRulesForClassRequest { int64 class_nref = 1; }
message ConnectionRulesForClassReply { Value rules = 1; }   // opaque
message EffectiveRulesForClassRequest { int64 class_nref = 1; }
message EffectiveRulesForClassReply { Value rules = 1; }    // opaque
message EffectiveConnectionRulesRequest { int64 class_nref = 1; }
message EffectiveConnectionRulesReply { Value rules = 1; }  // opaque
```

All five reply with `rules` as a `term_binary` `Value` — a serialized
Erlang list of rule terms with resolved precedence metadata (relevant for
`EffectiveRulesForClass`/`EffectiveConnectionRules` specifically, which
apply taxonomic-inheritance and horizontal-conflict precedence rules
server-side). Round-trip opaquely per §2.2; there is currently no
structured way to inspect individual rule fields from these five RPCs over
the wire — use `GetRule`/`ListRules` for structured `Node` access to a
rule's own AVPs (e.g. its `name_pattern`).

### 3.6 LanguageService

Mirrors `graphdb_language`. **Scope is hardcoded to `environment`.** The
`Chain` value is an intentionally opaque round-tripped token: `MakeChain`
produces it, `ResolveLabel` consumes it unchanged — never inspect or
construct it yourself.

| RPC                  | Purpose                                                           |
| -------------------- | ----------------------------------------------------------------- |
| `RegisterLanguage`   | Register a new language code                                      |
| `RegisterDialect`    | Register a dialect of an already-registered base language         |
| `LookupLanguageNref` | Resolve a code to its nref                                        |
| `SetLabels`          | Set per-language labels (AVPs) on a node                          |
| `MakeChain`          | Build an opaque dialect-fallback chain token from a list of codes |
| `ResolveLabel`       | Resolve a node's label, walking the chain for fallback            |

```proto
message RegisterLanguageRequest { string code = 1; string name = 2; }
message RegisterLanguageReply { int64 nref = 1; }

message RegisterDialectRequest { string code = 1; string name = 2; string base_code = 3; }
message RegisterDialectReply { int64 nref = 1; }

message LookupLanguageNrefRequest { string code = 1; }
message LookupLanguageNrefReply { int64 nref = 1; }

message SetLabelsRequest { int64 nref = 1; string code = 2; repeated AVP labels = 3; }
message SetLabelsReply {}

message MakeChainRequest { repeated string codes = 1; }
message MakeChainReply { Value chain = 1; }   // opaque -- round-trip only

message ResolveLabelRequest { int64 nref = 1; int64 attr_nref = 2; Value chain = 3; }
message ResolveLabelReply { Value label = 1; }
```

**Atom-minting is scoped to registration only.** `RegisterLanguage` and
`RegisterDialect` mint new Erlang atoms from `code`/`base_code`
(`binary_to_atom/2`) — legitimate, since these RPCs create a code that has
never existed. Every other RPC (`LookupLanguageNref`, `SetLabels`,
`MakeChain`) uses `binary_to_existing_atom/2` and **never** mints — an
unrecognized code is handled cleanly per RPC, not by crashing:

- `LookupLanguageNref` on an unregistered code → `NOT_FOUND` (5).
- `SetLabels` on an unregistered code → `unregistered_language` (uncurated
  → `INTERNAL`, 13).
- `MakeChain` **silently drops** unregistered codes from the built chain
  rather than erroring the whole call — mirrors
  `graphdb_language:make_chain/1`'s own "drop unknown, don't crash"
  contract. If you pass `["it", "zz-never-registered"]` and only `"it"` is
  registered, the resulting chain is identical to passing `["it"]` alone.

Example flow (register → label → resolve):

```json
// 1. RegisterLanguage
{ "code": "es", "name": "Spanish" }
// -> { "nref": 1000123 }

// 2. SetLabels — labels is a repeated AVP; value uses the Value oneof
{
  "nref": 1000050, "code": "es",
  "labels": [{ "attribute": 1000050, "value": { "str": "hola" } }]
}
// -> {}

// 3. MakeChain
{ "codes": ["es"] }
// -> { "chain": { "term_binary": "<opaque bytes -- pass through unchanged>" } }

// 4. ResolveLabel -- pass the chain field back exactly as received
{ "nref": 1000050, "attr_nref": 1000050, "chain": { "term_binary": "<same opaque bytes>" } }
// -> { "label": { "str": "hola" } }
```

### 3.7 ProjectService

Mirrors `graphdb_project`. Small — two RPCs.

| RPC               | Purpose                                              |
| ----------------- | ---------------------------------------------------- |
| `RegisterProject` | Register a new project, get back its `project_id`    |
| `IsProject`       | Check whether an nref is a registered project anchor |

```proto
message RegisterProjectRequest { string name = 1; }
message RegisterProjectReply { int64 project_id = 1; }

message IsProjectRequest { int64 nref = 1; }
message IsProjectReply { bool is_project = 1; }
```

`RegisterProjectReply.project_id` is the value you thread as
`project_id` on every `InstanceService` write RPC afterward (§2.1).
`IsProject` never errors — an unregistered or non-existent nref simply
returns `is_project: false`, not a `NOT_FOUND`.

### 3.8 QueryService

Mirrors `graphdb_query` — **`FindPath` only**. General query execution
(`ExecuteQuery`, arbitrary query ASTs, continuation-based resumption) is
explicitly out of scope for v1 — see §4.

```proto
message FindPathRequest { int64 from = 1; int64 to = 2; int64 max_depth = 3; }
message FindPathReply {
  bool found = 1;          // true iff a complete path was found
  repeated int64 path = 2; // the path (found=true), or the best-effort
                            // prefix reached before max_depth (found=false)
}
```

The underlying Erlang call has **three** possible outcomes, collapsed onto
this **two-outcome** wire shape:

| Erlang result                                                          | Wire reply                                             |
| ---------------------------------------------------------------------- | ------------------------------------------------------ |
| `{ok, no_path}` — BFS frontier genuinely emptied out, no path exists   | `found: false, path: []`                               |
| `{ok, Path}` — a complete path was found within `max_depth`            | `found: true, path: [from, hop1, ..., to]`             |
| `{partial, Prefix, Cont}` — `max_depth` exhausted before reaching `to` | `found: false, path: [from, ...best-effort prefix...]` |

**Gotcha — `found = false` is ambiguous between "definitely no path" and
"didn't search deep enough."** If the partial-prefix case terminates with
an empty prefix (e.g. `max_depth` too small to even take a first hop), the
wire reply is `found: false, path: []` — indistinguishable from the
genuine `no_path` case. If you get `found: false` with an empty `path` and
suspect the graph may simply be deeper than your `max_depth`, retry with a
larger `max_depth` before concluding no path exists.

**Gotcha — the continuation token is discarded.** The Erlang API supports
resuming a partial search via a continuation (`Cont`), but this RPC has no
way to consume it — there is no `Resume` RPC in v1. A `{partial, ...}`
result is a dead end on the wire; your only recourse is a fresh `FindPath`
call with a larger `max_depth`.

Example — a found path:

```json
{ "from": 1000042, "to": 1000055, "max_depth": 5 }
```
```json
{ "found": true, "path": [1000042, 1000055] }
```

Example — no path (two isolated project instance trees):

```json
{ "found": false, "path": [] }
```

## 4. Known limitations / deferred features

These are deliberately **not** in v1. Don't spend integration time looking
for them.

- **General query execution.** `ExecuteQuery`, session-threaded
  `execute_query/2`, and continuation-based `resume/2` are all deferred —
  `graphdb_query:parse_query/1` has no stable external query representation
  yet. Only `FindPath` (a fixed, stable convenience wrapper) ships.
- **Streaming RPCs.** Every RPC is unary; see §2.6.
- **Project-scoped rules and language overlays.** `RulesService` and
  `LanguageService` are hardcoded to `environment` scope. There is no way
  to create or query project-specific rules or per-project label overlays
  over this API.
- **Proxy authentication / TLS.** No auth, no TLS, no request signing. A
  `grpcbox` interceptor hook point is reserved but not implemented.
- **`NodeService.DeleteNode`.** Present on the wire, always returns
  `UNIMPLEMENTED` — hard node deletion isn't implemented server-side yet.
- **Per-op batch results from `Mutate`.** The batch either succeeds
  entirely (empty reply) or fails entirely (one error); there's no
  per-op result reporting on the wire.
- **Operational/maintenance tools.** `verify_caches/0`, `rebuild_caches/0`,
  and similar Erlang-console-only operations are intentionally not exposed
  — they're not proxy-facing domain functionality.

## 5. Quick-start example

A realistic end-to-end sequence, grounded in
`apps/graphdb_api/test/graphdb_api_e2e_SUITE.erl` and
`graphdb_api_instance_service_SUITE.erl`: register a project, create a
class, create two instances, connect them with a relationship, then find
the path between them.

```text
1. ProjectService.RegisterProject
   -> { "name": "Acme" }
   <- { "project_id": 1000042 }

2. ClassService.CreateClass
   -> { "name": "Widget", "parent_class_nref": 3, "avps": [] }
   <- { "nref": 1000010 }
   (parent_class_nref 3 = bootstrap "Classes" category)

3. AttributeService.CreateRelationshipAttributePair
   -> { "name": "linkedTo", "reciprocal_name": "linkedFrom",
        "target_kind": "INSTANCE", "parent_nref": 0 }
   <- { "forward_nref": 1000020, "reciprocal_nref": 1000021 }

4. InstanceService.CreateInstance  (instance "a", parented directly on the project anchor)
   -> { "project_id": 1000042, "name": "a", "class_nref": 1000010,
        "parent_nref": 1000042 }
   <- { "nref": 1000050, "report": { "term_binary": "<opaque>" } }

5. InstanceService.CreateInstance  (instance "b")
   -> { "project_id": 1000042, "name": "b", "class_nref": 1000010,
        "parent_nref": 1000042 }
   <- { "nref": 1000051, "report": { "term_binary": "<opaque>" } }

6. InstanceService.AddRelationship
   -> { "project_id": 1000042, "source": 1000050, "characterization": 1000020,
        "target": 1000051, "reciprocal": 1000021, "template": 0,
        "fwd_avps": [], "rev_avps": [] }
   <- {}

7. QueryService.FindPath
   -> { "from": 1000050, "to": 1000051, "max_depth": 5 }
   <- { "found": true, "path": [1000050, 1000051] }
```

All nref values above are illustrative shapes (runtime nrefs are allocated
sequentially from `?NREF_START` = 1000000) — treat every nref as an opaque
integer returned by an earlier call, not a value to hardcode.

## 6. Discrepancy note

`apps/graphdb_api/CLAUDE.md` was checked against the actual `.proto` and
`_impl.erl` source files while writing this document (per-service RPC
counts, scope notes, and behavioral summaries). No material inconsistencies
were found — the per-file table's stated RPC counts and behavioral notes
(e.g. `graphdb_api_rules_service_impl.erl`'s "Scope hardcoded to
environment", `graphdb_api_language_service_impl.erl`'s "Chain is an opaque
round-tripped token") all matched the source directly.
