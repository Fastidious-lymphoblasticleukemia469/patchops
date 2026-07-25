# PatchOps — Analysis & Implementation Plan

> **Do:** 5 phases that fix actual reliability/maintainability issues.
> **Skip:** 4 phases that are cosmetic or over-engineering at this scale.

---

## ✅ Phase 1+2 — Dockerfiles for compose (HIGH IMPACT)

**Problem:** `compose.lab.yml` has 6 identical 12-line `command:` blocks that run `apt-get install` on **every container boot**. No build caching, slow startup, fragile debugging.

**Fix:** Create two Dockerfiles, replace inline `command:` with `build:` in compose.

```
docker/
├── ssh-base.Dockerfile    # Shared SSH+Python for ubuntu1-5
└── aptly.Dockerfile       # Aptly variant (UID 115)
```

Key benefit: packages installed once at `docker build` time, cached forever.

---

## ✅ Phase 4 — AWX in start.sh (TRIVIAL)

**Problem:** `scripts/start.sh` starts govdb+grafana and the lab, but not the AWX stack.

**Fix:** Add a third section:

```bash
echo ""
echo "=== Starting AWX ==="
cd "$ROOT_DIR/awx"
docker compose up -d
cd "$ROOT_DIR"
```

Key benefit: `start.sh` produces a complete environment.

---

## ✅ Phase 5 — init-aptly.yml overlap (LOW EFFORT)

**Problem:** `playbooks/init-aptly.yml` re-declares vars and re-runs tasks that `roles/setup_aptly/` already handled. If `setup_aptly` defaults change, `init-aptly.yml` won't match.

**Fix:** Remove 3 duplicated blocks from `init-aptly.yml`:
- Vars `aptly_config`, `aptly_data`, `aptly_user` (role defaults provide them)
- "Ensure aptly directory structure exists" task (role creates these)
- "Import Ubuntu archive GPG keys" task (role handles this)

Keep only the mirror/snapshot/publish/verify workflow.

---

## ✅ Phase 6 — Python scripts to standalone files (HIGH IMPACT)

**Problem:** 3 long Python scripts embedded in `ansible.builtin.shell` via the `echo '...' | python3 -c "..."` pattern — fragile quoting, untestable, unmaintainable.

**Fix:** Extract to `scripts/*.py`, use `ansible.builtin.script` module.

```
scripts/
├── start.sh
├── parse_upgrades.py              # from lines 72-103
├── extract_cves.py                # from lines 117-163
└── enrich_package_rows.py         # from lines 391-425
```

Key benefit: testable, syntax-highlighted, proper module, no quoting hell.

---

## ✅ Phase 8a — setup_govdb SQL to files (MEDIUM IMPACT)

**Problem:** ~200 lines of DDL (CREATE TABLE, CREATE INDEX, CREATE VIEW) embedded in YAML strings. Can't run with `psql -f`, no syntax highlighting, mixed with Ansible logic.

**Fix:** Extract schema SQL to standalone files, load via `lookup('file', ...)`.

```
roles/setup_govdb/sql/
├── 001_create_scan_results.sql
├── 002_create_scan_package_details.sql
├── 003_create_patch_history.sql
├── 004_create_snapshots.sql
├── 005_create_reboot_debt_view.sql
└── 006_verify_schema.sql
```

Key benefit: independently testable with `psql -f`, clear git diffs on schema changes.

---

## ❌ SKIPPED — Analysis only, no implementation needed

| # | What | Why skipped |
|:--:|------|-------------|
| **3** | Nginx config → template | One-time deploy, rarely changes. Inline `content:` works fine. |
| **7** | Report templates → .j2 | 7–20 lines each, already using Jinja2. Extracting is aesthetic. |
| **8b** | patch-scan SQL → files | Short parametrized queries tied to Ansible vars. Indirection adds no value. |
| **9** | Shared hosts.yml | 7 hosts, rarely changes. 3-source refactor is over-engineering for this scale. |

---

