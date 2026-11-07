# Recipes (proven command blocks)

Read when writing Part 1 of a lab guide. These are blocks that worked in past campaigns but are too situation-specific to be scripts. `$IMG`, `$EVID` and `$DEPLOY` come from `lab.env`.

**Setup for these blocks** (the scripts apply their defaults inside their own processes only, so the variables are not set in your shell until you do this; `LAB_DIR` is the campaign directory and must be defined first, because lab.env is found through it):

```bash
LAB_DIR=$HOME/lab/<campaign>
set -a; . "$LAB_DIR/lab.env"; set +a
export LAB_ENV=$LAB_DIR/lab.env PATH=$LAB_DIR/bin:$PATH
: "${IMG:=/var/lib/libvirt/images}" "${EVID:=$LAB_DIR/evidence}" "${DEPLOY:=http://192.168.122.1}"
```
Separate non-interactive `ssh` calls to the host do not share an environment: start every call with this block, or put its first three lines in `$LAB_DIR/env.sh` and begin each call with `. ~/lab/<campaign>/env.sh;`. `labconsole.py` ignores lab.env; it finds the evidence directory through `EVID` or `LAB_DIR` in the environment, which the `set -a` line provides.
The multi-line blocks below that contain `exit 1` are meant to be saved and run as scripts (an `exit` in an interactive shell closes it).

`$DOM` and `$NAME` are the VM name. VM names must start with `VM_PREFIX` from `lab.env`: `vm-create`, `vm-clone` and `vm-snap` refuse other names. The example names `gi-build`, `gi-c1` and `hx-sb` assume a matching prefix. `vm-ssh`, `vm-sudo`, `wait-ready`, `ro-inspect` and `labconsole.py` do not check the prefix: never run them against VMs outside the campaign.

## Autoinstall over HTTP and wait for power-off

```bash
D=/var/www/deploy/iso/$VER
vm-create gi-build --size 40 --cdrom $D/ubuntu-$VER-live-server-amd64.iso \
  --kernel $D/casper/vmlinuz --initrd $D/casper/initrd \
  --args "autoinstall ds=nocloud-net;s=$DEPLOY/<path>/ console=tty0 console=ttyS0"
for i in $(seq 1 120); do                  # bounded: 120 x 30 s = 60 min
  [ "$(virsh domstate gi-build)" = "shut off" ] && break
  virsh domstats gi-build --block | grep -E 'block.0.wr.bytes'; sleep 30; done   # heartbeat
[ "$(virsh domstate gi-build)" = "shut off" ] || { echo "install timed out"; exit 1; }
CD=$(virsh domblklist gi-build --details | awk '$2=="cdrom"{print $3}')
virsh change-media gi-build "$CD" --eject --config
```
Validate `user-data` with a YAML parser (and the subiquity schema) before booting. Serve it with mode 644 (pitfall P3). Use `shutdown: poweroff` in the autoinstall. `--args` must not contain commas (use `console=ttyS0`, not `ttyS0,115200`).

## ISO with pinned sha256, casper kernel and initrd

```bash
D=/var/www/deploy/iso/$VER; mkdir -p $D/casper; cd $D
curl -fLO -C - https://releases.ubuntu.com/$VER/ubuntu-$VER-live-server-amd64.iso
echo "<sha256>  ubuntu-$VER-live-server-amd64.iso" | sha256sum -c -     # pin the hash in the guide
sudo mount -o loop,ro ubuntu-$VER-live-server-amd64.iso /mnt
cp /mnt/casper/vmlinuz /mnt/casper/initrd casper/; sudo umount /mnt
```
For cloud images: `curl -fLO .../SHA256SUMS` from the same directory, then `grep " \*\?<file>$" SHA256SUMS | sha256sum -c -`.

## NoCloud seed ISO (maintenance boots without adding a default user)

