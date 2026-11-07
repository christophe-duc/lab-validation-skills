source "$(dirname "$0")/lib.sh"
python3 -m py_compile "$BIN/labconsole.py" 2>/dev/null; assert_rc $? 0 "compiles"
out=$(python3 - "$BIN" "$FIX/ovmf-bootfail.serial.log" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
from labconsole import strip_ansi, highlighted_grub
raw = open(sys.argv[2], encoding="utf-8", errors="replace").read()
clean = strip_ansi(raw)
print("has_esc", "\x1b" in clean)
print("has_bds", "BdsDxe: failed to load Boot0002" in clean)
screen = "\x1b[H GNU GRUB  version 2.12\n\x1b[7m*Ubuntu, with Linux 6.8.0-147-generic          \x1b[0m\n Advanced options for Ubuntu\n"
print("sel", highlighted_grub(screen))
print("none", repr(highlighted_grub("no menu here")))
EOF
)
assert_contains "$out" "has_esc False" "ANSI removed"
assert_contains "$out" "has_bds True" "text kept"
assert_contains "$out" "sel Ubuntu, with Linux 6.8.0-147-generic" "GRUB highlight read back"
assert_contains "$out" "none ''" "no menu -> empty"
python3 "$BIN/labconsole.py" >/dev/null 2>&1; assert_rc $? 2 "CLI usage -> 2"
# --- Console/CLI against a FAKE pexpect (no virsh, no real pexpect needed) ---
out=$(EVID="$(mktemp -d)" PYTHONPATH="$FIX/fake_pexpect" python3 - "$BIN" <<'EOF'
import contextlib, glob, io, os, subprocess, sys
sys.path.insert(0, sys.argv[1])
import pexpect, labconsole

def run(argv, script):
    pexpect.SCRIPT.clear(); pexpect.SCRIPT.update(script)
    o, e = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(o), contextlib.redirect_stderr(e):
        try:
            rc = labconsole.main(argv)
        except BaseException as ex:
            rc = "TRACEBACK:" + repr(ex)
    return rc, o.getvalue(), e.getvalue()

def txt(name):
    return bool(glob.glob(os.environ["EVID"] + "/logs/console-%s-*.txt" % name))

# 1. drain consumes the buffer: stale 'login:' must not match; fresh text after drain must
pexpect.SCRIPT.clear(); pexpect.SCRIPT.update({"buffer": "old\nlogin:"})
con = labconsole.Console("stale", "dom")
try:
    con.expect("login:", timeout=1); print("stale_timeout False")
except pexpect.TIMEOUT:
    print("stale_timeout True")
con.close()
pexpect.SCRIPT.clear(); pexpect.SCRIPT.update({"buffer": "old\nlogin:", "late": ["new\nlogin:"]})
con = labconsole.Console("fresh", "dom")
print("fresh_match", con.expect("login:", timeout=1))
con.close()

# 2. CLI exit codes, never a traceback
rc, o, e = run(["expect", "d", "t1", "login:", "--timeout", "1"], {})
print("expect_timeout", rc, "timeout" in o)
rc, o, e = run(["expect", "d", "t2", "login:", "--timeout", "1"], {"eof": True})
print("expect_eof", rc, "EOF" in o)
rc, o, e = run(["expect", "d", "t3", "login:", "--timeout", "1"], {"late": ["x login:"]})
print("expect_match", rc, "matched" in o)
rc, o, e = run(["grub", "d", "t4", "Ubuntu"], {})
print("grub_nomenu", rc, "timeout" in o)
rc, o, e = run(["grub", "d", "t5", "Ubuntu"], {"eof": True})
print("grub_eof", rc, "EOF" in o)
rc, o, e = run(["grub", "d", "t6", "Ubuntu"],
               {"late": ["Use the ^ and v keys to select"], "after_match": ["\x1b[7m*Ubuntu, with Linux 6.8   \x1b[0m"]})
print("grub_ok", rc)

# 3. close() errors never mask the result or lose logs
rc, o, e = run(["expect", "d", "t7", "login:", "--timeout", "1"], {"late": ["login:"], "send_raises": True})
print("send_raises", rc, "logs:" in e, txt("t7"))
rc, o, e = run(["expect", "d", "t8", "login:", "--timeout", "1"], {"late": ["login:"], "close_raises": True})
print("close_raises", rc, "logs:" in e, txt("t8"))

# 4. constructor failure / missing pexpect
rc, o, e = run(["capture", "d", "t9", "--seconds", "0.1"], {"spawn_raises": True})
print("spawn_raises", rc, "labconsole.py:" in o + e)
r = subprocess.run([sys.executable, "-c",
    "import sys; sys.modules['pexpect']=None; sys.path.insert(0, %r); import labconsole; sys.exit(labconsole.main(['capture','d','t10']))" % sys.argv[1]],
    capture_output=True, text=True)
print("no_pexpect", r.returncode, "python3-pexpect is required" in r.stdout + r.stderr, "Traceback" in r.stderr)
EOF
)
assert_contains "$out" "stale_timeout True" "stale buffer text not matched after drain"
assert_contains "$out" "fresh_match 0" "text arriving after drain matches"
assert_contains "$out" "expect_timeout 1 True" "CLI expect timeout -> 1"
assert_contains "$out" "expect_eof 1 True" "CLI expect EOF -> 1"
assert_contains "$out" "expect_match 0 True" "CLI expect match -> 0"
assert_contains "$out" "grub_nomenu 1 True" "grub menu never appears -> 1"
assert_contains "$out" "grub_eof 1 True" "grub EOF -> 1"
assert_contains "$out" "grub_ok 0" "grub selects highlighted entry -> 0"
assert_contains "$out" "send_raises 0 True True" "close(): send() failure keeps rc, logs line, .txt"
assert_contains "$out" "close_raises 0 True True" "close(): close() failure keeps rc, logs line, .txt"
assert_contains "$out" "spawn_raises 1 True" "constructor failure -> 1 with message"
assert_contains "$out" "no_pexpect 1 True False" "missing pexpect -> message, rc 1, no traceback"
finish
