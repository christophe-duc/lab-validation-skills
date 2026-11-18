# lab-validation-skills

Skills for agent-run lab validation. Main skill: `design-doc-lab-validation/` (workflow, gates, guardrails) with its harness: `references/` (EC2 nested virtualization, pitfalls, recipes), `scripts/kvm/` (tested helpers for KVM/libvirt lab hosts) and `templates/`.

## Workflow

The skill will take a test plan, a design, a proposed architecture (preferably in MD format) and will execute tests to confirm if the document is working as intended or what are the corrections needed to the document. The skill will keep evidence of everything that has been run and tested and will write a lab-test report at the end of the run.

At the start of the run, the skill should ask the following to confirm what it will run:
Gate1: open points, any questions related to the document the agent has read
Gate2: approval of the test matrix, agent will propose tests, review them, change them if needed and approve them
Gate3: read the pitfalls, templates, versions to use
Gate4: Check pricing on what it needs and who is responsible for tearing down the lab environment

At the end, it will produce the lab-report and corrections to the original document (every change is well marked)

## How to install
```bash
./install.sh                # opencode symlink + dist/design-doc-lab-validation.zip
./install.sh --copy         # if opencode does not follow the symlink
```
Claude desktop: upload `dist/design-doc-lab-validation.zip` in the skill settings, and re-upload it after every update to the skill. Never edit `~/.claude/skills/synced/` by hand.

Until the zip is uploaded and synced, `~/.claude/skills/synced/*/design-doc-lab-validation/` holds an older copy. opencode also scans `~/.claude/skills`, so it sees two skills with the same name and keeps one of them. Which one it keeps varied between runs of `opencode debug skill` (it is not tied to the directory), so opencode may load the stale synced copy. Because opencode picks between the repo copy and the stale synced copy non-deterministically (observed stale in 7 of 20 repeat runs, 8 of 32 overall, about a quarter), a single run proves nothing: run the loop above (about 10 times; each run prints one `location` line). Treat the install as verified only when every run shows the repo path (`~/.config/opencode/skills/...`) or when the synced copy has been updated by uploading the zip. If a location under `~/.claude/skills/synced/` appears, the zip has not synced yet: upload or re-upload `dist/design-doc-lab-validation.zip` in Claude's skill settings. See `tests/results/2026-11-06/install.md`.

## Test
```bash
bash tests/offline/run.sh                                   # Mac, no lab needed
bash tests/lint.sh                                          # shellcheck + py_compile
# on a lab host (see the header of tests/smoke-kvm.sh):
tests/smoke-kvm.sh [--reduced] <cloud-image: .img/.qcow2/.vmdk path or https URL of a .img>
```
Results of verification runs: `tests/results/<date>/`.

## Updating
Updates are manual. Campaign reports list candidate pitfalls and harness fixes under "What I got wrong"; add the ones worth keeping to `references/pitfalls.md` (with the campaign name, never a customer name) and the scripts, add a test, run the offline tests, then commit.

## Before pushing
```bash
design-doc-lab-validation/scripts/kvm/scrub-evidence --secrets <dir with secret files> .
grep -rniE '<customer names>' . --exclude-dir=.git
```
