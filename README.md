# PatchOps

> Governed package promotion from source to server.

**Why this exists.** Traditional Linux patching is ad-hoc — cron-driven SSH loops, manual repo management, and no audit trail between "we pushed a package" and "we know it landed." PatchOps replaces that with governed snapshot promotion: upstream repos are mirrored once, frozen into immutable snapshots, promoted through time-gated environments, and applied to clients with full observability. Every patch is tracked, every failure is visible, and rollback is a single playbook run.

A self-contained Linux patch governance platform: **Aptly** mirrors upstream Ubuntu repos and cuts immutable snapshots, **AWX** orchestrates the promotion pipeline on a schedule, **Ansible** does the actual patching, and **Grafana** shows what's true about the fleet right now — not what a report claimed last week.

This is a from-scratch rewrite of patterns used in a real production patch-governance system (`infra-engine`), rebuilt as a portable, single-machine project. Nothing here is copy-pasted — every role, playbook, and AWX config was written fresh for this repo.

---

## What it does

```
Upstream Ubuntu mirrors (jammy/noble, security/updates/backports)
        │  aptly mirror update            ◄── daily, 01:00 UTC
        ▼
Immutable snapshot (patch-YYYYMMDD-HHMM)
        │  aptly snapshot merge + publish
        ▼
   dev  ──24h bake──►  staging  ──48h bake──►  prod
        │                                        │
        ▼                                        ▼
  apt upgrade on clients                  rolling apply, serial-controlled
        │
        ▼
  email + Postgres audit trail + Grafana dashboards
```

- **Aptly** is the single source of truth for packages — clients never talk to the public internet.
- **Promotion is time-gated, not vibes-gated**: staging requires a snapshot to have sat in dev for 24h, prod requires 48h in staging. The gate is a SQL assertion the playbook itself enforces, not a person remembering to wait.
- **Rollback is real.** Re-publishing an old snapshot only changes what the repo serves — it doesn't touch a host that already installed the bad version. `rollback.yml` also downgrades already-patched clients back to match the snapshot.
- **AWX runs the whole thing on a schedule** and gives you a web UI, job history, and credentials management instead of cron + SSH keys on a laptop.

---

## Screenshots

**Fleet status and package upgrades, live from the governance DB:**

| | |
|---|---|
| ![Fleet & Snapshots dashboard](preview/screenshot_2026-07-21_22-48-02.png) | ![Package Upgrades dashboard](preview/screenshot_2026-07-21_22-48-28.png) |
| 5 hosts, real risk scoring, 30 pending upgrades | Real package names and versions per host |

**Patch history — the "Successful" counter actually counts successes:**

![Patch History dashboard](preview/screenshot_2026-07-21_22-48-34.png)

**AWX orchestrating the pipeline:**

![AWX dashboard](preview/screenshot_2026-07-20_23-22-12.png)

**Email notifications on every scan and patch run:**

| Scan report | Patch succeeded |
|---|---|
| ![Scan report email](preview/screenshot_2026-07-18_14-39-20.png) | ![Patch success email](preview/screenshot_2026-07-18_14-39-45.png) |

The notification pipeline also reports failures with the actual error, not a generic "something broke" — caught here during earlier development, when an invalid `apt` module argument slipped through:

![Patch failed email with real error](preview/screenshot_2026-07-18_14-40-09.png)

---

## Architecture

| Component | Role |
|---|---|
| **Aptly** (bare metal / container) | Mirrors upstream repos, cuts snapshots, publishes `dev`/`staging`/`prod` |
| **Ansible** | `aptly-client`, `setup_aptly`, `setup_govdb`, `notify` roles + playbooks for scan/patch/promote/rollback |
| **PostgreSQL (`patchgov`)** | Governance DB — `scan_results`, `scan_package_details`, `patch_history`, `snapshots` |
| **AWX** (`awx/`) | Custom standalone build (`2ssk/awx-standalone`), Docker-based EE isolation, 14 job templates, 7 schedules |
| **Execution Environment** (`execution-environment/`) | `2ssk/patchops-ee` — Fedora 42, ansible-core 2.17.14, `community.general` + `community.postgresql` |
| **Grafana** | 3 dashboards reading directly from `patchgov` — Fleet & Snapshots, Package Upgrades, Patch History |

Secrets are ansible-vault encrypted end to end (`group_vars/all/vault.yml`) — the governance DB password, Grafana admin password, and SMTP credentials all resolve through one vaulted source, consumed identically by CLI runs and AWX job templates.