```bash
T=$(mktemp -d)
printf 'instance-id: %s-%s\nlocal-hostname: %s\n' "$NAME" "$(date +%s)" "$NAME" > $T/meta-data
printf '#cloud-config\nusers: []\n' > $T/user-data      # or a real user-data file
genisoimage -quiet -output $T.iso -volid cidata -joliet -rock $T
sudo cp $T.iso $IMG/$NAME-seed.iso && sudo chmod 600 $IMG/$NAME-seed.iso; rm -rf $T $T.iso
```

## VMware-like guest hardware

```bash
NIC_MODEL=vmxnet3 PVDATA=yes vm-clone gi-c1 $IMG/template.qcow2 $IMG/gi-c1-ovfenv.iso
```
A `NIC_MODEL` set in lab.env wins over the one on the command line, so leave it out of lab.env when you override it per call. The boot disk stays virtio-scsi (P2). ESXi names the NIC `ens192`; match `en*` in netplan to stay portable.

## Secure Boot and TPM

```bash
SB=yes TPM=yes vm-clone hx-sb $IMG/base.qcow2 $IMG/seed.iso
vm-ssh hx-sb 'od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c | awk "{print \$NF}"; ls /dev/tpm0'
# 1 = Secure Boot enabled
```
`vm-snap` saves the swtpm state with the disk and NVRAM. Restoring only the disk breaks TPM-sealed secrets. swtpm snapshot/restore is untested live (the smoke run snapshots a VM without a TPM).

A failed `vm-snap snap` can leave a partial snapshot directory (`$LAB_DIR/snaps/<vm>/<name>/`) without a `SHA256` file; names are never overwritten, so remove that directory by hand before retrying.

## Generalize in one session (cloud-init clean)

```bash
vm-sudo $DOM '
pro detach --assume-yes 2>/dev/null || true
cloud-init clean --logs --machine-id --seed --configs all
rm -f /etc/ssh/ssh_host_*            # LAST: sshd refuses new sessions after this (P4)
echo @@AFTER@@; ls /etc/cloud/cloud.cfg.d /etc/netplan; cat /etc/machine-id
systemctl poweroff --no-block' > $EVID/state/generalize.txt
```

## Read a disk you cannot reach

```bash
virsh shutdown $DOM    # consistent view
for i in $(seq 1 60); do [ "$(virsh domstate $DOM)" = "shut off" ] && break; sleep 5; done
[ "$(virsh domstate $DOM)" = "shut off" ] || { echo "$DOM did not shut off"; exit 1; }
printf 'cat /etc/machine-id\nls /etc/netplan\nglob ls /etc/ssh/ssh_host_*\ntail-n 20 /var/log/cloud-init.log\n' > /tmp/cmds
ro-inspect $IMG/$DOM.qcow2 /tmp/cmds | tee $EVID/state/$DOM-disk.txt
```
Alternative with block devices: `sudo qemu-nbd -r -c /dev/nbd0 disk.qcow2; sudo mount -o ro,noload /dev/nbd0p2 /mnt`.

## Memory dump and grep (where did a secret end up?)

```bash
virsh dump $DOM /tmp/$DOM.mem --memory-only --format raw
strings -n 8 /tmp/$DOM.mem | grep -c "<marker>"; rm -f /tmp/$DOM.mem
```
Never grep for a real secret on the command line: grep with `-f <file>`.

## Long job inside a guest that must survive SSH drops

Put the job in a script and run that, which avoids nested quoting:

```bash
vm-ssh $DOM 'cat > lab-job.sh' < ./lab-job.sh        # stdin is intentionally fed; vm-ssh passes it through
vm-sudo $DOM 'install -m 700 /home/<user>/lab-job.sh /root/lab-job.sh' </dev/null
vm-sudo $DOM 'rm -f /root/lab-job.log' </dev/null          # a stale EXIT=0 from a previous run must never count
vm-sudo $DOM 'systemd-run --collect --unit=lab-job --property=StandardOutput=file:/root/lab-job.log sh -c "/root/lab-job.sh; rc=\$?; echo EXIT=\$rc; exit \$rc"' </dev/null
for i in $(seq 1 240); do                  # bounded: 240 x 60 s = 4 h; adjust to the job
  [ "$(vm-sudo $DOM 'systemctl is-active lab-job' </dev/null)" = active ] || break
  vm-sudo $DOM 'tail -1 /root/lab-job.log' </dev/null; sleep 60; done
[ "$(vm-sudo $DOM 'systemctl is-active lab-job' </dev/null)" != active ] || { echo "loop timed out, job still running"; return 1 2>/dev/null || exit 1; }
vm-sudo $DOM 'tail -3 /root/lab-job.log' </dev/null
```
The `return 1 2>/dev/null || exit 1` guard: `return` works when sourced or inside a function; pasted at an interactive prompt it still exits the shell.

