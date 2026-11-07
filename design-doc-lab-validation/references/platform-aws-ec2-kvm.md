# Platform: AWS EC2 host + nested KVM/libvirt guests

Read at Phase 4 (access and guardrails). Facts carry a provenance tag. A `[lab ...]` fact was measured; an `[AWS docs]` fact was not. **Re-check anything that decides spend** with `scripts/kvm/ec2-nested-check`.

## Nested virtualization on EC2

| Fact | Provenance |
|---|---|
| `m8i.2xlarge` (8 vCPU, 32 GB) runs nested KVM: build VM + about 4 guests of 4 GB | [lab 2026-10, recovery-partition A/B, golden image, TPM FDE] |
| Nested virtualization confirmed on `m8i.4xlarge` too; used for Desktop-ISO installs (more RAM for the live session) | [lab 2026-10, recovery-partition B desktop] |
| Launch flag: `aws ec2 run-instances ... --cpu-options "NestedVirtualization=enabled"` | [lab 2026-10] |
| A running instance then reports `CpuOptions = {CoreCount 4, ThreadsPerCore 2, NestedVirtualization "enabled"}` (m8i.2xlarge) | [lab 2026-10] |
| On an existing instance: stop it, then `aws ec2 modify-instance-cpu-options --region R --instance-id ID --core-count <C> --threads-per-core 2 --nested-virtualization enabled`, then start | [lab 2026-10, recovery-partition A guide 1.3] |
| Core count `<C>` = vCPUs / 2: m8i.2xlarge 4 (matches the `CoreCount 4` reported above); m8i.4xlarge 8 (derived: vCPUs / 2, not measured) | derived |
| Inside the host: `grep -cw vmx /proc/cpuinfo` > 0 and `kvm-ok` says "KVM acceleration can be used" | [lab 2026-10] |
| The AWS CLI must be recent enough to know `CpuOptions.NestedVirtualization` (older v2 builds reject the shorthand) | [lab 2026-10] |
| Which types support it is reported by `aws ec2 describe-instance-types --filters Name=processor-info.supported-features,Values=nested-virtualization`. **Do not rely on a remembered list**: run `ec2-nested-check --region R` | [AWS docs] |

Lab note (2026-11): `ec2-nested-check --region us-east-1` reported 166 instance types with the nested-virtualization feature, in the families c7i, c7i-flex, c8i, c8i-flex, c8id, i7i, i7ie, m7i, m7i-flex, m8i, m8i-flex, m8id, r7i, r7iz, r8i, r8i-flex, r8id and x8i. Only `m8i` types were verified in a lab; for every other family the feature flag is all we know, so confirm with a small launch before relying on it. A fresh `ec2-launch` host `m8i.large` (2 vCPU / 8 GiB) ran nested KVM guests: the reduced smoke booted a 4 GiB guest in about 17 s (ssh ready). The fresh-host smoke was run with `MAX_RUNNING_GB=6` set by hand for that run, not recorded in the evidence; with the derived default (see Sizing) an 8 GiB host gets RAM minus 2 GiB in whole GiB (a host reporting 7.6 GiB gets 5), and any value from 4 to 7 works for one 4 GiB guest. The Canonical 26.04 AMI parameter below resolved to Ubuntu 26.04. [lab 2026-11, harness verification]

Commands:
```bash
ec2-nested-check --region us-east-1 --family m8i     # what qualifies, and is the CLI new enough?
ec2-launch --name <lab> --type m8i.2xlarge --region us-east-1          # plan only
ec2-launch --name <lab> --type m8i.2xlarge --region us-east-1 --yes    # after Gate 4
ec2-nested-check --region us-east-1 --instance <id>  # enabled on the launched host?
```

## Launch baseline

