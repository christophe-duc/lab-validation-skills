---
name: design-doc-lab-validation
description: Use when a design or architecture document, or a reply to a customer, must be proven or disproven in a lab before it is trusted - building and running a test campaign, setting up a lab host (AWS EC2 with nested virtualization, KVM/libvirt guests), keeping evidence, or writing a lab report with gap analysis.
---

# Design document to validated lab

Take a design or architecture document (one or more solution options with open points) and produce evidence that each option works, or does not, through a lab the agent builds and runs.

**Principle:** the agent produces the evidence; the engineer owns the question and the verdict. Never present a lab result as a decision.

## Harness (use it, do not rewrite it)

This skill ships a harness. Prefer it over writing new helpers:

| Path | What | When |
|---|---|---|
| `references/platform-aws-ec2-kvm.md` | EC2 nested virtualization (m8i verified), launch baseline, sizing, host facts | Phase 4 |
| `references/pitfalls.md` | 24 incidents from past campaigns: symptom, cause, fix | Phase 3, and whenever a step fails oddly |
| `references/recipes.md` | proven command blocks (autoinstall, ISO pinning, seed ISO, Secure Boot/TPM, generalize, read-only disk, long jobs) | Phase 3 |
| `scripts/kvm/` | `ec2-nested-check`, `ec2-launch`, `host-bootstrap`, `vm-create`, `vm-clone`, `vm-ip`, `vm-ssh`, `vm-sudo`, `wait-ready`, `vm-snap`, `ro-inspect`, `labconsole.py`, `env-dump`, `scrub-evidence`, `state-compare`, `proc-kill`, `mac-for`; each prints usage on bad arguments | Phases 4 to 6 |
| `templates/` | `lab-guide.md`, `report.md`, `lab-progress.md` | Phases 3, 5, 6 |

Set-up at Phase 4, after Gate 4: copy `scripts/kvm/` to the lab host as `$LAB_DIR/bin`, put it on `PATH`, and write `$LAB_DIR/lab.env` from `lab.env.example` (with a `VM_PREFIX` unique to the campaign). Separate non-interactive `ssh` calls share no environment, so every ssh call to the host starts by loading `$LAB_DIR/env.sh` (Phase 4, step 8). Product-specific generators and parsers stay in the campaign's own folder.

## Inputs to collect first

Ask for anything missing before Phase 1. Do not guess these.

| Input | Why |
|---|---|
| The design / architecture document (path or file) | Source of options and open points |
| Customer question in one sentence | Keeps the test matrix on target |
| Lab platform and access method (AWS account via SSO, region, nested virtualization needed?) | Decides the lab architecture |
| Budget and **teardown owner** (a person, not "later") | Cost guardrail |
| Where credentials will live (a file on the lab host, never the prompt) | Secrets guardrail |
| Output folder (default: next to the design doc) | All guides, reports, evidence go there |
| Reviewers (product teams, peers) | Phase 7 |

## Workflow and gates

```
Phase 1  Options and open points  -> GATE 1: engineer confirms options + open points
Phase 2  Test matrix              -> GATE 2: engineer approves tests + pass criteria
Phase 3  Lab guide per option     -> GATE 3: engineer reviews guide before any spend
Phase 4  Access and guardrails    -> GATE 4: engineer confirms access, budget, teardown owner
Phase 5  Execute, keep evidence   -> scope changes only with engineer approval
Phase 6  Reports + gap analysis
Phase 7  Team review package      -> GATE 5: engineer decides what goes to the customer
Phase 8  State left behind        -> teardown only on explicit engineer instruction
```

At every gate: stop, summarize what you have, ask a short question. If the engineer is not present, do the preparatory work and stop at the gate. Do not spend money or touch shared infrastructure without the gate being passed. `ec2-launch` without `--yes` (a plan) is preparatory work; with `--yes` it is spend.

---

## Phase 1: options and open points

1. Read the whole design document. List every solution option with a one-line mechanism.
2. Extract open points as **questions a test can answer yes or no** ("Does a single-disk reset keep the partition?", not "validate robustness").
3. Where behaviour is undocumented, read the upstream source (clone the repo, `git log -S`, read the controller, not only the model). Mark every claim as **from docs**, **from source**, or **from lab**. A source reading is a hypothesis until a lab run confirms it.
4. Note versions explicitly (OS point release, tool versions). Results do not transfer across versions without a rerun.

