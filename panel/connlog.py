#!/usr/bin/env python3
"""
DAHOOM · Connection Log Daemon
──────────────────────────────
Real, process-level connection tracking for SSH/VPN accounts, plus a
best-effort activity log for X-UI (V2Ray) clients.

Why this exists (root cause of the old "no login records" bug):
Every VPN account this project creates gets shell /usr/sbin/nologin
(menu.sh) — accounts are meant for tunneling (SOCKS/port-forward), not an
interactive shell. OpenSSH only writes a wtmp/utmp entry (what `last`/
`lastb` read) when a *session* channel (shell/exec/subsystem) is opened.
A pure "ssh -N -D ..." tunnel never opens one, so these accounts can
authenticate, forward traffic for hours, and disconnect — and `last`
will NEVER show a single line for them. That is a protocol-level fact,
not a misconfiguration, so the old handle_user_history() (built on
`last`/`lastb`) was structurally unable to work for this product. This
daemon replaces it with real process/socket inspection instead.

Design:
  - Every POLL_INTERVAL seconds, list live sshd worker processes
    (ps -C sshd,sshd-session — same call bandwidth_link.py already uses
    for its "online now" count) and diff the (pid) set against what was
    seen last cycle:
      * a pid that's new              -> INSERT a 'success' row, open
        (disconnect_time IS NULL). The real process start time is read
        from /proc/<pid>/stat so a connection isn't misreported as
        starting "now" just because the daemon itself restarted.
      * a pid that vanished           -> close that row: fill in
        disconnect_time + duration_seconds.
    The peer IP for a newly-seen pid comes from `ss -tnp` (maps a
    listening-port-22 ESTABLISHED socket to its owning pid).
  - Failed logins are picked up by tailing /var/log/auth.log (falling
    back to `journalctl -u ssh` polling when that file doesn't exist —
    common on systemd-only Ubuntu images with no rsyslog) for the usual
    sshd auth-failure lines, parsed into (username, ip, reason).
  - X-UI (V2Ray) clients have no wtmp-equivalent, but Xray tracks the
    IPs currently online per client itself and serves them over its own
    API — so this daemon asks Xray directly and records one open row per
    (client, IP), with the real IP. That also makes the per-client device
    limit enforceable: any IP beyond the client's allowance is routed to
    Xray's blackhole outbound live (no restart, and it lifts itself the
    moment the device count drops back). If Xray's API can't be reached,
    X-UI tracking falls back to the old traffic-delta heuristic, which
    detects activity but cannot attach an IP.

Everything is written to one sqlite database so the panel can search,
filter, sort and paginate without re-parsing text on every request.
"""
import os
import re
import sys
import time
import json
import sqlite3
import subprocess

DB_PATH = "/etc/firewallfalcon/connection_log.db"
AUTH_LOG_PATHS = [os.environ["CONNLOG_AUTH_LOG"]] if os.environ.get("CONNLOG_AUTH_LOG") else ["/var/log/auth.log", "/var/log/secure"]
AUTH_LOG_OFFSET_FILE = "/etc/firewallfalcon/.connlog_authlog_offset"
JOURNAL_CURSOR_FILE = "/etc/firewallfalcon/.connlog_journal_cursor"
XUI_DB_PATH = "/etc/x-ui/x-ui.db"

XUI_BIN_DIR = "/usr/local/x-ui/bin"
XUI_XRAY_CONFIG = os.path.join(XUI_BIN_DIR, "config.json")
XRAY_API_FALLBACK = "127.0.0.1:62789"

POLL_INTERVAL = float(os.environ.get("CONNLOG_POLL_INTERVAL", "5"))
XUI_POLL_EVERY = 3          # every N SSH poll cycles (i.e. ~15s by default)
XUI_IDLE_CLOSE = 60         # seconds of no traffic growth before closing an X-UI session
RETENTION_DAYS = int(os.environ.get("CONNLOG_RETENTION_DAYS", "90"))
# An IP that stops appearing in Xray's online list for this long is treated
# as disconnected. Measured directly against a live Xray: it drops an IP
# from this list within ~5s of the connection actually closing (clean or
# reset alike), and — just as importantly — keeps reporting a still-open
# idle connection online indefinitely, so there is no "list flickers while
# nothing changed" case to guard against here. This only needs to survive
# one missed poll cycle (a slow/failed API call already skips this check
# entirely rather than reaching it, so it isn't guarding against that
# either) — a small value keeps "disconnected" accurate within seconds
# instead of a stale device sitting in the panel for two minutes.
XUI_IP_STALE = 20

# Confirmed in the wild (real 3x-ui, real bundled xray-core, a real held-open
# authenticated connection): the online-stats RPC above (statsonlineiplist /
# GetUsersStats) can answer as "supported" — no Unimplemented error — while
# never actually reporting a single online user, even during a live,
# actively-transferring connection. See poll_xui_access_log()'s docstring for
# the fallback this feeds: Xray's own access log, tailed the same way
# poll_failed_logins_authlog already tails auth.log.
XUI_ACCESS_LOG_OFFSET_FILE = "/etc/firewallfalcon/.connlog_xui_accesslog_offset"
# How long an IP stays counted as "online" after its last logged accepted
# connection. Xray's access log only ever writes ONE line per TCP connection,
# at accept time — a single long-lived tunnel carrying hours of real traffic
# produces exactly one line and then silence, so "no new line recently" can't
# mean "gone". Five minutes comfortably outlasts how often a real client's
# app/OS re-dials (TCP keepalive, network switches, app foreground/background
# cycles), while still dropping a genuinely-departed device inside one panel
# refresh cycle rather than leaving it occupying a device-limit slot forever.
XUI_ACCESS_IP_WINDOW = 300
_XUI_ACCESS_LINE_RE = re.compile(
    r'from\s+(?P<addr>\S+)\s+accepted\s+\S+.*?\bemail:\s*(?P<email>\S+)\s*$'
)


def _db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=10000")
    return conn


def init_db():
    conn = _db()
    try:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS connections (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source TEXT NOT NULL,
                username TEXT NOT NULL,
                ip TEXT,
                status TEXT NOT NULL,
                session_key TEXT,
                connect_time INTEGER,
                disconnect_time INTEGER,
                duration_seconds INTEGER,
                fail_reason TEXT,
                user_agent TEXT,
                extra TEXT
            )
        """)
        conn.execute("CREATE INDEX IF NOT EXISTS idx_conn_username ON connections(username)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_conn_ip ON connections(ip)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_conn_time ON connections(connect_time)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_conn_source ON connections(source)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_conn_status ON connections(status)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_conn_session_key ON connections(session_key)")
        conn.commit()
        try:
            _migrate_schema(conn)
        except Exception as e:
            # Never let a migration hiccup take the whole daemon down —
            # that would stop real connection tracking entirely, which is
            # strictly worse than a stale column. panel.py independently
            # self-heals the column too (_ensure_connlog_schema), so the
            # worst case here is the historical-row cleanup doesn't run.
            print(f"[connlog] schema migration error (continuing anyway): {e}", file=sys.stderr)
    finally:
        conn.close()


def _migrate_schema(conn):
    """A real internet-facing SSH port gets probed constantly by bots —
    one server saw ~32,000 individual failed-login rows within its first
    day live, one per attempt, because the original schema had no way to
    represent 'this same IP tried again'. attempt_count fixes that going
    forward (see _upsert_failed_row); this migration adds the column to
    an already-running database and folds its pre-existing one-row-per-
    attempt history into the same aggregated shape, so an existing
    install doesn't stay stuck with tens of thousands of rows forever.

    The column-add is committed on its own, separately from the cleanup
    pass below — so even if that cleanup hits something unexpected on
    real-world data, every INSERT/UPDATE this daemon does afterward still
    has a column to write to, and panel.py's own queries stop failing."""
    cur = conn.cursor()
    cur.execute("PRAGMA table_info(connections)")
    cols = {row[1] for row in cur.fetchall()}

    if "attempt_count" not in cols:
        conn.execute("ALTER TABLE connections ADD COLUMN attempt_count INTEGER DEFAULT 1")
        conn.commit()
        try:
            _consolidate_legacy_failed_rows(conn)
        except Exception as e:
            conn.rollback()
            print(f"[connlog] legacy-row consolidation error (attempt_count column is still in place): {e}", file=sys.stderr)

    # client_port: the SSH client's own ephemeral port for this connection.
    # sshd's disconnect-reason log lines (see _DISCONNECT_PATTERNS below)
    # identify a connection by (ip, port), not by username, and a plain
    # (ip, username) match can hit the wrong one of two concurrent sessions
    # from behind the same NAT — the port is what makes that match exact.
    if "client_port" not in cols:
        conn.execute("ALTER TABLE connections ADD COLUMN client_port INTEGER")
        conn.commit()