- AMI: Ubuntu 26.04 from SSM `/aws/service/canonical/ubuntu/server/26.04/stable/current/amd64/hvm/ebs-gp3/ami-id`. [lab 2026-10]
- Root volume: 200 GB gp3 is enough for 2 to 3 campaigns. Full qcow2 copies cost their real size; overlays are small. Check `df -h /` before each campaign; the golden-image campaign needed about 60 GB. [lab 2026-10, golden image]
- Security group: tcp/22 from the engineer's /32 only. If the engineer's IP changes, update the rule. [lab 2026-10]
- **The public IP changes after a stop/start.** Re-read it (`aws ec2 describe-instances`) and update `instance-*.env` and `~/.ssh/config`. [lab 2026-10, golden image]
- `ec2-launch` never stops or terminates.
- `ec2-launch` prints the AMI id in its plan. With `--yes` it refuses to run when `./instance-<NAME>.env` already exists or a non-terminated instance with that Name tag exists, and it never overwrites an existing `~/.ssh/<key>.pem`.

## Sizing on the host

- Sum of guest RAM ≤ host RAM minus about 6 GB. On 32 GB that means at most 4 guests of 4 GB plus one 8 GB build VM. Nine 4 GB guests got one OOM-killed. `vm-create` enforces `MAX_RUNNING_GB`. [lab 2026-10, golden image]
- `MAX_RUNNING_GB` default (when neither lab.env nor the environment sets it): `MemTotal` from `/proc/meminfo` in whole GiB, minus 6 when above 8 GiB, minus 2 at 8 GiB or less, floor 4; 24 if `/proc/meminfo` cannot be read. `MemTotal` is a little below the nominal RAM and is rounded down, so a nominal 32 GiB host may get 25 instead of 26. Check the value at Phase 4 and set it in lab.env if the plan needs another. The derived default is not monotonic for small hosts (a host reporting 8 GiB gets 6, hosts reporting 9 or 10 GiB get 4 because of the floor), so set it explicitly there. [derived; offline-tested]
- The guard counts only **running** guests, and only when `vm-create`/`vm-clone` start one. `virsh start` of a stopped VM bypasses it: shut guests down after their test and do not start many stopped VMs at once (P11).
- A guest sees about 900 MiB less RAM than configured (firmware and kernel reservations). Keep that in mind for RAM-floor tests. [lab 2026-10, recovery-partition B desktop]
- A container with a large stack (e.g. Landscape) needs ≥ 10 GiB. [lab 2026-10, recovery-partition B]

## Host software facts (Ubuntu 26.04 host)

- QEMU 10.2, libvirt 12.0, virt-install 5.1, OVMF `2025.11` (4M images under `/usr/share/OVMF/`). [lab 2026-10, golden image]
- **Explicit loader required:** with `--boot firmware=efi`, libvirt auto-selects `OVMF.amdsev.fd` and AppArmor rejects it. Use `loader=/usr/share/OVMF/OVMF_CODE_4M.fd,...,nvram.template=/usr/share/OVMF/OVMF_VARS_4M.fd` (vm-create does). The Secure Boot variant (`firmware.feature0.name=secure-boot` + enrolled keys + `smm.state=on`) auto-selects correctly. [lab 2026-10, recovery-partition B; golden image]
- virt-install adds an emulated TPM by default on UEFI guests; pass `--tpm none` when the test must not have one (vm-create does unless `TPM=yes`). [lab 2026-10, golden image]
- QEMU emulates VMware `pvscsi` and `vmxnet3`, but **OVMF cannot boot from PVSCSI**. Use a virtio-scsi boot disk and, if needed, a PVSCSI data disk (`PVDATA=yes`). [lab 2026-10, golden image]
- `/var/lib/libvirt/images` is mode 711: a non-root `ls`, glob or `genisoimage -output` there fails silently or with "Permission denied". Use `sudo`. [lab 2026-10, golden image]
- libguestfs needs a readable host kernel: `sudo chmod 0644 /boot/vmlinuz-*` (host-bootstrap does). [lab 2026-10]
- libvirt's `default` network is 192.168.122.0/24 with dnsmasq. The nginx deploy server is reachable from guests at `http://192.168.122.1/`. [lab 2026-10]

## Cost and hygiene

- Stop the instance between sessions only when the teardown owner says so; a stopped instance still costs for its volume. [AWS docs]
- Name a teardown owner at Gate 4. Record every subscription/licence attachment (e.g. Ubuntu Pro) and detach before teardown.
- Before the first campaign on a reused host: list old VMs (`virsh list --all`) and old disks (`sudo du -h /var/lib/libvirt/images/*`). Ask before deleting anything that is not yours.