**Gate 1 output:** options table + open points list, each with its source.

## Phase 2: test matrix

For each option, map every open point to at least one test. Use IDs `T0..Tn` per option.

Each test must have:
- **Purpose** (which open point it closes)
- **Steps** (CLI only, copy-paste)
- **Pass criteria** that are machine-checkable state, not screen text (state files compared with `state-compare`, parsers, exit codes)
- **Evidence to capture** (file names)

Always include:
- **T0 pre-flight**: layout, entries, content as designed, before any destructive step
- **Repeatability**: the operation twice in a row without restoring the baseline
- **Negative tests that must fail** (version skew, naive refresh, server down, too little RAM). A negative test that passes is a finding.
- **Failure-mode tests**: what happens when a dependency is unreachable
- **Limits**: measured floors (RAM, disk, time) with a bracket ("768 MB passes, 512 MB fails")
- **Security mode**: encryption / hardened variants the customer will use
- **Management plane**: the remote trigger through the customer's management tool, not only a local trigger
- Mark expensive tests **optional** so the engineer can skip them

**Gate 2 output:** a table `ID | open point | pass criteria | optional?` per option.

## Phase 3: lab guide per option

Start from `templates/lab-guide.md`, one file per option: `<option>-<platform>-lab-guide.md`. Read `references/pitfalls.md` and `references/recipes.md` before writing any command. Use harness scripts in the guide's commands instead of new helpers.

Before Gate 3, verify what can be verified locally:
- Run every generator script and parse its output (YAML/JSON parser, not eyes).
- Check that every command used inside a target exists there (P24).
- Pin versions and checksums of every downloaded artifact.

**Gate 3:** engineer reads the guide against the design doc. Keep this original file untouched as `<evidence>/<guide>.original.md` once execution starts.

## Phase 4: access and guardrails setup

Read `references/platform-aws-ec2-kvm.md`. Then:

Preparatory work (changes nothing; allowed before Gate 4):
1. `ec2-nested-check --region R [--family m8i]`: which types qualify now, and is the AWS CLI new enough. Do not rely on a remembered list.
2. Read-only checks of an existing host (`ec2-nested-check --instance ID`), and, for a new host, the plan: `ec2-launch --name N --type T --region R` (no `--yes`). Show the plan and price at Gate 4.

**Gate 4 comes next (confirm the points below).** Everything that changes a host or spends money happens only after it: `ec2-launch ... --yes`, `host-bootstrap` (it installs packages, changes group membership and removes the nginx default site, so it can alter a reused host), copying scripts, writing `lab.env`.

Confirm with the engineer, then record in the guide's status block:

- **Network:** inbound only from the engineer's IP (security group SSH /32). No public services.
- **Identity:** the engineer logs in (SSO etc.). The agent never creates accounts, never types passwords, never completes sign-up or admin-creation forms; the engineer does those and hands over a key **in a file** if needed.
- **Secrets:** credentials go in files under `$LAB_DIR/secrets/` (directory mode 700, files mode 600, each file holding just the value), referenced by path (`PASSFILE`, `--secrets`). They live in files so that `scrub-evidence --secrets` can search the evidence for every line of them; a secret that is not in a file cannot be scrubbed. Never paste them in a prompt: session logs keep every prompt verbatim. Never print them to the console or logs.
- **Lab-only shortcuts** (known password, NOPASSWD sudo, disabled host-key checks) are allowed only inside the lab network and must be listed in the report.
- **Spend:** never stop, terminate or delete cloud resources unless told to. Name the teardown owner. Track shared quotas (licences, subscription slots) and report usage.
- **Shared media and shared hosts:** no destructive cleanup flags while shared artifacts are attached (P10). Ask before deleting VMs or disks that are not the campaign's. Only `vm-create`, `vm-clone` and `vm-snap` enforce `VM_PREFIX`; `vm-ssh`, `vm-sudo`, `wait-ready`, `ro-inspect` and `labconsole.py` do not, so never run them against VMs outside the campaign.

