#!/usr/bin/env python3
"""labconsole.py: drive a libvirt serial console (virsh console) with pexpect.

Library:  sys.path.insert(0, "<bin>"); from labconsole import Console, strip_ansi, highlighted_grub
CLI:      labconsole.py capture DOM NAME [--seconds N] [--enter]
          labconsole.py expect  DOM NAME REGEX [--timeout S] [--enter]
          labconsole.py grub    DOM NAME TITLE [--max-downs N]
Logs:     $EVID/logs/console-NAME-<epoch>.log (raw) and .txt (ANSI stripped).
Env:      does not read lab.env. It needs EVID (or LAB_DIR, giving $LAB_DIR/evidence) in the
          environment: `set -a; . "$LAB_DIR/lab.env"; set +a` before running it. Without
          either it writes to ~/lab/evidence/logs. It does not check VM_PREFIX.
Exit:     0 ok, 1 not found / timeout, 2 usage.

Rules enforced: drain() runs before every expect, so text already in the buffer (an old login
prompt) never counts as success; a menu entry is read back before Enter is sent.
pexpect is needed only for Console (python3-pexpect on the lab host).
"""
import argparse
import os
import re
import sys
import time

ANSI = re.compile(r"\x1b\[[0-9;:<=>?]*[A-Za-z]|\x1b[()][A-Z0-9]|\x1b[=>]")


def strip_ansi(text):
    """Remove ANSI escape sequences and carriage returns."""
    return ANSI.sub("", text).replace("\r", "")


def highlighted_grub(screen):
    """Title of the highlighted GRUB entry in a serial screen (GRUB marks it with '*'), or ''."""
    marks = re.findall(r"\*(\S.*?)(?:\s{2,}|$)", strip_ansi(screen), flags=re.M)
    return marks[-1].strip() if marks else ""


def logdir():
    evid = os.environ.get("EVID") or os.path.join(
        os.environ.get("LAB_DIR") or os.path.expanduser("~/lab"), "evidence")
    d = os.path.join(evid, "logs")
    os.makedirs(d, exist_ok=True)
    return d


class Console:
    def __init__(self, name, domain):
        import pexpect  # here, so the pure functions work without pexpect
        self._pexpect = pexpect
        base = os.path.join(logdir(), f"console-{name}-{int(time.time())}")
        self.raw_path, self.txt_path = base + ".log", base + ".txt"
        self.log = open(self.raw_path, "w", encoding="utf-8")
        try:
            self.c = pexpect.spawn(f"virsh console {domain}", encoding="utf-8",
                                   codec_errors="replace", timeout=60, dimensions=(50, 200))
        except BaseException:
            self.log.close()
            raise
        self.c.logfile_read = self.log

    def drain(self, seconds=1.0):
        """Read whatever arrives within `seconds`; return it ANSI-stripped."""
        out, end = "", time.time() + seconds
        while time.time() < end:
            try:
                out += self.c.read_nonblocking(65536, timeout=0.3)
            except self._pexpect.TIMEOUT:
                pass
            except self._pexpect.EOF:
                break
        # pexpect keeps its own internal buffer; purge it so nothing seen here can satisfy a later expect
        try:
            self.c.buffer = ""
        except Exception:
            pass
        return strip_ansi(out)

    def expect(self, pattern, timeout=60):
        """Drain stale output first, then wait for `pattern`; raises pexpect.TIMEOUT."""
        self.drain(0.5)
        return self.c.expect(pattern, timeout=timeout)

    def send(self, s):
        self.c.send(s)

    def select_grub_entry(self, title, max_downs=12):
        """Wait for the GRUB menu, arrow down until `title` is highlighted, then press Enter."""
        try:
            self.expect(r"Use the .* keys to select", timeout=300)
        except self._pexpect.TIMEOUT:
            print("timeout waiting for the GRUB menu", flush=True)
            return False
        except self._pexpect.EOF:
            print("console closed (EOF) waiting for the GRUB menu", flush=True)
            return False
        for n in range(max_downs + 1):
            sel = highlighted_grub(self.drain(1.5))
            print(f"[grub] step {n}: highlighted = {sel!r}", flush=True)
            if sel.startswith(title):
                self.send("\r")
                return True
            self.send("\x1b[B")  # Down
        return False

    def close(self):
        for step in (lambda: self.c.send("\x1d"),  # Ctrl+] leaves virsh console
                     lambda: self.c.close(force=True)):
            try:
                step()
            except Exception:
                pass  # the console may already be gone; the logs below must still be written
        try:
            self.log.close()
        finally:
            with open(self.raw_path, encoding="utf-8", errors="replace") as r, \
                    open(self.txt_path, "w", encoding="utf-8") as t:
                t.write(strip_ansi(r.read()))


def main(argv):
    p = argparse.ArgumentParser(prog="labconsole.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("capture"); c.add_argument("dom"); c.add_argument("name")
    c.add_argument("--seconds", type=float, default=10); c.add_argument("--enter", action="store_true")
    e = sub.add_parser("expect"); e.add_argument("dom"); e.add_argument("name"); e.add_argument("regex")
    e.add_argument("--timeout", type=float, default=60); e.add_argument("--enter", action="store_true")
    g = sub.add_parser("grub"); g.add_argument("dom"); g.add_argument("name"); g.add_argument("title")
    g.add_argument("--max-downs", type=int, default=12)
    a = p.parse_args(argv)
    try:
        con = Console(a.name, a.dom)
    except ImportError:
        print("labconsole.py: python3-pexpect is required on the lab host (apt install python3-pexpect)")
        return 1
    except Exception as ex:
        print(f"labconsole.py: cannot open console for {a.dom}: {ex}")
        return 1
    pe = con._pexpect
    try:
        if a.cmd == "capture":
            if a.enter:
                con.send("\r")
            print(con.drain(a.seconds)[-2000:])
            return 0
        if a.cmd == "expect":
            con.drain(0.5)
            if a.enter:
                con.send("\r")
            try:
                con.c.expect(a.regex, timeout=a.timeout)
                print(f"matched {a.regex!r}")
                return 0
            except pe.TIMEOUT:
                print(f"timeout after {a.timeout}s waiting for {a.regex!r}")
                return 1
            except pe.EOF:
                print(f"console closed (EOF) while waiting for {a.regex!r}")
                return 1
        if a.cmd == "grub":
            try:
                return 0 if con.select_grub_entry(a.title, a.max_downs) else 1
            except pe.TIMEOUT:
                print(f"timeout selecting GRUB entry {a.title!r}")
                return 1
            except pe.EOF:
                print(f"console closed (EOF) selecting GRUB entry {a.title!r}")
                return 1
    finally:
        con.close()
        print(f"logs: {con.raw_path} {con.txt_path}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
