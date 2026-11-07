"""Fake pexpect for offline labconsole tests. Script it via class attributes on `spawn` (SCRIPT dict).

SCRIPT keys: buffer (str, pre-existing internal buffer), incoming (chunks readable at once),
late (chunks that arrive only once expect() is first called, i.e. after the drain),
after_match (chunks that arrive after an expect() matches), eof (raise EOF when nothing is
left), send_raises, close_raises, spawn_raises.
"""
import re
import time

SCRIPT = {}


class ExceptionPexpect(Exception):
    pass


class TIMEOUT(ExceptionPexpect):
    pass


class EOF(ExceptionPexpect):
    pass


class spawn:
    def __init__(self, cmd, **kw):
        s = SCRIPT
        if s.get("spawn_raises"):
            raise ExceptionPexpect("virsh: not found")
        self.cmd, self.kw = cmd, kw
        self.buffer = s.get("buffer", "")
        self.incoming = list(s.get("incoming", []))
        self.late = list(s.get("late", []))
        self.after_match = list(s.get("after_match", []))
        self.eof = s.get("eof", False)
        self.send_raises = s.get("send_raises", False)
        self.close_raises = s.get("close_raises", False)
        self.sent = []
        self.closed = False
        self.logfile_read = None

    def _log(self, text):
        if self.logfile_read is not None:
            self.logfile_read.write(text)

    def read_nonblocking(self, size=1, timeout=-1):
        if self.incoming:
            data = self.incoming.pop(0)
            self._log(data)
            return data
        time.sleep(0.05)
        if self.eof:
            raise EOF("closed")
        raise TIMEOUT("no data")

    def expect(self, pattern, timeout=-1):
        self.incoming += self.late
        self.late = []
        while True:
            m = re.search(pattern, self.buffer)
            if m:
                self.buffer = self.buffer[m.end():]
                self.incoming += self.after_match
                self.after_match = []
                return 0
            if not self.incoming:
                if self.eof:
                    raise EOF("closed")
                raise TIMEOUT("timeout")
            data = self.incoming.pop(0)
            self._log(data)
            self.buffer += data

    def send(self, s):
        if self.send_raises:
            raise OSError("send failed")
        self.sent.append(s)

    def close(self, force=False):
        if self.close_raises:
            raise ExceptionPexpect("close failed")
        self.closed = True
