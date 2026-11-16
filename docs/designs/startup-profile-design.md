# Startup profile — design

**Status:** implemented 2026-11-16 (`graphdb_startup`).

## Intent

The environment database will grow large. Every boot should record where
its time goes, so that a slowdown shows up as the environment grows,
instead of being discovered when a boot is already slow.

## Goals and non-goals

- **Goal:** one log line per boot with each phase's time, the total and the
  environment size, plus a warning when the boot is slower than a
  configured threshold.
- **Goal:** zero effect outside a real boot. A worker restart and a test
  that starts workers directly only run their work.
- **Non-goal:** a history file, metrics export or console alerting. The log
  file is the record (`grep "graphdb startup" log/seerstone.log*`).
- **Non-goal:** making startup faster. The first measurements are filed as
  a follow-up in `TASKS.md` (*Startup scans that grow with the
  environment*).

## Approaches

| Approach                                                       | Trade-off                                                            | Chosen |
| -------------------------------------------------------------- | -------------------------------------------------------------------- | ------ |
| One summary line per boot in the log, warning over a threshold | Nothing new to look after; noticing a slowdown means reading the log | Yes    |
| The same, with the warning also printed on the console         | Breaks the console's errors-only setting                             | No     |
| The same, plus a CSV history file                              | Trend at a glance, but another file to rotate and keep               | No     |

David chose the first, with the threshold in config at 2000 ms.

## Design

- **Configuration:** `startup_warn_ms` in the `seerstone_graph_db`
  application environment, default 2000. It is in `config/sys.config` and
  `apps/seerstone/priv/default.config`. A missing or invalid value means
  2000.
- **Phases**, in the order they finish:
  - Each `graphdb_sup` child's `init/1`. The children start through
    `graphdb_startup:start_child/1`.
  - Inside `graphdb_mgr`: `ensure_mnesia`, `create_tables`,
    `wait_for_tables` and, on the first boot only, `bootstrap_load`. These
    finish just before `graphdb_mgr`, and its time includes them.
  - `runtime_flip` and `seed_cache`.
- **Line:**
  - Layout: `graphdb startup: <total> ms total (nodes N, relationships R,
    VM up U ms); phases (ms): <phase> <ms>, ...`.
  - Level: warning when total > `startup_warn_ms`, info otherwise.
  - The same figures go in the `startup_profile` logger metadata.
  - The VM uptime also covers time spent before `graphdb:start/2`, such
    as Mnesia's own start.
- **Collection:** phases are recorded from more than one process, so they
  go to a public named ETS table.
  - The process running `graphdb:start/2` creates the table in
    `begin_profile/0`.
  - `finish/0` deletes it after a successful start; `discard/0` deletes it
    after a failed one.
  - `begin_profile/0` drops a table left by an earlier failed start.
  - When the table is absent, `timed/2` only runs its fun.

## Left to the builder

The phase names are the module and function names; the number format is
one decimal place in milliseconds.
