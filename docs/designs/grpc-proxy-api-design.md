# Internal gRPC API for the External REST Proxy

**Status:** Design (approved for planning — autonomous session, see §9)
**Date:** 2026-07-08
**Scope:** A new peer OTP application exposing SeerStoneGraphDb's existing
`graphdb_*` public API over gRPC, for consumption by a non-Erlang REST proxy
running on the same internal network. The proxy itself is out of scope — this
spec designs the service the proxy calls.

## 1. Context — why this exists

External (non-Erlang) clients need access to the graph database. The agreed
shape (from prior conversation, not re-litigated here): a REST proxy faces
the public/external clients and translates to a **binary, efficient**
protocol for the internal hop to this Erlang service, since both processes
run inside a trusted internal network. gRPC (protobuf over HTTP/2) was
selected over hand-rolled binary framing because it gives the proxy
first-class client support in any language, and over Erlang-native term
transport because the proxy is explicitly non-Erlang.

**Toolchain verified against this repo's actual environment (OTP 28.5,
rebar3 3.27.0):** `grpcbox 0.17.1` (pulling `chatterbox`, `gproc`, `hpack`,
`ctx`, `acceptor_pool`) compiles cleanly with zero changes. Its protobuf
codegen path uses `gpb`, a pure-Erlang `.proto` parser/compiler — **no
`protoc` binary dependency**. This was a go/no-go gate for the whole design
and it passed.

This document grounds the API surface in `graphdb_mgr`, `graphdb_instance`,
`graphdb_class`, `graphdb_attr`, `graphdb_rules`, `graphdb_language`,
`graphdb_project`, and `graphdb_query`'s **actual current `-export` lists**
(re-read from source on 2026-07-08, not from memory or docs), plus `TASKS.md`
for what to deliberately leave room for.

## 2. Two forks this design must resolve (not defer)

Two things a naive "just expose the functions" pass would get wrong:

### 2.1 Session identity across the wire

PR #52 (SP1) made project-scoped writes (`create_instance`, `add_relationship`,
`remove_relationship`, `update_relationship`(`_both`), `add_class_membership`)
require a `Session` first argument. Reading `graphdb_project.erl`:

```erlang
open_session(ProjectNref) ->
    case is_project(ProjectNref) of
        true  -> {ok, #{kind => project_session, project => ProjectNref}};
        false -> {error, not_a_project}
    end.

require_session(#{kind := project_session, project := _}) -> ok;
require_session(_)                                        -> {error, invalid_session}.
```

A session is **not a capability token or a secret** — it's a shape-checked
value, cheaply reconstructible from the project nref alone, and
`require_session/1` does no store access. **Decision:** the wire never
carries a serialized session term. Every project-scoped RPC carries a plain
`int64 project_id` field; the gRPC handler calls
`graphdb_project:open_session(ProjectId)` itself, per call, and passes the
resulting session into the delegate. This is simpler than inventing a session
serialization format and exactly preserves today's validation semantics (an
unregistered `project_id` fails the same way `open_session/1` fails today).

### 2.2 AVP value serialization

`attribute_value_pairs` / relationship `avps` carry `value :: term()` — any
Erlang term. Protobuf is schema-typed, so this needs an explicit encoding
that is both efficient for the common case and lossless for everything else.
**Decision:** a `Value` message with a `oneof` covering the common literal
types directly, and a binary escape hatch for anything else:

```proto
message Value {
  oneof kind {
    string   str         = 1;
    int64    i           = 2;
    double   d           = 3;
    bool     b           = 4;
    bytes    term_binary = 5;  // erlang:term_to_binary/1 fallback
    NullValue null_value = 6;
  }
}
```

A codec module (`graphdb_api_value`) converts `#{attribute => Nref, value =>
term()}` maps to/from `Value` on every AVP boundary: string/integer/float/
boolean/`undefined` map to the direct variants; every other term (nested
lists, maps, tuples, other atoms) round-trips through `term_binary`. Nothing
is silently dropped or lossily stringified. AVPs are `message AVP { int64
attribute = 1; Value value = 2; }`.

## 3. Scope — what ships in v1