def _consolidate_legacy_failed_rows(conn):
    cur = conn.cursor()
    cur.execute(
        "SELECT ip, COUNT(*), MIN(connect_time), MAX(connect_time) "
        "FROM connections WHERE source='ssh' AND status='failed' AND ip IS NOT NULL AND ip!='' "
        "AND connect_time IS NOT NULL GROUP BY ip HAVING COUNT(*) > 1"
    )
    groups = cur.fetchall()
    for ip, count, first_seen, last_seen in groups:
        cur.execute(
            "SELECT username, fail_reason FROM connections "
            "WHERE source='ssh' AND status='failed' AND ip=? ORDER BY connect_time DESC LIMIT 1",
            (ip,),
        )
        row = cur.fetchone()
        last_username = row[0] if row else "unknown"
        last_reason = row[1] if row else None
        last_seen = last_seen if last_seen is not None else first_seen
        cur.execute("DELETE FROM connections WHERE source='ssh' AND status='failed' AND ip=?", (ip,))
        cur.execute(
            "INSERT INTO connections (source, username, ip, status, connect_time, disconnect_time, "
            "duration_seconds, fail_reason, attempt_count) VALUES ('ssh', ?, ?, 'failed', ?, ?, ?, ?, ?)",
            (last_username, ip, first_seen, last_seen, max(0, last_seen - first_seen), last_reason, count),
        )
    conn.commit()


# ─── SSH connection tracking (process/socket based, no wtmp involved) ───

def _clk_tck():
    try:
        return os.sysconf("SC_CLK_TCK")
    except Exception:
        return 100


def _boot_epoch():
    try:
        with open("/proc/uptime") as f:
            up = float(f.read().split()[0])
        return time.time() - up
    except Exception:
        return None


def _proc_start_epoch(pid, boot_epoch, clk_tck):
    """Real wall-clock start time of a pid, from /proc — so a connection
    already running before this daemon (re)started isn't misreported as
    having just connected 'now'."""
    if boot_epoch is None:
        return time.time()
    try:
        with open(f"/proc/{pid}/stat", "rb") as f:
            raw = f.read().decode("utf-8", "ignore")
        # comm (2nd field) is "(...)" and may itself contain ')' — split
        # on the LAST ')' to safely recover the fields after it.
        after = raw.rsplit(")", 1)[1].split()
        starttime_ticks = float(after[19])  # field 22 overall, 20th after comm
        return boot_epoch + (starttime_ticks / clk_tck)
    except Exception:
        return time.time()


_SSHD_NON_CONNECTION_USERS = {"root", "sshd"}  # 'root' = the master listener;
# 'sshd' = OpenSSH's own default privilege-separation user (see
# /etc/passwd — Debian/Ubuntu set this up at package-install time). Every
# incoming TCP connection to sshd, authenticated or not — including a
# port scanner or a health check that never logs in — spins up a
# pre-auth monitor child running AS this unprivileged system user, alive
# for as long as that one connection lasts. Only AFTER a real
# authentication succeeds does OpenSSH re-exec a second child as the
# actual target account. Counting the privsep user's own row as if it
# were "user sshd connected" would fabricate a successful login for
# every unrelated probe against port 22 that never even authenticates.
# (bandwidth_link.py's online_sessions() checks equality against one
# specific, already-known username instead of enumerating every row, so
# it was never exposed to this — no VPN account is ever named "sshd".)


def _ssh_worker_pids():
    """(pid -> username) for real, currently-connected SSH workers — one
    entry per authenticated connection, keyed by the account that
    actually logged in."""
    try:
        out = subprocess.run(
            ["ps", "-C", "sshd,sshd-session", "-o", "pid=,user="],
            capture_output=True, text=True, timeout=5,
        ).stdout
    except Exception:
        return {}
    result = {}
    for line in out.strip().splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1] not in _SSHD_NON_CONNECTION_USERS:
            try:
                result[int(parts[0])] = parts[1]
            except ValueError:
                continue
    return result


REALIP_DIR = "/run/dahoom-realip"


def _read_realip_map():
    """{source_port: real_client_ip}, published by the connection proxy
    (firewallfalcon-socksproxy.py) for every connection it relays.

    Without it the whole SSH log records 127.0.0.1 for every customer,
    because the proxy — not the customer — is what opens the socket sshd
    accepts. The proxy keys each entry by the source port of that inner
    socket, which is exactly the peer port seen here."""
    out = {}
    try:
        names = os.listdir(REALIP_DIR)
    except OSError:
        return out
    for name in names:
        if not name.isdigit():
            continue
        try:
            with open(os.path.join(REALIP_DIR, name), encoding="utf-8", errors="ignore") as f:
                ip = f.read().strip()
        except OSError:
            continue
        if ip:
            out[name] = ip
    return out


def _is_local_addr(ip):
    return not ip or ip.startswith(("127.", "::1", "0.0.0.0", "::ffff:127."))