## Implementation checklist

### Phase 1+2 — Dockerfiles + compose refactor
- [x] Create `docker/lab-host.Dockerfile` — single Dockerfile parameterized by build args (SSH_USER, SSH_PASS, SSH_UID, SSH_PUBKEY) shared by the aptly host and ubuntu1-5, plus a `HEALTHCHECK`. (Originally two near-duplicate Dockerfiles; merged after code review flagged the drift risk.)
- [x] Replace all `command:` blocks in `compose.lab.yml` with `build:` directives; ubuntu1-5's identical build stanza is now a YAML anchor (`x-ssh-host-build`)
- [x] Remove ssh-key volume mounts (key is now baked into image via `SSH_PUBKEY` build arg, exported by `start.sh`)
- [x] Test: `docker compose -f compose.lab.yml build` — both images build cleanly, cached on rebuild
- [x] Test: authorized_keys/permissions/UID verified inside built images; `sshd` boots, accepts connections, and the `HEALTHCHECK` transitions starting→healthy in a standalone container run
- [ ] Test: `docker compose -f compose.lab.yml up -d` against real inventory — not run (would leave the lab stack up); ready to run via `scripts/start.sh`

### Phase 4 — AWX in start.sh
- [x] Add AWX startup section to `scripts/start.sh` (after lab, before SSH wait)
- [x] Verify `awx/docker-compose.yml` env vars are loaded from `awx/.env` (compose auto-loads `.env` from its own directory); missing `awx/.env` now just skips the AWX section with a warning instead of aborting the whole script (govdb/grafana/lab don't depend on AWX)
- [ ] Test: `./scripts/start.sh` launches all 3 stacks cleanly — not run end-to-end (needs real SSH keys/AWX secrets); `bash -n` syntax-checked

### Phase 5 — Clean init-aptly.yml overlap
- [x] Remove duplicated vars (`aptly_config`, `aptly_data`, `aptly_user`) from `init-aptly.yml` vars block — now pulled from `roles/setup_aptly/defaults/main.yml` via `vars_files`
- [x] Remove "Ensure aptly directory structure exists" task (role creates these)
- [x] Remove "Import Ubuntu archive GPG keys" task (role handles this)
- [x] Keep only mirror/snapshot/publish/verify workflow
- [x] Test: `ansible-playbook playbooks/init-aptly.yml --syntax-check` (full `--check` needs a live aptly host)

### Phase 6 — Extract Python scripts from patch-scan.yml
- [x] Extract `parse_upgrades.py`
- [x] Extract `extract_cves.py`
- [x] Extract `enrich_package_rows.py`
- [x] Replace 3 shell tasks with `ansible.builtin.script` module calls
- [x] Payloads are written to a remote temp file and passed by path, not inline as a CLI argument — a fleet-wide JSON blob could exceed the kernel's ~128KiB per-argument limit (`MAX_ARG_STRLEN`), which the old `echo ... | python3 -c` (stdin) form never hit. Caught by code review; scripts now read `sys.argv[1]` as a file path.
- [x] Test: `ansible-playbook playbooks/patch-scan.yml --syntax-check`, plus each script smoke-tested standalone with representative JSON input files (full `--check` needs a live ubuntu host)

### Phase 8a — Extract SQL from setup_govdb
- [x] Create `roles/setup_govdb/sql/` directory
- [x] Extract 4 CREATE TABLE + 1 CREATE VIEW + 1 verification query into `.sql` files
- [x] Replace inline `query:` with `query: "{{ lookup('file', 'sql/...') }}"`
- [x] Test: `psql -f` each `.sql` file independently against an ephemeral Postgres — all 6 ran clean
- [x] Test: `ansible-playbook playbooks/setup_govdb.yml` run end-to-end against an ephemeral Postgres — schema created correctly (5 objects), confirming the role-relative `lookup('file', ...)` path resolution works

---

*Analysis completed 2026-07-24. Implementation completed 2026-07-25 — see commit history for details.*
