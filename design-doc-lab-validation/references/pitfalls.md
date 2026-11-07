# Pitfalls seen in past lab campaigns

Read before writing guide commands (Phase 3) and whenever a step fails oddly. Each row is one real incident. "Prevented by" names the harness script that makes it impossible or visible.

| # | Symptom | Cause | Fix | Prevented by | Seen in |
|---|---|---|---|---|---|
| P1 | `virt-install` fails: "cannot load AppArmor profile" | `firmware=efi` auto-selects the AMD SEV firmware | explicit `loader=` / `nvram.template=` | `vm-create` | recovery-partition B |
| P2 | Install on PVSCSI works, first boot falls to PXE ("failed to load Boot0002 ... Not Found") | OVMF has no PVSCSI boot driver | virtio-scsi boot disk; PVSCSI only as data disk | `vm-create` defaults, `PVDATA=yes` | golden image |
| P3 | Autoinstall never starts; nginx log shows 403 for `user-data` | file mode 600, nginx runs as www-data | 644 (or 640 group www-data); the file holds only hashes | host-bootstrap note | recovery-partition B, golden image |
| P4 | SSH "Connection reset" right after generalizing; next command and poweroff never run | `rm /etc/ssh/ssh_host_*` makes sshd refuse new sessions | remove host keys **last**, in the same session, then `systemctl poweroff --no-block` | recipe "generalize in one session" | golden image |
| P5 | A driver script stops halfway, silently | `ssh` inside `bash -s` / a heredoc read the rest of the script from stdin | `</dev/null` on every ssh that is not meant to read stdin | `vm-ssh` doc, all harness scripts | golden image |
| P6 | The command that should kill stray drivers kills its own shell | `pkill -f PATTERN` matches the `bash -c` / ssh command line containing PATTERN | `proc-kill PATTERN` (or the `[p]attern` trick) | `proc-kill` | four campaigns |
| P7 | SSH to the "VM IP" hangs or reaches the wrong machine | libvirt keeps stale leases; two clones with the same machine-id share one lease | probe each candidate on port 22 | `vm-ip` | recovery-partition A/B, golden image |
| P8 | A test reads "success" although the VM never rebooted | old login prompt still in the console buffer | drain before expect; judge by state on disk | `labconsole.py`, state files | recovery-partition B |
| P9 | Enter pressed on the wrong boot entry | menu choice not read back | read the highlighted entry before Enter | `labconsole.py grub` | recovery-partition A |
| P10 | A shared ISO disappeared | `virsh undefine --remove-all-storage` removes attached CD-ROM images too | never use it while shared media are attached; remove disks by path | (rule) | TPM FDE |
| P11 | A guest dies with "shutting down, reason=crashed" | host OOM: too many guests | respect `MAX_RUNNING_GB`; shut guests down after their test. The guard counts only running guests and is bypassed by `virsh start` of stopped VMs | `vm-create` guard (creation only) | golden image |
| P12 | `guestfish` cannot launch | host kernel not readable | `chmod 0644 /boot/vmlinuz-*` | `host-bootstrap` | golden image |
| P13 | `findmnt -lo ... /tmp /var ...` prints nothing, rc 1 | findmnt takes one target | loop over mounts | (rule) | golden image |
| P14 | A changed default in an env file has no effect | `${VAR:-default}` keeps the value already exported in the shell | start a new shell or `unset VAR` after editing | (rule) | golden image |
| P15 | Helper scripts broken by quoting; `sed -i` fails on the Mac | nested heredocs/escaping; BSD sed needs `-i ''` | write helpers as files, copy them over; use perl `-pi -e` | harness scripts are files | recovery-partition A |
| P16 | `sudo: a terminal is required` | no NOPASSWD and no password channel | `vm-sudo` with `PASSFILE` (sudo -S from a 600 file) | `vm-sudo` | recovery-partition B |
| P17 | `grub.cfg` unreadable by the test user | mode 0400 | read through sudo | `vm-sudo` | recovery-partition A |
| P18 | `ci_status` is `degraded done` on every guest | `open-vm-tools` in the image calls `vmware-rpctool` on a non-VMware hypervisor | accept it when `errors` is empty; do not gate on `done` outside ESXi | (rule) | golden image |
| P19 | `ls`, globs, `sha256sum $IMG/*`, `genisoimage -output $IMG/x.iso` fail as the normal user | `/var/lib/libvirt/images` is 711 | `sudo sh -c '...'`, build in /tmp then `sudo cp` | all harness scripts | golden image |
| P20 | A wait loop sat for 20 minutes on a VM that could never get an IP | no timeout, no heartbeat | timeout + heartbeat (CPU time, disk writes, request log) | `wait-ready` | recovery-partition A |
| P21 | A rerun destroyed the raw capture of the first failure | same log name reused | unique log name per run. `vm-create` prints the serial log path (`/var/log/libvirt/qemu/<name>-<epoch>.serial.log`, root-readable): `sudo cp` it into `$EVID/logs/` after each boot or failure | `vm-create` serial names, `labconsole.py` | a previous campaign |
| P22 | guestfish script aborts at the first missing file | failing command ends the script | prefix commands with `-`; `tail-n N F` not `tail -n` | `ro-inspect` | golden image |
| P23 | Evidence bundle contained `/etc/shadow` hashes (USG HTML report) | compliance reports embed file content | scan and redact before delivery. `scrub-evidence --fix` redacts only crypt(3) password hashes; secrets, keys and pubkeys it finds must be removed by hand, and the tool exits 1 while any hit remains | `scrub-evidence --fix` | golden image |
| P24 | `curl` missing in the target live image | tool assumed present | check tools inside the target before writing steps | (rule) | recovery-partition B desktop |