**Gate 4:** access works (a read-only call succeeds), budget and teardown owner confirmed.

After Gate 4, in this order:
3. New host only: re-run the same `ec2-launch` command with `--yes`.
4. On the host `mkdir -p $LAB_DIR/bin`, then copy the contents of `scripts/kvm/` from the workstation into it (e.g. `scp design-doc-lab-validation/scripts/kvm/* host:lab/<campaign>/bin/`; a bare `scp -r .../kvm host:.../bin/` creates `bin/kvm/` when `bin` exists), then `chmod +x $LAB_DIR/bin/*` (exec bits may not survive an upload). `$LAB_DIR` is expanded by the local shell before scp/ssh sees it, and it is empty on the workstation, so a pasted `scp ... host:$LAB_DIR/bin` or `ssh host mkdir -p $LAB_DIR/bin` targets `/bin`. Do not paste it literally: for scp/rsync targets write the home-relative path (`host:lab/<campaign>/bin/`), and for commands run on the host put a remote-expanded path in single quotes (`ssh host 'mkdir -p ~/lab/<campaign>/bin'`). The same applies to the other `$LAB_DIR` commands in this phase when typed on the workstation; `$LAB_DIR` is only defined on the host after `env.sh` (step 8) is sourced there.
5. Run `$LAB_DIR/bin/host-bootstrap`.
6. Open a new SSH session: the libvirt group applies only to new logins.
7. `mkdir -p $LAB_DIR/secrets && chmod 700 $LAB_DIR/secrets`. Write `$LAB_DIR/lab.env` from `lab.env.example` with a campaign-unique `VM_PREFIX` (VM names must start with it). Check `MAX_RUNNING_GB`: unless lab.env or the environment sets it, the default is derived from host RAM (RAM in GiB minus 6, minus 2 on hosts of 8 GiB or less, floor 4); set it in lab.env when the plan needs another value. The guard counts only running guests and is bypassed by `virsh start` of a stopped VM, so shut guests down after their test.
8. Write `$LAB_DIR/env.sh` (the campaign name replaces `<campaign>`):
   ```bash
   LAB_DIR=$HOME/lab/<campaign>
   set -a; . "$LAB_DIR/lab.env"; set +a      # exports LAB_DIR etc. (labconsole.py ignores lab.env: it needs EVID or LAB_DIR in the environment)
   export LAB_ENV=$LAB_DIR/lab.env PATH=$LAB_DIR/bin:$PATH
   ```
   Separate non-interactive `ssh` calls do not share an environment, so **every ssh call to the host starts with `. ~/lab/<campaign>/env.sh;`** (for example `ssh host '. ~/lab/<campaign>/env.sh; env-dump'`). Then run `env-dump`.

## Phase 5: execute and keep evidence

### Working rules

- Run tests in guide order or in parallel (if asked to). Restore the baseline (`vm-snap restore`) where the guide says so; re-plant markers before every destructive step (a marker deleted by the first run proves nothing on the second).
- **The first run verifies the guide.** When a step is wrong, fix the guide in place and tag it `🔧 CORRECTED (Gn)` with a row in the corrections log (where, what was wrong, evidence, fix). Tag measured behaviour `📝 LAB FINDING`. Distinguish guide defects from product defects.
- When something fails, explain it before retrying: logs first, then `references/pitfalls.md`, then upstream source. Record the source excerpt in the evidence.
- Ask before changing scope (new test, skipping a test, different image). The engineer may also stop a measurement early; record that as the reason.

### Evidence rules

- Every claim in the report cites a file in the evidence bundle.
- Console logs: keep raw `.log` and ANSI-stripped `.txt` (`labconsole.py` writes both).
- **Unique log name per run**; never overwrite (P21).
- `vm-create` prints the serial log path (`/var/log/libvirt/qemu/<name>-<epoch>.serial.log`, readable by root only). After each boot or failure, copy it into `$EVID/logs/` with `sudo cp`.
- Keep the files actually served (configs, autoinstall, scripts), state dumps, source excerpts, screenshots of failures, `environment.txt` (`env-dump`).

