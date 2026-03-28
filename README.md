# SeerStoneGraphDb

A distributed graph database written in Erlang/OTP, originally authored by
Dallas Noyes (SeerStone, Inc., 2008). Dallas passed away before completing the
project. The goal is to finish and extend his work. PRs are welcome. Treat this
codebase with care — preserve Dallas's style and conventions wherever possible
when completing NYI stubs.

---

## Requirements

- **Erlang/OTP 27** or later
- **rebar3** (bootstrapped automatically via `make rebar3` if not present)

---

## Quick Start

```sh
# 1. Bootstrap rebar3 if you don't have it on PATH
make rebar3

# 2. Compile all applications
make compile

# 3. Start an interactive shell with all apps loaded
make shell
```

Inside the shell, start the full system:

```erlang
application:start(nref),
application:start(database).
```

Or start just the nref subsystem and exercise it:

```erlang
application:start(nref).
nref_server:get_nref().   % => 1
nref_server:get_nref().   % => 2
```

---

## Project Structure

```
SeerStoneGraphDb/
├── apps/
│   ├── seerstone/     # Top-level OTP application and supervisor
│   ├── database/      # database application (supervises graphdb + dictionary)
│   ├── graphdb/       # Graph database application and worker stubs
│   ├── dictionary/    # ETS/file-backed key-value dictionary application
│   └── nref/          # Globally unique node-reference ID allocator
├── rebar.config       # rebar3 umbrella build configuration
├── Makefile           # Convenience targets (compile, shell, release, clean)
├── TASKS.md           # Inventory of remaining implementation work
└── CLAUDE.md          # Project guide and coding conventions
```

### OTP Supervision Tree

```
seerstone (application)
  └── seerstone_sup
        └── database_sup
              ├── graphdb_sup
              │     ├── graphdb_mgr
              │     ├── graphdb_rules
              │     ├── graphdb_attr
              │     ├── graphdb_class
              │     ├── graphdb_instance
              │     └── graphdb_language
              └── dictionary_sup
                    ├── dictionary_server
                    └── term_server

nref (application — started independently)
  └── nref_sup
        ├── nref_allocator   (DETS-backed block allocator)
        └── nref_server      (serves nrefs to callers)
```

---

## Make Targets

| Target | Description |
|---|---|
| `make compile` | Compile all applications |
| `make shell` | Start an Erlang shell with all apps on the code path |
| `make release` | Build a self-contained production release under `_build/` |
| `make clean` | Remove all build artifacts |
| `make rebar3` | Download the rebar3 escript into the project root |

---

## Knowledge Model

SeerStoneGraphDb implements the knowledge graph model described in
`knowledge-graph-database-guide.md` (derived from US patents 5,379,366;
5,594,837; 5,878,406 — Noyes; and Cogito knowledge center documentation).

### Node Types

| Type               | Description                                                                                                          |
|--------------------|----------------------------------------------------------------------------------------------------------------------|
| **Instance Node**  | Concrete entity — has a name attribute, class membership, compositional parent, and relationships to other instances |
| **Class Node**     | Type/schema — has a class name attribute, an instance name attribute, and qualifying characteristics                 |
| **Attribute Node** | Name attribute, relationship attribute, or literal attribute stored in the attribute library                         |

### Hierarchy Systems

- **Taxonomic hierarchy** ("is a") — class structure; child inherits all parent attributes and adds distinguishing qualifiers
- **Compositional hierarchy** ("part of") — instance structure; big things composed of smaller things
- The two hierarchies are **perpendicular** — they intersect only at instance-to-class membership

### Relationships

All relationships are **reciprocal**. Each arc stores:
```
{Characterization, Value, ReciprocalCharacterization}
```
Example: Ford→makes→Taurus / Taurus→made-by→Ford

### Inheritance

Priority order — each step applies only to attributes not yet resolved by a higher-priority step:

1. **Local values** (highest priority — override all else)
2. **Class-level bound values** (values explicitly bound at the class)
3. **Compositional ancestors** (unbroken chain upward only)
4. **Directly connected nodes** (one level deep only; lowest priority)

### graphdb Workers

| Module             | Role                                                                             |
|--------------------|----------------------------------------------------------------------------------|
| `graphdb_attr`     | Attribute library — name attributes, literal attributes, relationship attributes, relationship types |
| `graphdb_class`    | Taxonomic hierarchy — class nodes, qualifying characteristics, class inheritance |
| `graphdb_instance` | Instance nodes — creation, retrieval, compositional hierarchy                    |
| `graphdb_rules`    | Graph rules — pattern recognition and relationship constraints                   |
| `graphdb_language` | Query language — parsing and executing graph queries                             |
| `graphdb_mgr`      | Primary coordinator — routes operations across the other five workers            |

---

## Storage

| Technology   | Used by                         | Purpose                                |
|--------------|---------------------------------|----------------------------------------|
| DETS         | `nref_allocator`, `nref_server` | Persistent disk-based term storage     |
| ETS          | `dictionary_imp`                | In-memory term storage                 |
| ETS tab2file | `dictionary_imp`                | Persistent serialization of ETS tables |

---

## Configuration

Release configuration lives in `config/sys.config`:

```erlang
[{seerstone_graph_db, [
  {app_port, 8080},
  {data_path, "data"},
  {index_path, "index"}
]}].
```

---

## Logging

Logs are written to `log/seerstone.log` (rotating, 5 × 10 MB segments). Errors
are also echoed to stdout. The `log/` directory is created automatically at
startup.

### Changing the log level at runtime

No restart is required. From an Erlang shell connected to the running node:

```erlang
%% Raise or lower the global log level
logger:set_primary_config(level, debug).
logger:set_primary_config(level, info).

%% Or target a specific handler only
logger:set_handler_config(file_handler, level, debug).
logger:set_handler_config(default, level, warning).
```

Valid levels in ascending severity: `debug`, `info`, `notice`, `warning`,
`error`, `critical`, `alert`, `emergency`.

Note: runtime changes do not persist across restarts. The initial level is
controlled by `logger_level` in `config/sys.config`.

---

## Contributing

See `CLAUDE.md` for detailed coding conventions, the NYI/UEM macro pattern,
module header format, naming conventions, and the git workflow. See `TASKS.md`
for a prioritised list of remaining implementation work.

Key conventions at a glance:

- Every module uses `?NYI(X)` and `?UEM(F, X)` macros for unimplemented paths
- Module names follow the pattern: `name.erl`, `name_sup.erl`, `name_server.erl`, `name_imp.erl`
- Graph nodes are identified by **Nrefs** — plain positive integers allocated by `nref_server:get_nref/0`
- See `knowledge-graph-database-guide.md` for the knowledge model behind the graphdb workers
- Feature work goes on `develop`; PRs target `main`
