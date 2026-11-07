# <Option>: lab test report

**Date:** <date>. **Lab:** <platform, instance id, region>. **Guide:** `<guide>.md` (corrected in place; original in the evidence folder). **Evidence:** `<evidence folder>/`. Each test ran <once>. The engineer owns the verdicts; this report records what the lab measured.

## 1. Summary

| Test | Description | Result |
|---|---|---|
| T0 | Pre-flight | <PASS / FAIL AS WRITTEN / PASS AFTER FIX / FAILS AS EXPECTED / RECORDED / NOT RUN / INCONCLUSIVE> |

### Main conclusions
1. <One finding per item, each backed by an evidence path in section 4.>

## 2. Not covered
- <What this lab cannot show, and where it must be checked (Part 3 of the guide).>

## 3. Environment
| Item | Value |
|---|---|
| Host | <type, OS, QEMU/libvirt/OVMF versions (environment.txt)> |
| Guest | <image, sha256, key package versions> |
| Lab-only shortcuts | <known password, host-key checks off, ...> |

## 4. Results in detail
- **T0:** <result>. Evidence: `<path>`.

## 5. Mistakes in the original guide
<Corrections table (G1..Gn) is at the top of the guide. Summary here.>

**Checked and found correct:** <list>

## 6. What I got wrong along the way
- <The agent's own mistakes, separate from lab results.>
- <Candidate new pitfalls or harness fixes for the skill (the engineer decides whether to add them).>

## 7. Limitations
<Single run per test; VMs not hardware; versions tested; network conditions.>

## 8. State left behind
- **Running and costing money:** <instances, VMs>
- **Credentials on hosts:** <files, paths>
- **Subscriptions / quotas:** <what is still attached>
- **Teardown commands not run:** <commands>

## 9. Gap analysis
| Design assumption | Lab result | Impact |
|---|---|---|
| <...> | <...> | <...> |

## 10. Pros and cons, comparison, decision guide
| | <Option 1> | <Option 2> |
|---|---|---|
| <criterion> | <...> | <...> |

**Decision guide (for the engineer):** <...>