**Grounding rule:** every RPC below mirrors one existing exported function.
Nothing is invented ahead of the Erlang API. Where `TASKS.md` documents a
grammar that is still growing (`mutate/1`'s mutation kinds), the `.proto`
leaves room (a `oneof` that already anticipates the documented-but-not-yet-
built kinds is *not* added — that would be speculative; the `oneof` grows
when the Erlang grammar grows).

### In scope (mirrors real exports, one gRPC service per owning worker)

| Service             | Backing module      | RPCs (arity-collapsed)                                                                                                                          |
| -------------------- | -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `NodeService`         | `graphdb_mgr`         | `GetNode`, `GetRelationships`, `CreateAttribute`, `CreateClass`, `RetireNode`, `UnretireNode`, `UpdateNodeAvps`, `DeleteNode`, `Mutate`             |
| `InstanceService`     | `graphdb_instance` / `graphdb_project` | `CreateInstance`, `AddRelationship`, `RemoveRelationship`, `UpdateRelationship`, `UpdateRelationshipBoth`, `AddClassMembership`, `GetInstance`, `Children`, `CompositionalAncestors`, `ClassOf`, `ClassMemberships`, `ResolveValue` |
| `ClassService`        | `graphdb_class`       | `CreateClass`, `AddSuperclass`, `AddQualifyingCharacteristic`, `BindQcValue`, `AddTemplate`, `GetClass`, `Subclasses`, `Ancestors`, `GetTemplate`, `TemplatesForClass`, `DefaultTemplate`, `IsInstantiable`                        |
| `AttributeService`    | `graphdb_attr`        | `CreateNameAttribute`, `CreateLiteralAttribute`, `CreateRelationshipAttributePair`, `CreateRelationshipType`, `GetAttribute`, `ListAttributes`, `ListRelationshipTypes`                                                            |
| `RulesService`        | `graphdb_rules`       | `CreateCompositionRule`, `CreateConnectionRule`, `GetRule`, `RulesForClass`, `CompositionRulesForClass`, `ConnectionRulesForClass`, `EffectiveRulesForClass`, `EffectiveConnectionRules`, `ListRules`                              |
| `LanguageService`     | `graphdb_language`    | `RegisterLanguage`, `RegisterDialect`, `LookupLanguageNref`, `SetLabels`, `ResolveLabel`                                                                                                                                             |
| `ProjectService`      | `graphdb_project`     | `RegisterProject`, `IsProject`                                                                                                                                                                                                        |
| `QueryService`        | `graphdb_query`       | `FindPath` only (see §3.1)                                                                                                                                                                                                            |

`CreateClass` appears on both `NodeService` (the `graphdb_mgr` pass-through,
`/2` form) and `ClassService` (the fuller `graphdb_class` surface, `/2,3` +
QC/template management) because that's genuinely how the Erlang API is
layered today — `graphdb_mgr` is a thin coordinator, `graphdb_class` owns the
domain. Mirroring that split keeps each service a faithful, independently
testable wrapper of one owning module (brainstorming's isolation principle),
rather than inventing a flattened API that doesn't exist in Erlang.

`DeleteNode` is included even though `graphdb_mgr:delete_node/1` returns
`{error, not_implemented}` today — that maps naturally to gRPC's
`UNIMPLEMENTED` status with no special-casing in the handler. When the real
hard-delete lands (blocked on the project-boundary work per `TASKS.md`), the
RPC starts working with no wire-contract change.

### 3.1 Explicit scope cut — general query execution deferred

`graphdb_query:parse_query/1` is documented as "identity until a text DSL
lands" — today a `Query` is an arbitrary Erlang record
(`#q_find_path{}` etc., defined in `graphdb_query.hrl`) with no stable
external representation. Inventing a protobuf mirror of every internal query
record now would be designing ahead of the Erlang API, which this spec
explicitly avoids (§3 grounding rule). **`ExecuteQuery`, `execute_query/2`
(session-threaded), and `resume/2` continuation are deferred** until either a
text DSL or a deliberate query-AST `.proto` is designed — that's its own
spec. `find_path/3` ships now because it's a concrete, already-stable
convenience wrapper (`source, target, max_hops -> path`) that needs no query
record on the wire.

### Explicitly out of scope for v1 (with reasons)

- **`graphdb_mgr:verify_caches/0` / `rebuild_caches/0`** — operational/
  maintenance tools, not proxy-facing domain functionality. Stay
  Erlang-console-only.
- **General `ExecuteQuery`** — see §3.1.
- **Proxy authentication / TLS** — v1 binds gRPC to a configurable
  internal-only listen address (mirrors the existing `app_port` config
  pattern) and runs plaintext, matching the user's stated trust boundary
  ("run inside an internal network"). An `grpcbox` server interceptor hook
  point is reserved (documented, not implemented) for a future shared-secret
  or mTLS layer — YAGNI until there's a concrete threat model to design
  against.
- **SP2+ multi-project physical isolation** — the wire API already threads
  `project_id`; deeper isolation is a `graphdb_project`-side concern
  (`TASKS.md` → Multi-project sessions), transparent to this layer.
- **Server-streaming** — see §4.

## 4. Streaming vs. unary

Every RPC in v1 is **unary**, including list-returning ones (`ListAttributes`,
`Subclasses`, `Ancestors`, `ListRules`) via a `repeated` field. These are
ontology-scale collections (attributes, classes, rules — hundreds, not
millions of rows) where the framing overhead of server-streaming isn't
justified. `find_path/3` returns one bounded path. **Revisit trigger:** if a
future v-next exposes project-instance bulk listing (which could be
unbounded), split that RPC to server-streaming then — don't build the
streaming machinery speculatively now.

## 5. Error mapping

Erlang write/read paths return `{error, Reason}` where `Reason` ranges from
plain atoms (`not_found`, `invalid_session`) to structured tuples
(`{instance_only_attribute, AttrNref}`, `{ambiguous_relationship, Templates}`).
gRPC status codes are coarse (an enum); Erlang reasons are precise. **Decision:
keep both.** A curated table maps known atoms/tuple-heads to the closest gRPC
status code (`not_found → NOT_FOUND`, `invalid_session → UNAUTHENTICATED`,
`category_nodes_are_immutable` / `permanent_node_immutable` /
`instance_only_attribute → INVALID_ARGUMENT`, `not_implemented →
UNIMPLEMENTED`, unmapped → `INTERNAL`). Separately, **every** error response
also carries the raw Erlang reason, `term_to_binary`-encoded, in a
`x-erlang-reason-bin` gRPC trailer — so the status code drives generic
proxy/client branching while the exact reason is always available for
logging or fine-grained handling, never lossily flattened to a status-code
enum or a stringified message. `graphdb_api_error:to_status/1` is the single
chokepoint implementing this.

## 6. New application: `graphdb_api`

A new peer OTP application, not folded into `seerstone` or `graphdb`.
Verified against a throwaway `grpcbox_plugin` codegen probe (package
`graphdb_api`, service `NodeService`, proto file `node_service.proto`) so
the module names below are real, not guessed:

- The `.proto` **file name** drives the gpb message module:
  `node_service.proto` → `node_service_pb.erl` (message types as maps, e.g.
  `#{nref => integer()}`).
- The `.proto` **package + service name** drive the generated behaviour and
  client modules, snake-cased: package `graphdb_api`, service `NodeService`
  → `graphdb_api_node_service_bhvr.erl` (a `-callback` per RPC, generated,
  never hand-edited) and `graphdb_api_node_service_client.erl`.
- A generated unary callback has the exact shape:
  `get_node(ctx:t(), node_service_pb:get_node_request()) -> {ok,
  node_service_pb:get_node_reply(), ctx:t()} |
  grpcbox_stream:grpc_error_response()`.
- **The implementation module is hand-written and separate from the
  generated `_bhvr` module** — e.g. `graphdb_api_node_service_impl.erl`,
  declaring `-behaviour(graphdb_api_node_service_bhvr)`. Regenerating the
  `.proto` never overwrites hand-written code.

```
apps/graphdb_api/
  src/
    graphdb_api.erl                     %% application behaviour (near-empty; see §6.1)
    graphdb_api_sup.erl                 %% supervisor (one_for_one, empty child list initially)
    graphdb_api_node_service_impl.erl
    graphdb_api_instance_service_impl.erl
    graphdb_api_class_service_impl.erl
    graphdb_api_attribute_service_impl.erl
    graphdb_api_rules_service_impl.erl
    graphdb_api_language_service_impl.erl
    graphdb_api_project_service_impl.erl
    graphdb_api_query_service_impl.erl
    graphdb_api_value.erl               %% Value <-> term() codec (§2.2)
    graphdb_api_error.erl               %% Erlang reason -> grpc status (§5)
  priv/protos/
    common.proto                        %% Node, Relationship, AVP, Value, Kind enum
    node_service.proto
    instance_service.proto
    class_service.proto
    attribute_service.proto
    rules_service.proto
    language_service.proto
    project_service.proto
    query_service.proto
  graphdb_api.app.src
```

(Generated `*_pb.erl` / `*_bhvr.erl` / `*_client.erl` files land in the same
`src/` directory per `grpcbox_plugin` convention, `.gitignore`d like other
generated build artifacts — not hand-maintained, not listed above.)

One hand-written `_impl` module per owning worker (§3's table), each
depending only on that worker's public API plus the shared
`graphdb_api_value` / `graphdb_api_error` codecs — mirrors the existing
`graphdb_*` module boundaries, so each is independently understandable,
testable, and assignable as one implementation slice.

### 6.1 Supervision placement and startup ordering — resolves a standing TASKS.md item

**Verified mechanism (via the codegen/runtime probe, not assumed):**
`grpcbox` ships as a self-contained OTP application (`mod =>
{grpcbox_app, []}`) that, on its own `application:start/1`, reads a
`{grpcbox, [{servers, [...]}]}` entry from `sys.config` and — if present —
starts the configured listener(s) itself, under its own
`grpcbox_services_simple_sup`. **`graphdb_api` never manually starts or
supervises the gRPC listener.** `graphdb_api_sup` only hosts (currently
nothing; reserved for future interceptor/auth state — §3 out-of-scope). The
`sys.config` shape:

```erlang
{grpcbox, [
  {servers, [
    #{grpc_opts   => #{service_protos => [common_pb, node_service_pb, ...],
                        services       => #{'graphdb_api.NodeService' => graphdb_api_node_service_impl,
                                             'graphdb_api.InstanceService' => graphdb_api_instance_service_impl,
                                             %% ... one entry per service in §3's table
                                            }},
      listen_opts => #{port => 8081, ip => {0,0,0,0}}}
  ]}
]}.
```

`TASKS.md` → *Phased application startup (deferred)* flags exactly this
situation: "revisit when an externally-visible entry point (an API server or
socket listener) is added ... that must not accept connections until the
full graphdb stack is bootstrapped." **Resolution: sequence, not
`start_phases`.** OTP's `application_controller` starts applications in
`relx` release-list order and does not begin the next application until the
current one has finished starting. The load-bearing placement is therefore
**`grpcbox` itself**, not `graphdb_api`: putting `grpcbox` *after* `database`
in the release app list — `[nref, database, seerstone, grpcbox, graphdb_api]`
— guarantees `database` (which supervises `graphdb` + `dictionary`,
bootstrap included) has fully started before `grpcbox_app` runs and binds
the listen port. `graphdb_api`'s own position only needs to be "compiled and
on the code path," which `relx` guarantees regardless of app-start order
(code loading is release-wide, not per-app-start); it's listed last simply
for readability. No `start_phases` complexity needed — this is a direct
consequence of release app-list order, not a new mechanism. (Housekeeping:
the plan should update that `TASKS.md` entry to reflect this resolution.)

`grpcbox` must also be added to `graphdb_api.app.src`'s `applications` list
(so the release includes it as a dependency), and to `graphdb_api`'s
`rebar.config` deps alongside the `grpcbox_plugin` rebar3 plugin, which
provides the `rebar3 grpc gen` provider that compiles `priv/protos/*.proto`
into the `_pb.erl` / `_bhvr.erl` / `_client.erl` modules described above.

## 7. Testing approach

Per-service Common Test suites (`graphdb_api_<service>_SUITE.erl`), same
harness pattern as the existing `graphdb_*_SUITE` suites (bootstrap once,
exercise via a real in-process `grpcbox` client against the running
service — no mocking of `graphdb_mgr`/etc., consistent with this project's
existing test conventions of hitting real Mnesia). Each suite covers: the
happy path per RPC, the `Value`/`AVP` codec round-trip (including the
`term_binary` fallback path), and the error-mapping table (§5) for at least
one representative reason per gRPC status bucket.

## 8. Follow-ups (recorded, not solved here)

- **Proxy auth/TLS** — interceptor hook reserved, not implemented (§3).
- **General query execution** — needs its own spec once a text DSL or query
  AST exists (§3.1).
- **Server-streaming** — revisit if a future RPC returns an unbounded
  collection (§4).
- **`TASKS.md` update** — fold this feature in as a tracked item and update
  the *Phased application startup* entry per §6.1's resolution.

## 9. Process note

This spec was produced autonomously per explicit user authorization (session
"API", 2026-07-08): brainstorming, spec, plan, and implementation all run via
agents on the pre-provisioned local branch `api_for_proxy` without interactive
per-question dialogue, committing at each stage for after-the-fact review
rather than gating on it. The "propose 2-3 approaches" step of the
brainstorming skill is folded into §2 and §3.1 above — those are the two
forks with real architectural weight (session model, query scope); library
selection (grpcbox) and streaming policy (§4) had a clear single right answer
once the constraints were checked, so no false choice is presented for them.