---

## Quick start

### Prerequisites

- **Docker** 24+ and **Docker Compose** v2.24+
- **~20 GB** free disk for the one-time Ubuntu mirror sync
- **Ansible** 2.15+ on the control node (the EE has its own)
- **`ansible-vault`** available on the control node

**Expected ports:** `5432` (Postgres), `3000` (Grafana), `8080` (Aptly API), `8081` (AWX)

### First run

```bash
# Fastest path — builds and starts govdb+grafana, the aptly+lab fleet, and AWX:
./scripts/start.sh

# Or drive each stack yourself:

# 1. Governance DB + Grafana
docker compose up -d

# 2. Aptly + Ubuntu lab fleet (5 clients + 1 aptly host)
# SSH_PUBKEY is baked into the lab images at build time (see docker/*.Dockerfile) —
# export it before building/starting, or use scripts/start.sh, which does this for you.
export SSH_PUBKEY="$(cat ~/.ssh/personal.pub)"
docker compose -f compose.lab.yml up -d --build

# 3. Vault setup (one-time)
echo -n 'your-random-password' > .vault_pass
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
# edit group_vars/all/vault.yml with real values, then:
ansible-vault encrypt group_vars/all/vault.yml

# 4. Bootstrap
ansible-playbook playbooks/setup_govdb.yml
ansible-playbook playbooks/setup-aptly.yml
ansible-playbook playbooks/init-aptly.yml     # one-time: create mirrors, first snapshot+publish

# 5. Run the pipeline directly
ansible-playbook playbooks/patch-scan.yml
ansible-playbook playbooks/patch-security.yml
ansible-playbook playbooks/promote-staging.yml   # fails until the snapshot has soaked 24h in dev
ansible-playbook playbooks/promote-staging.yml -e "skip_soak=true"   # testing override, logs a warning
```

**Or drive it all through AWX:**

```bash
cd awx
cp .env.example .env      # fill in SSH_KEY_PATH, AWX_SECRET_KEY, AWX_VAULT_PASSWORD, etc.
docker compose up -d
ansible-playbook awx/configure.yml   # creates inventory, 14 job templates, 7 schedules
```

AWX comes up on `:8081` (not `:8080` — that's aptly's own API port). `2ssk/patchops-ee` and `2ssk/awx-standalone` are prebuilt on Docker Hub; `execution-environment/build.sh` and `awx/build.sh` rebuild them from source if you need to.

---

## What's in / what's out

- The mirror sync is a **real** multi-GB download of Ubuntu Noble (`main restricted universe multiverse` across 4 components) plus Docker/NodeSource/Nginx third-party repos — expect it to take a while on first run, not seconds.
- The lab fleet (`compose.lab.yml`) images bake in SSH/Python at build time (see `docker/*.Dockerfile`) — but OS-level packages installed by Ansible afterward (aptly, nginx) still do **not** survive a container recreation, only `/var/cache/aptly` and the client home volumes do. Fine for a demo lab; not how you'd run this against real hosts.
- CVE severity/CVSS in the Package Upgrades dashboard come from a real pipeline: `patch-scan.yml` parses each security package's changelog for the CVE IDs it actually fixes, then scores them via Ubuntu's public security tracker. It degrades gracefully — a slow or unreachable lookup just leaves that CVE's priority/score blank for that scan, it doesn't fail the pipeline.

---

## Supported environments

| Target | OS | Notes |
|--------|-----|-------|
| **Mirror sources** | Ubuntu 22.04 (jammy), 24.04 (noble) | security, updates, backports + third-party repos |
| **Patched hosts** | Debian-family with `apt` | Tested on Ubuntu 22.04/24.04 |
| **Control / Compose host** | Linux (any distro) | Docker Compose host; Ansible control via EE |
| **Demo lab** | Docker on any Linux host | 5 `ubuntu:24.04` containers |

---

## Repository layout

```
playbooks/          patch-scan, patch-security, promote-*, rollback, setup-*, init-aptly
roles/               aptly-client, setup_aptly, setup_govdb, notify
group_vars/all/      vault.yml (encrypted, gitignored) + vars.yml
awx/                 custom AWX standalone image, docker-compose, AWX-as-code (configure.yml)
execution-environment/  patchops-ee build spec
grafana/             dashboards + datasource provisioning
compose.yml          govdb + grafana
compose.lab.yml      aptly + 5-host demo fleet
```

---

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Saurav Singh Karmwar.
