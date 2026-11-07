# Lab guide: <option name>, tested on <platform>

**Companion to:** <design document / customer reply, path and date>. That document is the design under test.

<Two or three sentences: what the lab builds, what it checks, that it is CLI-only.>

> **Status: plan only, not executed (<date>).** Gates 1 to 4 are open. Generators were validated offline (<parsers used>). During the first run, mistakes in this text are fixed in place and marked **🔧 CORRECTED (Gn)**; measured behaviour is marked **📝 LAB FINDING**. The untouched original goes to `<evidence>/<this file>.original.md` when execution starts.

### Corrections log

| # | Where | What was wrong in the original | Fix (with evidence path) |
|---|---|---|---|
| | | *(empty until the first run)* | |

## Before you start (gates)

| Gate | What is needed | Status |
|---|---|---|
| 1 | Confirm the design options and open points | Open |
| 2 | Approve the test matrix and pass criteria (and which optional tests run) | Open |
| 3 | Review this guide before any spend | Open |
| 4 | Host decision, budget, **teardown owner**, secrets **in files on the host** | Open |

## What the tools actually do

| # | Behaviour | Tag (source / docs / community) | Test |
|---|---|---|---|
| 1 | <behaviour, with version: "cloud-init 26.1 does X"> | <source: repo@commit file> | <Tn> |

A source reading is a hypothesis until a test confirms it on the versions in the image.

## Design under test

| Option | Mechanism | In this lab |
|---|---|---|
| <O1> | <one line> | <full test / comparison / not covered> |

## Open points

| # | Question a test answers yes or no | Status before testing | Test |
|---|---|---|---|
| OP1 | <Does X happen when Y?> | <docs: yes / source: yes / unknown> | <Tn> |

## Test matrix

Pass criteria are state on disk or exit codes (state files, `state-compare`, parsers), never console text.

| ID | Open point | Pass criteria (machine-checkable) | Optional? |
|---|---|---|---|
| T0 | Pre-flight | <layout, entries, versions recorded, before anything destructive> | |
| T1 | <OPn> | <...> | |
| T<n> | Repeatability | <the operation twice without restoring the baseline> | |
| N1 | <negative: must fail> | **Must fail:** <...> | |
| T<n> | Limits | Recorded: <bracket, e.g. "768 MB passes, 512 MB fails"> | Yes |

A negative test that passes is a finding.

## 0. Lab architecture

```
<ASCII diagram: host, networks, VMs, deploy server>
```

**What this lab validates:** <...>

**What it does not validate:** <...> (see Part 3)

### Sizing and cost

| Item | Value |
|---|---|
| Instance | <type, from ec2-nested-check> |
| Disk | <GB, with the largest artifacts> |
| Memory | at most <n> guests of <m> GB at once (`MAX_RUNNING_GB=<x>`) |
| Duration | <build h, tests h> |
| Licences / subscriptions | <what is attached, at most how many at once, who detaches> |

Stop the instance between sessions only on the teardown owner's instruction.

# Part 1: Build the lab

## 1.1 Prerequisites and secrets
<Secrets live only in files on the host, under `$LAB_DIR/secrets/` (directory mode 700, files mode 600, one value per file). They are in files so that `scrub-evidence --secrets` can search the evidence for them before it leaves the host. Name the campaign-unique `VM_PREFIX` here: every VM name must start with it, and `vm-create`, `vm-clone` and `vm-snap` refuse other names.>

## 1.2 Host
<Reuse (`ec2-nested-check --instance`) or launch (`ec2-launch`). Then: `mkdir -p $LAB_DIR/bin`, copy the contents of `scripts/kvm` into it (e.g. `scp design-doc-lab-validation/scripts/kvm/* host:lab/<campaign>/bin/`; a bare `scp -r .../kvm host:.../bin/` creates `bin/kvm/` when `bin` exists) (a local shell expands `$LAB_DIR` before ssh/scp sees it, and it is empty there, so a literal paste would create `/bin`: use the home-relative path for scp/rsync targets, `host:lab/<campaign>/bin/`, and a single-quoted remote-expanded path for host commands, e.g. `ssh host 'mkdir -p ~/lab/<campaign>/bin'`), `chmod +x $LAB_DIR/bin/*` (exec bits may not survive an upload), `host-bootstrap`, `mkdir -p $LAB_DIR/secrets && chmod 700 $LAB_DIR/secrets`, write `lab.env` (check `MAX_RUNNING_GB`; the default is derived from host RAM).

Separate non-interactive ssh calls share no environment. Write `$LAB_DIR/env.sh` and start every ssh call to the host with `. ~/lab/<campaign>/env.sh;`:
```bash
LAB_DIR=$HOME/lab/<campaign>
set -a; . "$LAB_DIR/lab.env"; set +a      # exports LAB_DIR etc.; labconsole.py ignores lab.env and needs EVID or LAB_DIR in the environment
export LAB_ENV=$LAB_DIR/lab.env PATH=$LAB_DIR/bin:$PATH
```

## 1.3 Artifacts
<Downloads with pinned sha256 (recipes.md).>

## 1.4 <Build steps>
<One section per build step; every wait uses wait-ready or a loop with timeout and heartbeat.>

## 1.n Baseline
<`vm-snap snap <vm> baseline`; how a test restores it.>

# Part 2: Tests

Keep `lab-progress.md` up to date after every test. Each run gets a unique label (`r1`, `r2`); never overwrite a log or state file.

## T0 Pre-flight
```bash
<commands>
```
**Pass criteria:** <...>

## T1 <title>
```bash
<commands>
```
**Pass criteria:** <...>

## Results sheet

| Test | Description | Expected | Result | Notes |
|---|---|---|---|---|
| T0 | Pre-flight | Pass | | |

Result values: PASS / FAIL AS WRITTEN / PASS AFTER FIX / FAILS AS EXPECTED / RECORDED / NOT RUN / INCONCLUSIVE.

# Part 3: Customer-side validation
| # | Check | How |
|---|---|---|
| V1 | <what only the customer's environment can show> | <CLI steps> |

# Part 4: Teardown
Run **only when the teardown owner says so.** Detach subscriptions first.
```bash
<commands>
```

## Appendix: Troubleshooting
| Symptom | Likely cause | Check / fix |
|---|---|---|
| <...> | <...> | <see references/pitfalls.md Pn> |