```
<option>-testing-evidence/
  environment.txt
  <guide>.original.md
  logs/            raw .log + clean .txt, one per run
  scripts/         drivers and helpers exactly as run
  deploy-server/   files actually served
  state/           key=value state files, partition tables, disk dumps
  timing/          timestamps written by vm-create and wait-ready
  source-excerpts/
  screenshots/
```
On the host, `$EVID` defaults to `$LAB_DIR/evidence`; the folder is renamed `<option>-testing-evidence/` when copied back.

### Reliability rules

| Rule | Tool | Pitfall |
|---|---|---|
| Judge success by state on disk (stamps, markers, checksums), never by console text | state files, `state-compare`, `ro-inspect` | P8 |
| Read back an interactive choice before confirming it | `labconsole.py grub` | P9 |
| Every wait has a timeout and a heartbeat; report progress when a step runs long; zero load means investigate | `wait-ready` | P20 |
| Validate generated files with a parser before booting anything | parsers | |
| Files served to guests (autoinstall user-data, seeds) must be readable by the web server: mode 644, not 600 | `host-bootstrap` creates the deploy site | P3 |
| Kill background processes from earlier runs before starting | `proc-kill` | P6 |
| Read disks read-only to inspect a machine you cannot reach (commands are `-`-prefixed so one failure does not abort) | `ro-inspect` | P22 |
| Probe the guest IP; never trust the first lease | `vm-ip` | P7 |
| Never let ssh in a script read the script | `</dev/null` | P5 |
| Respect the host's memory; shut guests down after their test | `vm-create` guard | P11 |
| Check tool availability inside the target image | | P24 |
| Prefer the image's own tools to new custom scripts | | engineer's preference |

### Long sessions

Keep `lab-progress.md` (from `templates/lab-progress.md`) in the output folder and update it after every test. If the session runs out of context or the host restarts (new public IP), resume from that file, not from memory.

## Phase 6: reports and gap analysis

Start from `templates/report.md`: one `<option>-testing.report.md` when the campaign completes, before stopping anything. Its sections: summary table and conclusions, not covered, environment, results in detail, mistakes in the original guide, what I got wrong, limitations, state left behind, gap analysis, pros/cons and decision guide.

Before any evidence leaves the host: `env-dump`, then `scrub-evidence --fix "$EVID"` (P23: reports can embed `/etc/shadow` hashes); it must end clean. Then re-scan the workstation copy with `scrub-evidence --secrets <copy of the host's secrets dir> <local copy>`. Without `--secrets` (and without a secrets dir in `lab.env`) the tool checks only hashes and private keys (public keys only with `--pubkey`), and a re-scan without `--secrets` ends with `(secrets not checked)`. See `references/recipes.md`, "Copy evidence back and scrub it".

Gap analysis: one row per place the design and the lab disagree (`Design assumption | Lab result | Impact`). Then a lab-corrected copy of the design doc (keep reviewers' comments; mark source-only vs lab-confirmed claims), and pros and cons per option, a comparison, and a decision guide.

## Phase 7 and 8

Phase 7: hand the engineer the report, the gap table, the corrected design doc and a review checklist; the engineer decides what goes to the customer (Gate 5). Phase 8: list what is left running and costing money, credentials on hosts, quota usage, and the teardown commands not run. In "What I got wrong", list candidate new pitfalls or harness fixes; do not edit this skill. The engineer updates it.

## Quick checklist

- [ ] Options and yes/no open points confirmed (Gate 1)
- [ ] Test matrix with pass criteria and negative tests approved (Gate 2)
- [ ] Guide from the template, pitfalls read, generators parsed, original saved (Gate 3)
- [ ] `ec2-nested-check` run; access, IP restriction, secrets in files, budget, teardown owner confirmed (Gate 4)
- [ ] Harness on the host, `lab.env` with a campaign prefix, `env-dump` taken
- [ ] Corrections tagged in place, evidence per claim, unique logs, progress file kept
- [ ] `scrub-evidence` clean; report with Not covered, own mistakes, state left behind
- [ ] Gap table delivered; review checklist handed over (Gate 5)
- [ ] Nothing torn down without instruction; secrets reminder given