Quoting: `vm-sudo` writes its single argument verbatim to a script on the guest and runs it with bash. In the single-quoted argument `\$` stays a literal backslash-dollar; inside the guest script's double quotes bash turns `\$rc` into a literal `$rc`, which `sh -c` then expands when the job ends.

Success is decided only by the final line of `/root/lab-job.log` being `EXIT=0` (the wrapper's `echo EXIT=$rc` is the last line written when the wrapper completes; a killed unit or a guest reboot writes no EXIT line, which counts as not successful; `<user>` in `/home/<user>` is `VM_USER`, or `LAB_USER` from lab.env). With `--collect` the unit disappears when it ends, success or failure, so the log is the only authority. `systemctl show` on a collected unit prints `ActiveState=inactive`, `Result=success` and `ExecMainStatus=0` whatever happened, so it must not be consulted for the outcome; `systemctl is-active` in the loop only rules out "still running". A dropped ssh also ends the loop, so that must not be read as "job finished": re-check with `vm-ip $DOM`, then read the log. No final `EXIT=0` line means the job did not complete successfully or its state is unknown; reconnect and look again.

## Boot logs

`vm-create` (and so `vm-clone`) prints the serial log path, `/var/log/libvirt/qemu/<name>-<epoch>.serial.log`, readable by root only. Copy it into the evidence after each boot or failure, so a later run cannot lose it (P21):

```bash
sudo cp /var/log/libvirt/qemu/<name>-<epoch>.serial.log "$EVID/logs/" && sudo chown "$USER" "$EVID/logs/"*.serial.log
```

## Copy evidence back and scrub it

Step (a), on the lab host, with the campaign's `$SECRETS`:

```bash
env-dump <artifacts...>
scrub-evidence --fix "$EVID"
```
Exit 0 = clean, exit 1 = hits remain or the scan was incomplete, exit 2 = usage. Step (a) must print the plain `is clean`. If it prints `is clean of hashes and private keys (secrets not checked)`, the secrets dir was not found: set `LAB_DIR` or `LAB_ENV` (or pass `--secrets <dir>`) and run it again. On exit 1, stop, remove the hits by hand, and re-run. Do not continue until it prints the plain `is clean`.

Step (b), on the workstation, only after (a) printed `is clean`:

```bash
rsync -a <host>:lab/<campaign>/evidence/ <campaign>-testing-evidence/
scrub-evidence --secrets <dir of secret files> <campaign>-testing-evidence/
```
The second scan checks the local copy; it must also print the plain `is clean`. `<dir of secret files>` is a copy of the host's `$SECRETS` directory (take it from the engineer's own record, not from the evidence bundle), including dotfiles and subdirectories; each line of each file is one search string, so a secret file should hold just the value. Without it the scan checks only hashes and private keys, prints a `note:` and ends with `is clean of hashes and private keys (secrets not checked)`.

Known limit: symlinks inside the evidence dir are not followed (`grep -R`, which would follow them, is not portable to macOS BSD grep), so a link to a file outside the bundle is not scanned. Replace any symlink in the bundle with a copy of its target before scanning. A dangling link in the secrets dir is different: it ends the scan incomplete (exit 1).

`--fix` redacts only crypt(3) password hashes. Secrets, private keys and public keys it reports must be removed by hand. Public keys are checked only when given with `--pubkey FILE`.