def _ssh_peer_ips(pids):
    """pid -> (remote IP, remote port), read from `ss -tnp` (works for any
    pid that owns an established TCP socket, not just port 22 — good
    enough since the only pids we ever look up here are already-confirmed
    sshd workers). The port is what later lets a disconnect-reason log
    line (see _DISCONNECT_PATTERNS) identify exactly this connection,
    since sshd's own messages never mention a pid or username together
    with the reason."""
    if not pids:
        return {}
    try:
        out = subprocess.run(["ss", "-tnp"], capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return {}
    realip = _read_realip_map()
    peer_by_pid = {}
    for line in out.splitlines():
        m = re.search(r"pid=(\d+)", line)
        if not m:
            continue
        pid = int(m.group(1))
        if pid not in pids or pid in peer_by_pid:
            continue
        cols = line.split()
        if len(cols) < 5:
            continue
        peer = cols[4]
        ip, _, port = peer.rpartition(":")
        ip = ip.strip("[]")
        # The RECORDED address becomes the customer's real one; the port
        # deliberately stays the loopback one, because that is what
        # sshd's own disconnect lines quote and what client_port has to
        # match to tie a reason back to this row.
        if _is_local_addr(ip):
            ip = realip.get(port, ip)
        try:
            port = int(port)
        except ValueError:
            port = None
        peer_by_pid[pid] = (ip, port)
    return peer_by_pid


def poll_ssh(conn, active):
    """active: {pid: {'username', 'ip', 'port', 'connect_time', 'row_id'}}
    — kept in memory across cycles by the caller."""
    now_pids = _ssh_worker_pids()
    new_pids = [p for p in now_pids if p not in active]
    gone_pids = [p for p in active if p not in now_pids]

    if new_pids:
        boot_epoch = _boot_epoch()
        clk_tck = _clk_tck()
        peer_map = _ssh_peer_ips(set(new_pids))
        cur = conn.cursor()
        for pid in new_pids:
            username = now_pids[pid]
            connect_time = int(_proc_start_epoch(pid, boot_epoch, clk_tck))
            ip, port = peer_map.get(pid, ("", None))
            session_key = f"ssh:{pid}:{connect_time}"
            cur.execute(
                "INSERT INTO connections (source, username, ip, client_port, status, session_key, connect_time) "
                "VALUES ('ssh', ?, ?, ?, 'success', ?, ?)",
                (username, ip, port, session_key, connect_time),
            )
            active[pid] = {"username": username, "ip": ip, "port": port, "connect_time": connect_time, "row_id": cur.lastrowid}
        conn.commit()

    if gone_pids:
        cur = conn.cursor()
        now = int(time.time())
        for pid in gone_pids:
            info = active.pop(pid)
            duration = max(0, now - info["connect_time"])
            cur.execute(
                "UPDATE connections SET disconnect_time=?, duration_seconds=? WHERE id=?",
                (now, duration, info["row_id"]),
            )
        conn.commit()


# ─── Failed-login tracking (auth.log tail, journalctl fallback) ───

_FAIL_PATTERNS = [
    # Ordered by how informative the reason is — one real attempt makes
    # sshd log 2-3 of these lines back to back (same ip:port), and only
    # the most specific one should end up as the stored record.
    (2, re.compile(r"Failed password for invalid user (\S+) from ([\d.:a-fA-F]+) port (\d+)"), "كلمة مرور خاطئة (مستخدم غير موجود)"),
    (2, re.compile(r"Failed password for (\S+) from ([\d.:a-fA-F]+) port (\d+)"), "كلمة مرور خاطئة"),
    (2, re.compile(r"error: maximum authentication attempts exceeded for (?:invalid user )?(\S+) from ([\d.:a-fA-F]+) port (\d+)"), "تجاوز الحد الأقصى لمحاولات الدخول"),
    (1, re.compile(r"Invalid user (\S+) from ([\d.:a-fA-F]+) port (\d+)"), "مستخدم غير موجود"),
    (0, re.compile(r"Connection closed by invalid user (\S+) ([\d.:a-fA-F]+) port (\d+) \[preauth\]"), "مستخدم غير موجود (أُغلق الاتصال)"),
    (0, re.compile(r"Connection closed by authenticating user (\S+) ([\d.:a-fA-F]+) port (\d+) \[preauth\]"), "أُغلق الاتصال أثناء المصادقة"),
    (0, re.compile(r"Disconnected from authenticating user (\S+) ([\d.:a-fA-F]+) port (\d+) \[preauth\]"), "قُطع الاتصال أثناء المصادقة"),
]


def _parse_fail_line(line):
    for priority, pat, reason in _FAIL_PATTERNS:
        m = pat.search(line)
        if m:
            return priority, m.group(1), m.group(2), m.group(3), reason
    return None


# ─── Disconnect-reason tracking for successful SSH sessions ───
# What sshd actually logs when an established session ends was measured
# against a real sshd, one scenario at a time, at both log levels — not
# assumed. The result (and the reason this needs more than log parsing):
#
#   scenario                                  LogLevel INFO   VERBOSE
#   ------------------------------------------------------------------
#   A client quits politely (SSH_MSG_DISCONNECT)   logged      logged
#   B client dies abruptly (bare TCP FIN)          NOTHING     logged
#   C network vanishes silently                  only with ClientAlive set
#   D admin kills the worker (panel's button)      NOTHING     NOTHING
#   E sshd itself stops/restarts             no per-session line at all
#
# B is the common case in practice — a phone VPN app being force-closed,
# or the TLS/websocket proxy in front of sshd tearing its backend socket
# down, both end the connection with a bare FIN and no SSH goodbye. At
# stock LogLevel INFO sshd says nothing at all about it, which is why
# every ended session used to read "unknown". ensure_sshd_logging() below
# turns on the VERBOSE level (and ClientAlive probes for C) so B and C
# become observable at all; D and E can never be answered from sshd's
# logs, so they are recorded from the server side instead — D by panel.py
# at the moment it sends the kill, E by _close_dangling_open_rows() and
# the mass-disconnect pass, which see the aftermath directly.
#
# None of these lines carry a username, only IP and port — and behind the
# proxy every session shares one IP (127.0.0.1), so the client's port is
# the only thing that identifies which session a line refers to. That is
# what the client_port column is for.
_DISCONNECT_REASON_MAP = {
    "disconnected by user": "أغلق المستخدم الاتصال",
}

_DISCONNECT_PATTERNS = [
    re.compile(r"Received disconnect from ([\d.:a-fA-F]+) port (\d+):\d+: (.+?)\s*$"),
]
_TIMEOUT_PATTERN = re.compile(r"Timeout, client not responding from user \S+ ([\d.:a-fA-F]+) port (\d+)")

# Scenario B. Post-auth only: the pre-auth spellings ("Connection closed
# by invalid user ...", "... authenticating user ...", anything tagged
# [preauth]) are failed logins, already owned by _FAIL_PATTERNS, and must
# not be mistaken for a real session ending. OpenSSH prints this either
# bare or with a "user NAME" part depending on version, so both shapes
# are matched here.
_CLIENT_GONE_PATTERNS = [
    re.compile(r"Connection (?:closed|reset) by (?:user \S+ )?([\d.:a-fA-F]+) port (\d+)"),
]
_PREAUTH_MARKERS = ("[preauth]", "invalid user", "authenticating user")


def _parse_disconnect_line(line):
    """Returns (ip, port, reason) or None. reason is a ready-to-store
    string — already mapped to Arabic for the messages that account for
    the vast majority of real disconnects, passed through as-is (sshd's
    own English text) for anything less common rather than guessing a
    translation."""
    m = _TIMEOUT_PATTERN.search(line)
    if m:
        return m.group(1), int(m.group(2)), "انتهت المهلة — لم يستجب الجهاز (غالبًا انقطاع شبكة)"
    for pat in _DISCONNECT_PATTERNS:
        m = pat.search(line)
        if m:
            ip, port, msg = m.group(1), int(m.group(2)), m.group(3).strip()
            return ip, port, _DISCONNECT_REASON_MAP.get(msg, msg)
    if not any(mark in line for mark in _PREAUTH_MARKERS):
        for pat in _CLIENT_GONE_PATTERNS:
            m = pat.search(line)
            if m:
                return m.group(1), int(m.group(2)), "انقطع الاتصال من جهة المستخدم (إغلاق التطبيق أو انقطاع الشبكة)"
    return None


_DISCONNECT_REASON_TTL = 30  # seconds — how stale a "success" row is
# allowed to be and still accept a late-arriving reason. poll_ssh and the
# auth-log tailer run independently, so the row can already be closed (or
# not yet) by the time this fires; an open row always wins over a closed
# one (see the ORDER BY below), this bound only guards the closed-row
# fallback against attaching a reason to some unrelated old session that
# coincidentally reused the same (ip, port).


def _record_disconnect_reason(conn, ip, port, reason, ts=None):
    if port is None:
        return
    ts = ts if ts is not None else int(time.time())
    cur = conn.cursor()
    cur.execute(
        "SELECT id, disconnect_time FROM connections WHERE source='ssh' AND status='success' "
        "AND ip=? AND client_port=? ORDER BY (disconnect_time IS NULL) DESC, "
        "COALESCE(disconnect_time, connect_time) DESC LIMIT 1",
        (ip, port),
    )
    row = cur.fetchone()
    if not row:
        return
    row_id, disconnect_time = row
    if disconnect_time is not None and ts - disconnect_time > _DISCONNECT_REASON_TTL:
        return  # closed too long ago to plausibly be this reason
    cur.execute("UPDATE connections SET fail_reason=? WHERE id=?", (reason, row_id))
    conn.commit()


_RECENT_FAIL_TTL = 15  # seconds — one real failed attempt's related log
                       # lines (Invalid user / Failed password / Connection
                       # closed) can legitimately span several poll cycles
                       # (retry prompts take real wall-clock time), so the
                       # dedup window has to outlive a single poll, not just
                       # cover one file-read batch.
_recent_fail = {}      # (ip, port) -> {"row_id", "priority", "expires_at"}

_FAILED_AGGREGATE_WINDOW = 3600  # seconds — a real internet-facing SSH
# port gets probed by scanning bots constantly (one server saw ~32,000
# individual failed rows within its first day live — one per attempt,
# same handful of source IPs, over and over). Repeated failures from the
# SAME ip within this window fold into one row instead of a new one each
# time: attempt_count goes up, connect_time is the first attempt seen,
# disconnect_time slides forward to the latest one. A full hour of
# silence from that ip before it resumes starts a fresh row — so the
# count still reflects distinct attack episodes, not one row forever.


def _prune_recent_fail(now):
    for key in [k for k, v in _recent_fail.items() if v["expires_at"] < now]:
        del _recent_fail[key]


def _upsert_failed_row(conn, username, ip, reason, ts):
    cur = conn.cursor()
    if ip:
        cur.execute(
            "SELECT id FROM connections WHERE source='ssh' AND status='failed' AND ip=? AND disconnect_time>=? "
            "ORDER BY disconnect_time DESC LIMIT 1",
            (ip, ts - _FAILED_AGGREGATE_WINDOW),
        )
        row = cur.fetchone()
    else:
        row = None
    if row:
        row_id = row[0]
        cur.execute(
            "UPDATE connections SET username=?, fail_reason=?, disconnect_time=?, "
            "duration_seconds=?-connect_time, attempt_count=COALESCE(attempt_count,1)+1 WHERE id=?",
            (username, reason, ts, ts, row_id),
        )
    else:
        cur.execute(
            "INSERT INTO connections (source, username, ip, status, connect_time, disconnect_time, "
            "duration_seconds, fail_reason, attempt_count) VALUES ('ssh', ?, ?, 'failed', ?, ?, 0, ?, 1)",
            (username, ip, ts, ts, reason),
        )
        row_id = cur.lastrowid
    conn.commit()
    return row_id


def _record_failed(conn, priority, username, ip, port, reason, when_epoch=None):
    """One (ip, port) pair is one real connection attempt from the
    client's point of view — sshd just logs it in several lines; those
    get folded into a single attempt via the short-lived _recent_fail
    cache, upgrading to a more specific reason if a later line in the
    same attempt is more informative. That single attempt then goes
    through _upsert_failed_row(), which is the layer that collapses
    *repeated* attempts from the same ip (see _FAILED_AGGREGATE_WINDOW)."""
    ts = int(when_epoch if when_epoch is not None else time.time())
    now = time.time()
    _prune_recent_fail(now)
    key = (ip, port)
    existing = _recent_fail.get(key)
    if existing is None:
        row_id = _upsert_failed_row(conn, username, ip, reason, ts)
        _recent_fail[key] = {"row_id": row_id, "priority": priority, "expires_at": now + _RECENT_FAIL_TTL}
    elif priority > existing["priority"]:
        conn.execute(
            "UPDATE connections SET username=?, fail_reason=? WHERE id=?",
            (username, reason, existing["row_id"]),
        )
        conn.commit()
        existing["priority"] = priority
        existing["expires_at"] = now + _RECENT_FAIL_TTL
    else:
        existing["expires_at"] = now + _RECENT_FAIL_TTL


def poll_failed_logins_authlog(conn, path):
    offset = 0
    if os.path.exists(AUTH_LOG_OFFSET_FILE):
        try:
            with open(AUTH_LOG_OFFSET_FILE) as f:
                saved_path, saved_off = f.read().strip().split(":", 1)
            if saved_path == path:
                offset = int(saved_off)
        except Exception:
            offset = 0
    try:
        size = os.path.getsize(path)
    except Exception:
        return
    if size < offset:
        offset = 0  # log rotated
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            f.seek(offset)
            for line in f:
                parsed = _parse_fail_line(line)
                if parsed:
                    priority, username, ip, port, reason = parsed
                    _record_failed(conn, priority, username, ip, port, reason)
                    continue
                disc = _parse_disconnect_line(line)
                if disc:
                    _record_disconnect_reason(conn, *disc)
            offset = f.tell()
    except Exception:
        return
    try:
        with open(AUTH_LOG_OFFSET_FILE, "w") as f:
            f.write(f"{path}:{offset}")
    except Exception:
        pass


def poll_failed_logins_journal(conn):
    cursor = ""
    if os.path.exists(JOURNAL_CURSOR_FILE):
        try:
            with open(JOURNAL_CURSOR_FILE) as f:
                cursor = f.read().strip()
        except Exception:
            cursor = ""
    cmd = ["journalctl", "-u", "ssh", "-u", "sshd", "--no-pager", "-o", "short-unix", "--show-cursor"]
    if cursor:
        cmd += ["--after-cursor", cursor]
    else:
        cmd += ["-n", "0"]  # first run: don't replay the whole history
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return
    if not out:
        return
    lines = out.splitlines()
    new_cursor = None
    for line in lines:
        if line.startswith("-- cursor:"):
            new_cursor = line.split(":", 1)[1].strip()
            continue
        ts = None
        m_ts = re.match(r"^(\d+)\.\d+\s", line)
        if m_ts:
            ts = int(m_ts.group(1))
        parsed = _parse_fail_line(line)
        if parsed:
            priority, username, ip, port, reason = parsed
            _record_failed(conn, priority, username, ip, port, reason, ts)
            continue
        disc = _parse_disconnect_line(line)
        if disc:
            _record_disconnect_reason(conn, *disc, ts=ts)
    if new_cursor:
        try:
            with open(JOURNAL_CURSOR_FILE, "w") as f:
                f.write(new_cursor)
        except Exception:
            pass


def poll_failed_logins(conn):
    for path in AUTH_LOG_PATHS:
        if os.path.exists(path):
            poll_failed_logins_authlog(conn, path)
            return
    poll_failed_logins_journal(conn)


# ─── X-UI (V2Ray) activity tracking ───
# Xray itself knows exactly which IPs are currently online for each client
# and exposes them over its own gRPC API (StatsService.GetStatsOnlineIpList,
# reachable through the bundled xray binary's `api statsonlineiplist`), as
# long as policy.levels.*.statsUserOnline is on — which x-ui's default
# template already sets. That is the real per-device signal, so it is what
# this daemon uses: one open row per (client, IP), with the IP recorded.
#
# It needs no access log and no xray restart. Note Xray deliberately does
# not track loopback sources, so a client tunnelling from the server itself
# never shows up — real users always come from a routable address.
#
# If the API can't be reached (xray down, older build, api disabled), we
# fall back to the previous traffic-delta heuristic so the log degrades to
# "activity without an IP" instead of going blank.


def _xray_bin():
    """The xray executable x-ui ships (name carries the arch, e.g.
    xray-linux-amd64 / xray-linux-arm64), so glob rather than hardcode."""
    try:
        for name in sorted(os.listdir(XUI_BIN_DIR)):
            if name.startswith("xray-") and not name.endswith((".dat", ".json")):
                path = os.path.join(XUI_BIN_DIR, name)
                if os.path.isfile(path) and os.access(path, os.X_OK):
                    return path
    except Exception:
        pass
    return None


def _xray_api_addr():
    """Where xray's API listens — read it from the very config x-ui
    generated rather than assuming the default port."""
    try:
        with open(XUI_XRAY_CONFIG, encoding="utf-8") as f:
            listen = (json.load(f).get("api") or {}).get("listen")
        if listen:
            return listen
    except Exception:
        pass
    return XRAY_API_FALLBACK


def _xray_api(*args, timeout=10):
    """Run `xray api <args>`; returns parsed JSON, or None if unavailable.
    Flags must precede positional arguments — xray's CLI stops parsing
    flags at the first positional, so `-reset` after an IP is read as
    another IP and the whole call is rejected."""
    binary = _xray_bin()
    if not binary:
        return None
    cmd = [binary, "api", args[0], "--server=" + _xray_api_addr()] + list(args[1:])
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except Exception:
        return None
    out = (res.stdout or "").strip()
    if not out:
        return {} if res.returncode == 0 else None
    try:
        return json.loads(out)
    except Exception:
        pass
    # Some verbs (sib) print one JSON object per rule they touched, so the
    # output is several objects back to back and isn't valid JSON as a
    # whole — read the first one rather than calling the whole call failed.
    try:
        obj, _ = json.JSONDecoder().raw_decode(out)
        return obj
    except Exception:
        return {} if res.returncode == 0 else None


# How long a genuinely dead peer is allowed to sit "online" before Xray
# notices, on an inbound with no keepalive configured (measured against a
# real inbound, no sockopt at all — x-ui's own default): tcp_keepalive_time
# is 7200s system-wide, and Xray never turns SO_KEEPALIVE on for a socket
# by itself, so nothing even starts that 2-hour clock — a client that
# vanishes without sending FIN/RST (phone loses signal, app killed, WiFi
# turned off) can look "online" indefinitely, not just for a while.
XUI_KEEPALIVE_SECONDS = 15


def ensure_xray_online_stats():
    """Xray only reports online IPs when the policy for a client's level
    has statsUserOnline on and StatsService is exposed on the API. x-ui's
    current default template sets both, but an installation created by an
    older x-ui (or an admin who edited the template) can be missing them —
    and then nothing downstream works: no IPs, no device count, no limit.

    Patches x-ui's own template in place. Returns True only when something
    was actually changed — restarting x-ui to apply it is the caller's job
    (ensure_xray_health), which also runs ensure_xui_inbound_keepalive, so
    the two repairs share one restart instead of two.
    """
    if not os.path.exists(XUI_DB_PATH):
        return False
    try:
        conn = sqlite3.connect(XUI_DB_PATH, timeout=10)
    except Exception:
        return False
    try:
        cur = conn.cursor()
        cur.execute("SELECT value FROM settings WHERE key='xrayTemplateConfig'")
        row = cur.fetchone()
        if not row or not row[0]:
            return False
        cfg = json.loads(row[0])

        changed = False
        policy = cfg.setdefault("policy", {})
        levels = policy.setdefault("levels", {})
        if not levels:
            levels["0"] = {}
        # Every level in use must report it, not just level 0 — a client on
        # a level without it would silently stay invisible.
        for lvl in list(levels.keys()):
            if not levels[lvl].get("statsUserOnline"):
                levels[lvl]["statsUserOnline"] = True
                changed = True

        api = cfg.setdefault("api", {})
        services = api.setdefault("services", [])
        if "StatsService" not in services:
            services.append("StatsService")
            changed = True
        # The online map lives in the stats app; without it registered the
        # policy flag has nowhere to record anything.
        if "stats" not in cfg:
            cfg["stats"] = {}
            changed = True

        if not changed:
            return False

        cur.execute("UPDATE settings SET value=? WHERE key='xrayTemplateConfig'",
                    (json.dumps(cfg, indent=2),))
        conn.commit()
    except Exception as e:
        print(f"[connlog] could not check/repair xray online-stats config: {e}", file=sys.stderr)
        return False
    finally:
        conn.close()

    print("[connlog] xray was not configured to report online IPs "
          "(statsUserOnline/StatsService missing) — fixed it", file=sys.stderr)
    return True


def ensure_xray_access_log():
    """Turns on Xray's own connection access log — the one signal this
    project can still trust for per-device tracking and IP-limit enforcement
    on a core whose online-stats RPC lies about being empty (see
    XUI_ACCESS_LOG_OFFSET_FILE's comment for how that was confirmed). Every
    accepted connection gets one line naming its source IP and client email,
    written by Xray itself, regardless of whether the RPC ever works.

    Builds the new template from the CURRENTLY RUNNING generated config
    (XUI_XRAY_CONFIG) rather than a hand-written one, so this never has to
    guess at what x-ui/3x-ui need in the other sections (api, policy,
    outbounds, routing, dns, stats) — only "log.access" is changed. Some
    builds (3x-ui) confine whatever path is requested here under their own
    log folder rather than using it verbatim; poll_xui_access_log() re-reads
    the regenerated config to learn the real resulting path instead of
    assuming one, so that confinement doesn't need to be predicted here.

    Returns True only when something was actually changed — restarting x-ui
    to apply it is the caller's job (ensure_xray_health), same contract as
    ensure_xray_online_stats.
    """
    if not os.path.exists(XUI_DB_PATH):
        return False
    try:
        with open(XUI_XRAY_CONFIG, encoding="utf-8") as f:
            live_cfg = json.load(f)
    except Exception:
        return False

    current_access = str((live_cfg.get("log") or {}).get("access", "")).strip()
    if current_access and current_access.lower() != "none":
        return False  # already on — a prior run enabled it, or an admin did

    try:
        conn = sqlite3.connect(XUI_DB_PATH, timeout=10)
    except Exception:
        return False
    try:
        cur = conn.cursor()
        # Everything except "inbounds" — that section is always rebuilt from
        # the inbounds table separately and isn't part of the template; a
        # stale copy of it here would just be ignored, but leaving it out
        # entirely avoids ever giving the impression this pins inbounds too.
        template = {k: v for k, v in live_cfg.items() if k != "inbounds"}
        template.setdefault("log", {})
        template["log"]["access"] = "access.log"
        cur.execute("DELETE FROM settings WHERE key='xrayTemplateConfig'")
        cur.execute("INSERT INTO settings (key, value) VALUES ('xrayTemplateConfig', ?)",
                    (json.dumps(template),))
        conn.commit()
    except Exception as e:
        print(f"[connlog] could not enable the xray access log: {e}", file=sys.stderr)
        return False
    finally:
        conn.close()

    print("[connlog] xray access log was off — enabled it for real per-IP tracking "
          "(the online-stats RPC alone isn't trustworthy on every core build)", file=sys.stderr)
    return True


def _xray_access_log_path():
    """The real on-disk path Xray is currently writing its access log to,
    read straight from the live generated config rather than assumed —
    some builds (3x-ui) rewrite whatever path the template requested to
    confine it under their own log folder. None when logging is off
    ('none'/empty) or the config can't be read."""
    try:
        with open(XUI_XRAY_CONFIG, encoding="utf-8") as f:
            access = str((json.load(f).get("log") or {}).get("access", "")).strip()
    except Exception:
        return None
    if not access or access.lower() == "none":
        return None
    return access


def _parse_xui_access_line(line):
    """Pulls (source_ip, email) out of one Xray access-log line, e.g.:
    '...from 127.0.0.10:37585 accepted tcp:example.com:80 [in-21000-tcp >> direct] email: someone'
    Returns None for a line with no email tag (traffic on an inbound with no
    per-client email — not something this project's own inbounds produce,
    but a hand-added one could) or that otherwise doesn't match."""
    m = _XUI_ACCESS_LINE_RE.search(line)
    if not m:
        return None
    email = m.group("email").strip()
    if not email:
        return None
    addr = m.group("addr")
    if addr.startswith("["):  # bracketed IPv6, e.g. [::1]:1234
        ip = addr[1:addr.find("]")] if "]" in addr else ""
    else:
        ip = addr.rsplit(":", 1)[0] if ":" in addr else addr
    if not ip:
        return None
    return ip, email


def poll_xui_access_log(state):
    """{email: {ip: last_seen_epoch}} built by tailing Xray's access log,
    restricted to entries seen within XUI_ACCESS_IP_WINDOW seconds. `state`
    is {(email, ip): last_seen}, kept across calls by the caller so this
    only ever reads the bytes appended since the previous poll (same
    tailing idiom as poll_failed_logins_authlog).

    Returns None when the log isn't enabled/available at all this cycle —
    distinguishing "can't tell" from "genuinely nobody in the window" the
    same way xray_online_ips() already does for its own source, so a caller
    combining both can tell a real empty result apart from both being down.
    """
    path = _xray_access_log_path()
    if not path or not os.path.exists(path):
        return None

    offset = 0
    if os.path.exists(XUI_ACCESS_LOG_OFFSET_FILE):
        try:
            with open(XUI_ACCESS_LOG_OFFSET_FILE) as f:
                saved_path, saved_off = f.read().strip().split(":", 1)
            if saved_path == path:
                offset = int(saved_off)
        except Exception:
            offset = 0
    try:
        size = os.path.getsize(path)
    except Exception:
        return None
    if size < offset:
        offset = 0  # log rotated

    now = int(time.time())
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            f.seek(offset)
            for line in f:
                parsed = _parse_xui_access_line(line)
                if parsed:
                    ip, email = parsed
                    state[(email, ip)] = now
            offset = f.tell()
    except Exception:
        return None
    try:
        with open(XUI_ACCESS_LOG_OFFSET_FILE, "w") as f:
            f.write(f"{path}:{offset}")
    except Exception:
        pass

    online = {}
    for key in list(state.keys()):
        email, ip = key
        last_seen = state[key]
        if now - last_seen > XUI_ACCESS_IP_WINDOW:
            del state[key]
            continue
        online.setdefault(email, {})[ip] = last_seen
    return online


def _needs_keepalive_fix(sockopt, field):
    current = sockopt.get(field)
    return (
        not isinstance(current, (int, float))
        or isinstance(current, bool)
        or current <= 0
        or current > XUI_KEEPALIVE_SECONDS
    )


def ensure_xui_inbound_keepalive():
    """Make every inbound's socket ask the kernel to probe idle connections,
    so a peer that vanishes without a clean close is reaped in seconds
    instead of sitting "online" for hours — see XUI_KEEPALIVE_SECONDS.
    x-ui does not set this on its own, on any inbound, at any point — new
    ones need it exactly as much as old ones.

    Both tcpKeepAliveIdle (how long a connection may sit with no traffic
    before the first probe) AND tcpKeepAliveInterval (time between
    probes) must be set — they are separate fields in xray's sockopt, and
    setting only one leaves the other on its old default. That old
    default (Linux's tcp_keepalive_time, 7200s system-wide) is exactly
    the multi-hour "still shows connected" symptom this exists to fix, so
    setting interval alone would silently not have fixed it — confirmed
    against a live Xray: interval-only left a killed connection reporting
    online past 120s, both-fields-set cleared it within the first probe
    cycle after the idle period.

    Only touches a field that's missing, non-numeric, zero/negative, or
    looser than our target; a field already configured tighter (an
    admin's own choice) is left alone. Returns True only when at least
    one inbound was actually changed.
    """
    if not os.path.exists(XUI_DB_PATH):
        return False
    try:
        conn = sqlite3.connect(XUI_DB_PATH, timeout=10)
    except Exception:
        return False
    changed_any = False
    try:
        cur = conn.cursor()
        cur.execute("SELECT id, stream_settings FROM inbounds")
        rows = cur.fetchall()
        for inbound_id, ss_str in rows:
            try:
                ss = json.loads(ss_str) if ss_str else {}
            except Exception:
                continue
            sockopt = ss.setdefault("sockopt", {})
            if not (_needs_keepalive_fix(sockopt, "tcpKeepAliveIdle")
                    or _needs_keepalive_fix(sockopt, "tcpKeepAliveInterval")):
                continue
            if _needs_keepalive_fix(sockopt, "tcpKeepAliveIdle"):
                sockopt["tcpKeepAliveIdle"] = XUI_KEEPALIVE_SECONDS
            if _needs_keepalive_fix(sockopt, "tcpKeepAliveInterval"):
                sockopt["tcpKeepAliveInterval"] = XUI_KEEPALIVE_SECONDS
            cur.execute("UPDATE inbounds SET stream_settings=? WHERE id=?",
                        (json.dumps(ss), inbound_id))
            changed_any = True
        if changed_any:
            conn.commit()
    except Exception as e:
        print(f"[connlog] could not check/repair inbound keepalive settings: {e}", file=sys.stderr)
        return False
    finally:
        conn.close()

    if changed_any:
        print(f"[connlog] one or more inbounds had no TCP keepalive configured "
              f"— set tcpKeepAliveIdle/Interval={XUI_KEEPALIVE_SECONDS}s", file=sys.stderr)
    return changed_any


SSHD_MAIN_CONFIG = "/etc/ssh/sshd_config"
SSHD_DROPIN_DIR = "/etc/ssh/sshd_config.d"
# zz- prefix so it sorts last among the drop-ins: OpenSSH keeps the FIRST
# value it sees for a keyword, but a later Include can still be the only
# place a keyword appears at all, and sorting last keeps this file from
# shadowing anything the operator set deliberately in an earlier drop-in.
SSHD_DROPIN = os.path.join(SSHD_DROPIN_DIR, "zz-dahoom-connlog.conf")

# LogLevel VERBOSE is what makes an abruptly-dropped session (scenario B
# above — the common one) produce any log line at all. ClientAlive makes
# sshd notice a silently-vanished client instead of holding the session
# open forever, which both produces scenario C's line and stops a dead
# phone from occupying a device slot.
#
# 60s x 3 = a session is dropped after ~3 minutes of a client not
# answering. These probes are ordinary SSH protocol traffic that every
# compliant client answers on its own, so this does not disturb an idle
# tunnel — but the margin is deliberately generous rather than the 30s
# often suggested for servers: these are phones on mobile data, and one
# that goes quiet through a tunnel or a handover for a minute is normal
# and must not be cut off. Being a couple of minutes slow to notice a
# dead device is a far smaller cost than dropping a live customer.
SSHD_DESIRED = (
    ("loglevel", "LogLevel", "VERBOSE"),
    ("clientaliveinterval", "ClientAliveInterval", "60"),
    ("clientalivecountmax", "ClientAliveCountMax", "3"),
)


def _sshd_effective_config():
    """The settings sshd would actually run with, straight from sshd's own
    parser (`sshd -T`) rather than inferred by reading files — Include
    ordering and first-value-wins make guessing from the text unreliable.
    Returns {keyword_lowercase: value} or None if sshd can't tell us."""
    for exe in ("/usr/sbin/sshd", "/usr/bin/sshd", "sshd"):
        try:
            r = subprocess.run([exe, "-T", "-f", SSHD_MAIN_CONFIG],
                               capture_output=True, text=True, timeout=10)
        except Exception:
            continue
        if r.returncode != 0:
            continue
        cfg = {}
        for line in r.stdout.splitlines():
            parts = line.strip().split(None, 1)
            if len(parts) == 2:
                cfg.setdefault(parts[0].lower(), parts[1])
        return cfg
    return None


def _sshd_config_ok():
    for exe in ("/usr/sbin/sshd", "/usr/bin/sshd", "sshd"):
        try:
            r = subprocess.run([exe, "-t", "-f", SSHD_MAIN_CONFIG],
                               capture_output=True, text=True, timeout=10)
        except Exception:
            continue
        return r.returncode == 0, (r.stderr or "").strip()
    return False, "sshd binary not found"


def ensure_sshd_logging():
    """Make sshd report *why* a session ended, self-healingly and safely.

    Without this, stock sshd (LogLevel INFO, no ClientAlive) logs nothing
    at all when a client drops abruptly or goes silent — which is most
    real disconnects — so the panel can only ever say "unknown".

    Every step is verified against sshd's own parser and fully rolled
    back on any doubt: a VPN box that stops accepting SSH is far worse
    than one that can't explain a disconnect, so this bails out rather
    than leave a config it hasn't confirmed sshd accepts."""
    current = _sshd_effective_config()
    if current is None:
        print("[connlog] could not read sshd's effective config; leaving sshd alone", file=sys.stderr)
        return False
    if all(current.get(key) == want.lower() or current.get(key) == want
           for key, _, want in SSHD_DESIRED):
        return False  # already exactly as needed

    if not os.path.isdir(SSHD_DROPIN_DIR):
        try:
            os.makedirs(SSHD_DROPIN_DIR, exist_ok=True)
        except Exception as e:
            print(f"[connlog] cannot create {SSHD_DROPIN_DIR}: {e}", file=sys.stderr)
            return False

    body = ("# Managed by DAHOOM — lets the panel report why a session ended.\n"
            "# Removing this only costs the disconnect reason; nothing else breaks.\n"
            + "".join(f"{name} {val}\n" for _, name, val in SSHD_DESIRED))

    prev_dropin = None
    if os.path.exists(SSHD_DROPIN):
        try:
            with open(SSHD_DROPIN) as f:
                prev_dropin = f.read()
        except Exception:
            prev_dropin = None
    try:
        with open(SSHD_MAIN_CONFIG) as f:
            prev_main = f.read()
    except Exception as e:
        print(f"[connlog] cannot read {SSHD_MAIN_CONFIG}: {e}", file=sys.stderr)
        return False

    def restore():
        try:
            if prev_dropin is None:
                if os.path.exists(SSHD_DROPIN):
                    os.remove(SSHD_DROPIN)
            else:
                with open(SSHD_DROPIN, "w") as f:
                    f.write(prev_dropin)
            with open(SSHD_MAIN_CONFIG, "w") as f:
                f.write(prev_main)
        except Exception as e:
            print(f"[connlog] WARNING: failed to restore sshd config: {e}", file=sys.stderr)

    try:
        with open(SSHD_DROPIN, "w") as f:
            f.write(body)
        os.chmod(SSHD_DROPIN, 0o600)
    except Exception as e:
        print(f"[connlog] cannot write {SSHD_DROPIN}: {e}", file=sys.stderr)
        return False

    # The drop-in is worthless if nothing includes it. OpenSSH keeps the
    # first value it sees, so the Include has to come before any keyword
    # it means to supply — prepend rather than append.
    include_line = f"Include {SSHD_DROPIN_DIR}/*.conf\n"
    include_re = rf"(?m)^\s*Include\s+{re.escape(SSHD_DROPIN_DIR)}/"
    if not re.search(include_re, prev_main):
        try:
            with open(SSHD_MAIN_CONFIG, "w") as f:
                f.write(include_line + prev_main)
        except Exception as e:
            print(f"[connlog] cannot add Include to sshd_config: {e}", file=sys.stderr)
            restore()
            return False

    ok, err = _sshd_config_ok()
    if not ok:
        print(f"[connlog] sshd rejected the new config, reverting: {err}", file=sys.stderr)
        restore()
        return False

    now = _sshd_effective_config()
    missing = [name for key, name, want in SSHD_DESIRED
               if now is None or (now.get(key) != want.lower() and now.get(key) != want)]
    if missing:
        # Something earlier in the main config already pinned these and
        # wins on first-value-wins. Comment those lines out (they are
        # restored wholesale if this doesn't pan out) and re-verify.
        pinned = "|".join(re.escape(name) for _, name, _ in SSHD_DESIRED)
        patched = re.sub(rf"(?mi)^(\s*(?:{pinned})\s+.*)$", r"# \1  # superseded by DAHOOM", prev_main)
        if not re.search(include_re, patched):
            patched = include_line + patched
        try:
            with open(SSHD_MAIN_CONFIG, "w") as f:
                f.write(patched)
        except Exception as e:
            print(f"[connlog] cannot patch sshd_config: {e}", file=sys.stderr)
            restore()
            return False
        ok, err = _sshd_config_ok()
        now = _sshd_effective_config() if ok else None
        still = [name for key, name, want in SSHD_DESIRED
                 if now is None or (now.get(key) != want.lower() and now.get(key) != want)]
        if not ok or still:
            print(f"[connlog] could not make sshd apply {still or missing}, reverting", file=sys.stderr)
            restore()
            return False

    # reload, not restart: established sessions must survive this.
    for unit in ("ssh", "sshd"):
        try:
            r = subprocess.run(["systemctl", "reload", unit], capture_output=True, text=True, timeout=15)
            if r.returncode == 0:
                print(f"[connlog] sshd now logs disconnect reasons (LogLevel VERBOSE + ClientAlive)", file=sys.stderr)
                return True
        except Exception:
            continue
    print("[connlog] sshd config updated but reload failed; it applies on the next sshd restart", file=sys.stderr)
    return True


def ensure_xray_health():
    """Run both one-time xray config repairs and restart x-ui once if
    either changed something — never twice, and never for no reason."""
    changed = False
    try:
        changed = ensure_xray_online_stats() or changed
    except Exception as e:
        print(f"[connlog] xray online-stats check failed: {e}", file=sys.stderr)
    try:
        changed = ensure_xray_access_log() or changed
    except Exception as e:
        print(f"[connlog] xray access-log check failed: {e}", file=sys.stderr)
    try:
        changed = ensure_xui_inbound_keepalive() or changed
    except Exception as e:
        print(f"[connlog] xray keepalive check failed: {e}", file=sys.stderr)
    if changed:
        print("[connlog] restarting x-ui to apply the config repair(s) above", file=sys.stderr)
        try:
            subprocess.run(["systemctl", "restart", "x-ui"], capture_output=True, timeout=60)
        except Exception as e:
            print(f"[connlog] x-ui restart failed, apply it manually: {e}", file=sys.stderr)
    return changed


def xray_online_ips():
    """{email: {ip: last_seen_epoch}} for every currently-online client.
    Returns None (not {}) when the API itself is unreachable, so callers
    can tell "nobody online" apart from "can't ask"."""
    data = _xray_api("statsonlineiplist", "-all")
    if data is None:
        return None
    result = {}
    for user in (data.get("users") or []):
        email = user.get("email") or ""
        if not email:
            continue
        ips = {}
        for entry in (user.get("ips") or []):
            ip = entry.get("ip")
            if ip:
                try:
                    ips[ip] = int(entry.get("lastSeen") or 0)
                except (TypeError, ValueError):
                    ips[ip] = 0
        if ips:
            result[email] = ips
    return result


def _xui_traffic_snapshot():
    if not os.path.exists(XUI_DB_PATH):
        return {}
    try:
        conn = sqlite3.connect(f"file:{XUI_DB_PATH}?mode=ro", uri=True, timeout=5)
        try:
            cur = conn.cursor()
            cur.execute("SELECT inbound_id, email, up, down FROM client_traffics")
            return {(iid, email): (up or 0) + (down or 0) for iid, email, up, down in cur.fetchall()}
        finally:
            conn.close()
    except Exception:
        return {}


def poll_xui_ips(conn, ip_state, access_log_state):
    """Real per-device tracking: one open row per (client email, IP), with
    the IP recorded, merged from the two sources that can report it — the
    core's online-stats RPC (real-time, but confirmed unreliable on some
    builds, see poll_xui_access_log) and Xray's own access log (always
    reliable, but only knows about a connection at accept time). Neither
    source is trusted alone: the RPC because it can silently report nothing,
    the access log because a single line can't prove a session is still
    open (see XUI_ACCESS_IP_WINDOW). Together they cover for each other.

    ip_state: {(email, ip): {'row_id', 'last_seen'}}
    access_log_state: {(email, ip): last_seen} — poll_xui_access_log's own
    state, threaded through here only so both sources are read together and
    merged into one 'online' view before any row bookkeeping happens.
    Returns the online map ({email: {ip: last_seen}}) so the caller can
    reuse it for limit enforcement, or None if BOTH sources came back
    unavailable this cycle (xray not running, no binary, log not enabled)."""
    rpc_online = xray_online_ips()
    al_online = poll_xui_access_log(access_log_state)
    if rpc_online is None and al_online is None:
        return None
    online = {}
    for source in (rpc_online, al_online):
        if not source:
            continue
        for email, ips in source.items():
            dest = online.setdefault(email, {})
            for ip, ts in ips.items():
                if ip not in dest or ts > dest[ip]:
                    dest[ip] = ts
    now = int(time.time())
    cur = conn.cursor()

    for email, ips in online.items():
        for ip in ips:
            key = (email, ip)
            st = ip_state.get(key)
            if st is None or st.get("row_id") is None:
                cur.execute(
                    "INSERT INTO connections (source, username, ip, status, session_key, connect_time, extra) "
                    "VALUES ('xui', ?, ?, 'success', ?, ?, ?)",
                    (email, ip, f"xui:{email}:{ip}:{now}", now, json.dumps({"via": "xray-api"})),
                )
                ip_state[key] = {"row_id": cur.lastrowid, "last_seen": now}
                conn.commit()
            else:
                st["last_seen"] = now

    # An (email, ip) Xray no longer reports has gone away — close its row
    # once it has been missing long enough to not just be a poll gap.
    for key in list(ip_state.keys()):
        email, ip = key
        if ip in (online.get(email) or {}):
            continue
        st = ip_state[key]
        if now - st.get("last_seen", now) < XUI_IP_STALE:
            continue
        if st.get("row_id") is not None:
            started = int(_row_connect_time(conn, st["row_id"]))
            cur.execute(
                "UPDATE connections SET disconnect_time=?, duration_seconds=? WHERE id=?",
                (st["last_seen"], max(0, st["last_seen"] - started), st["row_id"]),
            )
            conn.commit()
        del ip_state[key]

    return online


def xui_client_ip_limits():
    """{email: {"limit", "tag", "port"}} for every X-UI client that has a
    device limit set. limitIp lives in the inbound's own settings JSON,
    alongside the tag (to scope the sib block rule) and port (to scope the
    ss -K kill of already-open excess sockets — sib only stops new dials)."""
    if not os.path.exists(XUI_DB_PATH):
        return {}
    try:
        conn = sqlite3.connect(f"file:{XUI_DB_PATH}?mode=ro", uri=True, timeout=5)
        try:
            cur = conn.cursor()
            cur.execute("SELECT tag, port, settings FROM inbounds WHERE enable=1")
            rows = cur.fetchall()
        finally:
            conn.close()
    except Exception:
        return {}
    limits = {}
    for tag, port, settings_str in rows:
        try:
            clients = (json.loads(settings_str or "{}") or {}).get("clients") or []
        except Exception:
            continue
        for c in clients:
            email = c.get("email") or ""
            try:
                limit = int(c.get("limitIp") or 0)
            except (TypeError, ValueError):
                limit = 0
            if email and limit > 0:
                limits[email] = {"limit": limit, "tag": tag or "", "port": port}
    return limits


def enforce_xui_ip_limits(conn, online, blocked_state):
    """Block only the devices beyond each client's allowance.

    Which IPs are "beyond" is decided by when each device first connected
    (its open row's connect_time) — the first N devices keep working and
    only later ones are cut, so a paying customer's own phone isn't the
    one dropped because someone else shared their link.

    Blocking is Xray's own source-IP routing rule: matching traffic goes
    to the blackhole outbound. It applies live, needs no restart, and is
    rebuilt from scratch every cycle — so an IP stops being blocked as
    soon as it is no longer in excess. blocked_state carries the last
    applied set per inbound tag so we only call the API when it changes.

    A newly-blocked IP also gets its already-established socket killed via
    `ss -K` — the routing rule alone only affects a future dial, so without
    this an excess device that connected before this cycle ran would just
    keep working, undisturbed, until it happened to reconnect on its own.
    """
    limits = xui_client_ip_limits()
    if not limits:
        limits = {}

    # earliest-seen-first ordering per client, from the rows we opened
    first_seen = {}
    cur = conn.cursor()
    cur.execute(
        "SELECT username, ip, MIN(connect_time) FROM connections "
        "WHERE source='xui' AND status='success' AND disconnect_time IS NULL "
        "AND ip IS NOT NULL GROUP BY username, ip"
    )
    for email, ip, started in cur.fetchall():
        first_seen[(email, ip)] = started or 0

    per_tag = {}
    port_by_tag = {}
    over = []
    for email, ips in (online or {}).items():
        info = limits.get(email)
        if not info:
            continue
        limit, tag = info["limit"], info["tag"]
        if tag:
            port_by_tag[tag] = info.get("port")
        if len(ips) <= limit:
            continue
        ordered = sorted(ips, key=lambda ip: (first_seen.get((email, ip), 0), ip))
        excess = ordered[limit:]
        per_tag.setdefault(tag, set()).update(excess)
        over.append((email, limit, len(ips), excess))

    # Every inbound we have ever blocked on must be revisited, otherwise a
    # tag that just dropped to zero excess would keep its stale block rule.
    for tag in list(blocked_state.keys()):
        per_tag.setdefault(tag, set())

    for tag, ips in per_tag.items():
        if not tag:
            continue
        if blocked_state.get(tag) == ips:
            continue
        # An empty set still needs a call to clear the rule; xray has no
        # "remove" verb here, so point the rule at a documentation-range
        # address (RFC 5737) that can never be a real client.
        targets = sorted(ips) if ips else ["192.0.2.0/32"]
        res = _xray_api("sib", "-outbound=blocked", f"-inbound={tag}", "-reset", *targets)
        if res is None:
            continue  # API unreachable — keep old state and retry next cycle
        blocked_state[tag] = set(ips)
        # sib only affects the routing decision for a NEW dial — it does
        # nothing for a device's connection that was already open before it
        # became excess (e.g. a 2nd/3rd device that connected before this
        # cycle ever ran). Killing the already-established socket for each
        # newly-blocked IP is what actually disconnects it now instead of
        # leaving it running until it happens to reconnect on its own.
        port = port_by_tag.get(tag)
        if port:
            for ip in ips:
                try:
                    subprocess.run(
                        ["ss", "-K", "dst", ip, "sport", "=", f":{port}"],
                        capture_output=True, timeout=5,
                    )
                except Exception:
                    pass  # best-effort — the sib rule above still stops a reconnect

    for email, limit, count, excess in over:
        print(f"[connlog] ip-limit: {email} allows {limit} device(s), {count} online — blocking {', '.join(excess)}",
              file=sys.stderr)


def poll_xui(conn, xui_state, skip_emails=None):
    """xui_state: {(inbound_id,email): {'last_total','last_change_time','row_id'}}

    skip_emails: emails poll_xui_ips already reported as online THIS cycle —
    trust that precise, IP-attributed signal for them and don't also derive
    activity from traffic deltas, which would double-count the same client
    once from each mechanism. Confirmed in the wild: some xray-core builds
    answer the online-IP-list RPC as "supported" (no Unimplemented error)
    but never actually populate it, even for a real, currently-open,
    actively-transferring connection — the RPC call itself isn't a reliable
    signal that it's WORKING, only that it exists. Emails not in this set
    still fall through to the traffic-delta check below, so a client stuck
    in that broken state is still caught the moment its byte counters move,
    instead of showing 0 sessions forever despite real traffic."""
    skip_emails = skip_emails or set()
    snap = _xui_traffic_snapshot()
    now = int(time.time())
    cur = conn.cursor()
    for key, total in snap.items():
        inbound_id, email = key
        st = xui_state.get(key)
        if email in skip_emails:
            # Xray's own online-IP list is precisely tracking this client
            # this cycle — close any stale fallback row from an earlier
            # cycle where it wasn't, so the client isn't counted as two
            # separate devices (one with a real IP, one without).
            if st is not None and st.get("row_id") is not None:
                duration = max(0, now - int(_row_connect_time(conn, st["row_id"])))
                cur.execute(
                    "UPDATE connections SET disconnect_time=?, duration_seconds=? WHERE id=?",
                    (now, duration, st["row_id"]),
                )
                conn.commit()
                st["row_id"] = None
            xui_state[key] = {"last_total": total, "last_change_time": now, "row_id": None}
            continue
        if st is None:
            xui_state[key] = {"last_total": total, "last_change_time": now, "row_id": None}
            continue
        if total > st["last_total"]:
            st["last_total"] = total
            st["last_change_time"] = now
            if st["row_id"] is None:
                inbound_id, email = key
                cur.execute(
                    "INSERT INTO connections (source, username, status, session_key, connect_time, extra) "
                    "VALUES ('xui', ?, 'success', ?, ?, ?)",
                    (email, f"xui:{inbound_id}:{email}:{now}", now, json.dumps({"inbound_id": inbound_id})),
                )
                st["row_id"] = cur.lastrowid
                conn.commit()
        elif st["row_id"] is not None and (now - st["last_change_time"]) >= XUI_IDLE_CLOSE:
            duration = max(0, st["last_change_time"] - int(_row_connect_time(conn, st["row_id"])))
            cur.execute(
                "UPDATE connections SET disconnect_time=?, duration_seconds=? WHERE id=?",
                (st["last_change_time"], duration, st["row_id"]),
            )
            conn.commit()
            st["row_id"] = None

    # keys that disappeared entirely (client deleted) — close any open row
    for key in list(xui_state.keys()):
        if key not in snap and xui_state[key]["row_id"] is not None:
            st = xui_state[key]
            duration = max(0, now - int(_row_connect_time(conn, st["row_id"])))
            cur.execute(
                "UPDATE connections SET disconnect_time=?, duration_seconds=? WHERE id=?",
                (now, duration, st["row_id"]),
            )
            conn.commit()
            del xui_state[key]


def _row_connect_time(conn, row_id):
    cur = conn.cursor()
    cur.execute("SELECT connect_time FROM connections WHERE id=?", (row_id,))
    row = cur.fetchone()
    return row[0] if row else time.time()


def prune_old_rows(conn):
    """Age out by last activity (disconnect_time if the row has one —
    which failed rows always do now, since _upsert_failed_row sets it on
    every attempt — otherwise connect_time). A still-open 'success' row
    (a live connection) is never touched regardless of how old
    connect_time is; everything else ages out normally. The original
    version of this only ever matched closed 'success' rows, so failed-
    login rows — the ones that actually pile up from internet-wide bot
    scanning — were never pruned at all and grew forever."""
    cutoff = int(time.time()) - RETENTION_DAYS * 86400
    conn.execute(
        "DELETE FROM connections WHERE COALESCE(disconnect_time, connect_time) < ? "
        "AND (status != 'success' OR disconnect_time IS NOT NULL)",
        (cutoff,),
    )
    conn.commit()


def _close_dangling_open_rows(conn):
    """On (re)start, active_ssh/xui_state both start empty in memory, so
    any row still marked open (disconnect_time IS NULL) from a previous
    run of this daemon can never be closed by pid/traffic matching again
    — close it out now rather than let it show as 'connected forever'.
    Genuinely still-active connections get a fresh, correctly-dated row
    within the next poll cycle since they're picked up as 'new'.

    These rows also carry their own answer to "why did it end?", and it
    is one sshd could never have given us (scenario E): a session that
    began before the current boot ended because the machine went down,
    and one that began after it was only interrupted by this daemon
    restarting — which is not the user's connection dropping at all, so
    it says so rather than blaming the user's side."""
    now = int(time.time())
    try:
        boot = int(_boot_epoch())
    except Exception:
        boot = None
    conn.execute(
        "UPDATE connections SET disconnect_time=?, duration_seconds=CASE WHEN connect_time IS NOT NULL THEN MAX(0, ?-connect_time) ELSE NULL END "
        "WHERE status='success' AND disconnect_time IS NULL",
        (now, now),
    )
    if boot:
        # Only ever fills a blank — a reason already established from a
        # log line or from panel.py's kill is the more specific truth.
        conn.execute(
            "UPDATE connections SET fail_reason=? WHERE status='success' AND fail_reason IS NULL "
            "AND disconnect_time=? AND connect_time < ?",
            ("أُعيد تشغيل السيرفر", now, boot),
        )
        conn.execute(
            "UPDATE connections SET fail_reason=? WHERE status='success' AND fail_reason IS NULL "
            "AND disconnect_time=? AND connect_time >= ?",
            ("أُعيد تشغيل خدمة المراقبة (ربما استمر اتصال المستخدم)", now, boot),
        )
    conn.commit()


# A server-side event — sshd restarting, the box hanging under load, the
# uplink dropping — takes every live session down at once, so connlog
# closes them all in a single poll cycle and they end up sharing one
# exact disconnect_time (poll_ssh stamps one `now` per cycle). Individual
# users quitting are independent events and essentially never land on the
# same second in this number. That clustering is the only evidence such
# an outage leaves behind, since sshd logs nothing per-session for it.
_MASS_DISCONNECT_MIN = 3
# Rows younger than the reason TTL may still be waiting for their own log
# line; rows older than this are long settled and not worth re-scanning.
_MASS_DISCONNECT_MAX_AGE = 6 * 3600


def finalize_unknown_reasons(conn):
    """Label reason-less sessions that clearly went down together."""
    now = int(time.time())
    cur = conn.cursor()
    cur.execute(
        "SELECT disconnect_time, COUNT(*), SUM(fail_reason IS NULL) FROM connections "
        "WHERE source='ssh' AND status='success' AND disconnect_time IS NOT NULL "
        "AND disconnect_time BETWEEN ? AND ? GROUP BY disconnect_time HAVING COUNT(*) >= ?",
        (now - _MASS_DISCONNECT_MAX_AGE, now - _DISCONNECT_REASON_TTL, _MASS_DISCONNECT_MIN),
    )
    for dt, _total, blank in cur.fetchall():
        if not blank:
            continue
        conn.execute(
            "UPDATE connections SET fail_reason=? WHERE source='ssh' AND status='success' "
            "AND disconnect_time=? AND fail_reason IS NULL",
            # Ends with the Latin word rather than wrapping it in
            # brackets: a "(... SSH)" tail gets its closing bracket
            # yanked to the start of the line by the bidi algorithm.
            ("انقطاع جماعي لعدة جلسات في نفس اللحظة — غالبًا ضغط أو تعليق في السيرفر أو إعادة تشغيل خدمة SSH", dt),
        )
    conn.commit()


def report_disconnect_reason_readiness():
    """One clear line at startup saying whether disconnect reasons can
    actually work right now, so a stale daemon or a log source that is
    not what we assume is visible in `journalctl -u firewallfalcon-connlog`
    instead of having to be inferred from missing data in the panel."""
    eff = _sshd_effective_config() or {}
    lvl = eff.get("loglevel", "?")
    alive = eff.get("clientaliveinterval", "?")
    src = next((p for p in AUTH_LOG_PATHS if os.path.exists(p)), None)
    src_desc = src or "journalctl"
    ready = "yes" if str(lvl).upper() == "VERBOSE" else "PARTIAL (abrupt drops stay unknown)"
    print(f"[connlog] disconnect reasons: {ready} "
          f"(sshd LogLevel={lvl}, ClientAliveInterval={alive}, log source={src_desc})",
          file=sys.stderr)


def main():
    init_db()
    # Make sure xray is actually configured to report online IPs, and to
    # detect a dead peer promptly, before we start relying on either —
    # otherwise every X-UI feature downstream (real IPs, device count, the
    # device limit, and how fast a disconnected device stops showing as
    # connected) silently misbehaves.
    ensure_xray_health()
    # Without this, sshd stays silent about most disconnects and every
    # ended session can only ever be reported as "unknown".
    try:
        ensure_sshd_logging()
    except Exception as e:
        print(f"[connlog] sshd logging check failed: {e}", file=sys.stderr)
    try:
        report_disconnect_reason_readiness()
    except Exception:
        pass
    conn = _db()
    _close_dangling_open_rows(conn)
    active_ssh = {}
    xui_state = {}
    xui_ip_state = {}
    xui_access_log_state = {}
    xui_blocked = {}
    cycle = 0
    last_prune = 0
    while True:
        try:
            poll_ssh(conn, active_ssh)
        except Exception as e:
            print(f"[connlog] ssh poll error: {e}", file=sys.stderr)
        try:
            poll_failed_logins(conn)
        except Exception as e:
            print(f"[connlog] failed-login poll error: {e}", file=sys.stderr)
        try:
            finalize_unknown_reasons(conn)
        except Exception as e:
            print(f"[connlog] reason finalize error: {e}", file=sys.stderr)
        if cycle % XUI_POLL_EVERY == 0:
            try:
                # Preferred path: Xray's own online-IP list gives real
                # per-device rows *with* an IP, and makes the per-client
                # device limit enforceable. If Xray can't be asked at all,
                # fall back to the IP-less traffic-delta heuristic for
                # everyone. If it CAN be asked but comes back with fewer
                # clients than are actually transferring data (confirmed
                # real-world case, not hypothetical: a core that answers
                # the RPC as supported yet never populates it for a real,
                # live connection), still run the traffic-delta check for
                # whichever emails it didn't report — same fallback, just
                # scoped to the gap instead of all-or-nothing.
                online = poll_xui_ips(conn, xui_ip_state, xui_access_log_state)
                if online is None:
                    poll_xui(conn, xui_state)
                else:
                    try:
                        enforce_xui_ip_limits(conn, online, xui_blocked)
                    except Exception as e:
                        print(f"[connlog] xui ip-limit error: {e}", file=sys.stderr)
                    try:
                        poll_xui(conn, xui_state, skip_emails=set(online.keys()))
                    except Exception as e:
                        print(f"[connlog] xui traffic-delta poll error: {e}", file=sys.stderr)
            except Exception as e:
                print(f"[connlog] xui poll error: {e}", file=sys.stderr)
        now = time.time()
        if now - last_prune > 3600:
            try:
                prune_old_rows(conn)
            except Exception:
                pass
            last_prune = now
        cycle += 1
        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
