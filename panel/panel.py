#!/usr/bin/env python3
import os
import sys
import json
import math
import time
import subprocess
import tempfile
import secrets
import hashlib
import threading
import re
import sqlite3
import uuid
import base64
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from http import cookies
from urllib.parse import urlparse, parse_qs
import urllib.request
import urllib.error
import urllib.parse
from datetime import datetime, timedelta

# Ensure local directories are in python search path
for _p in ["/etc/firewallfalcon/panel", "/usr/local/bin", os.path.dirname(os.path.abspath(__file__))]:
    if _p and _p not in sys.path:
        sys.path.insert(0, _p)

# --- CONSTANTS ---
DB_FILE = "/etc/firewallfalcon/users.db"
RESELLERS_DB = "/etc/firewallfalcon/resellers.db"
BW_DIR = "/etc/firewallfalcon/bandwidth"
USER_NOTES_FILE = "/etc/firewallfalcon/user_notes.json"
LOGIN_MODES_FILE = "/etc/firewallfalcon/login_modes.db"
PANEL_CONF = "/etc/firewallfalcon/panel.conf"
PANEL_HTML = "/etc/firewallfalcon/panel/index.html"
PANEL_RESELLER_HTML = "/etc/firewallfalcon/panel/reseller.html"
RESELLER_KEY_FILE = "/etc/firewallfalcon/panel/reseller.key"
FF_USERS_GROUP = "firewallfalcon-users"
PORT = 44380
IP_BLACKLIST_CONF = "/etc/firewallfalcon/ip_blacklist.conf"
IP_WHITELIST_CONF = "/etc/firewallfalcon/ip_whitelist.conf"
USER_SPEED_CONF = "/etc/firewallfalcon/user_speeds.conf"
CLOUDFLARE_INFO = "/etc/firewallfalcon/cloudflare.info"
LOGS_DIR = "/etc/firewallfalcon/logs"

# --- User Bandwidth Status Link ---
BW_LINK_TOKENS_DB = "/etc/firewallfalcon/bandwidth_tokens.db"
BW_LINK_SCRIPT = "/usr/local/bin/firewallfalcon-bwlink.py"
BW_LINK_SERVICE_FILE = "/etc/systemd/system/firewallfalcon-bwlink.service"
BW_LINK_PORT = 47653
# Decrypted alongside panel.py itself by menu.sh's _fm_pull_src — already on
# disk in plaintext by the time panel.py runs, no decryption needed here.
FM_SRC_BW_LINK = "/etc/firewallfalcon/.src/panel/bandwidth_link.py"

# --- Connection Log Daemon ---
# update_panel.sh installs & enables this unconditionally on every
# install/update (unlike the bandwidth link, which is opt-in per user,
# this is core: real connect/disconnect/failed-login tracking, since
# `last`/`lastb` structurally can never show these accounts — see
# connlog.py's own module docstring for why). ensure_connlog_service()
# below is a defensive fallback for the rare case an existing install's
# panel.py got updated some other way.
CONNLOG_DB_PATH = "/etc/firewallfalcon/connection_log.db"
CONNLOG_SCRIPT = "/usr/local/bin/firewallfalcon-connlog.py"
CONNLOG_SERVICE_FILE = "/etc/systemd/system/firewallfalcon-connlog.service"
FM_SRC_CONNLOG = "/etc/firewallfalcon/.src/panel/connlog.py"

# Fallback for development environments
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if not os.path.exists(PANEL_HTML):
    PANEL_HTML = os.path.join(_SCRIPT_DIR, "index.html")
if not os.path.exists(PANEL_RESELLER_HTML):
    PANEL_RESELLER_HTML = os.path.join(_SCRIPT_DIR, "reseller.html")
if not os.path.exists("/etc/firewallfalcon/panel"):
    RESELLER_KEY_FILE = os.path.join(_SCRIPT_DIR, "reseller.key")

# --- CLOUDFLARE CACHE & HELPERS ---
_CF_CACHE = {
    "status": None,
    "status_ts": 0,
    "records": None,
    "records_ts": 0
}
_CF_CACHE_TTL = 5.0  # 5 seconds smart cache

def invalidate_cf_cache():
    global _CF_CACHE
    _CF_CACHE["status"] = None
    _CF_CACHE["status_ts"] = 0
    _CF_CACHE["records"] = None
    _CF_CACHE["records_ts"] = 0

def read_cloudflare_config():
    cfg = {
        "api_token": "",
        "zone_id": "",
        "domain": "",
        "proxied": False
    }
    target_files = [CLOUDFLARE_INFO, "/etc/firewallfalcon/cloudflare.conf"]
    info_file = None
    for tf in target_files:
        if os.path.exists(tf):
            info_file = tf
            break
    if not info_file:
        return cfg
    try:
        with open(info_file, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip().replace("\r", "")
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    k, v = line.split("=", 1)
                    k = k.strip().upper()
                    v = v.strip().strip('"').strip("'")
                    if k in ("CF_API_TOKEN", "API_TOKEN", "TOKEN"):
                        cfg["api_token"] = v
                    elif k in ("CF_ZONE_ID", "ZONE_ID", "ZONE"):
                        cfg["zone_id"] = v
                    elif k in ("CF_DOMAIN", "DOMAIN"):
                        cfg["domain"] = v
                    elif k in ("CF_PROXIED", "PROXIED"):
                        cfg["proxied"] = (v == "1" or v.lower() in ("true", "yes", "on"))
    except Exception as e:
        print(f"Error reading cloudflare info: {e}", file=sys.stderr)
    return cfg

def write_cloudflare_config(api_token, zone_id, domain, proxied=False):
    invalidate_cf_cache()
    os.makedirs(os.path.dirname(CLOUDFLARE_INFO), exist_ok=True)
    p_val = "1" if proxied else "0"
    content = f'''CF_API_TOKEN="{api_token}"
CF_ZONE_ID="{zone_id}"
CF_DOMAIN="{domain}"
CF_PROXIED="{p_val}"
'''
    with open(CLOUDFLARE_INFO, "w", encoding="utf-8") as f:
        f.write(content)
    try:
        os.chmod(CLOUDFLARE_INFO, 0o600)
    except Exception:
        pass

def cf_api_request(endpoint, method="GET", data=None, token=None):
    if not token:
        cfg = read_cloudflare_config()
        token = cfg.get("api_token", "")
    if not token:
        raise Exception("Cloudflare API Token غير متوفر")
    
    url = f"https://api.cloudflare.com/client/v4{endpoint}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "User-Agent": "DAHOOM-Panel"
    }
    body_bytes = json.dumps(data).encode("utf-8") if data is not None else None
    req = urllib.request.Request(url, data=body_bytes, headers=headers, method=method)
    
    try:
        with urllib.request.urlopen(req, timeout=12) as response:
            res_data = response.read().decode("utf-8")
            return json.loads(res_data)
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="ignore")
        err_msgs = []
        try:
            err_json = json.loads(err_body)
            if isinstance(err_json, dict):
                for err in err_json.get("errors", []):
                    msg = err.get("message", "")
                    if msg:
                        err_msgs.append(msg)
                    for ch in err.get("error_chain", []):
                        ch_msg = ch.get("message", "")
                        if ch_msg and ch_msg not in err_msgs:
                            err_msgs.append(ch_msg)
                for msg in err_json.get("messages", []):
                    if isinstance(msg, str) and msg not in err_msgs:
                        err_msgs.append(msg)
                    elif isinstance(msg, dict) and msg.get("message") and msg.get("message") not in err_msgs:
                        err_msgs.append(msg.get("message"))
        except Exception:
            pass
        if err_msgs:
            raise Exception(" | ".join(err_msgs))
        raise Exception(f"HTTP {e.code}: {e.reason}")
    except Exception as e:
        raise Exception(f"خطأ في الاتصال مع Cloudflare: {str(e)}")

def write_categorized_log(category, level, operator, action, target, details="", client_ip=""):
    try:
        os.makedirs(LOGS_DIR, exist_ok=True)
        log_map = {
            "admin": "admin_audit.log",
            "clients": "client_connections.log",
            "services": "service_health.log",
            "security": "security_alerts.log",
            "reseller": "reseller_audit.log"
        }
        fname = log_map.get(category, "admin_audit.log")
        fpath = os.path.join(LOGS_DIR, fname)
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        ip_part = f" | {client_ip}" if client_ip else ""
        line = f"{ts} | {level:<4} | {operator:<10} | {action:<14} | {target:<15} | {details}{ip_part}\n"
        with open(fpath, "a", encoding="utf-8") as f:
            f.write(line)
    except Exception:
        pass

# --- GLOBAL STATE ---
SESSION_FILE = "/etc/firewallfalcon/sessions.json"
sessions = {}  # token -> {"username": str, "role": "admin"|"reseller", "created_at": float}

# --- LOGIN BRUTE-FORCE PROTECTION ---
# In-memory only (per-process): the panel is a single ThreadingHTTPServer
# process, and a restart clearing this is an acceptable tradeoff for not
# having to persist/rotate yet another file. Keyed by client IP.
_LOGIN_ATTEMPTS = {}   # ip -> {"count": int, "first_ts": float, "locked_until": float}
_LOGIN_LOCK = threading.Lock()
LOGIN_MAX_ATTEMPTS = 5
LOGIN_WINDOW_SEC = 15 * 60
LOGIN_LOCKOUT_SEC = 15 * 60

def _login_lockout_remaining(ip):
    """Seconds left in an active lockout for this IP, or 0 if not locked."""
    with _LOGIN_LOCK:
        rec = _LOGIN_ATTEMPTS.get(ip)
        if not rec:
            return 0
        remaining = rec.get("locked_until", 0) - time.time()
        return int(remaining) if remaining > 0 else 0

def _login_record_failure(ip):
    now = time.time()
    with _LOGIN_LOCK:
        rec = _LOGIN_ATTEMPTS.get(ip)
        if not rec or now - rec.get("first_ts", 0) > LOGIN_WINDOW_SEC:
            rec = {"count": 0, "first_ts": now, "locked_until": 0}
        rec["count"] += 1
        if rec["count"] >= LOGIN_MAX_ATTEMPTS:
            rec["locked_until"] = now + LOGIN_LOCKOUT_SEC
        _LOGIN_ATTEMPTS[ip] = rec

def _login_clear_failures(ip):
    with _LOGIN_LOCK:
        _LOGIN_ATTEMPTS.pop(ip, None)

def load_sessions():
    global sessions
    try:
        if os.path.exists(SESSION_FILE):
            with open(SESSION_FILE, "r") as f:
                sessions = json.load(f)
    except Exception:
        sessions = {}

def save_sessions():
    try:
        os.makedirs(os.path.dirname(SESSION_FILE), exist_ok=True)
        with open(SESSION_FILE, "w") as f:
            json.dump(sessions, f)
    except Exception:
        pass

load_sessions()
db_lock = threading.Lock()

PROTOCOLS = [
    {"name": "OpenSSH", "service": "sshd", "service_alt": "ssh", "check_file": None, "port": "22"},
    {"name": "SSL / TLS Tunnel", "service": "stunnel4", "service_alt": "stunnel", "check_file": "/etc/stunnel/stunnel.conf", "port": "444/442"},
    {"name": "BadVPN (UDPGW)", "service": "badvpn", "check_file": "/etc/systemd/system/badvpn.service", "port": "7300"},
    {"name": "UDP Custom", "service": "udp-custom", "check_file": "/etc/systemd/system/udp-custom.service", "port": "36712"},
    {"name": "HAProxy Edge", "service": "haproxy", "check_file": "/etc/haproxy/haproxy.cfg", "port": "80/443"},
    {"name": "Nginx Proxy", "service": "nginx", "check_file": "/etc/nginx/nginx.conf", "port": "8880/8443"},
    {"name": "DNSTT (SlowDNS)", "service": "dnstt", "check_file": "/etc/systemd/system/dnstt.service", "port": "53"},
    {"name": "Net Relay", "service": "netrelay", "check_file": "/etc/systemd/system/netrelay.service", "port": "8080"},
    {"name": "ZiVPN UDP", "service": "zivpn", "check_file": "/etc/systemd/system/zivpn.service", "port": "5667"},
    {"name": "X-UI / 3X-UI", "service": "x-ui", "service_alt": "3x-ui", "check_file": "/etc/systemd/system/x-ui.service", "port": "2053"},
    {"name": "Xray Core (V2Ray / Reality)", "service": "xray", "service_alt": "xray-core", "check_file": "/usr/local/bin/xray", "port": "8443/2052/2096"},
    {"name": "Multi-Login Limiter", "service": "firewallfalcon-limiter", "check_file": "/etc/systemd/system/firewallfalcon-limiter.service", "port": "Daemon"},
    {"name": "Bandwidth Monitor", "service": "firewallfalcon-bandwidth", "check_file": "/etc/systemd/system/firewallfalcon-bandwidth.service", "port": "Daemon"},
    {"name": "Outage & Health Guard", "service": "firewallfalcon-health", "check_file": "/etc/systemd/system/firewallfalcon-health.service", "port": "Daemon"},
]

# --- X-UI BRIDGE ---
# X-UI (the third-party panel, installed separately via install_xui_panel() in
# menu.sh) keeps its own SQLite database — completely independent of this
# panel's users.db/v2ray_users.db. There is no API bridge between the two
# systems by design elsewhere in this project; the functions below ARE that
# bridge, so this panel can create/list/delete X-UI clients without needing
# X-UI's own web UI at all.
#
# Approach: read-modify-write X-UI's own tables directly (matching exactly
# what X-UI's own /xui/inbound/addClient handler does internally), then
# restart the x-ui service so the running Xray core picks up the change.
# X-UI itself normally adds a client to the live Xray core over its gRPC API
# without a restart, but replicating that API from here would mean
# reimplementing a chunk of Xray's control-plane protocol for no real
# benefit — a restart is slower (drops active connections for ~1s) but is
# far simpler and exactly as correct. Verified end-to-end in a real X-UI
# install: a client added this way (raw DB write + restart) authenticates
# real VLESS traffic and gets its usage tracked by X-UI's own dashboard
# identically to a client added through X-UI's native "Add Client" button —
# confirmed via a live vless:// connection through it and non-zero traffic
# recorded in X-UI's own client_traffics table.
XUI_DB_PATH = "/etc/x-ui/x-ui.db"


def xui_installed():
    return os.path.exists("/etc/systemd/system/x-ui.service") or os.path.exists(XUI_DB_PATH)


def _xui_db():
    conn = sqlite3.connect(XUI_DB_PATH, timeout=10)
    conn.execute("PRAGMA busy_timeout=10000")
    return conn


# ── 3X-UI (MHSanaei) support ─────────────────────────────────────────────
# The original alireza0/x-ui keeps every client inside inbounds.settings, so
# the direct-SQLite writes below are the whole story there. 3x-ui v3 does not:
# it normalises clients into its own clients/client_inbounds tables and builds
# the live Xray config from THOSE (xray.go -> ClientService.ListForInbound),
# treating inbounds.settings as a mirror it maintains itself. Writing only the
# JSON there produces a client that this panel lists, that X-UI's own UI never
# shows, and that Xray never authenticates — a silent no-op.
#
# So on 3x-ui every write is routed through its documented REST API instead,
# which drives 3x-ui's own write path and keeps all five stores consistent
# (verified end-to-end against a live v3.7.0 instance). Reads need no change:
# 3x-ui keeps inbounds.settings up to date, so the listing code below still
# sees exactly what the panel shows.
XUI_INSTALL_ENV = "/etc/x-ui/install-result.env"
_XUI_VARIANT_CACHE = {"is_3xui": None, "checked_at": 0.0}


def _xui_read_install_env():
    """Parses /etc/x-ui/install-result.env (KEY=value, values shell-quoted by
    the installer's printf %q) into a plain dict. Missing file -> empty dict."""
    data = {}
    try:
        with open(XUI_INSTALL_ENV, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, val = line.partition("=")
                val = val.strip()
                if len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"'):
                    val = val[1:-1]
                data[key.strip()] = val
    except Exception:
        pass
    return data


def _xui_is_3xui():
    """True when the installed panel is 3x-ui rather than alireza0/x-ui.

    Two independent signals, so an install done outside this project's menu is
    still detected correctly:
      * XUI_DB_TYPE=postgres in the installer's result file — only 3x-ui offers
        a Postgres backend at all, and there is then no SQLite file to probe.
      * the client_inbounds table, which only 3x-ui's schema has.
    Cached for a minute: this is consulted on every client write and the answer
    only changes when the panel is reinstalled."""
    now = time.time()
    if _XUI_VARIANT_CACHE["is_3xui"] is not None and now - _XUI_VARIANT_CACHE["checked_at"] < 60:
        return _XUI_VARIANT_CACHE["is_3xui"]

    result = False
    if _xui_read_install_env().get("XUI_DB_TYPE", "").lower() == "postgres":
        result = True
    elif os.path.exists(XUI_DB_PATH):
        try:
            conn = _xui_db()
            try:
                cur = conn.cursor()
                cur.execute(
                    "SELECT 1 FROM sqlite_master WHERE type='table' AND name='client_inbounds' LIMIT 1"
                )
                result = cur.fetchone() is not None
            finally:
                conn.close()
        except Exception:
            result = False

    _XUI_VARIANT_CACHE["is_3xui"] = result
    _XUI_VARIANT_CACHE["checked_at"] = now
    return result


def _xui_extras_from_body(body):
    """Pulls the 3x-ui-only client settings out of a request body.

    A field the form did not send stays absent rather than becoming 0, so
    3x-ui keeps its own default instead of being told "no limit" by a form
    that never offered the setting. Values are clamped at zero and capped so
    a typo in the browser cannot store an absurd figure."""
    extras = {}
    for key, cap in (("limit_hwid", 10000), ("reset_days", 3650),
                     ("reset_day", 31), ("reset_max", 10000)):
        raw = body.get(key)
        if raw not in (None, ""):
            try:
                extras[key] = max(0, min(int(raw), cap))
            except (TypeError, ValueError):
                pass
    raw = body.get("tg_id")
    if raw not in (None, ""):
        try:
            extras["tg_id"] = int(raw)
        except (TypeError, ValueError):
            pass
    for key, limit in (("comment", 512), ("group", 128)):
        raw = body.get(key)
        if raw is not None:
            extras[key] = str(raw).strip()[:limit]
    if body.get("delayed_start"):
        extras["delayed_start"] = True
    return extras


def _xui_credential_fields_from_body(body):
    """Validates and extracts the Credentials-tab overrides (new_uuid,
    new_password, new_sub_id, new_auth, and the older single-field
    new_secret). Raises ValueError with a user-facing message on a bad
    format, mirroring custom_uuid's own check — silently dropping an
    invalid value here would look like the edit was accepted and quietly
    do nothing, which is worse than refusing it outright."""
    fields = {}
    for key, label in (("new_uuid", "UUID"), ("new_password", "Password"),
                       ("new_sub_id", "Subscription ID"), ("new_auth", "Hysteria Auth"),
                       ("new_secret", "UUID/Secret")):
        raw = str(body.get(key, "")).strip()
        if not raw:
            continue
        if not re.match(r'^[A-Za-z0-9-]{1,64}$', raw):
            raise ValueError(f"قيمة {label} تحتوي على رموز غير مسموحة")
        fields[key] = raw
    return fields


def xui_variant():
    """Which X-UI is installed: "3xui", "x-ui" (the original alireza0 build),
    or "none". The web UI uses it to decide which client settings to offer —
    3x-ui accepts several the original has nowhere to store."""
    if not xui_installed():
        return "none"
    return "3xui" if _xui_is_3xui() else "x-ui"


def _xui_api_token():
    """The panel's API bearer token: whatever is cached in install-result.env,
    or minted fresh if that file has none yet.

    3x-ui's CLI (`setting -getApiToken`) does NOT "reuse the existing token"
    despite how that might read — when any token already exists it deletes
    and recreates the one named "cli-fallback" every single time it's asked,
    invalidating whatever was there a moment before (see RecreateByName in
    3x-ui's api_token.go). So this path is only correct for a server that has
    never minted one before; once a token is cached, _xui_api's own retry
    (via _xui_refresh_api_token) is what has to run this CLI command again —
    never this function silently, since a random unrelated call re-running it
    would invalidate a token another request might be mid-flight with."""
    token = _xui_read_install_env().get("XUI_API_TOKEN", "").strip()
    if token:
        return token
    return _xui_refresh_api_token()


def _xui_write_install_env_key(key, value):
    """Rewrites one KEY=value line in install-result.env, preserving every
    other line — including ones this project doesn't recognise, and the
    differently-shaped "Key: value" lines an older installer variant may
    have written (menu.sh's show_xui_access_info reads those; this project's
    own _xui_read_install_env never does, so they're left alone either way)."""
    lines = []
    if os.path.exists(XUI_INSTALL_ENV):
        try:
            with open(XUI_INSTALL_ENV, "r", encoding="utf-8", errors="replace") as fh:
                lines = [ln for ln in fh.read().split("\n") if ln and not ln.startswith(key + "=")]
        except OSError:
            pass
    lines.append(f"{key}={value}")
    try:
        os.makedirs(os.path.dirname(XUI_INSTALL_ENV), exist_ok=True)
        fd = os.open(XUI_INSTALL_ENV, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
    except OSError:
        pass


def _xui_refresh_api_token():
    """Mints a fresh admin-scoped API token straight from x-ui's CLI and
    persists it, replacing whatever was cached. This is the only place that
    should ever call `setting -getApiToken` after the very first token
    exists — see _xui_api_token's docstring for why calling it casually
    would invalidate a token some other request is using right now."""
    try:
        out = subprocess.run(
            ["/usr/local/x-ui/x-ui", "setting", "-getApiToken", "true"],
            capture_output=True, text=True, timeout=20,
        ).stdout
    except Exception:
        return ""
    token = ""
    for line in out.splitlines():
        if line.startswith("apiToken:"):
            token = line.split(":", 1)[1].strip()
            break
    if token:
        _xui_write_install_env_key("XUI_API_TOKEN", token)
    return token


def _xui_api_base():
    """Loopback base URL for the panel's API, e.g.
    https://127.0.0.1:54321/<secret-path>/panel/api

    Port and web base path come from the live settings table when SQLite is
    readable, falling back to what the installer recorded (the only source on a
    Postgres install). HTTPS whenever a certificate is configured, because the
    panel then serves TLS only."""
    env = _xui_read_install_env()
    port = env.get("XUI_PANEL_PORT", "").strip()
    base_path = env.get("XUI_WEB_BASE_PATH", "").strip()
    scheme = "http"

    if os.path.exists(XUI_DB_PATH):
        try:
            conn = _xui_db()
            try:
                cur = conn.cursor()
                cur.execute(
                    "SELECT key, value FROM settings "
                    "WHERE key IN ('webPort','webBasePath','webCertFile','webKeyFile')"
                )
                rows = dict(cur.fetchall())
            finally:
                conn.close()
            live_port = str(rows.get("webPort", "") or "").strip()
            if live_port and live_port != "0":
                port = live_port
            if rows.get("webBasePath"):
                base_path = str(rows["webBasePath"]).strip()
            cert = str(rows.get("webCertFile", "") or "").strip()
            key = str(rows.get("webKeyFile", "") or "").strip()
            if cert and key and os.path.isfile(cert) and os.path.isfile(key):
                scheme = "https"
        except Exception:
            pass

    if not port:
        port = "2053"
    base_path = "/" + base_path.strip("/") if base_path.strip("/") else ""
    return f"{scheme}://127.0.0.1:{port}{base_path}/panel/api"


def _xui_api(method, path, payload=None, timeout=25):
    """One authenticated call against the panel's own API.

    Raises RuntimeError carrying the panel's own message so the failure the
    operator sees is the real reason, not a generic one. TLS verification is
    off by design: the connection never leaves loopback, and the panel's
    certificate is issued for its public domain, so it can never validate
    against 127.0.0.1.

    A rejected token (401/403, or 404 — checkAPIAuth's own "not logged in,
    not a browser XHR" response) is retried ONCE with a freshly-minted token
    before giving up, rather than surfacing the rejection straight away.
    This matters because the cached token can genuinely go stale in ways
    nothing here caused: an admin resetting the panel's credentials back to
    the factory defaults (this project's own "Reset Port & Credentials"
    tool included) makes 3x-ui's installer treat the NEXT `install`/`update`
    run as "insecure defaults detected" and mint a replacement token on its
    own initiative — see _xui_api_token's docstring for the mechanics. A
    stale-forever cache with no recovery path is what used to turn into
    every single client-creation attempt failing until an admin noticed and
    manually re-ran something."""
    url = _xui_api_base() + path
    body = json.dumps(payload).encode("utf-8") if payload is not None else None

    ctx = None
    if url.startswith("https://"):
        import ssl
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

    def attempt(token):
        req = urllib.request.Request(url, data=body, method=method)
        req.add_header("Authorization", "Bearer " + token)
        req.add_header("Accept", "application/json")
        if body is not None:
            req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            return resp.read().decode("utf-8", "replace")

    token = _xui_api_token()
    if not token:
        raise RuntimeError("Could not obtain the X-UI API token — is the panel installed and running?")

    stale_codes = (401, 403, 404)
    retried = False
    while True:
        try:
            raw = attempt(token)
            break
        except urllib.error.HTTPError as exc:
            detail = ""
            try:
                detail = json.loads(exc.read().decode("utf-8", "replace")).get("msg", "")
            except Exception:
                pass
            if exc.code in stale_codes and not retried:
                retried = True
                fresh = _xui_refresh_api_token()
                if fresh and fresh != token:
                    token = fresh
                    continue
            if exc.code in stale_codes:
                raise RuntimeError(detail or "X-UI rejected the request — the API token may be stale.")
            raise RuntimeError(detail or f"X-UI returned HTTP {exc.code}")
        except Exception as exc:
            raise RuntimeError(f"Could not reach the X-UI panel on loopback: {exc}")

    try:
        data = json.loads(raw) if raw else {}
    except Exception:
        raise RuntimeError("X-UI returned a response this panel could not parse")
    if not data.get("success", False):
        raise RuntimeError(data.get("msg") or "X-UI rejected the request")
    return data.get("obj")


def _xui_api_get_client(email):
    """The client record 3x-ui holds, or None when there is no such client."""
    try:
        obj = _xui_api("GET", "/clients/get/" + urllib.parse.quote(str(email), safe=""))
    except RuntimeError:
        return None
    if isinstance(obj, dict) and isinstance(obj.get("client"), dict):
        return obj["client"]
    return obj if isinstance(obj, dict) else None


def xui_list_inbounds():
    """Lists every inbound (protocol/port X-UI manages) with its client count."""
    if not os.path.exists(XUI_DB_PATH):
        return []
    conn = _xui_db()
    try:
        cur = conn.cursor()
        cur.execute("SELECT id, remark, port, protocol, settings, enable FROM inbounds ORDER BY id")
        rows = cur.fetchall()
    finally:
        conn.close()

    result = []
    for iid, remark, port, proto, settings_str, enable in rows:
        try:
            settings = json.loads(settings_str) if settings_str else {}
        except Exception:
            settings = {}
        result.append({
            "id": iid,
            "remark": remark or f"Inbound-{iid}",
            "port": port,
            "protocol": proto,
            "enable": bool(enable),
            "client_count": len(settings.get("clients", [])),
        })
    return result


def _xui_inbound_protocol(inbound_id):
    """The inbound's protocol, read from the mirror 3x-ui keeps in SQLite, or
    from its API when there is no SQLite file (Postgres backend)."""
    if os.path.exists(XUI_DB_PATH):
        conn = _xui_db()
        try:
            cur = conn.cursor()
            cur.execute("SELECT protocol FROM inbounds WHERE id=?", (inbound_id,))
            row = cur.fetchone()
            if row:
                return row[0]
        finally:
            conn.close()
    obj = _xui_api("GET", f"/inbounds/get/{int(inbound_id)}")
    if isinstance(obj, dict) and obj.get("protocol"):
        return obj["protocol"]
    raise ValueError("Inbound not found")


def _xui_email_taken(email):
    """Whether 3x-ui would reject this client name as a duplicate.

    Its own check lowercases both sides and spans every inbound, while the
    by-email lookup is an exact match — so `dahoom55` reads as free while
    `Dahoom55` exists, and the create then fails with a raw English error
    from deep inside 3x-ui. Cheap exact lookup first; only when that misses
    do we pay for the full list to compare case-insensitively."""
    if _xui_api_get_client(email) is not None:
        return True
    target = str(email).strip().lower()
    try:
        rows = _xui_api("GET", "/clients/list") or []
    except RuntimeError:
        return False
    for row in rows:
        if isinstance(row, dict) and str(row.get("email", "")).strip().lower() == target:
            return True
    return False


def _xui_validate_client_email(email):
    """Rejects exactly what 3x-ui's own server-side check rejects (see
    hasForbiddenClientChar/validateClientEmail in client_crud.go): "/", "\\",
    any control character, DEL, or ANY unicode whitespace — including a
    plain space, which is the easiest one for an admin to type by accident
    (a client named with two words). Everything else, Arabic included, is
    left alone — 3x-ui itself allows non-ASCII names.

    Checked here, before the request ever reaches 3x-ui, so the admin sees
    a clear message in the panel instead of the request silently failing
    server-side with only a line in journalctl to explain why."""
    email = str(email or "")
    if not email:
        raise ValueError("اسم العميل لا يمكن أن يكون فارغًا")
    for ch in email:
        if ch in ("/", "\\") or ord(ch) < 0x20 or ord(ch) == 0x7f or ch.isspace():
            raise ValueError(
                f"اسم العميل \"{email}\" يحتوي على رمز غير مسموح "
                f"(لا مسافات ولا / أو \\) — 3x-ui يرفضه"
            )


def _xui_api_add_client(inbound_id, remark, days, hours, bandwidth_gb, max_conn,
                        custom_secret, extras=None):
    """3x-ui path for xui_add_client. Same arguments, same return shape, same
    failure messages — 3x-ui performs the write itself, so the client lands in
    its clients and client_inbounds tables, in the live Xray config, and in the
    inbounds.settings mirror this panel reads back.

    extras carries the settings only 3x-ui has (device-fingerprint limit,
    auto-renew, Telegram id, comment, group); anything left unset is simply
    not sent, so 3x-ui applies its own default."""
    email = remark
    _xui_validate_client_email(email)
    if _xui_email_taken(email):
        raise ValueError(f"A client named '{email}' already exists on this inbound")

    protocol = _xui_inbound_protocol(inbound_id)
    expiry_ms = 0
    if days or hours:
        target = datetime.now() + timedelta(days=int(days or 0), hours=int(hours or 0))
        expiry_ms = int(target.timestamp() * 1000)
    total_bytes = int(float(bandwidth_gb) * 1073741824) if bandwidth_gb else 0
    secret = custom_secret or str(uuid.uuid4())
    sub_id = uuid.uuid4().hex[:16]

    extras = extras or {}
    # "Start after first use" is stored as a NEGATIVE expiry holding the
    # duration, which 3x-ui converts to a real date on the client's first
    # connection. Only meaningful when a duration was actually given.
    if extras.get("delayed_start") and expiry_ms:
        expiry_ms = -int(timedelta(days=int(days or 0), hours=int(hours or 0)).total_seconds() * 1000)

    client = {
        "email": email,
        "enable": True,
        "expiryTime": expiry_ms,
        "limitIp": int(max_conn or 0),
        "subId": sub_id,
        "tgId": int(extras.get("tg_id") or 0),
        "totalGB": total_bytes,
    }
    for key, field in (("limit_hwid", "limitHwid"), ("reset_days", "reset"),
                       ("reset_day", "resetDay"), ("reset_max", "resetMax")):
        if extras.get(key) is not None:
            client[field] = int(extras[key])
    for key, field in (("comment", "comment"), ("group", "group")):
        if extras.get(key):
            client[field] = str(extras[key])
    if extras.get("new_sub_id"):
        client["subId"] = str(extras["new_sub_id"])

    # Each protocol authenticates on exactly one of these — xray.go's own
    # client-entry builder switches on protocol and reads only the matching
    # field, so setting the wrong one leaves the client with no working
    # credential at all. Hysteria was the one case this got wrong: every
    # other protocol here falls into the "id" branch, but Hysteria (see
    # xray.go's GetXrayConfig) reads "auth", never "id" — a Hysteria client
    # created via the old code had its secret written to a field xray-core
    # never looks at, so it authenticated against nothing.
    if protocol in ("trojan", "shadowsocks"):
        client["password"] = extras.get("new_password") or secret
    elif protocol == "hysteria":
        client["auth"] = extras.get("new_auth") or secret
    else:
        client["id"] = extras.get("new_uuid") or secret
        if protocol == "vless":
            client["flow"] = ""

    _xui_api("POST", "/clients/add", {"client": client, "inboundIds": [int(inbound_id)]})
    return {
        "email": email, "secret": secret, "protocol": protocol, "port": None,
        "sub_id": sub_id, "expiry_time": expiry_ms, "total_bytes": total_bytes,
        "inbound_id": inbound_id,
    }


def xui_add_client(inbound_id, remark, days=30, hours=0, bandwidth_gb=0, max_conn=0,
                   custom_secret=None, extras=None):
    """Adds a client to an existing X-UI inbound. Raises ValueError/RuntimeError
    with a user-facing message on any failure; never leaves the DB half-written
    (the whole read-modify-write happens inside one transaction).

    extras holds the settings only 3x-ui supports and is ignored on the
    original x-ui, which has nowhere to store them."""
    if _xui_is_3xui():
        return _xui_api_add_client(inbound_id, remark, days, hours,
                                   bandwidth_gb, max_conn, custom_secret, extras)
    if not os.path.exists(XUI_DB_PATH):
        raise RuntimeError("X-UI is not installed on this server")

    email = (remark or "").strip()
    if not email:
        raise ValueError("Client name cannot be empty")
    if not re.match(r'^[a-zA-Z0-9_.-]{1,64}$', email):
        raise ValueError("Client name may only contain letters, numbers, _ . -")

    conn = _xui_db()
    try:
        cur = conn.cursor()
        cur.execute("SELECT protocol, settings FROM inbounds WHERE id=?", (inbound_id,))
        row = cur.fetchone()
        if not row:
            raise ValueError("Inbound not found")
        protocol, settings_str = row
        settings = json.loads(settings_str) if settings_str else {}
        clients = settings.setdefault("clients", [])

        if any(c.get("email") == email for c in clients):
            raise ValueError(f"A client named '{email}' already exists on this inbound")

        expiry_ms = 0
        if days or hours:
            target = datetime.now() + timedelta(days=int(days), hours=int(hours))
            expiry_ms = int(target.timestamp() * 1000)
        total_bytes = int(float(bandwidth_gb) * 1073741824) if bandwidth_gb else 0
        sub_id = uuid.uuid4().hex[:16]
        secret = custom_secret or str(uuid.uuid4())

        client = {
            "email": email,
            "enable": True,
            "expiryTime": expiry_ms,
            "limitIp": int(max_conn or 0),
            "reset": 0,
            "subId": sub_id,
            "tgId": "",
            "totalGB": total_bytes,
        }
        # Matches model.Client exactly (verified against X-UI's own source):
        # id-based auth for vless/vmess/most protocols, password-based for
        # trojan/shadowsocks. vless additionally carries a (usually empty) flow.
        if protocol == "trojan":
            client["password"] = secret
        elif protocol == "shadowsocks":
            client["password"] = secret
        else:
            client["id"] = secret
            if protocol == "vless":
                client["flow"] = ""

        clients.append(client)
        # This is the write that actually matters — the client Xray will
        # authenticate against once restarted. Commit it on its own so a
        # problem with the traffics row below (a schema difference on an
        # older/different X-UI fork) can never roll back a client that
        # would otherwise have worked correctly.
        cur.execute("UPDATE inbounds SET settings=? WHERE id=?", (json.dumps(settings), inbound_id))
        conn.commit()
        # client_traffics only powers X-UI's own usage/online display for
        # this client — best-effort, never fatal to client creation.
        try:
            cur.execute(
                "INSERT INTO client_traffics (inbound_id, enable, email, up, down, expiry_time, total, reset) VALUES (?,?,?,?,?,?,?,?)",
                (inbound_id, 1, email, 0, 0, expiry_ms, total_bytes, 0)
            )
            conn.commit()
        except Exception:
            conn.rollback()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    run_cmd(["systemctl", "restart", "x-ui"])
    return {
        "email": email, "secret": secret, "protocol": protocol, "port": None,
        "sub_id": sub_id, "expiry_time": expiry_ms, "total_bytes": total_bytes,
        "inbound_id": inbound_id,
    }


def _xui_api_client_payload(current, **overrides):
    """Builds an update payload from the client 3x-ui currently holds, changing
    only the named fields. 3x-ui's update replaces the record wholesale, so
    every identity field has to be carried over or it would be wiped — the
    credential in particular, which is what clients authenticate with."""
    payload = {
        "email": current.get("email", ""),
        "enable": bool(current.get("enable", True)),
        "expiryTime": int(current.get("expiryTime", 0) or 0),
        "limitIp": int(current.get("limitIp", 0) or 0),
        "totalGB": int(current.get("totalGB", 0) or 0),
        "subId": current.get("subId", "") or "",
        "tgId": int(current.get("tgId", 0) or 0),
    }
    # 3x-ui's own settings have to be carried across too. An edit that only
    # changes the quota still replaces the whole record, so a field left out
    # here comes back as zero — silently wiping a device-fingerprint limit or
    # an auto-renew schedule the operator set earlier.
    for field, cast in (("limitHwid", int), ("reset", int), ("resetDay", int),
                        ("resetMax", int), ("comment", str), ("group", str)):
        val = current.get(field)
        if val is not None:
            try:
                payload[field] = cast(val)
            except (TypeError, ValueError):
                pass
    # Carry the credential across under whichever key this protocol uses. The
    # API reports the UUID as "uuid" but expects it back as "id".
    for src, dst in (("uuid", "id"), ("id", "id"), ("password", "password"),
                     ("auth", "auth"), ("flow", "flow")):
        val = current.get(src)
        if isinstance(val, str) and val and dst not in payload:
            payload[dst] = val
    payload.update({k: v for k, v in overrides.items() if v is not None})
    return payload


def _xui_api_update_client(inbound_id, email, days, hours, bandwidth_gb, max_conn,
                           enable, extras=None):
    """3x-ui path for xui_update_client — same optional-field semantics."""
    current = _xui_api_get_client(email)
    if current is None:
        raise ValueError("Client not found")

    extras = extras or {}
    overrides = {}
    if days is not None or hours is not None:
        d, h = int(days or 0), int(hours or 0)
        if d or h:
            expiry_ms = int((datetime.now() + timedelta(days=d, hours=h)).timestamp() * 1000)
            # "Start after first use": store the still-untriggered duration as
            # a negative expiry, exactly as a fresh create does — the client
            # is being given a brand-new window, not one measured from now.
            if extras.get("delayed_start"):
                expiry_ms = -int(timedelta(days=d, hours=h).total_seconds() * 1000)
            overrides["expiryTime"] = expiry_ms
        else:
            overrides["expiryTime"] = 0
    if bandwidth_gb is not None:
        overrides["totalGB"] = int(float(bandwidth_gb) * 1073741824)
    if max_conn is not None:
        overrides["limitIp"] = int(max_conn)
    if enable is not None:
        overrides["enable"] = bool(enable)

    for key, field in (("limit_hwid", "limitHwid"), ("reset_days", "reset"),
                       ("reset_day", "resetDay"), ("reset_max", "resetMax"),
                       ("tg_id", "tgId")):
        if extras.get(key) is not None:
            overrides[field] = int(extras[key])
    for key, field in (("comment", "comment"), ("group", "group")):
        if extras.get(key) is not None:
            overrides[field] = str(extras[key])

    if extras.get("new_sub_id"):
        overrides["subId"] = str(extras["new_sub_id"])

    # Rotating the credential is opt-in: an admin who wants everything else
    # editable but never asked to reissue the link would otherwise have it
    # silently regenerated the moment any other field changed — carrying the
    # old one over (see _xui_api_client_payload) is what keeps that safe.
    # Which of these actually authenticates the client is fixed by protocol
    # (never more than one is non-empty on a real 3x-ui record), so applying
    # whichever one the client already uses is exactly as unambiguous as
    # checking the protocol directly, without a second API round trip.
    # new_secret is kept for callers using the older single-field form.
    generic_secret = extras.get("new_secret")
    if current.get("uuid"):
        val = extras.get("new_uuid") or generic_secret
        if val:
            overrides["id"] = val
    elif current.get("password"):
        val = extras.get("new_password") or generic_secret
        if val:
            overrides["password"] = val
    elif current.get("auth"):
        val = extras.get("new_auth") or generic_secret
        if val:
            overrides["auth"] = val

    payload = _xui_api_client_payload(current, **overrides)
    _xui_api("POST", "/clients/update/" + urllib.parse.quote(str(email), safe=""), payload)


def _xui_api_renew_client(inbound_id, email, days, hours, is_cumulative,
                          add_bandwidth_gb, reset_usage, max_conn):
    """3x-ui path for xui_renew_client, with the same stacking rules."""
    current = _xui_api_get_client(email)
    if current is None:
        raise ValueError("Client not found")

    overrides = {"enable": True}
    d, h = int(days or 0), int(hours or 0)
    if d or h:
        now_ms = int(datetime.now().timestamp() * 1000)
        current_expiry = int(current.get("expiryTime", 0) or 0)
        base_ms = current_expiry if (is_cumulative and current_expiry > now_ms) else now_ms
        overrides["expiryTime"] = base_ms + int(timedelta(days=d, hours=h).total_seconds() * 1000)

    if add_bandwidth_gb:
        current_total = int(current.get("totalGB", 0) or 0)
        if current_total > 0:  # 0 means unlimited — stays unlimited on renewal
            overrides["totalGB"] = current_total + int(float(add_bandwidth_gb) * 1073741824)

    if max_conn is not None:
        overrides["limitIp"] = int(max_conn)

    payload = _xui_api_client_payload(current, **overrides)
    quoted = urllib.parse.quote(str(email), safe="")
    _xui_api("POST", "/clients/update/" + quoted, payload)
    if reset_usage:
        _xui_api("POST", "/clients/resetTraffic/" + quoted)
    return {"expiry_time": payload.get("expiryTime", 0), "total_bytes": payload.get("totalGB", 0)}


def xui_update_client(inbound_id, email, days=None, hours=None, bandwidth_gb=None,
                      max_conn=None, enable=None, extras=None):
    """Edits an existing X-UI client in place. Every field is optional — pass
    None to leave it untouched. The client is identified by its email (X-UI's
    own unique key for a client within an inbound), which is never changed
    here: client_traffics rows are keyed on it, so renaming would orphan a
    client's usage history inside X-UI itself."""
    if _xui_is_3xui():
        return _xui_api_update_client(inbound_id, email, days, hours,
                                      bandwidth_gb, max_conn, enable, extras)
    if not os.path.exists(XUI_DB_PATH):
        raise RuntimeError("X-UI is not installed on this server")

    conn = _xui_db()
    try:
        cur = conn.cursor()
        cur.execute("SELECT settings FROM inbounds WHERE id=?", (inbound_id,))
        row = cur.fetchone()
        if not row:
            raise ValueError("Inbound not found")
        settings = json.loads(row[0]) if row[0] else {}
        clients = settings.get("clients", [])
        target = next((c for c in clients if c.get("email") == email), None)
        if target is None:
            raise ValueError("Client not found")

        if days is not None or hours is not None:
            d, h = int(days or 0), int(hours or 0)
            if d or h:
                target["expiryTime"] = int((datetime.now() + timedelta(days=d, hours=h)).timestamp() * 1000)
            else:
                target["expiryTime"] = 0
        if bandwidth_gb is not None:
            target["totalGB"] = int(float(bandwidth_gb) * 1073741824)
        if max_conn is not None:
            target["limitIp"] = int(max_conn)
        # Same opt-in credential rotation as the 3x-ui path — only touched
        # when the admin explicitly typed a new value.
        new_secret = (extras or {}).get("new_secret")
        if new_secret:
            if "id" in target:
                target["id"] = new_secret
            elif "password" in target:
                target["password"] = new_secret
        if enable is not None:
            target["enable"] = bool(enable)

        cur.execute("UPDATE inbounds SET settings=? WHERE id=?", (json.dumps(settings), inbound_id))
        conn.commit()
        # Keep X-UI's own usage/quota view in sync — best-effort, same as
        # everywhere else this table is touched.
        try:
            cur.execute(
                "UPDATE client_traffics SET expiry_time=?, total=?, enable=? WHERE inbound_id=? AND email=?",
                (target.get("expiryTime", 0), target.get("totalGB", 0),
                 1 if target.get("enable", True) else 0, inbound_id, email)
            )
            conn.commit()
        except Exception:
            conn.rollback()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    run_cmd(["systemctl", "restart", "x-ui"])


def xui_renew_client(inbound_id, email, days=0, hours=0, is_cumulative=True,
                     add_bandwidth_gb=0, reset_usage=False, max_conn=None):
    """Renews an X-UI client: extends its expiry, stacking on top of any time
    still remaining when is_cumulative is set (mirrors v2ray_manager.py's
    renew_v2ray_user, which does the same for the separate DAHOOM V2Ray
    system) rather than replacing it outright the way xui_update_client does.
    Also re-enables the client — X-UI's own background job flips enable=False
    once a client expires or exhausts its quota, so a renewal that didn't
    flip it back on would silently do nothing."""
    if _xui_is_3xui():
        return _xui_api_renew_client(inbound_id, email, days, hours, is_cumulative,
                                     add_bandwidth_gb, reset_usage, max_conn)
    if not os.path.exists(XUI_DB_PATH):
        raise RuntimeError("X-UI is not installed on this server")
    conn = _xui_db()
    try:
        cur = conn.cursor()
        cur.execute("SELECT settings FROM inbounds WHERE id=?", (inbound_id,))
        row = cur.fetchone()
        if not row:
            raise ValueError("Inbound not found")
        settings = json.loads(row[0]) if row[0] else {}
        clients = settings.get("clients", [])
        target = next((c for c in clients if c.get("email") == email), None)
        if target is None:
            raise ValueError("Client not found")

        d, h = int(days or 0), int(hours or 0)
        if d or h:
            now_ms = int(datetime.now().timestamp() * 1000)
            current_expiry = int(target.get("expiryTime", 0) or 0)
            base_ms = current_expiry if (is_cumulative and current_expiry > now_ms) else now_ms
            target["expiryTime"] = base_ms + int(timedelta(days=d, hours=h).total_seconds() * 1000)

        if add_bandwidth_gb:
            current_total = int(target.get("totalGB", 0) or 0)
            if current_total > 0:  # 0 means unlimited — stays unlimited on renewal
                target["totalGB"] = current_total + int(float(add_bandwidth_gb) * 1073741824)

        if max_conn is not None:
            target["limitIp"] = int(max_conn)

        target["enable"] = True

        cur.execute("UPDATE inbounds SET settings=? WHERE id=?", (json.dumps(settings), inbound_id))
        conn.commit()
        try:
            up_down_reset = "up=0, down=0, " if reset_usage else ""
            cur.execute(
                f"UPDATE client_traffics SET {up_down_reset}expiry_time=?, total=?, enable=1 WHERE inbound_id=? AND email=?",
                (target.get("expiryTime", 0), target.get("totalGB", 0), inbound_id, email)
            )
            conn.commit()
        except Exception:
            conn.rollback()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    run_cmd(["systemctl", "restart", "x-ui"])
    return {"expiry_time": target.get("expiryTime", 0), "total_bytes": target.get("totalGB", 0)}


def xui_reset_client_traffic(inbound_id, email):
    """Zeroes a client's used-traffic counters only — leaves expiry and quota
    untouched. Same operation X-UI's own UI exposes as 'Reset Traffic'."""
    if _xui_is_3xui():
        _xui_api("POST", "/clients/resetTraffic/" + urllib.parse.quote(str(email), safe=""))
        return
    if not os.path.exists(XUI_DB_PATH):
        raise RuntimeError("X-UI is not installed on this server")
    conn = _xui_db()
    try:
        cur = conn.cursor()
        cur.execute("UPDATE client_traffics SET up=0, down=0 WHERE inbound_id=? AND email=?", (inbound_id, email))
        if cur.rowcount == 0:
            raise ValueError("Client not found")
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
    run_cmd(["systemctl", "restart", "x-ui"])


def xui_delete_client(inbound_id, email):
    if _xui_is_3xui():
        if _xui_api_get_client(email) is None:
            raise ValueError("Client not found")
        _xui_api("POST", "/clients/del/" + urllib.parse.quote(str(email), safe=""))
        return
    if not os.path.exists(XUI_DB_PATH):
        raise RuntimeError("X-UI is not installed on this server")
    conn = _xui_db()
    try:
        cur = conn.cursor()
        cur.execute("SELECT settings FROM inbounds WHERE id=?", (inbound_id,))
        row = cur.fetchone()
        if not row:
            raise ValueError("Inbound not found")
        settings = json.loads(row[0]) if row[0] else {}
        clients = settings.get("clients", [])
        new_clients = [c for c in clients if c.get("email") != email]
        if len(new_clients) == len(clients):
            raise ValueError("Client not found")
        settings["clients"] = new_clients
        cur.execute("UPDATE inbounds SET settings=? WHERE id=?", (json.dumps(settings), inbound_id))
        conn.commit()
        try:
            cur.execute("DELETE FROM client_traffics WHERE inbound_id=? AND email=?", (inbound_id, email))
            conn.commit()
        except Exception:
            conn.rollback()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
    run_cmd(["systemctl", "restart", "x-ui"])


def _xui_limit_hwid_by_email():
    """3x-ui only: limit_hwid never made it into the inbounds.settings
    mirror — model.Client, the shape 3x-ui serialises there, has no such
    field at all — so it can only be read straight from the clients table.
    Best-effort, same spirit as the traffics join below: a lookup failure
    just means the edit form shows no HWID limit rather than erroring."""
    if not (_xui_is_3xui() and os.path.exists(XUI_DB_PATH)):
        return {}
    try:
        conn = _xui_db()
        try:
            cur = conn.cursor()
            cur.execute("SELECT email, limit_hwid FROM clients")
            return {email: (hwid or 0) for email, hwid in cur.fetchall()}
        finally:
            conn.close()
    except Exception:
        return {}


def xui_list_clients():
    """Every client across every inbound, joined with its live traffic stats."""
    if not os.path.exists(XUI_DB_PATH):
        return []
    hwid_by_email = _xui_limit_hwid_by_email()
    conn = _xui_db()
    try:
        cur = conn.cursor()
        cur.execute("SELECT id, remark, protocol, port, settings, stream_settings FROM inbounds ORDER BY id")
        inbounds = cur.fetchall()
        # client_traffics is a nice-to-have (usage stats, online/offline state)
        # layered on top of the clients that actually live in inbounds.settings
        # — the real source of truth. A schema difference here (older/newer
        # X-UI fork, a column renamed) must never blank out the whole client
        # list just because usage numbers couldn't be joined in.
        traffics = {}
        try:
            cur.execute("SELECT inbound_id, email, up, down, enable FROM client_traffics")
            traffics = {(iid, email): {"up": up, "down": down, "enable": bool(enable)}
                        for iid, email, up, down, enable in cur.fetchall()}
        except Exception:
            pass
    finally:
        conn.close()

    result = []
    for iid, remark, protocol, port, settings_str, stream_str in inbounds:
        try:
            settings = json.loads(settings_str) if settings_str else {}
        except Exception:
            settings = {}
        try:
            stream = json.loads(stream_str) if stream_str else {}
        except Exception:
            stream = {}
        for c in settings.get("clients", []):
            email = c.get("email", "")
            t = traffics.get((iid, email), {"up": 0, "down": 0, "enable": c.get("enable", True)})
            result.append({
                "inbound_id": iid,
                "inbound_remark": remark or f"Inbound-{iid}",
                "protocol": protocol,
                "port": port,
                "network": stream.get("network", "tcp"),
                "security": stream.get("security", "none"),
                "stream": stream,
                "email": email,
                "secret": c.get("id") or c.get("password") or c.get("auth", ""),
                "expiry_time": c.get("expiryTime", 0),
                "total_bytes": c.get("totalGB", 0),
                "max_conn": c.get("limitIp", 0),
                "sub_id": c.get("subId", ""),
                # Raw values for the Credentials tab: unlike "secret" above
                # (whichever ONE of these this protocol actually uses, for
                # display), the edit form needs each field distinctly so it
                # can prefill all four the way 3x-ui's own edit screen does.
                "cred_uuid": c.get("id", "") or "",
                "cred_password": c.get("password", "") or "",
                "cred_auth": c.get("auth", "") or "",
                "up": t["up"],
                "down": t["down"],
                "enable": t["enable"],
                # 3x-ui-only settings. Absent on an alireza0 client's dict —
                # every .get() below then falls back to the harmless default,
                # so the edit form on that build simply shows nothing there.
                "limit_hwid": hwid_by_email.get(email, 0),
                "tg_id": c.get("tgId", 0) or 0,
                "group": c.get("group", "") or "",
                "comment": c.get("comment", "") or "",
                "reset_days": c.get("reset", 0) or 0,
                "reset_day": c.get("resetDay", 0) or 0,
                "reset_max": c.get("resetMax", 0) or 0,
                # "Start after first use": 3x-ui stores the still-untriggered
                # duration as a negative expiry, so a negative value here
                # means the client hasn't connected yet — not that it expired
                # in the past.
                "delayed_start": (c.get("expiryTime", 0) or 0) < 0,
            })
    return result


def _xui_fetch_inbound_stream(inbound_id):
    """One-off lookup of a single inbound's raw stream_settings, for the
    client-creation endpoints — they only ever need this one inbound, not
    the full xui_list_clients() scan."""
    if not os.path.exists(XUI_DB_PATH):
        return {}
    conn = _xui_db()
    try:
        cur = conn.cursor()
        cur.execute("SELECT stream_settings FROM inbounds WHERE id=?", (inbound_id,))
        row = cur.fetchone()
    finally:
        conn.close()
    if not row or not row[0]:
        return {}
    try:
        return json.loads(row[0])
    except Exception:
        return {}


# --- X-UI "fixed 443/80" display mode ---
# This is purely cosmetic: ONE real client is created on whichever inbound
# the admin picks (exactly like the normal flow — nothing here ever creates
# a second client or a second inbound), and the port_mode/allow_insecure
# choice is remembered per (inbound_id, email) so the link shown for that
# client keeps reflecting it later (in the list, and when re-opened for
# editing) — not just at the moment it was created. Actually routing 443/80
# traffic to the real inbound is the admin's own infrastructure job.
XUI_CLIENT_PREFS_FILE = "/etc/firewallfalcon/xui_client_prefs.json"


def _read_xui_client_prefs():
    if not os.path.exists(XUI_CLIENT_PREFS_FILE):
        return {}
    try:
        with open(XUI_CLIENT_PREFS_FILE, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _write_xui_client_prefs(prefs):
    os.makedirs(os.path.dirname(XUI_CLIENT_PREFS_FILE), exist_ok=True)
    with open(XUI_CLIENT_PREFS_FILE, "w", encoding="utf-8") as f:
        json.dump(prefs, f)


def get_xui_client_pref(inbound_id, email):
    return _read_xui_client_prefs().get(f"{inbound_id}:{email}", {})


def set_xui_client_pref(inbound_id, email, port_mode=None, allow_insecure=None, note=None):
    prefs = _read_xui_client_prefs()
    key = f"{inbound_id}:{email}"
    entry = prefs.get(key, {})
    if port_mode is not None:
        entry["port_mode"] = port_mode
    if allow_insecure is not None:
        entry["allow_insecure"] = allow_insecure
    if note is not None:
        entry["note"] = note
    prefs[key] = entry
    _write_xui_client_prefs(prefs)


def delete_xui_client_pref(inbound_id, email):
    prefs = _read_xui_client_prefs()
    if prefs.pop(f"{inbound_id}:{email}", None) is not None:
        _write_xui_client_prefs(prefs)


# --- Admin notes on any SSH account (free-text, admin's own reminders —
# not shown to the user, never touches users.db). Same tiny JSON-file
# pattern as xui_client_prefs above, keyed by username directly since SSH
# usernames are already globally unique (unlike X-UI clients, which need
# inbound_id alongside the email). ---
def _read_user_notes():
    if not os.path.exists(USER_NOTES_FILE):
        return {}
    try:
        with open(USER_NOTES_FILE, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _write_user_notes(notes):
    os.makedirs(os.path.dirname(USER_NOTES_FILE), exist_ok=True)
    with open(USER_NOTES_FILE, "w", encoding="utf-8") as f:
        json.dump(notes, f)


def get_user_note(username):
    return _read_user_notes().get(username, "")


def set_user_note(username, text):
    notes = _read_user_notes()
    text = (text or "").strip()
    if text:
        notes[username] = text
    else:
        notes.pop(username, None)  # empty note = delete, keeps the file tidy
    _write_user_notes(notes)


def delete_user_note(username):
    notes = _read_user_notes()
    if notes.pop(username, None) is not None:
        _write_user_notes(notes)


# --- HWID login mode (device-ID-only accounts, same idea as HTTP Custom's
# "Login with HWID": one value used as BOTH username and password). Stored
# as a flat "username:mode" file — NOT JSON like the notes above, and
# deliberately not a new users.db column — so menu.sh's shell code (no JSON
# tooling there) can read and write the exact same file with a plain grep/
# sed, and an account created from either side shows correctly on the
# other. Lives under DB_FILE's directory so it rides along in the existing
# backup archive automatically. Absence of an entry means "normal" mode.
def _read_login_modes():
    modes = {}
    if not os.path.exists(LOGIN_MODES_FILE):
        return modes
    try:
        with open(LOGIN_MODES_FILE, encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line or ":" not in line:
                    continue
                u, _, m = line.partition(":")
                if u:
                    modes[u] = m
    except Exception:
        pass
    return modes


def get_login_mode(username):
    return _read_login_modes().get(username, "normal")


def set_login_mode(username, mode):
    modes = _read_login_modes()
    if mode and mode != "normal":
        modes[username] = mode
    else:
        modes.pop(username, None)
    os.makedirs(os.path.dirname(LOGIN_MODES_FILE), exist_ok=True)
    with open(LOGIN_MODES_FILE, "w", encoding="utf-8") as f:
        for u, m in modes.items():
            f.write(f"{u}:{m}\n")


def delete_login_mode(username):
    modes = _read_login_modes()
    if modes.pop(username, None) is not None:
        os.makedirs(os.path.dirname(LOGIN_MODES_FILE), exist_ok=True)
        with open(LOGIN_MODES_FILE, "w", encoding="utf-8") as f:
            for u, m in modes.items():
                f.write(f"{u}:{m}\n")


def _next_free_system_id():
    """First id free in BOTH /etc/passwd and /etc/group, within the
    UID_MIN..UID_MAX range from /etc/login.defs (1000-60000 by default).
    Mirrors menu.sh's _fm_next_free_id() exactly so accounts created from
    either side land in the same id space without collisions."""
    lo, hi = 1000, 60000
    try:
        with open("/etc/login.defs", encoding="utf-8") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 2 and parts[0] == "UID_MIN":
                    lo = int(parts[1])
                elif len(parts) >= 2 and parts[0] == "UID_MAX":
                    hi = int(parts[1])
    except Exception:
        pass
    used = set()
    for path in ("/etc/passwd", "/etc/group"):
        try:
            with open(path, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    fields = line.split(":")
                    if len(fields) >= 3 and fields[2].isdigit():
                        n = int(fields[2])
                        if lo <= n <= hi:
                            used.add(n)
        except Exception:
            pass
    for i in range(lo, hi + 1):
        if i not in used:
            return i
    return None


def create_system_user_safe(un):
    """Creates the Linux account for `un`, transparently handling names
    longer than 32 characters — HWID login (see handle_post_users) puts
    real device IDs there, which routinely exceed useradd's/groupadd's
    hard-coded 32-char name limit (--badname only relaxes the character-
    set check, not that length cap — confirmed against shadow-utils on
    this codebase's target distro). The OS itself has no such limit
    (glibc's LOGIN_NAME_MAX is 256; a live SSH login with a 64-char user
    and password was verified end-to-end), so on a length-only rejection
    this appends the passwd/group lines by hand and lets pwconv/grpconv
    fill in the matching shadow/gshadow entries. Those reconcile the whole
    file rather than one hand-written line, which costs more as the
    account count grows (measured ~0.6s at 5,000 existing accounts) but is
    the deliberate choice here: this project caps at ~500 users, where
    that cost is imperceptible, in exchange for the guarantee that
    shadow/gshadow stay fully consistent with passwd/group. Raises
    ValueError on any other failure so the caller aborts instead of
    writing a DB entry for an account that was never actually created —
    the bug this replaces."""
    code, _, err = run_cmd(["useradd", "-m", "-s", "/usr/sbin/nologin", un])
    if code == 0:
        return
    if "invalid user name" not in err:
        raise ValueError(f"System error creating user: {err}")
    code, _, _ = run_cmd(["id", un])
    if code == 0:
        return  # already exists (race with another path) — treat as success
    uid = _next_free_system_id()
    if uid is None:
        raise ValueError("No free system UID available")
    with open("/etc/passwd", "a", encoding="utf-8") as f:
        f.write(f"{un}:x:{uid}:{uid}::/home/{un}:/usr/sbin/nologin\n")
    with open("/etc/group", "a", encoding="utf-8") as f:
        f.write(f"{un}:x:{uid}:\n")
    run_cmd(["pwconv"], ignore_errors=True)
    run_cmd(["grpconv"], ignore_errors=True)
    os.makedirs(f"/home/{un}", exist_ok=True)
    try:
        os.chown(f"/home/{un}", uid, uid)
        os.chmod(f"/home/{un}", 0o700)
    except Exception:
        pass


def rename_system_user_safe(old, new):
    """Renames the Linux account `old` to `new` — username, matching
    private group, shadow/gshadow entries, and home directory — mirroring
    menu.sh's _fm_rename_system_user() so an account created on either
    side renames identically. usermod -l has the same 32-char name-length
    limit as useradd (a HWID account's name routinely exceeds it), so on
    that specific rejection this renames the fields by hand in all four
    files instead of failing outright.
    Returns True on success, False if the new name is already taken or a
    real usermod error occurred (unrelated to length)."""
    code, _, _ = run_cmd(["id", new])
    if code == 0:
        return False
    code, _, err = run_cmd(["usermod", "-l", new, old])
    if code == 0:
        run_cmd(["usermod", "-m", "-d", f"/home/{new}", new], ignore_errors=True)
        code_g, _, _ = run_cmd(["getent", "group", old])
        if code_g == 0:
            run_cmd(["groupmod", "-n", new, old], ignore_errors=True)
        return True
    if "invalid user name" not in err:
        return False
    run_cmd(["sed", "-i", f"s|^{old}:|{new}:|", "/etc/passwd", "/etc/shadow"])
    code_g, _, _ = run_cmd(["getent", "group", old])
    if code_g == 0:
        run_cmd(["sed", "-i", f"s|^{old}:|{new}:|", "/etc/group", "/etc/gshadow"])
    old_home, new_home = f"/home/{old}", f"/home/{new}"
    if os.path.isdir(old_home) and not os.path.exists(new_home):
        try:
            os.rename(old_home, new_home)
            run_cmd(["sed", "-i", f"s|:{old_home}:|:{new_home}:|", "/etc/passwd"])
        except Exception:
            pass
    return True


def rename_hwid_account(old, new):
    """Full HWID-account rename: the system account plus every sidecar
    store keyed by username — users.db row, login mode, admin notes,
    bandwidth usage/lock state, per-user speed cap, and the usage-link
    token — mirroring menu.sh's _fm_rename_hwid_account() so a rename from
    either side is fully interoperable with the other. Used when a
    client's device ID changes (OS/app update) and the admin needs to
    update it while keeping everything else — data used, expiry, notes —
    exactly as it was. The public usage-status link can't survive as the
    same URL (it embeds the username in its path); the token row is
    carried over but a fresh link should be re-shared afterward.
    Raises ValueError on failure; nothing is changed on failure since the
    system rename is attempted first, before any sidecar store."""
    if not rename_system_user_safe(old, new):
        raise ValueError("Failed to rename the system account (name may already be taken)")
    set_system_password(new, new)

    with db_lock:
        if os.path.exists(DB_FILE):
            with open(DB_FILE, "r") as f:
                lines = f.readlines()
            with open(DB_FILE, "w") as f:
                for line in lines:
                    if line.startswith(f"{old}:"):
                        parts = line.rstrip("\n").split(":")
                        parts[0] = new
                        parts[1] = new
                        f.write(":".join(parts) + "\n")
                    else:
                        f.write(line)

    set_login_mode(new, "hwid")
    delete_login_mode(old)

    for suffix in ("usage", "daily_usage", "conn_locked", "daily_locked"):
        old_p, new_p = f"{BW_DIR}/{old}.{suffix}", f"{BW_DIR}/{new}.{suffix}"
        if os.path.exists(old_p):
            try:
                os.rename(old_p, new_p)
            except Exception:
                pass
    old_pidtrack, new_pidtrack = f"{BW_DIR}/pidtrack/{old}", f"{BW_DIR}/pidtrack/{new}"
    if os.path.isdir(old_pidtrack) and not os.path.exists(new_pidtrack):
        try:
            os.rename(old_pidtrack, new_pidtrack)
        except Exception:
            pass

    if os.path.exists(USER_SPEED_CONF):
        speed = None
        with open(USER_SPEED_CONF) as f:
            for line in f:
                if line.strip().startswith(old + ":"):
                    speed = line.strip().split(":", 1)[1]
        if speed is not None:
            _remove_line_from_file(USER_SPEED_CONF, prefix=old + ":")
            with open(USER_SPEED_CONF, "a") as f:
                f.write(f"{new}:{speed}\n")

    if os.path.exists(BW_LINK_TOKENS_DB):
        rest = None
        with open(BW_LINK_TOKENS_DB) as f:
            for line in f:
                if line.strip().startswith(old + ":"):
                    rest = line.strip().split(":", 1)[1]
        if rest is not None:
            _remove_line_from_file(BW_LINK_TOKENS_DB, prefix=old + ":")
            with open(BW_LINK_TOKENS_DB, "a") as f:
                f.write(f"{new}:{rest}\n")

    notes = _read_user_notes()
    if old in notes:
        notes[new] = notes.pop(old)
        _write_user_notes(notes)


# ── Sales Bot data layer (shared with menu.sh's Telegram sales bot) ────
# Same files, same on-disk formats as menu.sh's _fm_bot_* functions — a
# change from either side (bot command or this web panel) is visible to
# the other immediately, no sync step needed.
BOT_PLANS_CONF = "/etc/firewallfalcon/bot_plans.conf"
BOT_TRIAL_LOG = "/etc/firewallfalcon/bot_trial_log.db"
BOT_WALLETS_DB = "/etc/firewallfalcon/bot_wallets.db"
BOT_COUPONS_DB = "/etc/firewallfalcon/bot_coupons.db"
BOT_BANS_DB = "/etc/firewallfalcon/bot_bans.db"
BOT_ORDERS_DB = "/etc/firewallfalcon/bot_orders.db"
BOT_TRIAL_BONUS_DB = "/etc/firewallfalcon/bot_trial_bonus.db"
BOT_HWID_CHANGE_BONUS_DB = "/etc/firewallfalcon/bot_hwid_change_bonus.db"
BOT_HWID_CHANGE_DEFAULT_MAX = 3
BOT_REFERRALS_DB = "/etc/firewallfalcon/bot_referrals.db"
BOT_REFERRAL_PAID_DB = "/etc/firewallfalcon/bot_referral_paid.db"
BOT_REFERRAL_TIERS_CONF = "/etc/firewallfalcon/bot_referral_tiers.conf"
BOT_REFERRAL_REWARDED_DB = "/etc/firewallfalcon/bot_referral_rewarded.db"
BOT_APP_FILES_DIR = "/etc/firewallfalcon/bot_app_files"
BOT_APP_HWID_GUIDE_DIR = "/etc/firewallfalcon/bot_app_hwid_guides"
BOT_HWID_GUIDE_MAX = 10   # Telegram caps one media group at 10 items
BOT_APP_FILE_GUIDE_DIR = "/etc/firewallfalcon/bot_app_file_guides"
BOT_FILE_GUIDE_MAX = 10   # Telegram caps one media group at 10 items
# The written explanation that goes out WITH each gallery — one text per
# app, per gallery. Deliberately its own directory rather than a file
# sitting beside the image folders: the gallery listings enumerate their
# directory and treat every entry as an app, so a note stored in there
# would show up as a phantom app named after the note.
BOT_APP_HWID_NOTE_DIR = "/etc/firewallfalcon/bot_app_hwid_notes"
BOT_APP_FILE_NOTE_DIR = "/etc/firewallfalcon/bot_app_file_notes"
# Telegram rejects a photo/album whose caption is over 1024 characters —
# the whole send fails, images and all. Past this the note is sent as its
# own message instead, so a long explanation can never cost the customer
# the pictures.
BOT_GUIDE_CAPTION_MAX = 1000
BOT_APP_FILES_META = "/etc/firewallfalcon/bot_app_files.db"
BOT_APP_PLATFORM_DB = "/etc/firewallfalcon/bot_app_platform.db"
BOT_SERVER_REGIONS_CONF = "/etc/firewallfalcon/bot_regions.db"
# ── Multi-server node API (bot on one box, VPN accounts on another) ────
# Two distinct roles a box can play, each with its own file:
#   - CONTROLLER: bot_nodes.db — the registry of OTHER nodes this box
#     calls into (slug:token:fingerprint:base_url). Only meaningful on
#     whichever box runs the bot itself.
#   - NODE: bot_node_self.conf — THIS box's own accepted credential and
#     TLS cert, set once via the "enable this server as a VPN node"
#     action. Only meaningful on a box that accepts remote calls.
# A single-box deployment touches neither file, so nothing here changes
# behaviour unless an admin explicitly opts in on one side or the other.
BOT_NODES_CONF = "/etc/firewallfalcon/bot_nodes.db"
BOT_NODE_SELF_CONF = "/etc/firewallfalcon/bot_node_self.conf"
NODE_CERT_DIR = "/etc/firewallfalcon/node_tls"
NODE_CERT_FILE = f"{NODE_CERT_DIR}/node.crt"
NODE_KEY_FILE = f"{NODE_CERT_DIR}/node.key"
NODE_API_PORT = 44381
# A device id longer than this can't be a Linux username (utmp/session
# limiter constraints) — mirrors menu.sh's _FM_BOT_NAME_MAX exactly. Short
# ids are returned untouched, so HTTP Custom/HTTP Injector keep using the
# device id as the literal username exactly as the panel's own manual
# "Device ID" account creation already does — including their default
# 32-character id (_fm_bot_hwid_expected_len), which must clear this same
# ceiling untouched: _fm_create_system_user already falls back to a manual
# /etc/passwd entry for ids up to the 128-character HWID cap. Minting only
# exists for the apps that genuinely need it (NPV Tunnel/NPVS below).
NPVT_DEVICES_DB = "/etc/firewallfalcon/npvt_devices.db"
_FM_BOT_NAME_MAX = 32
# Country + SIM/carrier-type step, shown after the app itself is picked
# (see menu.sh's identically-named constants for the full rationale).
BOT_COUNTRIES_CONF = "/etc/firewallfalcon/bot_countries.db"
BOT_SIMTYPES_CONF = "/etc/firewallfalcon/bot_simtypes.db"
# File type: one more optional step layered on a (country, SIM-type)
# pair, letting more than one file be attached to that exact pair. Keyed
# by the composite "prefix" string bot_country_simtype_key already
# produces, not by raw country/simtype fields — see bot_filetype_key.
BOT_FILETYPES_CONF = "/etc/firewallfalcon/bot_filetypes.db"
# Per-customer language preference, written by the bot (menu.sh). Arabic is
# the default, so a chat with no entry here is Arabic.
BOT_LANG_DB = "/etc/firewallfalcon/bot_lang.db"
# Written by the bot on every customer interaction — see menu.sh's
# _fm_bot_known_chat_add. Read-only here.
BOT_KNOWN_CHATS_DB = "/etc/firewallfalcon/bot_known_chats.db"
TELEGRAM_CONF = "/etc/firewallfalcon/telegram.conf"
# Every editable sales-bot message, keyed the same as menu.sh's
# BOT_MESSAGES_CONF — see that file's "Editable sales-bot messages"
# section for the full rationale. KEEP THIS DICT IN SYNC WITH
# _fm_bot_msg_default() in menu.sh: both are generated from the same
# source-of-truth catalog script, so a key added there must be added
# here too (and vice versa) or the two sides of the editor drift apart.
BOT_MESSAGES_CONF = "/etc/firewallfalcon/bot_messages.conf"

BOT_PLAN_DEFAULTS = {
    "TRIAL_MAX_USES": "2", "TRIAL_HOURS": "1", "TRIAL_BW_GB": "0", "TRIAL_DEVICES": "1",
    "MONTHLY_DAYS": "30", "MONTHLY_BW_GB": "0", "MONTHLY_DEVICES": "1", "MONTHLY_PRICE_SAR": "15",
    "MONTHLY2_DAYS": "60", "MONTHLY2_BW_GB": "0", "MONTHLY2_DEVICES": "1", "MONTHLY2_PRICE_SAR": "28",
    "PAYMENT_INFO": "Contact the admin for payment details.",
}


def _bot_plan_escape(val):
    return val.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")


def _bot_plan_unescape(val):
    return val.replace('\\"', '"').replace("\\\\", "\\")


_BOT_PLAN_NODE_KEY_RE = re.compile(r"[^A-Za-z0-9_]")

# Node-scoped plan key — exact mirror of _fm_bot_plan_node_key in
# menu.sh, and the same idea as bot_node_country_simtype_key: an empty
# node gives back the plain global key, so nothing that predates
# per-node plans reads or writes a different key than it always did.
BOT_PLAN_NODE_PREFIX = "NODE_"


def bot_plan_node_key(node, key):
    if not node:
        return key
    slug = _BOT_PLAN_NODE_KEY_RE.sub("_", str(node)).upper()
    return f"{BOT_PLAN_NODE_PREFIX}{slug}__{key}"


def _read_bot_plans_raw():
    """Every KEY="VALUE" line in the file exactly as stored, node
    overrides included. Read as plain text and deliberately NOT
    executed/eval'd, matching menu.sh's _fm_bot_get_plan: PAYMENT_INFO is
    free text the admin types, and a naive `source`/exec of a file like
    that would let an embedded $(...) or similar run as code. Read-only,
    so this direction has no injection surface regardless, but keeping
    the same plain-text parsing on both sides means the format only
    needs to be "safe to read as text" once, not per-language."""
    raw = {}
    if os.path.exists(BOT_PLANS_CONF):
        try:
            with open(BOT_PLANS_CONF, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    line = line.rstrip("\n")
                    if "=" not in line:
                        continue
                    k, _, v = line.partition("=")
                    k = k.strip()
                    if len(v) >= 2 and v.startswith('"') and v.endswith('"'):
                        v = v[1:-1]
                    raw[k] = _bot_plan_unescape(v)
        except Exception:
            pass
    return raw


def read_bot_plans(node=""):
    """The plan as one node actually sells it: that node's overrides on
    top of the global values, which is what a node with no overrides of
    its own (and every install with no nodes at all) gets unchanged. An
    override stored as an empty string counts as absent — that is what
    makes clearing a field in the panel fall back to the global value.
    The NODE_* lines themselves never appear in the result; the global
    view stays exactly the flat dict it has always been."""
    raw = _read_bot_plans_raw()
    plans = dict(BOT_PLAN_DEFAULTS)
    for k, v in raw.items():
        if not k.startswith(BOT_PLAN_NODE_PREFIX):
            plans[k] = v
    if node:
        for k in list(plans.keys()):
            v = raw.get(bot_plan_node_key(node, k))
            if v:
                plans[k] = v
    return plans


def read_bot_plan_overrides(node):
    """Only the keys this node actually overrides — what the panel shows
    in its per-node fields, so an empty field there reads as "inherit"
    rather than as a value someone deliberately set to the same number."""
    if not node:
        return {}
    raw = _read_bot_plans_raw()
    out = {}
    for k in BOT_PLAN_DEFAULTS:
        v = raw.get(bot_plan_node_key(node, k))
        if v:
            out[k] = v
    return out


BOT_MSG_CATEGORIES = [
    ("buttons", "أزرار القائمة"),
    ("welcome", "الترحيب والقوائم"),
    ("region", "نوع السيرفر والجهاز"),
    ("trial", "التجربة المجانية"),
    ("subscribe", "الاشتراك الشهري"),
    ("payment", "الدفع والإيصال"),
    ("account", "الرصيد والحسابات"),
    ("changehwid", "تغيير الجهاز (HWID)"),
    ("referral", "الإحالة"),
    ("appfiles", "ملفات التطبيقات"),
    ("support", "الدعم والحظر"),
    ("admin", "إشعارات الأدمن (عربي فقط)"),
]

BOT_MSG_CATALOG = {
    "BTN_TRIAL": {"cat": "buttons", "bilingual": True, "ar": "🎁 تجربة مجانية", "en": "🎁 Free Trial"},
    "BTN_SUBSCRIBE": {"cat": "buttons", "bilingual": True, "ar": "💳 اشتراك شهري", "en": "💳 Subscribe"},
    "BTN_BALANCE": {"cat": "buttons", "bilingual": True, "ar": "💰 رصيدي", "en": "💰 My Balance"},
    "BTN_MYACCOUNT": {"cat": "buttons", "bilingual": True, "ar": "📱 حساباتي", "en": "📱 My Accounts"},
    "BTN_REFERRAL": {"cat": "buttons", "bilingual": True, "ar": "🔗 رابط الإحالة", "en": "🔗 Referral Link"},
    "BTN_SUPPORT": {"cat": "buttons", "bilingual": True, "ar": "☎️ الدعم", "en": "☎️ Support"},
    "BTN_CANCEL": {"cat": "buttons", "bilingual": True, "ar": "❌ إلغاء", "en": "❌ Cancel"},
    "BTN_HWID_YES": {"cat": "buttons", "bilingual": True, "ar": "✅ نعم، تابع", "en": "✅ Yes, continue"},
    "BTN_HWID_NO": {"cat": "buttons", "bilingual": True, "ar": "✏️ لا، أرسل غيره", "en": "✏️ No, send another"},
    "BTN_MAINMENU": {"cat": "buttons", "bilingual": True, "ar": "🔙 القائمة الرئيسية", "en": "🔙 Main Menu"},
    "BTN_BACK": {"cat": "buttons", "bilingual": True, "ar": "↩️ رجوع", "en": "↩️ Back"},
    "BTN_RESEND_FILE": {"cat": "buttons", "bilingual": True, "ar": "📄 أعد إرسال ملف {USERNAME}", "en": "📄 Resend {USERNAME} file"},
    "BTN_LANGTOGGLE": {"cat": "buttons", "bilingual": True, "ar": "🌐 English", "en": "🌐 العربية"},
    "WELCOME": {"cat": "welcome", "bilingual": True, "ar": "👋 <b>أهلًا بك!</b>%0Aالاشتراك الشهري: {PRICE} ريال%0A%0Aاستخدم الأزرار بالأسفل — بدون أي أوامر. (يمكنك أيضًا كتابة /trial أو /subscribe إن أردت.)", "en": "👋 <b>Welcome!</b>%0AMonthly plan: {PRICE} SAR%0A%0AUse the buttons below — no commands needed. (Typing /trial, /subscribe, etc. still works too.)"},
    "APPLIST_PROMPT": {"cat": "welcome", "bilingual": True, "ar": "📁 اختر تطبيقًا:", "en": "📁 Choose an app:"},
    "TYPELIST_PROMPT": {"cat": "welcome", "bilingual": True, "ar": "📁 <b>{APP}</b> — اختر نوع الملف:", "en": "📁 <b>{APP}</b> — choose a file type:"},
    "INVALID_APP_CHOICE": {"cat": "welcome", "bilingual": True, "ar": "❌ اضغط أحد أزرار التطبيقات، أو {MAINMENU_BTN} للإلغاء.", "en": "❌ Please tap one of the app buttons, or {MAINMENU_BTN} to cancel."},
    "INVALID_TYPE_CHOICE": {"cat": "welcome", "bilingual": True, "ar": "❌ اضغط أحد أزرار نوع الملف، أو {MAINMENU_BTN} للإلغاء.", "en": "❌ Please tap one of the file-type buttons, or {MAINMENU_BTN} to cancel."},
    "FALLBACK_UNKNOWN": {"cat": "welcome", "bilingual": True, "ar": "❓ لم أفهم طلبك — استخدم الأزرار بالأسفل، أو أرسل /help.", "en": "❓ Not sure what you mean — use the buttons below, or send /help."},
    "BTN_ANDROID": {"cat": "buttons", "bilingual": True, "ar": "📱 أندرويد", "en": "📱 Android"},
    "BTN_IPHONE": {"cat": "buttons", "bilingual": True, "ar": "🍏 آيفون", "en": "🍏 iPhone"},
    "REGION_PROMPT": {"cat": "region", "bilingual": True, "ar": "🌍 اختر نوع السيرفر:", "en": "🌍 Choose a server type:"},
    "INVALID_REGION_CHOICE": {"cat": "region", "bilingual": True, "ar": "❌ اضغط أحد أزرار نوع السيرفر، أو {MAINMENU_BTN} للإلغاء.", "en": "❌ Please tap one of the server-type buttons, or {MAINMENU_BTN} to cancel."},
    "REGION_REDIRECT": {"cat": "region", "bilingual": True, "ar": "🌍 لخدمة <b>{REGION}</b>، تابع من هنا عبر البوت التالي:%0A{LINK}", "en": "🌍 For <b>{REGION}</b>, continue here through this bot:%0A{LINK}"},
    "DEVICE_PROMPT": {"cat": "region", "bilingual": True, "ar": "📱 اختر نوع جهازك:", "en": "📱 Choose your device type:"},
    "INVALID_DEVICE_CHOICE": {"cat": "region", "bilingual": True, "ar": "❌ اضغط أحد زرّي نوع الجهاز، أو {MAINMENU_BTN} للإلغاء.", "en": "❌ Please tap one of the device-type buttons, or {MAINMENU_BTN} to cancel."},
    "COUNTRY_PROMPT": {"cat": "region", "bilingual": True, "ar": "🌐 اختر الدولة:", "en": "🌐 Choose the country:"},
    "INVALID_COUNTRY_CHOICE": {"cat": "region", "bilingual": True, "ar": "❌ اضغط أحد أزرار الدولة، أو {MAINMENU_BTN} للإلغاء.", "en": "❌ Please tap one of the country buttons, or {MAINMENU_BTN} to cancel."},
    "SIMTYPE_PROMPT": {"cat": "region", "bilingual": True, "ar": "📶 اختر نوع الشريحة:", "en": "📶 Choose the SIM type:"},
    "INVALID_SIMTYPE_CHOICE": {"cat": "region", "bilingual": True, "ar": "❌ اضغط أحد أزرار نوع الشريحة، أو {MAINMENU_BTN} للإلغاء.", "en": "❌ Please tap one of the SIM-type buttons, or {MAINMENU_BTN} to cancel."},
    "FILETYPE_PROMPT": {"cat": "region", "bilingual": True, "ar": "📄 اختر نوع الملف:", "en": "📄 Choose the file type:"},
    "INVALID_FILETYPE_CHOICE": {"cat": "region", "bilingual": True, "ar": "❌ اضغط أحد أزرار نوع الملف، أو {MAINMENU_BTN} للإلغاء.", "en": "❌ Please tap one of the file-type buttons, or {MAINMENU_BTN} to cancel."},
    "INVALID_HWID": {"cat": "trial", "bilingual": True, "ar": "❌ معرّف الجهاز غير صالح — بدون مسافات أو ':' أو '/'، وبحد أقصى 128 حرفًا.", "en": "❌ Invalid device ID — no spaces, ':' or '/', max 128 characters."},
    "INVALID_HWID_NPVS": {"cat": "trial", "bilingual": True, "ar": "❌ هذا ليس معرّف جهاز NPV Tunnel.%0Aالمطلوب: <b>44 حرفًا</b> تنسخها من داخل التطبيق (Device ID / معرّف الجهاز).%0Aالذي أرسلته: <code>{HWID}</code>%0A%0Aانسخه من التطبيق وأعد إرساله هنا، أو اضغط «{MAINMENU_BTN}» للبدء من جديد.", "en": "❌ That is not an NPV Tunnel device ID.%0AExpected: <b>44 characters</b> copied from inside the app (Device ID).%0AYou sent: <code>{HWID}</code>%0A%0ACopy it from the app and send it again, or tap «{MAINMENU_BTN}» to start over."},
    "INVALID_HWID_NPVT": {"cat": "trial", "bilingual": True, "ar": "❌ هذا ليس معرّف جهاز NPV Tunnel.%0Aالمطلوب: <b>64 خانة</b> من الأرقام والحروف a-f تنسخها من داخل التطبيق (Device ID / معرّف الجهاز).%0Aالذي أرسلته: <code>{HWID}</code>%0A%0Aانسخه من التطبيق وأعد إرساله هنا، أو اضغط «{MAINMENU_BTN}» للبدء من جديد.", "en": "❌ That is not an NPV Tunnel device ID.%0AExpected: <b>64 hex characters</b> copied from inside the app (Device ID).%0AYou sent: <code>{HWID}</code>%0A%0ACopy it from the app and send it again, or tap «{MAINMENU_BTN}» to start over."},
    "INVALID_HWID_LEN": {"cat": "trial", "bilingual": True, "ar": "❌ معرّف الجهاز غير مكتمل.%0Aالمطلوب: <b>{LEN} محرفًا</b> بالضبط تنسخها من داخل التطبيق.%0Aالذي أرسلته: <code>{HWID}</code> — <b>{GOT}</b> محرفًا.%0A%0Aانسخه كاملًا وأعد إرساله، أو اضغط «{MAINMENU_BTN}» للبدء من جديد.", "en": "❌ That device ID is not complete.%0AExpected: exactly <b>{LEN} characters</b> copied from inside the app.%0AYou sent: <code>{HWID}</code> — <b>{GOT}</b> characters.%0A%0ACopy the whole thing and send it again, or tap «{MAINMENU_BTN}» to start over."},
    "HWID_CONFIRM": {"cat": "trial", "bilingual": True, "ar": "🔎 <b>تأكيد معرّف الجهاز</b>%0A%0Aسيُنشأ حسابك على هذا المعرّف:%0A<code>{HWID}</code>%0A%0Aتأكّد أنه معرّف جهازك أنت — بعد الإنشاء يعمل الملف على هذا الجهاز وحده.%0A%0Aهل نتابع؟", "en": "🔎 <b>Confirm your device ID</b>%0A%0AYour account will be created on this ID:%0A<code>{HWID}</code>%0A%0AMake sure it is your own device — once created, the file works on this device only.%0A%0AShall we continue?"},
    "HWID_CONFIRM_RETRY": {"cat": "trial", "bilingual": True, "ar": "✏️ حسنًا — أرسل معرّف الجهاز الصحيح الآن.", "en": "✏️ No problem — send the correct device ID now."},
    "FLOW_CANCELLED": {"cat": "trial", "bilingual": True, "ar": "❌ تم الإلغاء. لم يُنشأ أي حساب ولم يُخصم أي رصيد.%0Aتقدر تبدأ من جديد وقت ما تحب.", "en": "❌ Cancelled. No account was created and nothing was charged.%0AStart again whenever you like."},
    "HWID_CONFIRM_LOST": {"cat": "trial", "bilingual": True, "ar": "⚠️ انتهت صلاحية هذه الخطوة. أرسل معرّف الجهاز من جديد من فضلك.", "en": "⚠️ That step has expired. Please send your device ID again."},
    "PROVISION_FAILED": {"cat": "trial", "bilingual": True, "ar": "❌ فشل إنشاء الحساب. حاول مرة أخرى أو تواصل مع الأدمن.", "en": "❌ Failed to create the account. Try again or contact the admin."},
    "MESSAGE_SENT_TO_ADMIN": {"cat": "support", "bilingual": True, "ar": "✅ تم إرسال رسالتك إلى الأدمن.", "en": "✅ Your message was sent to the admin."},
    "TRIAL_ASK_HWID": {"cat": "trial", "bilingual": True, "ar": "📲 أرسل معرّف جهازك (HWID) الآن — سيُستخدم كاسم مستخدم وكلمة مرور معًا.", "en": "📲 Send your device ID (HWID) now — it will be used as both your username and password."},
    "TRIAL_CMD_USAGE": {"cat": "trial", "bilingual": True, "ar": "✋ أرسل معرّف جهازك (HWID) مع الأمر، مثال: <code>/trial abc123device</code>.", "en": "✋ Send your device ID with the command, e.g. <code>/trial abc123device</code>."},
    "TRIAL_LIMIT_REACHED": {"cat": "trial", "bilingual": True, "ar": "❌ لقد استخدمت بالفعل {MAX_USES} من محاولات التجربة المجانية هذا الشهر. أرسل <code>/subscribe {HWID}</code> للاشتراك الشهري، أو عد الشهر القادم.", "en": "❌ You've already used your {MAX_USES} free trial(s) this month. Send <code>/subscribe {HWID}</code> to buy a monthly plan, or come back next month."},
    "TRIAL_DEVICE_USED": {"cat": "trial", "bilingual": True, "ar": "❌ هذا الجهاز استخدم تجربته المجانية بالفعل هذا الشهر.", "en": "❌ This device has already used its free trial this month."},
    "TRIAL_DEVICE_TAKEN": {"cat": "trial", "bilingual": True, "ar": "❌ معرّف الجهاز هذا مسجّل بالفعل لحساب آخر (أو لديه اشتراك مدفوع نشط). تواصل مع الأدمن إن كنت تعتقد أن هذا خطأ.", "en": "❌ This device ID is already registered to a different account (or has an active paid subscription). Contact the admin if you believe this is a mistake."},
    "TRIAL_SUCCESS_NEW": {"cat": "trial", "bilingual": True, "ar": "✅ <b>تم تفعيل التجربة!</b>%0A%0A🆔 معرّف الجهاز: <code>{HWID}</code>%0A(يُستخدم كاسم مستخدم وكلمة مرور معًا)%0A⏳ المدة: {HOURS} ساعة%0A📱 عدد الأجهزة: {DEVICES}%0A📊 الباندويث: {BW}%0Aينتهي في: {EXPIRE}", "en": "✅ <b>Trial Activated!</b>%0A%0A🆔 Device ID: <code>{HWID}</code>%0A(used as both username &amp; password)%0A⏳ Duration: {HOURS}h%0A📱 Devices: {DEVICES}%0A📊 Bandwidth: {BW}%0AExpires: {EXPIRE}"},
    "TRIAL_SUCCESS_RENEWED": {"cat": "trial", "bilingual": True, "ar": "🔄 <b>تم تجديد التجربة!</b> (نفس الجهاز السابق)%0A%0A🆔 معرّف الجهاز: <code>{HWID}</code>%0A(يُستخدم كاسم مستخدم وكلمة مرور معًا)%0A⏳ المدة: {HOURS} ساعة%0A📱 عدد الأجهزة: {DEVICES}%0A📊 الباندويث: {BW}%0Aينتهي في: {EXPIRE}", "en": "🔄 <b>Trial Renewed!</b> (same device as before)%0A%0A🆔 Device ID: <code>{HWID}</code>%0A(used as both username &amp; password)%0A⏳ Duration: {HOURS}h%0A📱 Devices: {DEVICES}%0A📊 Bandwidth: {BW}%0AExpires: {EXPIRE}"},
    "TRIAL_ADMIN_NEW": {"cat": "admin", "bilingual": False, "ar": "🆓 <b>تجربة جديدة</b>%0Aمن: <a href=\"tg://openmessage?user_id={CHAT_ID}\">{CHAT_ID}</a>%0Aالجهاز: {HWID}"},
    "TRIAL_ADMIN_RENEWED": {"cat": "admin", "bilingual": False, "ar": "🆓 <b>تم تجديد تجربة</b>%0Aمن: <a href=\"tg://openmessage?user_id={CHAT_ID}\">{CHAT_ID}</a>%0Aالجهاز: {HWID}"},
    "BTN_MONTH1": {"cat": "buttons", "bilingual": True, "ar": "📅 شهر واحد", "en": "📅 1 Month"},
    "BTN_MONTH2": {"cat": "buttons", "bilingual": True, "ar": "📅 شهرين", "en": "📅 2 Months"},
    "SUBSCRIBE_DURATION_PROMPT": {"cat": "subscribe", "bilingual": True, "ar": "🗓️ اختر مدة الاشتراك:", "en": "🗓️ Choose the subscription duration:"},
    "INVALID_DURATION_CHOICE": {"cat": "subscribe", "bilingual": True, "ar": "❌ اضغط أحد زرّي مدة الاشتراك، أو {MAINMENU_BTN} للإلغاء.", "en": "❌ Please tap one of the duration buttons, or {MAINMENU_BTN} to cancel."},
    "SUBSCRIBE_CMD_USAGE": {"cat": "subscribe", "bilingual": True, "ar": "✋ أرسل معرّف جهازك مع الأمر، مثال: <code>/subscribe abc123device</code> أو <code>/subscribe abc123device COUPON10</code>.%0Aالسعر: {PRICE} ريال شهريًا.", "en": "✋ Send your device ID with the command, e.g. <code>/subscribe abc123device</code> or <code>/subscribe abc123device COUPON10</code>.%0APrice: {PRICE} SAR/month."},
    "SUBSCRIBE_ASK_HWID": {"cat": "subscribe", "bilingual": True, "ar": "📲 أرسل معرّف جهازك (HWID) الآن. السعر: {PRICE} ريال شهريًا.%0Aلديك كود خصم؟ أضفه بعد المعرّف بمسافة.", "en": "📲 Send your device ID (HWID) now. Price: {PRICE} SAR/month.%0AGot a discount code? Add it after the HWID separated by a space."},
    "SUBSCRIBE_ASK_HWID_COVERED": {"cat": "subscribe", "bilingual": True, "ar": "📲 أرسل معرّف جهازك (HWID) الآن. السعر: {PRICE} ريال شهريًا — مغطّى من رصيد محفظتك ({BALANCE} ريال).%0Aلديك كود خصم؟ أضفه بعد المعرّف بمسافة.", "en": "📲 Send your device ID (HWID) now. Price: {PRICE} SAR/month — covered by your wallet balance ({BALANCE} SAR).%0AGot a discount code? Add it after the HWID separated by a space."},
    "SUBSCRIBE_COUPON_INVALID": {"cat": "subscribe", "bilingual": True, "ar": "⚠️ الكوبون '{COUPON}' غير صالح أو منتهي — سيُكمل بالسعر الكامل ({PRICE} ريال).", "en": "⚠️ Coupon '{COUPON}' is invalid or expired — continuing at full price ({PRICE} SAR)."},
    "SUBSCRIBE_DEVICE_TAKEN": {"cat": "subscribe", "bilingual": True, "ar": "❌ معرّف الجهاز هذا مسجّل بالفعل لحساب آخر. تواصل مع الأدمن إن كنت تعتقد أن هذا خطأ.", "en": "❌ This device ID is already registered to a different account. Contact the admin if you believe this is a mistake."},
    "SUBSCRIBE_SUCCESS_WALLET_NEW": {"cat": "subscribe", "bilingual": True, "ar": "✅ <b>تم تفعيل الاشتراك!</b> (دفع من المحفظة)%0A%0A{ID_LINE}🆔 معرّف الجهاز: <code>{HWID}</code>%0A📅 المدة: {DAYS} يوم%0A📱 عدد الأجهزة: {DEVICES}%0A📊 الباندويث: {BW}%0A💳 المبلغ المخصوم: {PRICE} ريال — الرصيد المتبقي: {BALANCE} ريال%0Aينتهي في: {EXPIRE}%0A🔗 رابط متابعة الاستهلاك: {USAGE_LINK}", "en": "✅ <b>Subscription Activated!</b> (paid from wallet)%0A%0A{ID_LINE}🆔 Device ID: <code>{HWID}</code>%0A📅 Duration: {DAYS} days%0A📱 Devices: {DEVICES}%0A📊 Bandwidth: {BW}%0A💳 Charged: {PRICE} SAR — remaining balance: {BALANCE} SAR%0AExpires: {EXPIRE}%0A🔗 Usage tracking link: {USAGE_LINK}"},
    "SUBSCRIBE_SUCCESS_WALLET_RENEWED": {"cat": "subscribe", "bilingual": True, "ar": "🔄 <b>تم تجديد الاشتراك!</b> (دفع من المحفظة)%0A%0A{ID_LINE}🆔 معرّف الجهاز: <code>{HWID}</code>%0A📅 المدة: {DAYS} يوم%0A📱 عدد الأجهزة: {DEVICES}%0A📊 الباندويث: {BW}%0A💳 المبلغ المخصوم: {PRICE} ريال — الرصيد المتبقي: {BALANCE} ريال%0Aينتهي في: {EXPIRE}%0A🔗 رابط متابعة الاستهلاك: {USAGE_LINK}", "en": "🔄 <b>Subscription Renewed!</b> (paid from wallet)%0A%0A{ID_LINE}🆔 Device ID: <code>{HWID}</code>%0A📅 Duration: {DAYS} days%0A📱 Devices: {DEVICES}%0A📊 Bandwidth: {BW}%0A💳 Charged: {PRICE} SAR — remaining balance: {BALANCE} SAR%0AExpires: {EXPIRE}%0A🔗 Usage tracking link: {USAGE_LINK}"},
    "SUBSCRIBE_ADMIN_WALLET": {"cat": "admin", "bilingual": False, "ar": "💳 <b>عملية شراء من المحفظة</b>%0Aمن: <a href=\"tg://openmessage?user_id={CHAT_ID}\">{CHAT_ID}</a>%0Aالجهاز: {HWID}%0Aالمبلغ: {PRICE} ريال"},
    "SUBSCRIBE_ORDER_CREATED": {"cat": "subscribe", "bilingual": True, "ar": "💳 <b>الطلب #{ORDER_ID}</b>%0Aالمبلغ المطلوب: <b>{PRICE} ريال</b>{COUPON_LINE}%0A%0A{PAYMENT_INFO}%0A%0Aبعد التحويل، انتظر هنا — سيُفعَّل طلبك بمجرد تأكيد الأدمن للدفع.", "en": "💳 <b>Order #{ORDER_ID}</b>%0AAmount due: <b>{PRICE} SAR</b>{COUPON_LINE}%0A%0A{PAYMENT_INFO}%0A%0AAfter transferring, wait here — your order will be activated once the admin confirms your payment."},
    "NPVT_LOCK_MESSAGE": {"cat": "region", "bilingual": True, "ar": "DAHOOM — هذا الملف مرتبط بجهازك وحده", "en": "DAHOOM — this file is bound to your device only"},
    "NPVT_SERVER_MESSAGE": {"cat": "region", "bilingual": True, "ar": "DAHOOM — اشتراكك فعّال", "en": "DAHOOM — your subscription is active"},
    "STALE_CHOICE": {"cat": "region", "bilingual": True, "ar": "⚠️ هذا الخيار من رسالة سابقة ولم يعد صالحًا. تفضّل خطوتك الحالية:", "en": "⚠️ That option belongs to an earlier message and is no longer valid. Here is your current step:"},
    "RESEND_NOT_YOURS": {"cat": "region", "bilingual": True, "ar": "❌ هذا الحساب ليس لك.", "en": "❌ That account is not yours."},
    "ADMIN_CREDIT_ADDED": {"cat": "account", "bilingual": True, "ar": "💰 تمت إضافة {AMOUNT} ريال لمحفظتك من قبل الأدمن. رصيدك الجديد: {BALANCE} ريال.", "en": "💰 Your wallet was credited {AMOUNT} SAR by the admin. New balance: {BALANCE} SAR."},
    "ADMIN_TRIALS_ADDED": {"cat": "account", "bilingual": True, "ar": "🎁 حصلت على محاولات تجربة مجانية إضافية من الأدمن. الإجمالي المتاح هذا الشهر: {TOTAL}.", "en": "🎁 You were granted extra free trial attempts by the admin. Total available this month: {TOTAL}."},
    "ADMIN_HWIDCHANGE_ADDED": {"cat": "changehwid", "bilingual": True, "ar": "🔄 حصلت على مرات إضافية لتغيير الجهاز (HWID) من الأدمن. الإجمالي المسموح به الآن: {TOTAL}.", "en": "🔄 You were granted extra device (HWID) changes by the admin. Total allowed now: {TOTAL}."},
    "BAN_NOTICE": {"cat": "support", "bilingual": True, "ar": "🚫 تم حظرك من هذا البوت. السبب: {REASON}%0Aأرسل <code>/appeal رسالتك</code> للتواصل مع الأدمن.", "en": "🚫 You have been banned from this bot. Reason: {REASON}%0ASend <code>/appeal your message</code> to contact the admin."},
    "UNBAN_NOTICE": {"cat": "support", "bilingual": True, "ar": "✅ تم فك حظرك. يمكنك استخدام البوت مرة أخرى.", "en": "✅ You have been unbanned. You can use the bot again."},
    "REFERRAL_NEW_SIGNUP": {"cat": "referral", "bilingual": True, "ar": "🔗 <b>إحالة جديدة!</b> انضم شخص عبر رابطك.", "en": "🔗 <b>New referral!</b> Someone joined using your link."},
    "REFERRAL_REWARD": {"cat": "referral", "bilingual": True, "ar": "🎉 <b>مكافأة إحالة!</b> وصلت إلى {THRESHOLD} {KIND} — تمت إضافة {REWARD} ريال لمحفظتك (الرصيد الجديد: {BALANCE} ريال).", "en": "🎉 <b>Referral reward!</b> You reached {THRESHOLD} {KIND} — {REWARD} SAR was added to your wallet (new balance: {BALANCE} SAR)."},
    "REFERRAL_KIND_PAID": {"cat": "referral", "bilingual": True, "ar": "من قمت بإحالتهم واشتركوا", "en": "paid referrals"},
    "REFERRAL_KIND_SIGNUP": {"cat": "referral", "bilingual": True, "ar": "ممن قمت بإحالتهم", "en": "referred signups"},
    "ACCOUNT_DELETED_EXPIRED": {"cat": "account", "bilingual": True, "ar": "🗑️ <b>تم حذف حسابك المنتهي</b>%0A%0Aالحساب: <code>{USERNAME}</code>%0Aانتهى في: {EXPIRE}%0A%0Aمرّت {DAYS} أيام دون تجديد، فحُذف الحساب بالكامل مع بياناته.%0Aتقدر تشترك من جديد في أي وقت من القائمة.", "en": "🗑️ <b>Your expired account was removed</b>%0A%0AAccount: <code>{USERNAME}</code>%0AExpired on: {EXPIRE}%0A%0A{DAYS} days passed with no renewal, so the account and its data were deleted.%0AYou can subscribe again any time from the menu."},
    "ACCOUNT_DELETED_ADMIN": {"cat": "admin", "bilingual": False, "ar": "🗑️ <b>حذف حسابات منتهية</b>%0Aعددها: {COUNT}%0A{LIST}%0A%0A(كل حساب مضى على انتهائه {DAYS} أيام بلا تجديد)"},
    "NPVT_BUILD_FAILED_ADMIN": {"cat": "admin", "bilingual": False, "ar": "⚠️ <b>تعذّر تخصيص ملف NPV</b>%0Aالتطبيق: {APP} — {TYPE}%0Aالعميل: <a href=\"tg://openmessage?user_id={CHAT_ID}\">{CHAT_ID}</a>%0Aالسبب: {REASON}%0A%0A⚠️ وصل العميل الملف الأصلي بلا قفل جهاز — أي أنه قابل للمشاركة. أرسل /npvt لفحص السبب."},
    "RESEND_NO_RECORD": {"cat": "region", "bilingual": True, "ar": "❌ لا يوجد ملف محفوظ لهذا الحساب. اطلب اشتراكًا جديدًا أو راسل الدعم.", "en": "❌ No saved file for this account. Start a new order or contact support."},
    "SUBSCRIBE_ADMIN_ORDER_PENDING": {"cat": "admin", "bilingual": False, "ar": "🛒 <b>طلب جديد #{ORDER_ID} — بانتظار الدفع</b>%0Aمن: <a href=\"tg://openmessage?user_id={CHAT_ID}\">{CHAT_ID}</a>%0Aالجهاز: {HWID}%0Aالمبلغ: {PRICE} ريال{COUPON_LINE}%0A%0Aموافقة: <code>/approve {ORDER_ID}</code>%0Aرفض: <code>/reject {ORDER_ID}</code>"},
    "SUBSCRIBE_ORDER_APPROVED_NEW": {"cat": "subscribe", "bilingual": True, "ar": "✅ <b>تم تأكيد الدفع — تم تفعيل الاشتراك!</b>%0A%0A{ID_LINE}🆔 معرّف الجهاز: <code>{HWID}</code>%0A📅 المدة: {DAYS} يوم%0A📱 عدد الأجهزة: {DEVICES}%0A📊 الباندويث: {BW}%0Aينتهي في: {EXPIRE}%0A🔗 رابط متابعة الاستهلاك: {USAGE_LINK}", "en": "✅ <b>Payment confirmed — Subscription Activated!</b>%0A%0A{ID_LINE}🆔 Device ID: <code>{HWID}</code>%0A📅 Duration: {DAYS} days%0A📱 Devices: {DEVICES}%0A📊 Bandwidth: {BW}%0AExpires: {EXPIRE}%0A🔗 Usage tracking link: {USAGE_LINK}"},
    "SUBSCRIBE_ORDER_APPROVED_RENEWED": {"cat": "subscribe", "bilingual": True, "ar": "🔄 <b>تم تأكيد الدفع — تم تجديد الاشتراك!</b>%0A%0A{ID_LINE}🆔 معرّف الجهاز: <code>{HWID}</code>%0A📅 المدة: {DAYS} يوم%0A📱 عدد الأجهزة: {DEVICES}%0A📊 الباندويث: {BW}%0Aينتهي في: {EXPIRE}%0A🔗 رابط متابعة الاستهلاك: {USAGE_LINK}", "en": "🔄 <b>Payment confirmed — Subscription Renewed!</b>%0A%0A{ID_LINE}🆔 Device ID: <code>{HWID}</code>%0A📅 Duration: {DAYS} days%0A📱 Devices: {DEVICES}%0A📊 Bandwidth: {BW}%0AExpires: {EXPIRE}%0A🔗 Usage tracking link: {USAGE_LINK}"},
    "SUBSCRIBE_ORDER_REJECTED": {"cat": "subscribe", "bilingual": True, "ar": "❌ تم رفض طلبك #{ORDER_ID}. السبب: {REASON}%0Aتواصل مع الأدمن إن كنت تعتقد أن هذا خطأ.", "en": "❌ Your order #{ORDER_ID} was rejected. Reason: {REASON}%0AContact the admin if you believe this is a mistake."},
    "SUBSCRIBE_ORDER_DEVICE_CONFLICT": {"cat": "subscribe", "bilingual": True, "ar": "❌ تعذّر إتمام طلبك #{ORDER_ID}: هذا الجهاز مسجّل لحساب آخر. تواصل مع الأدمن.", "en": "❌ Your order #{ORDER_ID} could not be completed: that device is registered to a different account. Contact the admin."},
    "BTN_RENEW": {"cat": "buttons", "bilingual": True, "ar": "🔁 تجديد الاشتراك", "en": "🔁 Renew Subscription"},
    "RENEW_NO_ACCOUNT": {"cat": "subscribe", "bilingual": True, "ar": "ℹ️ ليس لديك اشتراك نشط لتجديده. اشترك أولًا من زر «💳 اشتراك شهري».", "en": "ℹ️ You don't have an active subscription to renew. Subscribe first via \"💳 Subscribe\"."},
    "RENEW_PICK_HWID": {"cat": "subscribe", "bilingual": True, "ar": "📱 لديك أكثر من جهاز مشترك، اختر الجهاز الذي تريد تجديده:", "en": "📱 You have more than one subscribed device — choose which one to renew:"},
    "INVALID_RENEW_HWID_CHOICE": {"cat": "subscribe", "bilingual": True, "ar": "❌ اضغط أحد أزرار الأجهزة، أو {MAINMENU_BTN} للإلغاء.", "en": "❌ Please tap one of the device buttons, or {MAINMENU_BTN} to cancel."},
    "PAYMENT_REQUEST": {"cat": "payment", "bilingual": True, "ar": "💳 <b>الدفع</b> — {PRICE} ريال شهريًا%0A%0A{PAYMENT_INFO}%0A%0A🧾 بعد التحويل، أرسل الإيصال هنا على شكل <b>صورة أو ملف</b>. سيصل مباشرة إلى الأدمن للتحقق منه، وبعدها سنطلب منك معرّف جهازك.", "en": "💳 <b>Payment</b> — {PRICE} SAR/month%0A%0A{PAYMENT_INFO}%0A%0A🧾 After transferring, send the receipt here as a <b>photo or file</b>. It goes straight to the admin for verification, and then you'll be asked for your device ID."},
    "RECEIPT_NUDGE": {"cat": "payment", "bilingual": True, "ar": "🧾 أرسل إيصال التحويل على شكل <b>صورة أو ملف</b> — أو اضغط {MAINMENU_BTN} للإلغاء.", "en": "🧾 Please send the transfer receipt as a <b>photo or file</b> — or tap {MAINMENU_BTN} to cancel."},
    "RECEIPT_ADMIN_CONTEXT": {"cat": "admin", "bilingual": False, "ar": "🧾 <b>إيصال دفع جديد</b>%0Aمن: <a href=\"tg://openmessage?user_id={CHAT_ID}\">{CHAT_ID}</a>%0Aالتطبيق: {APP} — {TYPE}%0A%0Aالإيصال في الرسالة التالية 👇%0A(طلب الاشتراك سيصلك بعد أن يرسل العميل معرّف جهازه.)"},
    "RECEIPT_RECEIVED": {"cat": "payment", "bilingual": True, "ar": "✅ تم استلام الإيصال وإرساله إلى الأدمن للتحقق منه.", "en": "✅ Receipt received and sent to the admin for verification."},
    "RECEIPT_RESEND": {"cat": "payment", "bilingual": True, "ar": "⚠️ لم يصل إيصالك إلى الأدمن.%0Aغالبًا بسبب إعدادات الخصوصية في تيليجرام التي تمنع إعادة التوجيه.%0A%0Aأعد إرساله <b>كصورة جديدة</b>، أو من الإعدادات ▸ الخصوصية ▸ الرسائل المُعاد توجيهها اسمح بذلك.", "en": "⚠️ Your receipt did not reach the admin.%0AThis usually happens when your Telegram privacy settings block forwarding.%0A%0APlease send it again as a <b>new photo</b>, or open Settings ▸ Privacy ▸ Forwarded Messages and allow it."},
    "RECEIPT_FORWARD_FAILED": {"cat": "admin", "bilingual": False, "ar": "⚠️ <b>إيصال لم يصل!</b>%0Aالعميل <a href=\"tg://openmessage?user_id={CHAT_ID}\">{CHAT_ID}</a> أرسل إيصالًا لكن تيليجرام رفض تمريره (غالبًا إعدادات خصوصية عنده تمنع إعادة التوجيه).%0A%0A<b>لم يُنشأ أي طلب</b>، وطُلب منه إعادة الإرسال."},
    "SUBSCRIBE_RECEIPT_REQUIRED": {"cat": "payment", "bilingual": True, "ar": "🧾 أرسل إيصال الدفع أولًا.%0Aالمبلغ: {PRICE} ريال%0A%0A{PAYMENT_INFO}%0A%0Aبعد إرسال الإيصال كصورة سيتم إنشاء طلب اشتراكك.", "en": "🧾 Send the payment receipt first.%0APrice: {PRICE} SAR%0A%0A{PAYMENT_INFO}%0A%0AAfter you send the receipt as a photo, your subscription request will be created."},
    "RECEIPT_ASK_HWID": {"cat": "payment", "bilingual": True, "ar": "📲 الآن أرسل معرّف جهازك (HWID).%0Aلديك كود خصم؟ أضفه بعد المعرّف بمسافة.", "en": "📲 Now send your device ID (HWID).%0AGot a discount code? Add it after the HWID separated by a space."},
    "BALANCE_MSG": {"cat": "account", "bilingual": True, "ar": "💰 رصيد محفظتك: <b>{BALANCE} ريال</b>", "en": "💰 Your wallet balance: <b>{BALANCE} SAR</b>"},
    "MYACCOUNT_HEADER": {"cat": "account", "bilingual": True, "ar": "📱 <b>حساباتك</b>%0A", "en": "📱 <b>Your Accounts</b>%0A"},
    "MYACCOUNT_ROW": {"cat": "account", "bilingual": True, "ar": "%0A🆔 <code>{USERNAME}</code>%0A   ينتهي في: {EXPIRE} | الأجهزة: {DEVICES} | الباندويث: {BW}", "en": "%0A🆔 <code>{USERNAME}</code>%0A   Expires: {EXPIRE} | Devices: {DEVICES} | BW: {BW}"},
    "MYACCOUNT_EMPTY": {"cat": "account", "bilingual": True, "ar": "ℹ️ ليس لديك حسابات بعد. جرّب <code>/trial &lt;HWID&gt;</code> أو <code>/subscribe &lt;HWID&gt;</code>.", "en": "ℹ️ You have no accounts yet. Try <code>/trial &lt;HWID&gt;</code> or <code>/subscribe &lt;HWID&gt;</code>."},
    "BTN_CHANGE_HWID": {"cat": "buttons", "bilingual": True, "ar": "🔄 تغيير الجهاز (HWID)", "en": "🔄 Change Device (HWID)"},
    "CHANGE_HWID_NO_ACCOUNT": {"cat": "changehwid", "bilingual": True, "ar": "ℹ️ ليس لديك اشتراك نشط لتغيير جهازه. اشترك أولًا من زر «💳 اشتراك شهري».", "en": "ℹ️ You don't have an active subscription to change the device on. Subscribe first via \"💳 Subscribe\"."},
    "CHANGE_HWID_LIMIT_REACHED": {"cat": "changehwid", "bilingual": True, "ar": "❌ استخدمت الحد الأقصى المسموح به لتغيير الجهاز ({MAX} مرة). تواصل مع الأدمن إن احتجت مرات إضافية.", "en": "❌ You've used up your allowed device changes ({MAX}). Contact the admin if you need more."},
    "CHANGE_HWID_PICK_HWID": {"cat": "changehwid", "bilingual": True, "ar": "📱 لديك أكثر من جهاز مشترك، اختر الجهاز الذي تريد تغييره:", "en": "📱 You have more than one subscribed device — choose which one to change:"},
    "INVALID_CHANGEHWID_PICK": {"cat": "changehwid", "bilingual": True, "ar": "❌ اضغط أحد أزرار الأجهزة، أو {MAINMENU_BTN} للإلغاء.", "en": "❌ Please tap one of the device buttons, or {MAINMENU_BTN} to cancel."},
    "CHANGE_HWID_START": {"cat": "changehwid", "bilingual": True, "ar": "⚠️ سيتم حذف حسابك الحالي نهائيًا واستبداله بحساب جديد بمجرد إدخال الجهاز الجديد — بنفس تاريخ الانتهاء وباقي المزايا. المرات المتبقية بعد هذه: {REMAINING}.%0A%0Aاختر تطبيقك من جديد:", "en": "⚠️ Your current account will be permanently deleted and replaced once you enter the new device — same expiry date and other benefits carried over. Changes remaining after this one: {REMAINING}.%0A%0AChoose your app again:"},
    "CHANGE_HWID_ASK_HWID": {"cat": "changehwid", "bilingual": True, "ar": "📲 أرسل الآن معرّف الجهاز (HWID) الجديد.", "en": "📲 Now send the new device ID (HWID)."},
    "CHANGE_HWID_SAME_DEVICE": {"cat": "changehwid", "bilingual": True, "ar": "❌ هذا هو نفس جهازك الحالي. أرسل معرّف جهاز مختلف، أو {MAINMENU_BTN} للإلغاء.", "en": "❌ That's the same device you already have. Send a different device ID, or {MAINMENU_BTN} to cancel."},
    "CHANGE_HWID_DONE": {"cat": "changehwid", "bilingual": True, "ar": "✅ <b>تم تغيير الجهاز بنجاح!</b>%0A%0A🆔 الجهاز القديم (محذوف): <code>{OLD_HWID}</code>%0A🆔 الجهاز الجديد: <code>{HWID}</code>%0A📅 ينتهي في: {EXPIRE}%0A🔗 رابط متابعة الاستهلاك: {USAGE_LINK}%0A%0Aالمرات المتبقية: {REMAINING}", "en": "✅ <b>Device changed successfully!</b>%0A%0A🆔 Old device (deleted): <code>{OLD_HWID}</code>%0A🆔 New device: <code>{HWID}</code>%0A📅 Expires: {EXPIRE}%0A🔗 Usage tracking link: {USAGE_LINK}%0A%0ARemaining changes: {REMAINING}"},
    "CHANGE_HWID_ADMIN": {"cat": "admin", "bilingual": False, "ar": "🔄 <b>تغيير جهاز (HWID)</b>%0Aمن: <a href=\"tg://openmessage?user_id={CHAT_ID}\">{CHAT_ID}</a>%0Aالقديم: {OLD_HWID}%0Aالجديد: {HWID}"},
    "REFERRAL_LINK_UNAVAILABLE": {"cat": "referral", "bilingual": True, "ar": "تواصل مع الأدمن للحصول على رابط الإحالة.", "en": "Contact the admin to get your referral link."},
    "REFERRAL_MSG": {"cat": "referral", "bilingual": True, "ar": "🔗 <b>رابط الإحالة الخاص بك</b>%0A{LINK}%0A%0A👥 عدد من قمت بإحالتهم: {SIGNUPS}%0A💳 منهم اشتركوا شهريًا: {PAID}%0A%0Aشارك رابطك — عندما يصل عدد كافٍ من المُحالين أو المشتركين، تحصل تلقائيًا على رصيد في محفظتك.", "en": "🔗 <b>Your Referral Link</b>%0A{LINK}%0A%0A👥 People you referred: {SIGNUPS}%0A💳 Of those, went monthly: {PAID}%0A%0AShare your link — when enough people join or subscribe through it, you earn wallet credit automatically."},
    "APPFILE_UNAVAILABLE": {"cat": "appfiles", "bilingual": True, "ar": "❌ هذا الملف لم يعد متوفرًا.", "en": "❌ That file is no longer available."},
    "APPFILE_NONE_FOR_APP": {"cat": "appfiles", "bilingual": True, "ar": "📭 لا توجد أي ملفات متاحة حاليًا لتطبيق <b>{APP}</b>.%0A%0Aاختر تطبيقًا آخر من القائمة بالأسفل.", "en": "📭 There are no files available for <b>{APP}</b> right now.%0A%0APick another app from the list below."},
    "APPFILE_CAPTION": {"cat": "appfiles", "bilingual": True, "ar": "📁 {APP} — {TYPE}", "en": "📁 {APP} — {TYPE}"},
    "HWID_GUIDE_CAPTION": {"cat": "appfiles", "bilingual": True, "ar": "📸 من هنا تجد HWID في تطبيق {APP}", "en": "📸 Here's where to find your HWID in {APP}"},
    "FILE_GUIDE_CAPTION": {"cat": "appfiles", "bilingual": True, "ar": "📖 طريقة إضافة الملف داخل تطبيق {APP}", "en": "📖 How to add the file inside {APP}"},
    "SUPPORT_ASK": {"cat": "support", "bilingual": True, "ar": "✍️ اكتب رسالتك الآن — ستصل مباشرة إلى الأدمن.", "en": "✍️ Type your message now — it goes straight to the admin."},
    "APPEAL_CMD_USAGE": {"cat": "support", "bilingual": True, "ar": "✋ أرسل رسالة بعد الأمر، مثال: <code>/appeal لدي سؤال</code>.", "en": "✋ Send a message after the command, e.g. <code>/appeal I have a question</code>."},
    "SUPPORT_ADMIN_FORWARD": {"cat": "admin", "bilingual": False, "ar": "✉️ <b>رسالة من مستخدم البوت</b>%0Aمن: <a href=\"tg://openmessage?user_id={CHAT_ID}\">{CHAT_ID}</a>%0Aالرسالة: {TEXT}"},
    "SUPPORT_REPLY_HEADER": {"cat": "support", "bilingual": True, "ar": "☎️ <b>رد من الدعم</b>", "en": "☎️ <b>Reply from support</b>"},
    "SUPPORT_REPLY_SENT": {"cat": "admin", "bilingual": False, "ar": "✅ وصل ردّك إلى <a href=\"tg://openmessage?user_id={CHAT_ID}\">{CHAT_ID}</a>."},
    "BROADCAST_STARTED": {"cat": "admin", "bilingual": False, "ar": "📢 <b>بدأ إرسال الإعلان</b>%0Aعدد المستلمين: {TOTAL}%0A%0Aالإرسال يجري في الخلفية — البوت يواصل خدمة العملاء أثناءه، وستصلك النتيجة عند انتهائه."},
    "BROADCAST_DONE": {"cat": "admin", "bilingual": False, "ar": "📢 <b>انتهى إرسال الإعلان</b>%0A✅ وصل: {SENT}%0A❌ لم يصل: {FAILED}%0A%0A(عادةً «لم يصل» تعني أن المستخدم حظر البوت أو حذف محادثته.)"},
    "BAN_BLOCKED": {"cat": "support", "bilingual": True, "ar": "🚫 <b>أنت محظور من هذا البوت.</b>%0Aأرسل رسالة (أو استخدم <code>/appeal رسالتك</code>) للتواصل مع الأدمن.", "en": "🚫 <b>You are banned from this bot.</b>%0ASend a message (or <code>/appeal your message</code>) to contact the admin."},
    "BAN_APPEAL_ADMIN": {"cat": "admin", "bilingual": False, "ar": "🚨 <b>استئناف حظر</b>%0Aمن: <a href=\"tg://openmessage?user_id={CHAT_ID}\">{CHAT_ID}</a>%0Aالرسالة: {TEXT}%0A%0Aلفك الحظر: <code>/unban {CHAT_ID}</code>"},
}
# fmt: on


def _bot_msg_escape(val):
    return val.replace("\\", "\\\\").replace('"', '\\"')


def _bot_msg_unescape(val):
    return val.replace('\\"', '"').replace("\\\\", "\\")


def read_bot_messages():
    """Reads bot_messages.conf as plain KEY_LANG="VALUE" text (same
    not-executed parsing as read_bot_plans, and for the same reason: an
    admin-authored override is free text)."""
    out = {}
    if os.path.exists(BOT_MESSAGES_CONF):
        try:
            with open(BOT_MESSAGES_CONF, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    line = line.rstrip("\n")
                    if "=" not in line:
                        continue
                    k, _, v = line.partition("=")
                    k = k.strip()
                    if len(v) >= 2 and v.startswith('"') and v.endswith('"'):
                        v = v[1:-1]
                    out[k] = _bot_msg_unescape(v)
        except Exception:
            pass
    return out


def bot_msg_get(key, lang):
    """One message's current text: a stored override if present, else the
    catalog default. Mirrors menu.sh's _fm_bot_msg exactly."""
    spec = BOT_MSG_CATALOG.get(key)
    if spec is None:
        return ""
    overrides = read_bot_messages()
    field = f"{key}_{lang.upper()}"
    if field in overrides:
        return overrides[field]
    return spec["ar"] if not spec["bilingual"] or lang != "en" else spec["en"]


def bot_msg_set(key, lang, value):
    if key not in BOT_MSG_CATALOG:
        raise ValueError(f"unknown message key: {key}")
    os.makedirs(os.path.dirname(BOT_MESSAGES_CONF), exist_ok=True)
    field = f"{key}_{lang.upper()}"
    value = value.replace("\r", "").replace("\n", "%0A")
    lines = []
    if os.path.exists(BOT_MESSAGES_CONF):
        with open(BOT_MESSAGES_CONF, encoding="utf-8", errors="ignore") as f:
            lines = [ln for ln in f.read().split("\n") if ln and not ln.startswith(field + "=")]
    lines.append(f'{field}="{_bot_msg_escape(value)}"')
    with open(BOT_MESSAGES_CONF, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def bot_msg_render(key, lang, **subs):
    """bot_msg_get() plus {TOKEN} substitution, with the stored %0A
    newline-encoding converted to a real '\\n' — send_bot_telegram_msg
    urlencodes its text before sending, so a literal '%0A' byte would be
    double-encoded into '%250A' and show up as the text "%0A" in the
    chat instead of a line break. menu.sh has no equivalent step: curl
    there is handed the raw '%0A' bytes on the wire directly."""
    msg = bot_msg_get(key, lang)
    for token, value in subs.items():
        msg = msg.replace("{" + token + "}", str(value))
    return msg.replace("%0A", "\n")


def bot_msg_reset(key, lang):
    field = f"{key}_{lang.upper()}"
    if not os.path.exists(BOT_MESSAGES_CONF):
        return
    with open(BOT_MESSAGES_CONF, encoding="utf-8", errors="ignore") as f:
        lines = [ln for ln in f.read().split("\n") if ln and not ln.startswith(field + "=")]
    with open(BOT_MESSAGES_CONF, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + ("\n" if lines else ""))


def write_bot_plan(key, value, node=""):
    """Sets one plan key, preserving every other key already in the file
    (including ones this process doesn't know about, and every other
    node's overrides). Escapes backslash and double-quote in the value so
    the file stays valid plain text no matter what the admin types — see
    _read_bot_plans_raw for why it's never executed as code.

    With a node, the value is stored as that node's override instead of
    the global setting, and an empty value removes the override entirely
    so the node goes back to inheriting the global — matching
    _fm_bot_set_plan. A global key is never dropped that way: an empty
    global value is a real, if unusual, setting."""
    plans = dict(BOT_PLAN_DEFAULTS)
    plans.update(_read_bot_plans_raw())
    stored_key = bot_plan_node_key(node, str(key))
    if node and str(value) == "":
        plans.pop(stored_key, None)
    else:
        plans[stored_key] = str(value)
    os.makedirs(os.path.dirname(BOT_PLANS_CONF), exist_ok=True)
    with open(BOT_PLANS_CONF, "w", encoding="utf-8") as f:
        for k, v in plans.items():
            f.write(f'{k}="{_bot_plan_escape(str(v))}"\n')


def _read_telegram_conf():
    conf = {}
    if os.path.exists(TELEGRAM_CONF):
        try:
            with open(TELEGRAM_CONF, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    line = line.strip()
                    if "=" not in line:
                        continue
                    k, _, v = line.partition("=")
                    v = v.strip()
                    if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
                        v = v[1:-1]
                    conf[k.strip()] = v
        except Exception:
            pass
    return conf


def sales_bot_enabled():
    """Whether the two sales-bot admin tabs (bot management + message
    editor) should appear in the panel sidebar at all — set from the
    terminal only (telegram_bot_menu's toggle in menu.sh), never from the
    panel itself, since it's a DAHOOM-specific commercial feature most
    single-VPN-node installs never touch. A fresh server has no
    TELEGRAM_CONF at all yet and stays hidden until explicitly turned on.
    A server that already had Telegram configured before this toggle
    existed was already relying on these tabs being visible, so an
    unset flag there defaults to enabled instead of silently hiding a
    feature someone is actively using."""
    conf = _read_telegram_conf()
    if "SALES_BOT_ENABLED" in conf:
        return conf["SALES_BOT_ENABLED"] == "true"
    return os.path.exists(TELEGRAM_CONF)


def bot_all_chat_ids():
    """Every customer the bot could reach, once each — the Python mirror
    of menu.sh's _fm_bot_all_chat_ids. Telegram offers no "list my
    users" call, so this is the union of the registry the bot writes and
    every store that already names a customer; without that union an
    announcement sent from the panel would miss everyone who bought
    before the registry existed. Banned customers are excluded.
    """
    ids = set()

    def _add(path, field, sep=":"):
        if not os.path.exists(path):
            return
        try:
            with open(path, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    parts = line.rstrip("\n").split(sep)
                    if len(parts) > field and re.fullmatch(r"-?\d+", parts[field].strip()):
                        ids.add(parts[field].strip())
        except OSError:
            pass

    _add(BOT_KNOWN_CHATS_DB, 0)
    _add(BOT_WALLETS_DB, 0)
    _add(BOT_TRIAL_LOG, 0)
    _add(BOT_LANG_DB, 0)
    _add(BOT_ORDERS_DB, 1)
    # users.db rows end with the owner tag "tg:<id>", so the id is the
    # last field and "tg" the one before it.
    if os.path.exists(DB_FILE):
        try:
            with open(DB_FILE, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    parts = line.rstrip("\n").split(":")
                    if len(parts) >= 9 and parts[7] == "tg" and re.fullmatch(r"-?\d+", parts[8]):
                        ids.add(parts[8])
        except OSError:
            pass

    banned = {b["telegram_id"] for b in read_bot_bans()} if os.path.exists(BOT_BANS_DB) else set()
    return sorted(ids - banned, key=lambda x: int(x))


def bot_broadcast(text):
    """Sends one announcement to every reachable customer and reports
    how many actually got it. Every send is counted, so a customer who
    blocked the bot is a number rather than a silent disappearance."""
    text = (text or "").strip()
    if not text:
        raise ValueError("Announcement text is required")
    token = _read_telegram_conf().get("BOT_TOKEN", "")
    if not token:
        raise ValueError("Telegram bot is not configured")
    sent = failed = 0
    for cid in bot_all_chat_ids():
        try:
            data = urllib.parse.urlencode({
                "chat_id": cid, "text": text,
                "parse_mode": "HTML", "disable_web_page_preview": "true",
            }).encode()
            req = urllib.request.Request(f"https://api.telegram.org/bot{token}/sendMessage", data=data)
            with urllib.request.urlopen(req, timeout=20) as resp:
                body = resp.read().decode("utf-8", "ignore")
            sent += 1 if '"ok":true' in body else 0
            failed += 0 if '"ok":true' in body else 1
        except Exception:
            failed += 1
        # Telegram caps bulk sending at ~30/second; staying well under it
        # is what stops the run being throttled into dropping the rest.
        time.sleep(0.05)
    return sent, failed


def send_bot_telegram_msg(chat_id, text):
    """Panel-side equivalent of menu.sh's send_telegram_msg_to — sends a
    message to an arbitrary Telegram chat using the admin's configured
    bot token, so approving/rejecting an order or crediting a wallet from
    the WEB panel notifies the customer exactly like doing it from the
    bot does. Best-effort: swallows all errors, since a failed
    notification must never block the actual action."""
    if not chat_id:
        return
    token = _read_telegram_conf().get("BOT_TOKEN", "")
    if not token:
        return
    try:
        data = urllib.parse.urlencode({"chat_id": str(chat_id), "text": text, "parse_mode": "HTML"}).encode()
        req = urllib.request.Request(f"https://api.telegram.org/bot{token}/sendMessage", data=data)
        urllib.request.urlopen(req, timeout=5)
    except Exception:
        pass


def bot_lang_get(chat_id):
    """The customer's chosen bot language ("ar"/"en"). Arabic unless they
    explicitly switched, matching menu.sh's _fm_bot_lang_get."""
    try:
        with open(BOT_LANG_DB, "r") as f:
            for line in f:
                parts = line.strip().split(":", 1)
                if len(parts) == 2 and parts[0] == str(chat_id) and parts[1] in ("ar", "en"):
                    return parts[1]
    except Exception:
        pass
    return "ar"


def _telegram_send_document(chat_id, file_path, filename, caption=""):
    """Sends a local file to a Telegram chat as a document, hand-building
    the multipart/form-data body with stdlib only (no extra dependency
    like `requests`) — mirrors what the bash side does with `curl -F`."""
    token = _read_telegram_conf().get("BOT_TOKEN", "")
    if not token or not os.path.isfile(file_path):
        return False
    boundary = "----DAHOOMBoundary" + uuid.uuid4().hex
    try:
        with open(file_path, "rb") as f:
            file_bytes = f.read()
    except OSError:
        return False

    def text_field(name, value):
        return (f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n').encode("utf-8")

    body = bytearray()
    body += text_field("chat_id", str(chat_id))
    if caption:
        body += text_field("caption", caption)
    body += (f'--{boundary}\r\nContent-Disposition: form-data; name="document"; filename="{filename}"\r\n'
              'Content-Type: application/octet-stream\r\n\r\n').encode("utf-8")
    body += file_bytes
    body += f'\r\n--{boundary}--\r\n'.encode("utf-8")

    try:
        req = urllib.request.Request(
            f"https://api.telegram.org/bot{token}/sendDocument",
            data=bytes(body), method="POST",
        )
        req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
        urllib.request.urlopen(req, timeout=30)
        return True
    except Exception:
        return False


def bot_appfile_render_and_send(chat_id, app, ftype, hwid):
    """Python mirror of menu.sh's _fm_bot_appfile_render_and_send — used
    when an order that picked its app/file-type before ever giving an
    HWID is approved from the WEB PANEL, so file delivery behaves
    identically whichever side approves the order. Same placeholders
    ({HWID} {USERNAME} {PASSWORD} {SERVER_IP} {EXPIRY}), same
    binary-safe pass-through for non-text templates."""
    src = os.path.join(BOT_APP_FILES_DIR, app, ftype)
    if not os.path.isfile(src):
        return False

    exp_date = ""
    u = next((x for x in read_db() if x["username"] == hwid), None)
    if u:
        exp_date = str(u.get("expire_date", ""))
    try:
        server_ip = subprocess.check_output(
            ["curl", "-s", "-4", "--max-time", "5", "icanhazip.com"], timeout=8
        ).decode().strip()
    except Exception:
        server_ip = "YOUR_SERVER_IP"
    server_ip = server_ip or "YOUR_SERVER_IP"

    with open(src, "rb") as f:
        raw = f.read()

    if b"\x00" in raw:
        out_bytes = raw  # binary template (e.g. an encrypted .ehi) — pass through untouched
    else:
        try:
            content = raw.decode("utf-8")
        except UnicodeDecodeError:
            content = raw.decode("latin-1")
        content = (content.replace("{HWID}", hwid).replace("{USERNAME}", hwid)
                          .replace("{PASSWORD}", hwid).replace("{SERVER_IP}", server_ip)
                          .replace("{EXPIRY}", exp_date))
        out_bytes = content.encode("utf-8")

    orig_name = _bot_appfile_meta_get(app, ftype) or f"{app}_{ftype}.txt"
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False) as tf:
            tf.write(out_bytes)
            tmp_path = tf.name
        return _telegram_send_document(chat_id, tmp_path, orig_name, caption=f"📁 {app} — {ftype}")
    finally:
        if tmp_path:
            try:
                os.remove(tmp_path)
            except OSError:
                pass


def bot_wallet_get(tg):
    tg = str(tg)
    if os.path.exists(BOT_WALLETS_DB):
        try:
            with open(BOT_WALLETS_DB, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    parts = line.strip().split(":")
                    if len(parts) >= 2 and parts[0] == tg:
                        try:
                            return float(parts[1])
                        except ValueError:
                            return 0.0
        except Exception:
            pass
    return 0.0


def read_bot_wallets():
    """All wallets with a non-zero balance, for the admin's wallet table."""
    wallets = []
    if os.path.exists(BOT_WALLETS_DB):
        try:
            with open(BOT_WALLETS_DB, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    parts = line.strip().split(":")
                    if len(parts) >= 2 and parts[0]:
                        try:
                            bal = float(parts[1])
                        except ValueError:
                            continue
                        if bal != 0:
                            wallets.append({"telegram_id": parts[0], "balance": bal})
        except Exception:
            pass
    return wallets


def bot_wallet_set(tg, amount):
    tg = str(tg)
    wallets = {}
    if os.path.exists(BOT_WALLETS_DB):
        with open(BOT_WALLETS_DB, encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.strip().split(":")
                if len(parts) >= 2 and parts[0]:
                    wallets[parts[0]] = parts[1]
    wallets[tg] = f"{float(amount):.2f}"
    os.makedirs(os.path.dirname(BOT_WALLETS_DB), exist_ok=True)
    with open(BOT_WALLETS_DB, "w", encoding="utf-8") as f:
        for k, v in wallets.items():
            f.write(f"{k}:{v}\n")


def bot_wallet_add(tg, delta):
    """Adds (or, with a negative delta, subtracts from) a wallet — never
    lets it go below zero. Returns the new balance."""
    new = max(0.0, bot_wallet_get(tg) + float(delta))
    bot_wallet_set(tg, new)
    return new


def read_bot_coupons():
    coupons = []
    if os.path.exists(BOT_COUPONS_DB):
        try:
            with open(BOT_COUPONS_DB, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    parts = line.strip().split(":")
                    if len(parts) >= 6:
                        coupons.append({
                            "code": parts[0], "type": parts[1],
                            "value": float(parts[2]) if _is_num(parts[2]) else 0.0,
                            "max_uses": int(parts[3]) if parts[3].isdigit() else 0,
                            "used": int(parts[4]) if parts[4].isdigit() else 0,
                            "enabled": parts[5] == "1",
                        })
        except Exception:
            pass
    return coupons


def _is_num(s):
    try:
        float(s)
        return True
    except (TypeError, ValueError):
        return False


def _write_bot_coupons(coupons):
    os.makedirs(os.path.dirname(BOT_COUPONS_DB), exist_ok=True)
    with open(BOT_COUPONS_DB, "w", encoding="utf-8") as f:
        for c in coupons:
            f.write(f"{c['code']}:{c['type']}:{c['value']}:{c['max_uses']}:{c['used']}:{1 if c['enabled'] else 0}\n")


def bot_coupon_add(code, ctype, value, max_uses=0):
    code = code.upper()
    coupons = [c for c in read_bot_coupons() if c["code"] != code]
    coupons.append({"code": code, "type": ctype, "value": float(value), "max_uses": int(max_uses or 0), "used": 0, "enabled": True})
    _write_bot_coupons(coupons)


def bot_coupon_delete(code):
    code = code.upper()
    coupons = [c for c in read_bot_coupons() if c["code"] != code]
    _write_bot_coupons(coupons)


def bot_coupon_set_enabled(code, enabled):
    code = code.upper()
    coupons = read_bot_coupons()
    found = False
    for c in coupons:
        if c["code"] == code:
            c["enabled"] = bool(enabled)
            found = True
    if found:
        _write_bot_coupons(coupons)
    return found


def bot_coupon_preview(code, price):
    """Returns (discounted_price, applied: bool) — price unchanged and
    applied=False if the coupon doesn't exist, is disabled, or has hit
    its use cap. Read-only: does not burn a use."""
    code = (code or "").upper()
    price = float(price)
    for c in read_bot_coupons():
        if c["code"] != code:
            continue
        if not c["enabled"]:
            return price, False
        if c["max_uses"] > 0 and c["used"] >= c["max_uses"]:
            return price, False
        if c["type"] == "pct":
            return max(0.0, round(price - price * c["value"] / 100, 2)), True
        return max(0.0, round(price - c["value"], 2)), True
    return price, False


def bot_coupon_increment_usage(code):
    code = (code or "").upper()
    coupons = read_bot_coupons()
    for c in coupons:
        if c["code"] == code:
            c["used"] += 1
            _write_bot_coupons(coupons)
            return True
    return False


def read_bot_bans():
    bans = []
    if os.path.exists(BOT_BANS_DB):
        try:
            with open(BOT_BANS_DB, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    line = line.rstrip("\n")
                    if not line:
                        continue
                    # Ban reasons are free text and may contain ':' — peel
                    # the timestamp off the END first, then split the
                    # remainder on the FIRST ':' for id vs. reason, so an
                    # embedded colon in the reason can't misalign fields.
                    rest, _, ts = line.rpartition(":")
                    tg_id, _, reason = rest.partition(":")
                    if tg_id:
                        bans.append({"telegram_id": tg_id, "reason": reason, "timestamp": ts})
        except Exception:
            pass
    return bans


def bot_is_banned(tg):
    tg = str(tg)
    return any(b["telegram_id"] == tg for b in read_bot_bans())


def _write_bot_bans(bans):
    os.makedirs(os.path.dirname(BOT_BANS_DB), exist_ok=True)
    with open(BOT_BANS_DB, "w", encoding="utf-8") as f:
        for b in bans:
            f.write(f"{b['telegram_id']}:{b['reason']}:{b['timestamp']}\n")


def bot_ban(tg, reason=""):
    tg = str(tg)
    bans = [b for b in read_bot_bans() if b["telegram_id"] != tg]
    bans.append({"telegram_id": tg, "reason": reason or "No reason given", "timestamp": str(int(time.time()))})
    _write_bot_bans(bans)


def bot_unban(tg):
    tg = str(tg)
    bans = [b for b in read_bot_bans() if b["telegram_id"] != tg]
    _write_bot_bans(bans)


def read_bot_trial_log():
    entries = []
    if os.path.exists(BOT_TRIAL_LOG):
        try:
            with open(BOT_TRIAL_LOG, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    parts = line.strip().split(":")
                    if len(parts) >= 3:
                        entries.append({"telegram_id": parts[0], "hwid": parts[1], "timestamp": parts[2]})
        except Exception:
            pass
    return entries


def _bot_current_month_start_epoch():
    now = datetime.now()
    return int(datetime(now.year, now.month, 1).timestamp())


def bot_trial_entries(query=""):
    """The trial log, newest first, optionally filtered by device id or
    Telegram id (substring, case-insensitive). Each row carries whether it
    still counts against this month's limits — a row from a previous month
    blocks nothing, since both the per-user and per-device trial gates
    reset on the 1st, so deleting it would achieve nothing."""
    ms = _bot_current_month_start_epoch()
    q = (query or "").strip().lower()
    out = []
    for e in read_bot_trial_log():
        if q and q not in e["hwid"].lower() and q not in e["telegram_id"].lower():
            continue
        ts = e.get("timestamp", "")
        ts_i = int(ts) if str(ts).isdigit() else 0
        out.append({
            "telegram_id": e["telegram_id"],
            "hwid": e["hwid"],
            "timestamp": ts,
            "date": datetime.fromtimestamp(ts_i).strftime("%Y-%m-%d %H:%M") if ts_i else "—",
            "blocking": ts_i >= ms,
        })
    out.sort(key=lambda r: int(r["timestamp"]) if str(r["timestamp"]).isdigit() else 0, reverse=True)
    return out


def bot_trial_log_delete(hwid, telegram_id=None, timestamp=None):
    """Forget that a device ever took a trial, so it can take one again.

    Removes whole rows rather than flagging an exception, because ONE row
    feeds BOTH gates: the per-device check ("this phone already had one
    this month, whoever asked") and the owner's own monthly counter.
    Clearing an exception list would have re-opened only the first and
    left the customer blocked by the second with a different message.

    Passing telegram_id+timestamp deletes exactly that one attempt;
    passing the device alone forgets every attempt it ever made.
    Returns how many rows were removed."""
    hwid = (hwid or "").strip()
    if not hwid or not os.path.exists(BOT_TRIAL_LOG):
        return 0
    tg = None if telegram_id is None else str(telegram_id).strip()
    ts = None if timestamp is None else str(timestamp).strip()
    kept, removed = [], 0
    with open(BOT_TRIAL_LOG, encoding="utf-8", errors="ignore") as f:
        for line in f:
            parts = line.strip().split(":")
            if len(parts) >= 3 and parts[1] == hwid \
               and (tg is None or parts[0] == tg) \
               and (ts is None or parts[2] == ts):
                removed += 1
                continue
            kept.append(line)
    if removed:
        with open(BOT_TRIAL_LOG, "w", encoding="utf-8") as f:
            f.writelines(kept)
    return removed


def bot_trial_count_for_user(tg):
    """Trials used by this Telegram id THIS CALENDAR MONTH — mirrors
    menu.sh's monthly-reset window on the same log file/cutoff, so the
    bot and the panel never disagree about how many trials are left."""
    tg = str(tg)
    ms = _bot_current_month_start_epoch()
    n = 0
    for e in read_bot_trial_log():
        ts = e.get("timestamp", "")
        if e["telegram_id"] == tg and str(ts).isdigit() and int(ts) >= ms:
            n += 1
    return n


def bot_trial_bonus_get(tg):
    tg = str(tg)
    if not os.path.exists(BOT_TRIAL_BONUS_DB):
        return 0
    try:
        with open(BOT_TRIAL_BONUS_DB, encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.strip().split(":")
                if len(parts) >= 2 and parts[0] == tg:
                    return int(parts[1]) if parts[1].lstrip("-").isdigit() else 0
    except Exception:
        pass
    return 0


def bot_trial_bonus_set(tg, value):
    tg = str(tg)
    value = max(0, int(value))
    os.makedirs(os.path.dirname(BOT_TRIAL_BONUS_DB), exist_ok=True)
    lines = []
    if os.path.exists(BOT_TRIAL_BONUS_DB):
        with open(BOT_TRIAL_BONUS_DB, encoding="utf-8", errors="ignore") as f:
            lines = [l for l in f if not l.startswith(f"{tg}:")]
    lines.append(f"{tg}:{value}\n")
    with open(BOT_TRIAL_BONUS_DB, "w", encoding="utf-8") as f:
        f.writelines(lines)
    return value


def bot_trial_bonus_add(tg, delta):
    return bot_trial_bonus_set(tg, bot_trial_bonus_get(tg) + int(delta))


def read_bot_trial_bonuses():
    """All admin-granted bonus trial balances, for the panel table."""
    out = []
    if os.path.exists(BOT_TRIAL_BONUS_DB):
        try:
            with open(BOT_TRIAL_BONUS_DB, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    parts = line.strip().split(":")
                    if len(parts) >= 2:
                        out.append({"telegram_id": parts[0], "bonus": int(parts[1]) if parts[1].lstrip("-").isdigit() else 0})
        except Exception:
            pass
    return out


def bot_hwidchange_bonus_get(tg):
    tg = str(tg)
    if not os.path.exists(BOT_HWID_CHANGE_BONUS_DB):
        return 0
    try:
        with open(BOT_HWID_CHANGE_BONUS_DB, encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.strip().split(":")
                if len(parts) >= 2 and parts[0] == tg:
                    return int(parts[1]) if parts[1].lstrip("-").isdigit() else 0
    except Exception:
        pass
    return 0


def bot_hwidchange_bonus_set(tg, value):
    tg = str(tg)
    value = max(0, int(value))
    os.makedirs(os.path.dirname(BOT_HWID_CHANGE_BONUS_DB), exist_ok=True)
    lines = []
    if os.path.exists(BOT_HWID_CHANGE_BONUS_DB):
        with open(BOT_HWID_CHANGE_BONUS_DB, encoding="utf-8", errors="ignore") as f:
            lines = [l for l in f if not l.startswith(f"{tg}:")]
    lines.append(f"{tg}:{value}\n")
    with open(BOT_HWID_CHANGE_BONUS_DB, "w", encoding="utf-8") as f:
        f.writelines(lines)
    return value


def bot_hwidchange_bonus_add(tg, delta):
    return bot_hwidchange_bonus_set(tg, bot_hwidchange_bonus_get(tg) + int(delta))


def read_bot_hwidchange_bonuses():
    """All admin-granted bonus HWID-change balances, for the panel table."""
    out = []
    if os.path.exists(BOT_HWID_CHANGE_BONUS_DB):
        try:
            with open(BOT_HWID_CHANGE_BONUS_DB, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    parts = line.strip().split(":")
                    if len(parts) >= 2:
                        out.append({"telegram_id": parts[0], "bonus": int(parts[1]) if parts[1].lstrip("-").isdigit() else 0})
        except Exception:
            pass
    return out


def read_bot_orders():
    orders = []
    if os.path.exists(BOT_ORDERS_DB):
        try:
            with open(BOT_ORDERS_DB, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    parts = line.strip().split(":")
                    if len(parts) >= 7:
                        orders.append({
                            "order_id": parts[0], "telegram_id": parts[1], "hwid": parts[2],
                            "amount": parts[3], "coupon": parts[4], "status": parts[5], "timestamp": parts[6],
                            # "app|type" the customer picked before being asked
                            # for their HWID (app-file-first flow), or "".
                            "app_type": parts[7] if len(parts) > 7 else "",
                            # Which duration tier ("1" or "2" months) this
                            # order is for — missing/blank on an order from
                            # before the 2-month plan existed, which always
                            # meant the 1-month plan.
                            "tier": parts[8] if len(parts) > 8 and parts[8] else "1",
                        })
        except Exception:
            pass
    return orders


def get_bot_order(order_id):
    order_id = str(order_id)
    for o in read_bot_orders():
        if o["order_id"] == order_id:
            return o
    return None


def set_bot_order_status(order_id, status):
    order_id = str(order_id)
    orders = read_bot_orders()
    found = False
    for o in orders:
        if o["order_id"] == order_id:
            o["status"] = status
            found = True
    if found:
        os.makedirs(os.path.dirname(BOT_ORDERS_DB), exist_ok=True)
        with open(BOT_ORDERS_DB, "w", encoding="utf-8") as f:
            for o in orders:
                f.write(f"{o['order_id']}:{o['telegram_id']}:{o['hwid']}:{o['amount']}:{o['coupon']}:{o['status']}:{o['timestamp']}:{o.get('app_type', '')}:{o.get('tier', '1')}\n")
    return found


def bot_provision_hwid_account(hwid, hours, bw_gb, devices, owner_tag, acct_type):
    """Python mirror of menu.sh's _fm_bot_provision_hwid_account — routes
    through create_system_user_safe exactly like every other account
    creation path in this file, so a panel-approved order behaves
    identically to a bot-approved one.

    A device id reused by its OWN owner (same tg:<chat_id>) is a normal
    renewal (reinstalled app, refreshed device id, trial-to-paid upgrade)
    — this extends the existing account in place instead of failing.
    Reused by a different owner, or a paid ("web") account being asked to
    downgrade to a trial, is still rejected.

    Returns (expire_date, renewed_bool). Raises ValueError on failure
    (device belongs to someone else, or a system-level failure)."""
    hours = int(hours)
    if hours >= 24:
        expire_date = (datetime.now() + timedelta(days=hours // 24)).strftime("%Y-%m-%d")
    else:
        expire_date = (datetime.now() + timedelta(days=1)).strftime("%Y-%m-%d")

    existing = next((u for u in read_db() if u["username"] == hwid), None)
    if existing:
        cur_owner = existing.get("owner", "")
        cur_type = existing.get("account_type", "web")
        if cur_owner != owner_tag:
            raise ValueError("This device ID is already registered to a different account")
        if acct_type == "trial" and cur_type != "trial":
            raise ValueError("This device ID already has an active paid subscription")
        run_cmd(["chage", "-E", expire_date, hwid], ignore_errors=True)
        renewed_u = {
            "username": hwid, "password": hwid, "expire_date": expire_date,
            "conn_limit": devices, "bandwidth_gb": bw_gb, "daily_bandwidth_gb": 0,
            "account_type": acct_type, "owner": owner_tag,
        }
        with db_lock:
            lines = []
            with open(DB_FILE, "r") as f:
                lines = f.readlines()
            with open(DB_FILE, "w") as f:
                for line in lines:
                    if line.startswith(f"{hwid}:"):
                        f.write(format_db_line(renewed_u))
                    else:
                        f.write(line)
        try:
            os.remove(f"{BW_DIR}/{hwid}.usage")
        except OSError:
            pass
        set_login_mode(hwid, "hwid")
        return expire_date, True

    code, _, _ = run_cmd(["id", hwid])
    if code == 0:
        raise ValueError("This device ID is already registered to a different account")

    create_system_user_safe(hwid)
    run_cmd(["usermod", "-aG", FF_USERS_GROUP, hwid], ignore_errors=True)
    set_system_password(hwid, hwid)
    run_cmd(["chage", "-E", expire_date, hwid])
    new_u = {
        "username": hwid, "password": hwid, "expire_date": expire_date,
        "conn_limit": devices, "bandwidth_gb": bw_gb, "daily_bandwidth_gb": 0,
        "account_type": acct_type, "owner": owner_tag,
    }
    with db_lock:
        os.makedirs(os.path.dirname(DB_FILE), exist_ok=True)
        with open(DB_FILE, "a") as f:
            f.write(format_db_line(new_u))
    set_login_mode(hwid, "hwid")
    return expire_date, False


# ── Device-id -> account-name minting for long device ids (NPV Tunnel's
# are 64 characters, far past what a Linux username / utmp / the session
# limiter can hold) — Python port of menu.sh's identically-named
# _fm_bot_account_name_for_device / _fm_bot_account_name_mint_for_device
# / _fm_bot_account_lookup_device / _fm_bot_device_for_account /
# _fm_bot_npvt_remap_device. Needed so a remote node (this file, reached
# over /api/node/*) can do its own minting — uniqueness is scoped to
# whichever node the account ends up living on, so it can only be
# resolved there, not on the controller sending the request. ───────────
def bot_account_lookup_device(device):
    """Read-only: does this device already own a minted account name?
    Short ids are returned unchanged (they ARE the username already)."""
    if not device:
        return None
    if len(device) <= _FM_BOT_NAME_MAX:
        return device
    if not os.path.exists(NPVT_DEVICES_DB):
        return None
    try:
        with open(NPVT_DEVICES_DB, encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.rstrip("\n").split(":", 1)
                if len(parts) == 2 and parts[0] == device:
                    return parts[1]
    except Exception:
        pass
    return None


def _bot_mint_device_name(device):
    os.makedirs(os.path.dirname(NPVT_DEVICES_DB), exist_ok=True)
    if not os.path.exists(NPVT_DEVICES_DB):
        open(NPVT_DEVICES_DB, "a").close()
    for _ in range(60):
        candidate = f"dahoom{secrets.randbelow(90000) + 10000}vip"
        code, _, _ = run_cmd(["id", candidate], ignore_errors=True)
        taken_in_db = False
        with open(NPVT_DEVICES_DB, encoding="utf-8", errors="ignore") as f:
            taken_in_db = any(l.rstrip("\n").endswith(f":{candidate}") for l in f)
        if code != 0 and not taken_in_db:
            with open(NPVT_DEVICES_DB, "a", encoding="utf-8") as f:
                f.write(f"{device}:{candidate}\n")
            return candidate
    raise ValueError("Could not mint a unique account name for this device")


def bot_account_name_for_device(device):
    """Reuse the device's last minted name if it has one, else mint a
    fresh one. A normal (non-"fresh") provision call — reinstalled app,
    refreshed device id, trial-to-paid upgrade — should land on the SAME
    account, not a second one."""
    if not device:
        raise ValueError("device is required")
    if len(device) <= _FM_BOT_NAME_MAX:
        return device
    known = bot_account_lookup_device(device)
    if known:
        return known
    return _bot_mint_device_name(device)


def bot_account_name_mint_for_device(device):
    """Always mints a new name, even if this device already has one —
    used for a fresh paid purchase (buying a second month from the same
    phone is a second account, not a renewal of the first)."""
    if not device:
        raise ValueError("device is required")
    if len(device) <= _FM_BOT_NAME_MAX:
        return device
    return _bot_mint_device_name(device)


def bot_device_for_account(account):
    if not os.path.exists(NPVT_DEVICES_DB):
        return None
    try:
        with open(NPVT_DEVICES_DB, encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.rstrip("\n").split(":", 1)
                if len(parts) == 2 and parts[1] == account:
                    return parts[0]
    except Exception:
        pass
    return None


def bot_npvt_remap_device(account, device):
    """Points an existing account at a new device — used by "change
    device": the account keeps its name and everything attached to it,
    only the lock inside the delivered file moves. Only this account's
    own row moves; another account already on the new phone (bought
    twice from one device) is left alone."""
    if not account or not device:
        raise ValueError("account and device are required")
    os.makedirs(os.path.dirname(NPVT_DEVICES_DB), exist_ok=True)
    lines = []
    if os.path.exists(NPVT_DEVICES_DB):
        with open(NPVT_DEVICES_DB, encoding="utf-8", errors="ignore") as f:
            lines = [l for l in f if not l.rstrip("\n").endswith(f":{account}")]
    lines.append(f"{device}:{account}\n")
    with open(NPVT_DEVICES_DB, "w", encoding="utf-8") as f:
        f.writelines(lines)


def bot_npvt_forget_account(account):
    """Drops every device row pointing at this account. Used when a
    device change rebuilds the customer under a NEW account name: the
    retired phone must stop resolving to a name that no longer serves
    it, otherwise an ownership check would still hand the old account
    back for a device that has been replaced."""
    if not account or not os.path.exists(NPVT_DEVICES_DB):
        return
    with open(NPVT_DEVICES_DB, encoding="utf-8", errors="ignore") as f:
        lines = [l for l in f if not l.rstrip("\n").endswith(f":{account}")]
    with open(NPVT_DEVICES_DB, "w", encoding="utf-8") as f:
        f.writelines(lines)


def bot_provision_device_account(device, hours, bw_gb, devices, owner_tag, acct_type, fresh=False):
    """Entry point for anything starting from a raw device id rather
    than an already-resolved account name — in particular the /api/node/
    accounts route: a device's account-name uniqueness is scoped to
    whichever node it ends up living on, so minting has to happen here,
    not on the controller. Python mirror of menu.sh's
    _fm_bot_provision_hwid_account's device-minting wrapper around the
    plain-hwid path bot_provision_hwid_account already implements.
    Returns (account_name, expire_date, renewed_bool); raises ValueError
    on failure exactly like bot_provision_hwid_account does."""
    hwid = bot_account_name_mint_for_device(device) if fresh else bot_account_name_for_device(device)
    expire_date, renewed = bot_provision_hwid_account(hwid, hours, bw_gb, devices, owner_tag, acct_type)
    return hwid, expire_date, renewed


def bot_delete_account(username):
    """Full account teardown — system user, users.db row, bandwidth
    files, banner, notes, login-mode. Mirrors handle_delete_user's body
    exactly (minus the session/ownership check, which is the caller's
    job) and menu.sh's delete_firewallfalcon_user_accounts."""
    force_delete_system_user(username)
    with db_lock:
        lines = []
        if os.path.exists(DB_FILE):
            with open(DB_FILE, "r") as f:
                lines = f.readlines()
            with open(DB_FILE, "w") as f:
                for line in lines:
                    if not line.startswith(f"{username}:"):
                        f.write(line)
    run_cmd(f"rm -f {BW_DIR}/{username}.*", ignore_errors=True)
    run_cmd(f"rm -f /etc/firewallfalcon/banners/{username}.txt", ignore_errors=True)
    refresh_ssh_banner_config()
    delete_user_note(username)
    delete_login_mode(username)


# ── Referral program (mirrors menu.sh's _fm_bot_referral_* exactly, same
# flat files, so a referral registered by the bot and one registered by
# the panel — not that the panel registers any, but the reward payouts
# below run from either surface — never disagree). ──────────────────────

def bot_referral_get_referrer(referred):
    referred = str(referred)
    if not os.path.exists(BOT_REFERRALS_DB):
        return None
    try:
        with open(BOT_REFERRALS_DB, encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.strip().split(":")
                if len(parts) >= 2 and parts[0] == referred:
                    return parts[1]
    except Exception:
        pass
    return None


def read_bot_referrals():
    out = []
    if os.path.exists(BOT_REFERRALS_DB):
        try:
            with open(BOT_REFERRALS_DB, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    parts = line.strip().split(":")
                    if len(parts) >= 3:
                        out.append({"referred": parts[0], "referrer": parts[1], "timestamp": parts[2]})
        except Exception:
            pass
    return out


def bot_referral_signup_count(referrer):
    referrer = str(referrer)
    return sum(1 for r in read_bot_referrals() if r["referrer"] == referrer)


def bot_referral_paid_count(referrer):
    referrer = str(referrer)
    if not os.path.exists(BOT_REFERRAL_PAID_DB):
        return 0
    n = 0
    try:
        with open(BOT_REFERRAL_PAID_DB, encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.strip().split(":")
                if len(parts) >= 2 and parts[1] == referrer:
                    n += 1
    except Exception:
        pass
    return n


def read_bot_referral_tiers():
    """[{'type': 'PAID'|'SIGNUP', 'threshold': int, 'reward': float}], sorted."""
    out = []
    if os.path.exists(BOT_REFERRAL_TIERS_CONF):
        try:
            with open(BOT_REFERRAL_TIERS_CONF, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    parts = line.strip().split(":")
                    if len(parts) >= 3:
                        out.append({"type": parts[0], "threshold": int(parts[1]), "reward": float(parts[2])})
        except Exception:
            pass
    out.sort(key=lambda t: (t["type"], t["threshold"]))
    return out


def bot_referral_tier_add(rtype, threshold, reward):
    rtype = rtype.upper()
    threshold = int(threshold)
    reward = float(reward)
    os.makedirs(os.path.dirname(BOT_REFERRAL_TIERS_CONF), exist_ok=True)
    lines = []
    if os.path.exists(BOT_REFERRAL_TIERS_CONF):
        with open(BOT_REFERRAL_TIERS_CONF, encoding="utf-8", errors="ignore") as f:
            lines = [l for l in f if not l.startswith(f"{rtype}:{threshold}:")]
    lines.append(f"{rtype}:{threshold}:{reward}\n")
    with open(BOT_REFERRAL_TIERS_CONF, "w", encoding="utf-8") as f:
        f.writelines(lines)


def bot_referral_tier_delete(rtype, threshold):
    rtype = rtype.upper()
    threshold = int(threshold)
    if not os.path.exists(BOT_REFERRAL_TIERS_CONF):
        return
    with open(BOT_REFERRAL_TIERS_CONF, encoding="utf-8", errors="ignore") as f:
        lines = [l for l in f if not l.startswith(f"{rtype}:{threshold}:")]
    with open(BOT_REFERRAL_TIERS_CONF, "w", encoding="utf-8") as f:
        f.writelines(lines)


def _bot_referral_is_rewarded(referrer, rtype, threshold):
    if not os.path.exists(BOT_REFERRAL_REWARDED_DB):
        return False
    target = f"{referrer}:{rtype}:{threshold}"
    try:
        with open(BOT_REFERRAL_REWARDED_DB, encoding="utf-8", errors="ignore") as f:
            return any(line.strip() == target for line in f)
    except Exception:
        return False


def bot_referral_check_and_reward(referrer, rtype):
    """Credits every PAID/SIGNUP tier the referrer newly qualifies for —
    each tier only ever pays out once, tracked in BOT_REFERRAL_REWARDED_DB."""
    referrer = str(referrer)
    rtype = rtype.upper()
    count = bot_referral_paid_count(referrer) if rtype == "PAID" else bot_referral_signup_count(referrer)
    for tier in read_bot_referral_tiers():
        if tier["type"] != rtype or count < tier["threshold"]:
            continue
        if _bot_referral_is_rewarded(referrer, rtype, tier["threshold"]):
            continue
        os.makedirs(os.path.dirname(BOT_REFERRAL_REWARDED_DB), exist_ok=True)
        with open(BOT_REFERRAL_REWARDED_DB, "a", encoding="utf-8") as f:
            f.write(f"{referrer}:{rtype}:{tier['threshold']}\n")
        new_bal = bot_wallet_add(referrer, tier["reward"])
        r_lang = bot_lang_get(referrer)
        kind_label = bot_msg_get("REFERRAL_KIND_PAID" if rtype == "PAID" else "REFERRAL_KIND_SIGNUP", r_lang)
        send_bot_telegram_msg(referrer, bot_msg_render(
            "REFERRAL_REWARD", r_lang, THRESHOLD=tier["threshold"], KIND=kind_label,
            REWARD=tier["reward"], BALANCE=f"{new_bal:.2f}"))


def bot_referral_on_paid_conversion(chat_id):
    """Called once a referred person's subscription is actually paid
    (panel-approved order here; the bot calls its own mirror for wallet
    purchases and its own approvals) — NOT on trial. Counts them toward
    their referrer's PAID ladder exactly once, ever."""
    chat_id = str(chat_id)
    referrer = bot_referral_get_referrer(chat_id)
    if not referrer:
        return
    if os.path.exists(BOT_REFERRAL_PAID_DB):
        try:
            with open(BOT_REFERRAL_PAID_DB, encoding="utf-8", errors="ignore") as f:
                if any(line.split(":", 1)[0] == chat_id for line in f):
                    return
        except Exception:
            pass
    os.makedirs(os.path.dirname(BOT_REFERRAL_PAID_DB), exist_ok=True)
    with open(BOT_REFERRAL_PAID_DB, "a", encoding="utf-8") as f:
        f.write(f"{chat_id}:{referrer}\n")
    bot_referral_check_and_reward(referrer, "PAID")


# ── Connection-app config files (mirrors menu.sh's _fm_bot_appfile_*) ───
# The panel is the easiest place to upload these (a normal file input),
# while the bot delivers them to customers. Same directory, same naming.

def _bot_appfile_sanitize(s):
    # Strip only what's actually dangerous in a filesystem path component
    # — '/' and control characters — mirroring menu.sh's
    # _fm_bot_sanitize_slug exactly. This used to be an ASCII-only
    # allow-list that silently deleted every non-Latin character, which
    # is exactly what corrupted Arabic app/file-type names uploaded
    # through the panel (Telegram-side had the identical bug, fixed
    # separately in _fm_bot_sanitize_slug).
    s = re.sub(r"[/\x00-\x1f\x7f]", "", s or "").strip()
    if s in (".", ".."):
        s = ""
    return s


def bot_appfile_apps_list():
    if not os.path.isdir(BOT_APP_FILES_DIR):
        return []
    return sorted(d for d in os.listdir(BOT_APP_FILES_DIR) if os.path.isdir(os.path.join(BOT_APP_FILES_DIR, d)))


def bot_appfile_types_list(app):
    d = os.path.join(BOT_APP_FILES_DIR, app)
    if not os.path.isdir(d):
        return []
    return sorted(f for f in os.listdir(d) if os.path.isfile(os.path.join(d, f)))


def _bot_appfile_meta_get(app, ftype):
    if not os.path.exists(BOT_APP_FILES_META):
        return ""
    try:
        with open(BOT_APP_FILES_META, encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.rstrip("\n").split(":", 2)
                if len(parts) >= 3 and parts[0] == app and parts[1] == ftype:
                    return parts[2]
    except Exception:
        pass
    return ""


def _bot_appfile_meta_set(app, ftype, fname):
    os.makedirs(os.path.dirname(BOT_APP_FILES_META), exist_ok=True)
    lines = []
    if os.path.exists(BOT_APP_FILES_META):
        with open(BOT_APP_FILES_META, encoding="utf-8", errors="ignore") as f:
            lines = [l for l in f if not l.startswith(f"{app}:{ftype}:")]
    lines.append(f"{app}:{ftype}:{fname}\n")
    with open(BOT_APP_FILES_META, "w", encoding="utf-8") as f:
        f.writelines(lines)


def bot_appfile_add(app, ftype, data_bytes, orig_name):
    app = _bot_appfile_sanitize(app)
    ftype = _bot_appfile_sanitize(ftype)
    if not app or not ftype:
        raise ValueError("App and file-type names are required")
    dest_dir = os.path.join(BOT_APP_FILES_DIR, app)
    os.makedirs(dest_dir, exist_ok=True)
    with open(os.path.join(dest_dir, ftype), "wb") as f:
        f.write(data_bytes)
    _bot_appfile_meta_set(app, ftype, orig_name or f"{app}_{ftype}")
    return app, ftype


def _bot_appfile_write(path, data):
    """Put the bytes in place in one step. A stored file can be read at any
    moment by a customer download in another thread, so a replacement is
    written beside it and renamed over it — never truncated and refilled,
    which would hand out a half file to whoever asked in between."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp-write"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, path)


def bot_appfile_move(old_app, old_type, new_app, new_type, new_filename="", data_bytes=None):
    """Re-file an upload without asking the admin to find the original and
    upload it again — the bytes are the part that is hard to reproduce,
    and they are exactly the part that does not change when a file was
    filed under the wrong country, SIM type or app.

    Pass data_bytes to swap the contents at the same time: the admin
    picked a newer version of the file, so the old bytes are replaced
    instead of carried over, while the row keeps its place and its
    display name unless those are edited too.

    A move onto an occupied slot is refused rather than silently
    overwriting whatever was already there.
    """
    new_app = _bot_appfile_sanitize(new_app)
    new_type = _bot_appfile_sanitize(new_type)
    if not new_app or not new_type:
        raise ValueError("App and file-type names are required")
    src = os.path.join(BOT_APP_FILES_DIR, old_app, old_type)
    if not os.path.isfile(src):
        raise ValueError("That file no longer exists")
    same_slot = (old_app == new_app and old_type == new_type)
    dst = os.path.join(BOT_APP_FILES_DIR, new_app, new_type)
    if not same_slot and os.path.exists(dst):
        raise ValueError("A file is already stored under that app and classification")
    keep = new_filename.strip() or _bot_appfile_meta_get(old_app, old_type) or f"{new_app}_{new_type}"
    if data_bytes is None and same_slot:
        _bot_appfile_meta_set(new_app, new_type, keep)
        return new_app, new_type
    if data_bytes is None:
        with open(src, "rb") as f:
            data_bytes = f.read()
    _bot_appfile_write(dst, data_bytes)
    _bot_appfile_meta_set(new_app, new_type, keep)
    # Only once the new copy is safely written does the original go, so an
    # interrupted move leaves the file present rather than lost.
    if not same_slot:
        bot_appfile_delete(old_app, old_type)
    return new_app, new_type


def bot_appfile_delete(app, ftype):
    try:
        os.remove(os.path.join(BOT_APP_FILES_DIR, app, ftype))
    except OSError:
        pass
    if os.path.exists(BOT_APP_FILES_META):
        with open(BOT_APP_FILES_META, encoding="utf-8", errors="ignore") as f:
            lines = [l for l in f if not l.startswith(f"{app}:{ftype}:")]
        with open(BOT_APP_FILES_META, "w", encoding="utf-8") as f:
            f.writelines(lines)
    try:
        os.rmdir(os.path.join(BOT_APP_FILES_DIR, app))
    except OSError:
        pass


# ── NPV Tunnel config files ───────────────────────────────────────────
# An .npvt file is encrypted, so unlike a text template it can't be shown
# or checked by eye. The bot personalises one per customer at delivery
# time (see menu.sh's _fm_bot_npvt_* helpers); all the panel does is tell
# the admin, right after an upload, whether the file it just stored is
# one of those and whether its device lock is actually switched on — a
# file uploaded with the lock off would be personalised and delivered and
# still be shareable, which is the kind of mistake you'd otherwise only
# find out about from a customer.
NPVT_MAGICS = (b"NPVTSUB1", b"NPVT1")
NPVS_MAGIC = b"NPVS\x01"


def _npv_codec_path(name):
    for cand in (os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", name),
                 "/etc/firewallfalcon/.src/" + name):
        cand = os.path.normpath(cand)
        if os.path.isfile(cand):
            return cand
    return None


def _npvt_codec_path():
    return _npv_codec_path("npvt_edit.py")


def _npv_head(path):
    try:
        with open(path, "rb") as fh:
            return fh.read(8)
    except OSError:
        return b""


def npvt_is_file(path):
    head = _npv_head(path)
    return any(head.startswith(m) for m in NPVT_MAGICS)


def npvs_is_file(path):
    return _npv_head(path).startswith(NPVS_MAGIC)


# Describing one NPV file means launching a whole separate Python
# interpreter to run the codec (measured: ~50ms for iPhone .npvt, ~250ms
# for Android .npvs, and several times that on a busy 2-core VPS). The
# panel's sales-bot page asks for the same description up to four times
# per page load — /api/bot/stats, /api/bot/appfiles and
# /api/bot/linkedfiles each rebuild the file list, and the linked-files
# pass used to describe every matched file a second time — so a library
# of a couple of hundred files turned one page open into hundreds of
# interpreter launches and minutes of waiting, with the browser giving
# up on the request and blanking the page. The description of a file is
# a pure function of its bytes, so it is cached here against the file's
# identity (size + modification time in nanoseconds): an upload, a
# replace or a move changes both, so a stale entry cannot survive a real
# edit, while re-asking about an untouched file costs a stat() call.
_NPVT_DESCRIBE_CACHE = {}
_NPVT_DESCRIBE_CACHE_MAX = 4096
_NPVT_DESCRIBE_LOCK = threading.Lock()


def _npvt_describe_uncached(path):
    android = npvs_is_file(path)
    if not android and not npvt_is_file(path):
        return {"npvt": False}
    codec = _npv_codec_path("npvs_edit.py" if android else "npvt_edit.py")
    base = {"npvt": True, "npvs": True} if android else {"npvt": True}
    if not codec:
        return dict(base, error="codec unavailable")
    try:
        out = subprocess.run([sys.executable, codec, "check", path],
                             capture_output=True, timeout=30)
        info = json.loads(out.stdout.decode() or "{}")
    except Exception as exc:
        return dict(base, error=str(exc))
    info.update(base)
    # On Android the lock is the seal itself: a readable admin file is
    # always delivered bound to one phone, so there is no "lock switched
    # off" state to warn about the way there is on iPhone.
    if android and info.get("editable"):
        info["locked"] = True
    return info


def npvt_describe(path):
    """{'npvt': False} for anything else, so callers can ask about any
    stored file without caring what it is.

    Both NPV Tunnel editions answer through this one function and set the
    same 'npvt' flag, because the panel shows them the same way — the
    difference between them is how the lock works, not whether the file
    gets personalised. 'npvs' marks the Android one for the badge text.

    Cached per file identity — see _NPVT_DESCRIBE_CACHE above. A file
    that cannot be stat()ed is described directly and never cached, so
    a transient error is never remembered as an answer.
    """
    try:
        st = os.stat(path)
        ident = (st.st_size, st.st_mtime_ns)
    except OSError:
        return _npvt_describe_uncached(path)
    with _NPVT_DESCRIBE_LOCK:
        hit = _NPVT_DESCRIBE_CACHE.get(path)
        if hit and hit[0] == ident:
            return dict(hit[1])
    info = _npvt_describe_uncached(path)
    with _NPVT_DESCRIBE_LOCK:
        # Plain size cap, oldest insertion first: this is a speed cache,
        # not a correctness one, so evicting the wrong entry only costs
        # one re-describe.
        if len(_NPVT_DESCRIBE_CACHE) >= _NPVT_DESCRIBE_CACHE_MAX:
            for k in list(_NPVT_DESCRIBE_CACHE)[:_NPVT_DESCRIBE_CACHE_MAX // 4]:
                _NPVT_DESCRIBE_CACHE.pop(k, None)
        _NPVT_DESCRIBE_CACHE[path] = (ident, dict(info))
    return info


def read_bot_app_files():
    """[{'app':..., 'type':..., 'filename':..., 'platform':...}, ...] for
    the panel table."""
    out = []
    for app in bot_appfile_apps_list():
        platform = bot_appfile_platform_get(app)
        for ftype in bot_appfile_types_list(app):
            row = {"app": app, "type": ftype,
                   "filename": _bot_appfile_meta_get(app, ftype) or f"{app}_{ftype}",
                   "platform": platform}
            info = npvt_describe(os.path.join(BOT_APP_FILES_DIR, app, ftype))
            if info.get("npvt"):
                row["npvt"] = True
                row["npvt_locked"] = bool(info.get("locked"))
                row["npvt_editable"] = bool(info.get("editable"))
                row["npvs"] = bool(info.get("npvs"))
                if info.get("error"):
                    row["npvt_error"] = info["error"]
            out.append(row)
    return out


def bot_app_files_count():
    """How many files the library holds. The dashboard tile only ever
    showed this number, but got it via len(read_bot_app_files()) — which
    describes every NPV file (a subprocess each) just to throw the
    descriptions away. Counting directory entries needs none of that."""
    return sum(len(bot_appfile_types_list(app)) for app in bot_appfile_apps_list())


# ── Which platform(s) each app is for — see menu.sh's identically named
# functions for the full rationale (untagged/unrecognized = "both", so
# the feature is a no-op until an admin actually tags an app). ──────────
# ── Per-app "where do I find my HWID" guide images ─────────────────────
# Python mirror of menu.sh's _fm_bot_hwid_guide_* helpers: an ordered
# directory per app (<guides>/<app>.d/NN), with the legacy one-image
# layout (<guides>/<app>) folded in on first touch so both sides agree
# on what a given app's images are, and in what order.
def _bot_guide_legacy_path(app):
    return os.path.join(BOT_APP_HWID_GUIDE_DIR, app)


def _bot_guide_dir(app):
    return os.path.join(BOT_APP_HWID_GUIDE_DIR, f"{app}.d")


def _bot_guide_migrate(app):
    legacy = _bot_guide_legacy_path(app)
    if not os.path.isfile(legacy):
        return
    dest = _bot_guide_dir(app)
    try:
        os.makedirs(dest, exist_ok=True)
        os.replace(legacy, os.path.join(dest, "01"))
    except OSError:
        pass


def bot_hwid_guide_list(app):
    """Full paths of this app's guide images, in display order."""
    app = _bot_appfile_sanitize(app)
    if not app:
        return []
    _bot_guide_migrate(app)
    d = _bot_guide_dir(app)
    if not os.path.isdir(d):
        return []
    return [os.path.join(d, n) for n in sorted(os.listdir(d))
            if os.path.isfile(os.path.join(d, n))]


def read_bot_hwid_guides():
    """Every app that has at least one guide image, with how many."""
    out = []
    if not os.path.isdir(BOT_APP_HWID_GUIDE_DIR):
        return out
    apps = set()
    for name in os.listdir(BOT_APP_HWID_GUIDE_DIR):
        apps.add(name[:-2] if name.endswith(".d") else name)
    for app in sorted(apps):
        n = len(bot_hwid_guide_list(app))
        if n:
            out.append({"app": app, "count": n})
    return out


def bot_hwid_guide_add(app, data_bytes):
    """Append one image. Raises ValueError when the app is already at
    BOT_HWID_GUIDE_MAX — the same cap the Telegram side enforces."""
    app = _bot_appfile_sanitize(app)
    if not app:
        raise ValueError("App name is required")
    _bot_guide_migrate(app)
    d = _bot_guide_dir(app)
    os.makedirs(d, exist_ok=True)
    existing = sorted(n for n in os.listdir(d) if os.path.isfile(os.path.join(d, n)))
    if len(existing) >= BOT_HWID_GUIDE_MAX:
        raise ValueError(f"This app already has the maximum of {BOT_HWID_GUIDE_MAX} images")
    # Numbered off the highest name in use, not the count, so deleting
    # image 2 of 3 can't make the next upload overwrite image 3.
    last = 0
    for n in existing:
        if n.isdigit():
            last = max(last, int(n))
    with open(os.path.join(d, f"{last + 1:02d}"), "wb") as f:
        f.write(data_bytes)
    return app, len(existing) + 1


def bot_hwid_guide_delete(app, index=None):
    """index=None wipes every image for the app (both layouts); an index
    is 1-based and addresses the image by the position it's shown in."""
    app = _bot_appfile_sanitize(app)
    if not app:
        return False
    if index is None:
        import shutil
        try:
            os.remove(_bot_guide_legacy_path(app))
        except OSError:
            pass
        shutil.rmtree(_bot_guide_dir(app), ignore_errors=True)
        return True
    images = bot_hwid_guide_list(app)
    if index < 1 or index > len(images):
        return False
    try:
        os.remove(images[index - 1])
    except OSError:
        return False
    return True


def bot_hwid_guide_content_type(path):
    """Sniff by magic bytes — these files are stored without extensions
    (Telegram uploads arrive as raw bytes), so the name says nothing."""
    try:
        with open(path, "rb") as f:
            head = f.read(12)
    except OSError:
        return "application/octet-stream"
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if head.startswith(b"GIF8"):
        return "image/gif"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "image/webp"
    return "image/jpeg"


# ── Per-app "how do I add this file inside the app" guide images ───────
# Same idea and layout as the HWID guides above (an ordered directory per
# app, up to BOT_FILE_GUIDE_MAX images), but for the opposite direction:
# these show the customer how to import the config file once they have
# it, and live under their own directory so the two galleries never mix.
def _bot_file_guide_dir(app):
    return os.path.join(BOT_APP_FILE_GUIDE_DIR, app)


def bot_file_guide_list(app):
    """Full paths of this app's guide images, in display order."""
    app = _bot_appfile_sanitize(app)
    if not app:
        return []
    d = _bot_file_guide_dir(app)
    if not os.path.isdir(d):
        return []
    return [os.path.join(d, n) for n in sorted(os.listdir(d))
            if os.path.isfile(os.path.join(d, n))]


def read_bot_file_guides():
    """Every app that has at least one guide image, with how many."""
    out = []
    if not os.path.isdir(BOT_APP_FILE_GUIDE_DIR):
        return out
    for app in sorted(os.listdir(BOT_APP_FILE_GUIDE_DIR)):
        n = len(bot_file_guide_list(app))
        if n:
            out.append({"app": app, "count": n})
    return out


# ── The written explanation that accompanies each gallery ─────────────
# Pictures alone leave the admin no way to say "tap the three dots, then
# Import" in words, and some apps need the words more than the pictures.
# One note per (gallery, app); empty or absent means the customer sees
# exactly what they saw before this existed, so every app the admin never
# writes a note for is untouched.
def _bot_guide_note_dir(kind):
    return BOT_APP_FILE_NOTE_DIR if kind == "file" else BOT_APP_HWID_NOTE_DIR


def _bot_guide_note_path(kind, app):
    app = _bot_appfile_sanitize(app)
    if not app:
        return None
    return os.path.join(_bot_guide_note_dir(kind), app)


def bot_guide_note_get(kind, app):
    path = _bot_guide_note_path(kind, app)
    if not path or not os.path.isfile(path):
        return ""
    try:
        with open(path, encoding="utf-8", errors="ignore") as f:
            return f.read().strip()
    except OSError:
        return ""


def bot_guide_note_set(kind, app, text):
    """Blank text deletes the note — so clearing the box in the panel is
    the same action as never having written one, with no empty-string
    state in between that would send a stray blank line to customers."""
    path = _bot_guide_note_path(kind, app)
    if not path:
        raise ValueError("App name is required")
    text = (text or "").strip()
    if not text:
        try:
            os.remove(path)
        except OSError:
            pass
        return ""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)
    return text


def read_bot_guide_notes(kind):
    """{app: text} for every app that has a note in this gallery."""
    d = _bot_guide_note_dir(kind)
    out = {}
    if not os.path.isdir(d):
        return out
    for name in sorted(os.listdir(d)):
        if name.endswith(".tmp"):
            continue
        text = bot_guide_note_get(kind, name)
        if text:
            out[name] = text
    return out


def bot_file_guide_add(app, data_bytes):
    """Append one image. Raises ValueError when the app is already at
    BOT_FILE_GUIDE_MAX — the same cap the Telegram side enforces."""
    app = _bot_appfile_sanitize(app)
    if not app:
        raise ValueError("App name is required")
    d = _bot_file_guide_dir(app)
    os.makedirs(d, exist_ok=True)
    existing = sorted(n for n in os.listdir(d) if os.path.isfile(os.path.join(d, n)))
    if len(existing) >= BOT_FILE_GUIDE_MAX:
        raise ValueError(f"This app already has the maximum of {BOT_FILE_GUIDE_MAX} images")
    last = 0
    for n in existing:
        if n.isdigit():
            last = max(last, int(n))
    with open(os.path.join(d, f"{last + 1:02d}"), "wb") as f:
        f.write(data_bytes)
    return app, len(existing) + 1


def bot_file_guide_delete(app, index=None):
    """index=None wipes every image for the app; an index is 1-based and
    addresses the image by the position it's shown in."""
    app = _bot_appfile_sanitize(app)
    if not app:
        return False
    if index is None:
        import shutil
        shutil.rmtree(_bot_file_guide_dir(app), ignore_errors=True)
        return True
    images = bot_file_guide_list(app)
    if index < 1 or index > len(images):
        return False
    try:
        os.remove(images[index - 1])
    except OSError:
        return False
    return True


def bot_appfile_platform_get(app):
    if not os.path.exists(BOT_APP_PLATFORM_DB):
        return "both"
    try:
        with open(BOT_APP_PLATFORM_DB, encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.rstrip("\n").split(":", 1)
                if len(parts) == 2 and parts[0] == app:
                    return parts[1] if parts[1] in ("android", "ios") else "both"
    except Exception:
        pass
    return "both"


def bot_appfile_platform_set(app, platform):
    if platform not in ("android", "ios", "both"):
        raise ValueError("platform must be android, ios, or both")
    os.makedirs(os.path.dirname(BOT_APP_PLATFORM_DB), exist_ok=True)
    lines = []
    if os.path.exists(BOT_APP_PLATFORM_DB):
        with open(BOT_APP_PLATFORM_DB, encoding="utf-8", errors="ignore") as f:
            lines = [l for l in f if not l.startswith(f"{app}:")]
    lines.append(f"{app}:{platform}\n")
    with open(BOT_APP_PLATFORM_DB, "w", encoding="utf-8") as f:
        f.writelines(lines)


# ── Server regions ("which server?" step right after trial/subscribe) —
# see menu.sh's _fm_bot_region_* functions for the full rationale, the
# row format (slug:name_ar:name_en:mode:enabled:url — url LAST since it
# routinely contains "://" itself), and the seeded defaults. ───────────
def _bot_ensure_regions_conf():
    if os.path.exists(BOT_SERVER_REGIONS_CONF):
        return
    os.makedirs(os.path.dirname(BOT_SERVER_REGIONS_CONF), exist_ok=True)
    with open(BOT_SERVER_REGIONS_CONF, "w", encoding="utf-8") as f:
        f.write("saudi:السعودي:Saudi:redirect:1:https://t.me/YourOtherBotUsername\n")
        f.write("germany:ألمانيا:Germany:internal:1:\n")


def read_bot_regions():
    """[{'slug', 'name_ar', 'name_en', 'mode', 'enabled', 'url'}, ...],
    every region regardless of enabled state — for the panel table."""
    _bot_ensure_regions_conf()
    out = []
    try:
        with open(BOT_SERVER_REGIONS_CONF, encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.rstrip("\n").split(":", 5)
                if len(parts) < 6:
                    continue
                slug, name_ar, name_en, mode, enabled, url = parts
                out.append({"slug": slug, "name_ar": name_ar, "name_en": name_en,
                            "mode": mode, "enabled": enabled == "1", "url": url})
    except Exception:
        pass
    return out


_REGION_SLUG_RE = re.compile(r"[^A-Za-z0-9 ._-]")


def bot_region_upsert(slug, name_ar, name_en, mode, url, enabled):
    name_ar = (name_ar or "").replace(":", "")
    name_en = (name_en or "").replace(":", "")
    slug = _REGION_SLUG_RE.sub("", (slug or "").strip())
    if not slug:
        # New region, no slug given — derive a stable one from whichever
        # name is set (English preferred, since it's more likely to be
        # ASCII and read cleanly in the stored file).
        slug = _REGION_SLUG_RE.sub("", (name_en or name_ar).strip()).replace(" ", "_").lower()
    if not slug:
        raise ValueError("A region name is required")
    # "node" (new): this region IS a registered VPN node (see
    # read_bot_nodes/bot_node_upsert) — the bot remembers the customer's
    # pick for the rest of that flow instead of redirecting away or
    # doing nothing. url is meaningless for it (the node's connection
    # info lives in bot_nodes.db under the same slug), same as internal.
    mode = mode if mode in ("redirect", "node") else "internal"
    url = (url or "") if mode == "redirect" else ""
    _bot_ensure_regions_conf()
    lines = []
    if os.path.exists(BOT_SERVER_REGIONS_CONF):
        with open(BOT_SERVER_REGIONS_CONF, encoding="utf-8", errors="ignore") as f:
            lines = [l for l in f if not l.startswith(f"{slug}:")]
    lines.append(f"{slug}:{name_ar}:{name_en}:{mode}:{'1' if enabled else '0'}:{url}\n")
    with open(BOT_SERVER_REGIONS_CONF, "w", encoding="utf-8") as f:
        f.writelines(lines)
    return slug


def bot_region_delete(slug):
    _bot_ensure_regions_conf()
    if not os.path.exists(BOT_SERVER_REGIONS_CONF):
        return
    with open(BOT_SERVER_REGIONS_CONF, encoding="utf-8", errors="ignore") as f:
        lines = [l for l in f if not l.startswith(f"{slug}:")]
    with open(BOT_SERVER_REGIONS_CONF, "w", encoding="utf-8") as f:
        f.writelines(lines)


# ── Node registry (CONTROLLER side): the other VPN-node servers this box
# calls into over /api/node/*, one row per node. A region row (above)
# with mode="node" is what the CUSTOMER sees when picking a server; a
# row here, sharing the same slug, is the connection info the bot needs
# to actually reach that node. Row format keeps the token/fingerprint
# fields BEFORE base_url — like region's url, base_url routinely
# contains "://" of its own, so it must stay last. ─────────────────────
def read_bot_nodes():
    """[{'slug','token','fingerprint','base_url'}, ...] — every
    registered node, regardless of whether its region row is enabled."""
    if not os.path.exists(BOT_NODES_CONF):
        return []
    out = []
    try:
        with open(BOT_NODES_CONF, encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.rstrip("\n").split(":", 3)
                if len(parts) < 4:
                    continue
                slug, token, fingerprint, base_url = parts
                out.append({"slug": slug, "token": token, "fingerprint": fingerprint, "base_url": base_url})
    except Exception:
        pass
    return out


def bot_node_get(slug):
    return next((row for row in read_bot_nodes() if row["slug"] == slug), None)


def bot_node_upsert(slug, base_url, token=None, fingerprint=None):
    """Registers (or edits) a node this box can call. A token is
    generated automatically the first time if none is given — the admin
    then copies it onto the node's own "enable as a VPN node" screen (or
    vice versa: paste the node's self-enable token/fingerprint here) —
    the same trust-on-first-use model as an SSH host key, deliberately
    manual rather than any automated first-contact exchange."""
    slug = _REGION_SLUG_RE.sub("", (slug or "").strip())
    if not slug:
        raise ValueError("A node slug is required")
    base_url = (base_url or "").strip()
    if not base_url:
        raise ValueError("A base URL is required")
    # Catches the single most common registration mistake before it ever
    # reaches bot_nodes.db: pasting the admin PANEL's own address (plain
    # HTTP, port 44380 — what's in the browser bar) instead of that
    # node's /api/node/* listener (TLS-only, NODE_API_PORT). Both
    # mistakes fail silently otherwise — a bare "host:port" (no scheme)
    # makes menu.sh's own host/port regex miss the port entirely and
    # fall back to guessing NODE_API_PORT anyway, while a scheme with
    # the wrong port fails much later at the TLS handshake, far from
    # this form. Reject up front instead, with the fix spelled out.
    m = re.match(r"^https://([^/\s:]+)(?::(\d+))?/?$", base_url)
    if not m:
        raise ValueError(
            f"Base URL must look like https://<host>:{NODE_API_PORT} — "
            f"got: {base_url!r} (the node's own /api/node/* address, "
            f"not the admin panel's)")
    port = int(m.group(2)) if m.group(2) else NODE_API_PORT
    if port != NODE_API_PORT:
        raise ValueError(
            f"Base URL uses port {port}, but a node's /api/node/* API "
            f"only ever listens on {NODE_API_PORT} — use "
            f"https://{m.group(1)}:{NODE_API_PORT} instead")
    # Two slugs that differ only by a space, dot or dash (all legal in a
    # slug) fold onto the SAME per-node plan key — "de-1" and "de.1" both
    # become NODE_DE_1__*. Left alone, the second node registered would
    # silently inherit the first one's prices. Cheaper to refuse the name
    # here, once, than to make every plan key longer forever.
    for other in read_bot_nodes():
        if other.get("slug") != slug and \
                bot_plan_node_key(other.get("slug", ""), "X") == bot_plan_node_key(slug, "X"):
            raise ValueError(
                f"A node named {other['slug']!r} already exists and would share this "
                f"node's plan settings — pick a slug that differs by more than a "
                f"space, dot or dash")

    existing = bot_node_get(slug) or {}
    token = token if token is not None else (existing.get("token") or secrets.token_urlsafe(32))
    fingerprint = fingerprint if fingerprint is not None else existing.get("fingerprint", "")
    lines = []
    if os.path.exists(BOT_NODES_CONF):
        with open(BOT_NODES_CONF, encoding="utf-8", errors="ignore") as f:
            lines = [l for l in f if not l.startswith(f"{slug}:")]
    lines.append(f"{slug}:{token}:{fingerprint}:{base_url}\n")
    os.makedirs(os.path.dirname(BOT_NODES_CONF), exist_ok=True)
    with open(BOT_NODES_CONF, "w", encoding="utf-8") as f:
        f.writelines(lines)
    try:
        os.chmod(BOT_NODES_CONF, 0o600)
    except OSError:
        pass
    return slug, token


def bot_node_delete(slug):
    if not os.path.exists(BOT_NODES_CONF):
        return
    with open(BOT_NODES_CONF, encoding="utf-8", errors="ignore") as f:
        lines = [l for l in f if not l.startswith(f"{slug}:")]
    with open(BOT_NODES_CONF, "w", encoding="utf-8") as f:
        f.writelines(lines)


# ── Node identity (NODE side): does THIS box accept remote /api/node/*
# calls, and with what credential? Independent of the registry above —
# a box can be a controller, a node, both (for local testing), or
# neither (the default, and the only state a single-box deployment ever
# sees). ────────────────────────────────────────────────────────────────
def bot_node_self_get():
    if not os.path.exists(BOT_NODE_SELF_CONF):
        return None
    conf = {}
    try:
        with open(BOT_NODE_SELF_CONF, encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                conf[k.strip()] = v.strip()
    except Exception:
        return None
    return {
        "enabled": conf.get("ENABLED") == "1",
        "token": conf.get("TOKEN", ""),
        "fingerprint": conf.get("FINGERPRINT", ""),
        "cert": NODE_CERT_FILE,
        "key": NODE_KEY_FILE,
        "port": NODE_API_PORT,
    }


def _node_cert_fingerprint(cert_path):
    code, out, _ = run_cmd(
        ["openssl", "x509", "-noout", "-fingerprint", "-sha256", "-in", cert_path], ignore_errors=True)
    return out.split("=", 1)[1].replace(":", "") if code == 0 and "=" in out else ""


def bot_node_self_enable():
    """Turns this box into a VPN node: generates a self-signed cert (if
    one doesn't exist yet — same openssl invocation as menu.sh's
    generate_self_signed_edge_cert) and a fresh accepted token, writes
    BOT_NODE_SELF_CONF, and returns {token, fingerprint, port} for the
    admin to copy into the CONTROLLER's registry (bot_node_upsert)."""
    os.makedirs(NODE_CERT_DIR, exist_ok=True)
    if not (os.path.exists(NODE_CERT_FILE) and os.path.exists(NODE_KEY_FILE)):
        code, _, err = run_cmd([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "3650",
            "-keyout", NODE_KEY_FILE, "-out", NODE_CERT_FILE, "-subj", "/CN=dahoom-node",
        ])
        if code != 0:
            raise ValueError(f"Failed to generate the node certificate: {err}")
        try:
            os.chmod(NODE_KEY_FILE, 0o600)
        except OSError:
            pass
    fingerprint = _node_cert_fingerprint(NODE_CERT_FILE)
    token = secrets.token_urlsafe(32)
    os.makedirs(os.path.dirname(BOT_NODE_SELF_CONF), exist_ok=True)
    with open(BOT_NODE_SELF_CONF, "w", encoding="utf-8") as f:
        f.write(f"ENABLED=1\nTOKEN={token}\nFINGERPRINT={fingerprint}\n")
    try:
        os.chmod(BOT_NODE_SELF_CONF, 0o600)
    except OSError:
        pass
    return {"token": token, "fingerprint": fingerprint, "port": NODE_API_PORT}


def bot_node_self_disable():
    if not os.path.exists(BOT_NODE_SELF_CONF):
        return
    with open(BOT_NODE_SELF_CONF, encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()
    with open(BOT_NODE_SELF_CONF, "w", encoding="utf-8") as f:
        for line in lines:
            f.write("ENABLED=0\n" if line.strip().startswith("ENABLED=") else line)


# ── Country + SIM/carrier-type selection (mirrors menu.sh's identically
# named functions/constants) ────────────────────────────────────────────
# Country is a flat admin-managed list, same shape as a region minus the
# internal/redirect distinction. SIM type is a simple technical label
# (like an app's file-type name — no ar/en) scoped to exactly one
# country. Neither touches the existing per-app file library: uploading
# a "linked file" below just folds the (country, simtype) pick into the
# same "type" string bot_appfile_add already keys files by.
def _bot_ensure_countries_conf():
    if os.path.exists(BOT_COUNTRIES_CONF):
        return
    os.makedirs(os.path.dirname(BOT_COUNTRIES_CONF), exist_ok=True)
    with open(BOT_COUNTRIES_CONF, "w", encoding="utf-8") as f:
        f.write("saudi:السعودية:Saudi Arabia:1\n")
        f.write("egypt:مصر:Egypt:1\n")


def read_bot_countries():
    """[{'slug', 'name_ar', 'name_en', 'enabled'}, ...], every country
    regardless of enabled state — for the panel table."""
    _bot_ensure_countries_conf()
    out = []
    try:
        with open(BOT_COUNTRIES_CONF, encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.rstrip("\n").split(":", 3)
                if len(parts) < 4:
                    continue
                slug, name_ar, name_en, enabled = parts
                out.append({"slug": slug, "name_ar": name_ar, "name_en": name_en,
                            "enabled": enabled == "1"})
    except Exception:
        pass
    return out


def bot_country_upsert(slug, name_ar, name_en, enabled):
    name_ar = (name_ar or "").replace(":", "")
    name_en = (name_en or "").replace(":", "")
    slug = _REGION_SLUG_RE.sub("", (slug or "").strip())
    if not slug:
        slug = _REGION_SLUG_RE.sub("", (name_en or name_ar).strip()).replace(" ", "_").lower()
    if not slug:
        raise ValueError("A country name is required")
    _bot_ensure_countries_conf()
    lines = []
    if os.path.exists(BOT_COUNTRIES_CONF):
        with open(BOT_COUNTRIES_CONF, encoding="utf-8", errors="ignore") as f:
            lines = [l for l in f if not l.startswith(f"{slug}:")]
    lines.append(f"{slug}:{name_ar}:{name_en}:{'1' if enabled else '0'}\n")
    with open(BOT_COUNTRIES_CONF, "w", encoding="utf-8") as f:
        f.writelines(lines)
    return slug


def bot_country_delete(slug):
    _bot_ensure_countries_conf()
    if os.path.exists(BOT_COUNTRIES_CONF):
        with open(BOT_COUNTRIES_CONF, encoding="utf-8", errors="ignore") as f:
            lines = [l for l in f if not l.startswith(f"{slug}:")]
        with open(BOT_COUNTRIES_CONF, "w", encoding="utf-8") as f:
            f.writelines(lines)
    # Cascade: a SIM type scoped to a country that no longer exists is
    # meaningless — drop them together rather than leaving orphans an
    # admin would otherwise have no way to see or clean up. File types
    # are scoped one level deeper still (by prefix, not by country), so
    # collect every prefix this country ever reached — its own bare
    # prefix plus one per SIM type — before those SIM types disappear.
    prefixes = [bot_country_simtype_key(slug, "")] + [
        bot_country_simtype_key(slug, row["name"])
        for row in read_bot_simtypes() if row["country"] == slug
    ]
    bot_simtype_delete_for_country(slug)
    for prefix in prefixes:
        bot_filetype_delete_for_prefix(prefix)


def read_bot_simtypes():
    """[{'country', 'name'}, ...] — every SIM type, any country."""
    if not os.path.exists(BOT_SIMTYPES_CONF):
        return []
    out = []
    try:
        with open(BOT_SIMTYPES_CONF, encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.rstrip("\n").split(":", 1)
                if len(parts) < 2 or not parts[1]:
                    continue
                out.append({"country": parts[0], "name": parts[1]})
    except Exception:
        pass
    return out


def bot_simtype_add(country, name):
    country = (country or "").strip()
    name = (name or "").replace(":", "").strip()
    if not country or not name:
        raise ValueError("Country and SIM-type name are required")
    os.makedirs(os.path.dirname(BOT_SIMTYPES_CONF), exist_ok=True)
    lines = []
    if os.path.exists(BOT_SIMTYPES_CONF):
        with open(BOT_SIMTYPES_CONF, encoding="utf-8", errors="ignore") as f:
            lines = [l for l in f if l.rstrip("\n") != f"{country}:{name}"]
    lines.append(f"{country}:{name}\n")
    with open(BOT_SIMTYPES_CONF, "w", encoding="utf-8") as f:
        f.writelines(lines)


def bot_simtype_delete(country, name):
    # Cascade first: file types are scoped to this SIM type's own prefix,
    # meaningless once it's gone.
    bot_filetype_delete_for_prefix(bot_country_simtype_key(country, name))
    if not os.path.exists(BOT_SIMTYPES_CONF):
        return
    with open(BOT_SIMTYPES_CONF, encoding="utf-8", errors="ignore") as f:
        lines = [l for l in f if l.rstrip("\n") != f"{country}:{name}"]
    with open(BOT_SIMTYPES_CONF, "w", encoding="utf-8") as f:
        f.writelines(lines)


def bot_simtype_delete_for_country(country):
    if not os.path.exists(BOT_SIMTYPES_CONF):
        return
    with open(BOT_SIMTYPES_CONF, encoding="utf-8", errors="ignore") as f:
        lines = [l for l in f if not l.startswith(f"{country}:")]
    with open(BOT_SIMTYPES_CONF, "w", encoding="utf-8") as f:
        f.writelines(lines)


def bot_country_simtype_key(country, simtype):
    """Folds a (country, SIM-type) pick into the exact same "type" string
    _fm_bot_appfile_*/bot_appfile_* already key files by — see menu.sh's
    _fm_bot_country_simtype_key for the full rationale. Uses the
    non-ASCII-stripping sanitizer (not _REGION_SLUG_RE) since a SIM-type
    name is a free-form label like an app's file-type name, which may
    legitimately be Arabic."""
    country_part = _bot_appfile_sanitize(country)
    if not simtype:
        return country_part
    return f"{country_part}_{_bot_appfile_sanitize(simtype)}"


def bot_filetype_key(prefix, filetype):
    """Folds a chosen file type onto a (country, SIM-type) prefix — same
    single-string trick as bot_country_simtype_key, one level deeper, so
    every existing appfile/order/render/deliver path keeps working
    unchanged."""
    if not filetype:
        return prefix
    return f"{prefix}_{_bot_appfile_sanitize(filetype)}"


def bot_node_country_simtype_key(node, country, simtype):
    """One level ABOVE bot_country_simtype_key: folds which VPN node a
    file belongs to into the same composite-key trick, so a Germany
    upload and a Saudi upload for the identical (app, country, SIM-type,
    file-type) pick still resolve to two different stored files instead
    of colliding — "no mixing between nodes" falls out of the key
    itself, not a separate directory or a runtime check. node="" (no
    node chosen, or a single-box deployment with none registered)
    reproduces bot_country_simtype_key's own output exactly, so every
    file uploaded before this feature existed keeps resolving unchanged."""
    prefix = bot_country_simtype_key(country, simtype)
    if not node:
        return prefix
    return f"{_bot_appfile_sanitize(node)}_{prefix}"


def read_bot_filetypes():
    """[{'prefix', 'name'}, ...] — every file type, any (country,
    SIM-type) prefix. Keyed by the exact composite string
    bot_country_simtype_key produces, not by raw country/simtype
    fields, so this needs no change if either of those changes shape."""
    if not os.path.exists(BOT_FILETYPES_CONF):
        return []
    out = []
    try:
        with open(BOT_FILETYPES_CONF, encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.rstrip("\n").split(":", 1)
                if len(parts) < 2 or not parts[1]:
                    continue
                out.append({"prefix": parts[0], "name": parts[1]})
    except Exception:
        pass
    return out


def bot_filetype_add(prefix, name):
    prefix = (prefix or "").strip()
    name = (name or "").replace(":", "").strip()
    if not prefix or not name:
        raise ValueError("Prefix and file-type name are required")
    os.makedirs(os.path.dirname(BOT_FILETYPES_CONF), exist_ok=True)
    lines = []
    if os.path.exists(BOT_FILETYPES_CONF):
        with open(BOT_FILETYPES_CONF, encoding="utf-8", errors="ignore") as f:
            lines = [l for l in f if l.rstrip("\n") != f"{prefix}:{name}"]
    lines.append(f"{prefix}:{name}\n")
    with open(BOT_FILETYPES_CONF, "w", encoding="utf-8") as f:
        f.writelines(lines)


def bot_filetype_delete(prefix, name):
    if not os.path.exists(BOT_FILETYPES_CONF):
        return
    with open(BOT_FILETYPES_CONF, encoding="utf-8", errors="ignore") as f:
        lines = [l for l in f if l.rstrip("\n") != f"{prefix}:{name}"]
    with open(BOT_FILETYPES_CONF, "w", encoding="utf-8") as f:
        f.writelines(lines)


def bot_filetype_delete_for_prefix(prefix):
    if not os.path.exists(BOT_FILETYPES_CONF):
        return
    with open(BOT_FILETYPES_CONF, encoding="utf-8", errors="ignore") as f:
        lines = [l for l in f if not l.startswith(f"{prefix}:")]
    with open(BOT_FILETYPES_CONF, "w", encoding="utf-8") as f:
        f.writelines(lines)


def read_bot_linked_files():
    """Every uploaded app-file whose type follows the
    node[_country[_simtype][_filetype]] naming convention above,
    decomposed back into app/node/country/simtype/filetype for display —
    purely derived from the existing app-files list plus the current
    nodes/countries/SIM-types/file-types lists, so there is nothing new
    to keep in sync: delete a country, SIM type, file type or node and
    its linked files simply stop matching here (they re-appear as plain
    flat-type rows in the regular app-files list) instead of vanishing
    or erroring. node="" (no node registered, or a file uploaded before
    this dimension existed) matches exactly as it always has — nothing
    already stored changes shape or stops showing up."""
    nodes = [""] + [n["slug"] for n in read_bot_nodes()]
    countries = [c["slug"] for c in read_bot_countries()]
    simtypes_by_country = {}
    for row in read_bot_simtypes():
        simtypes_by_country.setdefault(row["country"], []).append(row["name"])
    filetypes_by_prefix = {}
    for row in read_bot_filetypes():
        filetypes_by_prefix.setdefault(row["prefix"], []).append(row["name"])
    # Every key the current lists can produce, built once, then one dict
    # lookup per file. This used to walk nodes x countries x SIM-types x
    # file-types again for every single file, which turned into millions
    # of comparisons on a real library. Built in the exact same order the
    # old loops visited, keeping the first key to claim a value, so an
    # ambiguous key (possible in principle, since the parts are joined
    # with "_" and a slug may itself contain one) still resolves to the
    # same row it resolved to before.
    key_index = {}
    for node in nodes:
        for country in countries:
            for simtype in [""] + simtypes_by_country.get(country, []):
                prefix = bot_node_country_simtype_key(node, country, simtype)
                for filetype in [""] + filetypes_by_prefix.get(prefix, []):
                    key_index.setdefault(bot_filetype_key(prefix, filetype),
                                         (node, country, simtype, filetype))
    out = []
    for f in read_bot_app_files():
        hit = key_index.get(f["type"])
        if not hit:
            continue
        node, country, simtype, filetype = hit
        lrow = {"app": f["app"], "node": node, "country": country, "simtype": simtype,
                "filetype": filetype, "filename": f["filename"], "type_key": f["type"]}
        # read_bot_app_files already described this exact file; asking
        # again only paid for a second interpreter launch per file.
        if f.get("npvt"):
            lrow["npvt"] = True
            lrow["npvt_locked"] = bool(f.get("npvt_locked"))
            lrow["npvt_editable"] = bool(f.get("npvt_editable"))
            lrow["npvs"] = bool(f.get("npvs"))
        out.append(lrow)
    return out


def bot_linked_file_add(app, country, simtype, filetype, data_bytes, orig_name, node=""):
    prefix = bot_node_country_simtype_key(node, country, simtype)
    ftype = bot_filetype_key(prefix, filetype)
    result = bot_appfile_add(app, ftype, data_bytes, orig_name)
    # Auto-register the file type against this exact prefix so the bot
    # immediately offers it to customers — the admin just uploads a
    # second file under the same node/country/SIM-type with a different
    # label instead of separately managing a file-types list beforehand.
    if filetype:
        bot_filetype_add(prefix, filetype)
    return result


def bot_linked_file_move(old_app, old_type, app, country, simtype, filetype, ftype, filename,
                         data_bytes=None, node=""):
    """The move above, addressed the way the panel thinks: by app plus
    node/country/SIM-type/file-type rather than by the composite key
    those encode into. With no country it falls back to the raw type
    string, exactly as the upload form does."""
    if country:
        prefix = bot_node_country_simtype_key(node, country, simtype)
        new_type = bot_filetype_key(prefix, filetype)
    else:
        new_type = ftype
    result = bot_appfile_move(old_app, old_type, app, new_type, filename, data_bytes)
    # Same as on upload: a file-type label starts existing the moment a
    # file uses it, so the bot offers it without a separate setup step.
    if country and filetype:
        bot_filetype_add(bot_node_country_simtype_key(node, country, simtype), filetype)
    return result


def bot_linked_file_delete(app, country, simtype, filetype, node=""):
    prefix = bot_node_country_simtype_key(node, country, simtype)
    bot_appfile_delete(app, bot_filetype_key(prefix, filetype))


def _link_with_port(link, new_port):
    """Returns a copy of an already-built client link with only its port
    number changed — every other field (secret, security, network, SNI,
    etc.) is left exactly as the real inbound produced it. vmess encodes
    its fields as base64 JSON rather than a plain URI, so it needs its own
    branch; every other protocol here (vless/trojan/ss) is a plain
    'scheme://user@host:port?...' URI."""
    if link.startswith("vmess://"):
        try:
            obj = json.loads(base64.b64decode(link[len("vmess://"):]).decode())
            obj["port"] = str(new_port)
            return "vmess://" + base64.b64encode(json.dumps(obj).encode()).decode()
        except Exception:
            return link
    return re.sub(r'(@[^:/?#]+):\d+', rf'\g<1>:{new_port}', link, count=1)


def _xui_stream_link_params(protocol, stream, allow_insecure=False):
    """Extracts the transport/security query params a vless:// or trojan://
    link actually needs to be importable, straight from the inbound's own
    stream_settings — the same REALITY/TLS/WS/gRPC configuration the X-UI
    panel itself wrote when the inbound was created. Building a link from
    just network+security (the old behavior) silently drops publicKey/
    shortId/serverName/flow/path/serviceName, which is why REALITY and
    WS/gRPC clients came out unusable: the link *looked* right but had none
    of the parameters a client needs to actually complete the handshake."""
    net = stream.get("network", "tcp")
    sec = stream.get("security", "none")
    params = {"type": net, "security": sec}
    if protocol == "vless":
        params["encryption"] = "none"

    if sec == "reality":
        rs = stream.get("realitySettings") or {}
        rs_inner = rs.get("settings") or {}
        sni_list = rs.get("serverNames") or []
        sid_list = rs.get("shortIds") or []
        if rs_inner.get("publicKey"):
            params["pbk"] = rs_inner["publicKey"]
        params["fp"] = rs_inner.get("fingerprint") or "chrome"
        if sni_list:
            params["sni"] = sni_list[0]
        if sid_list:
            params["sid"] = sid_list[0]
        params["spx"] = rs_inner.get("spiderX") or "/"
        if protocol == "vless":
            params["flow"] = "xtls-rprx-vision"
    elif sec == "tls":
        ts = stream.get("tlsSettings") or {}
        if ts.get("serverName"):
            params["sni"] = ts["serverName"]
        alpn = ts.get("alpn") or []
        if alpn:
            params["alpn"] = ",".join(alpn)
        fp = (ts.get("settings") or {}).get("fingerprint")
        if fp:
            params["fp"] = fp
        # Per-client choice made at creation time (e.g. the domain's cert
        # doesn't match the SNI yet, or it's self-signed during testing) —
        # not something the inbound itself stores, so it's threaded in as
        # an argument rather than read from stream_settings. Omitted when
        # false so a normal, properly-certified link stays unchanged.
        if allow_insecure:
            params["allowInsecure"] = "1"

    if net == "ws":
        ws = stream.get("wsSettings") or {}
        params["path"] = ws.get("path") or "/"
        host_header = (ws.get("headers") or {}).get("Host")
        if host_header:
            params["host"] = host_header
    elif net == "grpc":
        gs = stream.get("grpcSettings") or {}
        if gs.get("serviceName"):
            params["serviceName"] = gs["serviceName"]
        if gs.get("multiMode"):
            params["mode"] = "multi"
    elif net == "tcp":
        header = (stream.get("tcpSettings") or {}).get("header") or {}
        if header.get("type") == "http":
            req = header.get("request") or {}
            hdrs = req.get("headers") or {}
            host_hdr = hdrs.get("Host")
            if isinstance(host_hdr, list) and host_hdr:
                params["host"] = host_hdr[0]
            path_list = req.get("path") or []
            if path_list:
                params["path"] = path_list[0]
            params["headerType"] = "http"
    elif net == "httpupgrade":
        hu = stream.get("httpupgradeSettings") or {}
        params["path"] = hu.get("path") or "/"
        if hu.get("host"):
            params["host"] = hu["host"]

    return params


def xui_generate_client_link(client, server_ip="", domain="", allow_insecure=False):
    """Builds a vless/vmess/trojan/ss:// URI for one client dict from
    xui_list_clients(). Deliberately mirrors the link formats already built
    by menu.sh's show_xui_client_configs() (same protocols, same field
    choices) so a client looks identical whether inspected from the CLI or
    from this panel."""
    host = domain if domain else server_ip
    protocol = client["protocol"]
    port = client["port"]
    secret = client["secret"]
    stream = client.get("stream") or {"network": client.get("network", "tcp"), "security": client.get("security", "none")}
    remark = f"{client['inbound_remark']}-{client['email']}"
    tag = urllib.parse.quote(remark)

    if protocol in ("vless", "trojan"):
        params = _xui_stream_link_params(protocol, stream, allow_insecure=allow_insecure)
        qs = urllib.parse.urlencode(params, safe=",/")
        return f"{protocol}://{secret}@{host}:{port}?{qs}#{tag}"
    if protocol == "vmess":
        net = stream.get("network", "tcp")
        sec = stream.get("security", "none")
        ws = stream.get("wsSettings") or {}
        vmess_obj = {
            "v": "2", "ps": remark, "add": host, "port": port, "id": secret,
            "aid": 0, "net": net, "type": "none",
            "host": (ws.get("headers") or {}).get("Host", ""),
            "path": ws.get("path", ""),
            "tls": "tls" if sec == "tls" else "",
        }
        return "vmess://" + base64.b64encode(json.dumps(vmess_obj).encode()).decode()
    if protocol == "shadowsocks":
        method = "aes-256-gcm"
        userpass = base64.b64encode(f"{method}:{secret}".encode()).decode()
        return f"ss://{userpass}@{host}:{port}#{tag}"
    return ""


# --- UTILS ---
SYSTEM_METRICS_HISTORY = {
    "cpu": [],
    "ram": [],
    "connections": [],
    "timestamps": []
}
MAX_HISTORY_POINTS = 24

def record_system_metric(cpu, ram, conns):
    global SYSTEM_METRICS_HISTORY
    now_str = datetime.now().strftime("%H:%M:%S")
    SYSTEM_METRICS_HISTORY["cpu"].append(round(float(cpu), 1))
    SYSTEM_METRICS_HISTORY["ram"].append(round(float(ram), 1))
    SYSTEM_METRICS_HISTORY["connections"].append(int(conns))
    SYSTEM_METRICS_HISTORY["timestamps"].append(now_str)
    
    if len(SYSTEM_METRICS_HISTORY["cpu"]) > MAX_HISTORY_POINTS:
        SYSTEM_METRICS_HISTORY["cpu"].pop(0)
        SYSTEM_METRICS_HISTORY["ram"].pop(0)
        SYSTEM_METRICS_HISTORY["connections"].pop(0)
        SYSTEM_METRICS_HISTORY["timestamps"].pop(0)

# Seed initial history points if empty
def seed_initial_metrics():
    if not SYSTEM_METRICS_HISTORY["cpu"]:
        for i in range(12, 0, -1):
            t = (datetime.now() - timedelta(minutes=i*2)).strftime("%H:%M:%S")
            SYSTEM_METRICS_HISTORY["cpu"].append(15.0 + (i % 4) * 3.5)
            SYSTEM_METRICS_HISTORY["ram"].append(32.0 + (i % 3) * 1.5)
            SYSTEM_METRICS_HISTORY["connections"].append(max(1, (i % 5)))
            SYSTEM_METRICS_HISTORY["timestamps"].append(t)
seed_initial_metrics()

_DEVICE_ID_RE = re.compile(r"^[A-Za-z0-9_.-]{1,128}$")


def valid_device_id(device):
    """Whether a device id is safe to turn into a Linux account name.

    menu.sh validates device ids before it ever calls a node, so this is
    a boundary check rather than the primary one — but a node must not
    depend on its caller being correct: the id becomes a system username
    and is passed to useradd/chage, and it arrives here over the network
    from a box holding a shared token. Same character set the panel's own
    create-user path accepts."""
    return bool(_DEVICE_ID_RE.match(str(device or "")))


MENU_BIN = "/usr/local/bin/dahoom"


def nodes_are_registered():
    """True when this box is a CONTROLLER with at least one VPN node
    registered — i.e. accounts do not belong on this machine."""
    try:
        with open(BOT_NODES_CONF, encoding="utf-8", errors="ignore") as f:
            return any(l.strip() and ":" in l for l in f)
    except OSError:
        return False


def delegate_order_to_bot(action, order_id, reason=""):
    """Hands an order decision to menu.sh's own bot code.

    Only menu.sh knows how to resolve which node a customer's account
    lives on, price the order against that node's plan, and provision
    over the node API — the registry, the pinned certificates and the
    TLS client all live there. Duplicating any of that here would mean
    two implementations of the same money-touching logic drifting apart,
    so the panel's Approve/Reject buttons call the exact code path
    /approve and /reject use in Telegram. Returns (ok, detail)."""
    args = [MENU_BIN, f"_run_bot_{action}_order", str(order_id)]
    if action == "reject":
        args.append(reason or "")
    try:
        res = subprocess.run(args, capture_output=True, text=True, timeout=120)
        if res.returncode != 0:
            return False, (res.stderr or res.stdout or "").strip()[:400]
        return True, ""
    except FileNotFoundError:
        return False, f"{MENU_BIN} not found on this server"
    except Exception as e:
        return False, str(e)


def set_system_password(username, password):
    """Sets a Linux account's password WITHOUT going through a shell.

    The obvious `run_cmd(f"echo '{u}:{p}' | chpasswd")` looks harmless
    and is not: run_cmd takes the shell path for a string argument, so
    any quote in the password ends the quoting and the rest runs as
    root. Passwords here are attacker-influenced in the ordinary course
    of business — a reseller types one into the create-user form, and a
    device id arrives from the bot — so this feeds "user:pass" to
    chpasswd on stdin instead, where no character means anything to
    anyone. Newlines are stripped because chpasswd reads one record per
    line, so an embedded newline would otherwise be a second record.
    Returns True on success."""
    u = str(username).replace("\n", "").replace("\r", "")
    pw = str(password).replace("\n", "").replace("\r", "")
    try:
        res = subprocess.run(["chpasswd"], input=f"{u}:{pw}\n",
                             capture_output=True, text=True, timeout=10)
        if res.returncode != 0:
            print(f"chpasswd failed for {u}: {res.stderr}", file=sys.stderr)
        return res.returncode == 0
    except Exception as e:
        print(f"chpasswd exception for {u}: {e}", file=sys.stderr)
        return False


def run_cmd(cmd_args, ignore_errors=False):
    try:
        if isinstance(cmd_args, str):
            res = subprocess.run(cmd_args, shell=True, capture_output=True, text=True, timeout=10)
        else:
            res = subprocess.run(cmd_args, capture_output=True, text=True, timeout=10)
        if not ignore_errors and res.returncode != 0:
            print(f"Command error: {cmd_args} -> {res.stderr}", file=sys.stderr)
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    except Exception as e:
        print(f"Exception running command {cmd_args}: {e}", file=sys.stderr)
        return -1, "", str(e)

def detect_server_ip():
    """Detect server public IPv4 address with fast fallbacks."""
    for srv in ("https://icanhazip.com", "https://api.ipify.org", "https://ifconfig.me/ip"):
        try:
            req = urllib.request.Request(srv, headers={"User-Agent": "curl/7.68.0"})
            with urllib.request.urlopen(req, timeout=3) as resp:
                ip = resp.read().decode("utf-8").strip()
                if ip and re.match(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$", ip):
                    return ip
        except Exception:
            continue
    code, out, _ = run_cmd("curl -s -4 --max-time 3 icanhazip.com", ignore_errors=True)
    if code == 0 and out:
        return out.strip()
    return ""

def _ensure_bandwidth_link_service():
    """Lazily install & start the bandwidth-status-link service the first
    time a link is needed. No-op if it's already running."""
    code, _, _ = run_cmd(["systemctl", "is-active", "--quiet", "firewallfalcon-bwlink"], ignore_errors=True)
    if code == 0:
        return True
    if not os.path.exists(FM_SRC_BW_LINK):
        # Decrypted source isn't on disk yet (shouldn't normally happen once
        # the panel itself is installed, since both ship in the same
        # encrypted bundle) — nothing safe to do without re-implementing the
        # decrypt/license-gate logic here.
        return False
    try:
        import shutil
        shutil.copyfile(FM_SRC_BW_LINK, BW_LINK_SCRIPT)
        os.chmod(BW_LINK_SCRIPT, 0o755)
    except Exception:
        return False

    run_cmd(["ufw", "allow", f"{BW_LINK_PORT}/tcp"], ignore_errors=True)
    run_cmd(["iptables", "-I", "INPUT", "-p", "tcp", "--dport", str(BW_LINK_PORT), "-j", "ACCEPT"], ignore_errors=True)

    unit = f"""[Unit]
Description=DAHOOM User Bandwidth Status Link
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 {BW_LINK_SCRIPT}
Restart=always
RestartSec=5
Nice=10
MemoryHigh=32M
MemoryMax=64M
Environment=BW_LINK_PORT={BW_LINK_PORT}

[Install]
WantedBy=multi-user.target
"""
    try:
        with open(BW_LINK_SERVICE_FILE, "w") as f:
            f.write(unit)
    except Exception:
        return False

    run_cmd(["systemctl", "daemon-reload"], ignore_errors=True)
    run_cmd(["systemctl", "enable", "firewallfalcon-bwlink"], ignore_errors=True)
    run_cmd(["systemctl", "restart", "firewallfalcon-bwlink"], ignore_errors=True)
    time.sleep(1)
    code, _, _ = run_cmd(["systemctl", "is-active", "--quiet", "firewallfalcon-bwlink"], ignore_errors=True)
    return code == 0

def _ensure_connlog_service():
    """update_panel.sh installs & enables this unconditionally, so this is
    normally a fast no-op — kept as a defensive fallback for an install
    that reached this panel.py some other way. Same install shape as
    _ensure_bandwidth_link_service() above."""
    code, _, _ = run_cmd(["systemctl", "is-active", "--quiet", "firewallfalcon-connlog"], ignore_errors=True)
    if code == 0:
        return True
    if not os.path.exists(FM_SRC_CONNLOG):
        return False
    try:
        import shutil
        shutil.copyfile(FM_SRC_CONNLOG, CONNLOG_SCRIPT)
        os.chmod(CONNLOG_SCRIPT, 0o755)
    except Exception:
        return False

    unit = f"""[Unit]
Description=DAHOOM Connection Log Daemon
After=network.target sshd.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 {CONNLOG_SCRIPT}
Restart=always
RestartSec=5
Nice=10
MemoryHigh=48M
MemoryMax=96M

[Install]
WantedBy=multi-user.target
"""
    try:
        with open(CONNLOG_SERVICE_FILE, "w") as f:
            f.write(unit)
    except Exception:
        return False

    run_cmd(["systemctl", "daemon-reload"], ignore_errors=True)
    run_cmd(["systemctl", "enable", "firewallfalcon-connlog"], ignore_errors=True)
    run_cmd(["systemctl", "restart", "firewallfalcon-connlog"], ignore_errors=True)
    time.sleep(1)
    code, _, _ = run_cmd(["systemctl", "is-active", "--quiet", "firewallfalcon-connlog"], ignore_errors=True)
    return code == 0


def _connlog_db():
    conn = sqlite3.connect(CONNLOG_DB_PATH, timeout=10)
    conn.execute("PRAGMA busy_timeout=10000")
    conn.row_factory = sqlite3.Row
    _ensure_connlog_schema(conn)
    return conn


def _ensure_connlog_schema(conn):
    """connlog.py's own daemon adds the attempt_count column via its own
    startup migration — but this file's queries reference that column
    too, and the two processes update/restart independently (this file
    on the panel's own service, connlog.py on its own systemd unit). If
    panel.py gets the new code before the connlog daemon has actually
    (re)started and run its migration, every query naming that column
    fails outright ('no such column: attempt_count') even though nothing
    is actually broken — the fix is just a column that hasn't landed
    yet. Make this side self-sufficient too, so it never depends on
    which of the two processes happens to restart first."""
    try:
        cur = conn.cursor()
        cur.execute("PRAGMA table_info(connections)")
        cols = {row[1] for row in cur.fetchall()}
        if cols and "attempt_count" not in cols:
            conn.execute("ALTER TABLE connections ADD COLUMN attempt_count INTEGER DEFAULT 1")
            conn.commit()
    except Exception:
        pass  # table may not exist yet (daemon hasn't run at all) — queries below already handle that


def _record_admin_disconnect(pids, reason="تم فصل الجلسة من لوحة التحكم"):
    """Killing an sshd worker produces no log line at all — verified
    against a real sshd at every log level — so this is the only moment
    the answer exists anywhere. Record it now, while we still know it.

    connlog.py keys every SSH row by session_key 'ssh:<pid>:<start>', so
    the pid we just killed identifies the row exactly. The row is still
    open here (connlog closes it on its next poll, which leaves
    fail_reason alone), and the write is best-effort: failing to explain
    a disconnect must never turn into a failed disconnect."""
    if not pids:
        return
    try:
        conn = _connlog_db()
    except Exception:
        return
    try:
        cur = conn.cursor()
        for pid in pids:
            cur.execute(
                # disconnect_time IS NULL pins this to the session that is
                # live right now: pids get recycled, and an old closed row
                # from a previous session could otherwise share the key.
                "UPDATE connections SET fail_reason=? WHERE source='ssh' AND status='success' "
                "AND disconnect_time IS NULL AND fail_reason IS NULL AND session_key LIKE ?",
                (reason, f"ssh:{int(pid)}:%"),
            )
        conn.commit()
    except Exception:
        pass
    finally:
        try:
            conn.close()
        except Exception:
            pass


def get_active_now_count(source="all", q="", usernames=None):
    """Currently-connected UNIQUE users, right now — deliberately ignores
    the status/date-range filters a view might have applied (those are
    about history; 'active right now' is a live fact), only source/search
    narrow it, same as the rest of the page's scope."""
    if not os.path.exists(CONNLOG_DB_PATH):
        return 0
    if usernames is not None and not usernames:
        return 0
    where = ["status='success'", "disconnect_time IS NULL"]
    params = []
    if source in ("ssh", "xui"):
        where.append("source=?"); params.append(source)
    if usernames:
        where.append(f"username IN ({','.join('?' * len(usernames))})")
        params.extend(usernames)
    if q:
        where.append("(username LIKE ? OR ip LIKE ?)")
        like = f"%{q}%"; params += [like, like]
    conn = _connlog_db()
    try:
        cur = conn.cursor()
        cur.execute(f"SELECT COUNT(DISTINCT username) FROM connections WHERE {' AND '.join(where)}", params)
        return cur.fetchone()[0] or 0
    finally:
        conn.close()


def get_active_xui_device_counts():
    """{email: number of distinct devices online right now} for X-UI
    clients. connlog opens one row per (client, IP) from Xray's own
    online-IP list, so counting distinct IPs gives the real device count —
    the same 'sessions: N/limit' figure the SSH accounts list shows.

    Rows recorded while Xray's API was unreachable have no IP (the
    traffic-delta fallback); those still count as one active device so the
    column degrades to 0/1 rather than reading 0 while traffic flows."""
    if not os.path.exists(CONNLOG_DB_PATH):
        return {}
    conn = _connlog_db()
    try:
        cur = conn.cursor()
        cur.execute("SELECT username, ip FROM connections "
                    "WHERE source='xui' AND status='success' AND disconnect_time IS NULL")
        per_email = {}
        for email, ip in cur.fetchall():
            per_email.setdefault(email, set()).add(ip or "")
        return {email: len(ips) for email, ips in per_email.items()}
    finally:
        conn.close()


def query_connections(source="all", q="", username=None, usernames=None, status="all", range_="", ts_from=None, ts_to=None,
                       sort="time", direction="desc", page=1, page_size=25):
    empty = {"items": [], "total": 0, "page": page, "page_size": page_size,
             "stats": {"total": 0, "success": 0, "failed": 0, "active_now": 0,
                       "total_duration_seconds": 0, "top_ips": []}}
    if not os.path.exists(CONNLOG_DB_PATH):
        return empty
    if usernames is not None and not usernames:
        return empty  # e.g. a reseller with no users of their own yet

    where = []
    params = []
    if source in ("ssh", "xui"):
        where.append("source=?"); params.append(source)
    if username:
        where.append("username=?"); params.append(username)
    if usernames:
        where.append(f"username IN ({','.join('?' * len(usernames))})")
        params.extend(usernames)
    if q:
        where.append("(username LIKE ? OR ip LIKE ?)")
        like = f"%{q}%"; params += [like, like]
    if status == "success":
        where.append("status='success'")
    elif status == "failed":
        where.append("status='failed'")
    elif status == "active":
        where.append("status='success' AND disconnect_time IS NULL")

    now = int(time.time())
    if range_ == "today":
        start = int(datetime.now().replace(hour=0, minute=0, second=0, microsecond=0).timestamp())
        where.append("connect_time >= ?"); params.append(start)
    elif range_ == "yesterday":
        today_start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
        y_start = today_start - timedelta(days=1)
        where.append("connect_time >= ? AND connect_time < ?")
        params += [int(y_start.timestamp()), int(today_start.timestamp())]
    elif range_ == "7d":
        where.append("connect_time >= ?"); params.append(now - 7 * 86400)
    elif range_ == "30d":
        where.append("connect_time >= ?"); params.append(now - 30 * 86400)
    elif range_ == "custom":
        if ts_from is not None:
            where.append("connect_time >= ?"); params.append(int(ts_from))
        if ts_to is not None:
            where.append("connect_time <= ?"); params.append(int(ts_to))

    where_sql = ("WHERE " + " AND ".join(where)) if where else ""
    sort_col = {"time": "connect_time", "username": "username", "duration": "duration_seconds"}.get(sort, "connect_time")
    dir_sql = "ASC" if direction == "asc" else "DESC"

    conn = _connlog_db()
    try:
        cur = conn.cursor()
        cur.execute(f"SELECT COUNT(*) FROM connections {where_sql}", params)
        total = cur.fetchone()[0]

        page = max(1, page)
        page_size = max(1, min(200, page_size))
        offset = (page - 1) * page_size
        # Sessions still open float to the top regardless of the chosen
        # sort — a live monitoring view should always surface "connected
        # right now" first, same idea as the SSH accounts table already
        # does for its own 'online' badge.
        cur.execute(
            f"SELECT * FROM connections {where_sql} "
            f"ORDER BY (status='success' AND disconnect_time IS NULL) DESC, {sort_col} {dir_sql} "
            f"LIMIT ? OFFSET ?",
            params + [page_size, offset],
        )
        items = []
        for row in cur.fetchall():
            d = dict(row)
            d["is_active"] = bool(d["status"] == "success" and d["disconnect_time"] is None)
            items.append(d)

        # A failed row can represent many attempts folded into one (see
        # connlog.py's _upsert_failed_row — a real internet-facing SSH
        # port gets probed constantly, and counting every retry as its
        # own row would make the log unusable), so the failed/total
        # counts here sum attempt_count rather than counting rows —
        # otherwise "فاشلة" would understate how much probing actually
        # happened just because it got compacted into fewer rows.
        # duration_seconds means something different on a failed row (how
        # long that IP has been probing us, from _upsert_failed_row's
        # sliding window) than on a success row (actual connected time) —
        # only success rows belong in "total connected time", or a single
        # long-running attack campaign would swamp the real number.
        cur.execute(
            f"SELECT "
            f"SUM(CASE WHEN status='success' THEN 1 ELSE 0 END), "
            f"SUM(CASE WHEN status='failed' THEN COALESCE(attempt_count,1) ELSE 0 END), "
            f"SUM(CASE WHEN status='success' AND disconnect_time IS NULL THEN 1 ELSE 0 END), "
            f"SUM(CASE WHEN status='success' THEN COALESCE(duration_seconds,0) ELSE 0 END) "
            f"FROM connections {where_sql}", params
        )
        srow = cur.fetchone()
        success_n, failed_n = srow[0] or 0, srow[1] or 0
        stats = {
            "total": success_n + failed_n, "success": success_n, "failed": failed_n,
            "active_now": srow[2] or 0, "total_duration_seconds": srow[3] or 0,
        }
        ip_where = where + ["ip IS NOT NULL", "ip != ''"]
        cur.execute(
            f"SELECT ip, SUM(COALESCE(attempt_count,1)) c FROM connections WHERE {' AND '.join(ip_where)} "
            f"GROUP BY ip ORDER BY c DESC LIMIT 5",
            params,
        )
        stats["top_ips"] = [{"ip": r[0], "count": r[1]} for r in cur.fetchall()]

        return {"items": items, "total": total, "page": page, "page_size": page_size, "stats": stats}
    finally:
        conn.close()


def generate_bandwidth_link(username):
    """Issue (or re-issue) a private usage-status link for a user. Never
    touches the password. Returns None on any failure — link generation
    must never be able to break user creation. A freshly (re)issued link
    always starts enabled."""
    try:
        os.makedirs(os.path.dirname(BW_LINK_TOKENS_DB), exist_ok=True)
        lines = []
        if os.path.exists(BW_LINK_TOKENS_DB):
            with open(BW_LINK_TOKENS_DB) as f:
                lines = [l for l in f if l.strip() and not l.startswith(f"{username}:")]
        token = secrets.token_hex(10)
        lines.append(f"{username}:{token}:1\n")
        with open(BW_LINK_TOKENS_DB, "w") as f:
            f.writelines(lines)
        os.chmod(BW_LINK_TOKENS_DB, 0o600)

        _ensure_bandwidth_link_service()

        server_ip = get_public_host()
        return f"http://{server_ip}:{BW_LINK_PORT}/status/{username}/{token}"
    except Exception as e:
        print(f"bandwidth link generation failed for {username}: {e}", file=sys.stderr)
        return None

def _read_bw_token_line(username):
    """Return (token, enabled) for a user's stored line, or None if they
    have never had a link issued. Legacy 2-field lines (from before the
    enable/disable toggle existed) are treated as enabled."""
    if not os.path.exists(BW_LINK_TOKENS_DB):
        return None
    with open(BW_LINK_TOKENS_DB) as f:
        for line in f:
            line = line.strip()
            if not line or ":" not in line:
                continue
            parts = line.split(":")
            if parts[0] == username and len(parts) >= 2:
                enabled = (len(parts) < 3) or (parts[2] != "0")
                return parts[1], enabled
    return None

def get_bandwidth_link(username):
    """Return (link, enabled) using the user's existing token without
    rotating it (so a link already handed to a client keeps working) —
    issues one only if this user has never had one. Used by the 'retrieve
    link' button so a lost/misplaced link can always be looked up again."""
    try:
        found = _read_bw_token_line(username)
        if found:
            token, enabled = found
            _ensure_bandwidth_link_service()
            server_ip = get_public_host()
            return f"http://{server_ip}:{BW_LINK_PORT}/status/{username}/{token}", enabled
        return generate_bandwidth_link(username), True
    except Exception as e:
        print(f"bandwidth link lookup failed for {username}: {e}", file=sys.stderr)
        return None, True

def set_bandwidth_link_enabled(username, enabled):
    """Flip the enabled/disabled flag on a user's existing link, keeping the
    same token/URL — so a link that's re-enabled later doesn't have to be
    resent. Returns False if this user has never had a link issued."""
    try:
        if not os.path.exists(BW_LINK_TOKENS_DB):
            return False
        found = False
        lines = []
        with open(BW_LINK_TOKENS_DB) as f:
            for line in f:
                raw = line.strip()
                if not raw or ":" not in raw:
                    continue
                parts = raw.split(":")
                if parts[0] == username and len(parts) >= 2:
                    lines.append(f"{parts[0]}:{parts[1]}:{'1' if enabled else '0'}\n")
                    found = True
                else:
                    lines.append(raw + "\n")
        if not found:
            return False
        with open(BW_LINK_TOKENS_DB, "w") as f:
            f.writelines(lines)
        os.chmod(BW_LINK_TOKENS_DB, 0o600)
        return True
    except Exception as e:
        print(f"bandwidth link toggle failed for {username}: {e}", file=sys.stderr)
        return False

# --- X-UI CLIENT BANDWIDTH LINKS ---
# Same private-status-link idea as above, but keyed by (inbound_id, email)
# since X-UI only guarantees a client's "email" is unique within one
# inbound, not across the whole server. Served by the same shared
# bandwidth-link micro-service (bandwidth_link.py), on a separate /xstatus/
# route from the SSH one.
XUI_BW_LINK_TOKENS_DB = "/etc/firewallfalcon/xui_bandwidth_tokens.db"

def generate_xui_bandwidth_link(inbound_id, email):
    """Issue (or re-issue) a private usage-status link for one X-UI client.
    Never touches the client's UUID/password. Returns None on any failure —
    link generation must never be able to break client creation."""
    key = f"{inbound_id}:{email}:"
    try:
        os.makedirs(os.path.dirname(XUI_BW_LINK_TOKENS_DB), exist_ok=True)
        lines = []
        if os.path.exists(XUI_BW_LINK_TOKENS_DB):
            with open(XUI_BW_LINK_TOKENS_DB) as f:
                lines = [l for l in f if l.strip() and not l.startswith(key)]
        token = secrets.token_hex(10)
        lines.append(f"{key}{token}:1\n")
        with open(XUI_BW_LINK_TOKENS_DB, "w") as f:
            f.writelines(lines)
        os.chmod(XUI_BW_LINK_TOKENS_DB, 0o600)

        _ensure_bandwidth_link_service()

        server_ip = get_public_host()
        return f"http://{server_ip}:{BW_LINK_PORT}/xstatus/{inbound_id}/{email}/{token}"
    except Exception as e:
        print(f"xui bandwidth link generation failed for {key}: {e}", file=sys.stderr)
        return None

def _read_xui_bw_token_line(inbound_id, email):
    if not os.path.exists(XUI_BW_LINK_TOKENS_DB):
        return None
    key = f"{inbound_id}:{email}:"
    with open(XUI_BW_LINK_TOKENS_DB) as f:
        for line in f:
            line = line.strip()
            if not line.startswith(key):
                continue
            rest = line[len(key):].split(":")
            if not rest or not rest[0]:
                continue
            enabled = (len(rest) < 2) or (rest[1] != "0")
            return rest[0], enabled
    return None

def get_xui_bandwidth_link(inbound_id, email):
    """Return (link, enabled) using the client's existing token without
    rotating it — issues one only if this client has never had one."""
    try:
        found = _read_xui_bw_token_line(inbound_id, email)
        if found:
            token, enabled = found
            _ensure_bandwidth_link_service()
            server_ip = get_public_host()
            return f"http://{server_ip}:{BW_LINK_PORT}/xstatus/{inbound_id}/{email}/{token}", enabled
        return generate_xui_bandwidth_link(inbound_id, email), True
    except Exception as e:
        print(f"xui bandwidth link lookup failed for {inbound_id}:{email}: {e}", file=sys.stderr)
        return None, True

def set_xui_bandwidth_link_enabled(inbound_id, email, enabled):
    """Flip the enabled/disabled flag on a client's existing link, keeping
    the same token/URL. Returns False if this client has never had a link
    issued."""
    key = f"{inbound_id}:{email}:"
    try:
        if not os.path.exists(XUI_BW_LINK_TOKENS_DB):
            return False
        found = False
        lines = []
        with open(XUI_BW_LINK_TOKENS_DB) as f:
            for line in f:
                raw = line.strip()
                if not raw:
                    continue
                if raw.startswith(key):
                    rest = raw[len(key):].split(":")
                    token = rest[0] if rest and rest[0] else ""
                    if token:
                        lines.append(f"{key}{token}:{'1' if enabled else '0'}\n")
                        found = True
                        continue
                lines.append(raw + "\n")
        if not found:
            return False
        with open(XUI_BW_LINK_TOKENS_DB, "w") as f:
            f.writelines(lines)
        os.chmod(XUI_BW_LINK_TOKENS_DB, 0o600)
        return True
    except Exception as e:
        print(f"xui bandwidth link toggle failed for {inbound_id}:{email}: {e}", file=sys.stderr)
        return False

def kill_user_sessions(username):
    """Kill every currently-running session/process owned by a user, using
    several methods together instead of relying on killall -u alone (which
    has been unreliable at actually dropping an already-open session on some
    setups, silently leaving it connected even though the account is now
    locked). pkill -u is a more dependable primary method; the
    /proc/*/loginuid sweep is a last-resort fallback that kills by kernel
    login UID directly, bypassing process-name matching entirely."""
    if not username:
        return
    run_cmd(["pkill", "-9", "-u", username], ignore_errors=True)
    run_cmd(["killall", "-u", username, "-9"], ignore_errors=True)
    try:
        import pwd
        uid = str(pwd.getpwnam(username).pw_uid)
    except Exception:
        return
    try:
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            try:
                with open(f"/proc/{entry}/loginuid") as f:
                    if f.read().strip() != uid:
                        continue
            except Exception:
                continue
            run_cmd(["kill", "-9", entry], ignore_errors=True)
    except Exception:
        pass

def disable_system_user(username):
    """Disables a system account WITHOUT ever attempting to remove it —
    the same failure-swallowing pattern menu.sh's delete could hit:
    userdel can fail for reasons outside this project's control (a busy
    home dir, a session some distros still refuse to force through), and
    the caller used to carry on as if it had succeeded, wiping the DB row
    and bandwidth counters while the real account kept working — right as
    a brand-new one got created under a different name. Locking the
    password and forcing an already-past expiry are plain shadow
    attribute writes that cannot fail that way, and PAM (pam_unix)
    rejects both independently. Kept distinct from
    force_delete_system_user on purpose: that one is for permanently
    retiring an account, not for a live rebuild that must not half-fail."""
    code, _, _ = run_cmd(["id", username], ignore_errors=True)
    if code != 0:
        return
    run_cmd(["usermod", "-L", username], ignore_errors=True)
    run_cmd(["chage", "-E", "1", username], ignore_errors=True)
    kill_user_sessions(username)


def force_delete_system_user(username):
    """Kill all processes and force-delete a Linux system user."""
    import time as _time
    # Kill all processes owned by this user
    kill_user_sessions(username)
    _time.sleep(0.5)
    # Force delete with retry
    code, _, _ = run_cmd(["userdel", "-rf", username], ignore_errors=True)
    if code != 0:
        # Retry after killing harder
        run_cmd(["pkill", "-9", "-u", username], ignore_errors=True)
        _time.sleep(1)
        run_cmd(["userdel", "-rf", username], ignore_errors=True)

def _remove_line_from_file(filepath, target=None, prefix=None):
    if not os.path.exists(filepath): return
    with open(filepath) as f:
        lines = f.readlines()
    with open(filepath, 'w') as f:
        for line in lines:
            if target and line.strip() == target:
                continue
            if prefix and line.strip().startswith(prefix):
                continue
            f.write(line)

# --- USERS DB ---
def parse_db_line(line):
    parts = line.strip().split(":")
    if len(parts) < 5:
        return None
    user = {
        "username": parts[0],
        "password": parts[1],
        "expire_date": parts[2],
        "conn_limit": int(parts[3]) if parts[3].isdigit() else 1,
        "bandwidth_gb": float(parts[4]),
        "daily_bandwidth_gb": 0.0,
        "account_type": "",
        "owner": "admin"
    }
    if len(parts) > 5:
        try:
            user["daily_bandwidth_gb"] = float(parts[5])
        except ValueError:
            user["daily_bandwidth_gb"] = 0.0
    if len(parts) > 6:
        user["account_type"] = parts[6]
    if len(parts) > 7:
        # owner is normally a plain reseller username, but a bot-issued
        # account stores it as "tg:<chat_id>" — which has a colon of its
        # own, so it must be rejoined from every remaining field instead
        # of taking parts[7] alone (that would silently truncate it to
        # just "tg", losing the chat id and breaking every owner-based
        # lookup for that account).
        owner_val = ":".join(parts[7:])
        user["owner"] = owner_val if owner_val else "admin"
    return user

def read_db():
    users = []
    if not os.path.exists(DB_FILE):
        return users
    with open(DB_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            u = parse_db_line(line)
            if u:
                users.append(u)
    return users

def _fmt_bw(v):
    """Format bandwidth: 0.0 -> '0', 3.5 -> '3.5', 10.0 -> '10'"""
    f = float(v)
    return str(int(f)) if f == int(f) else str(f)

def format_db_line(u):
    bw = _fmt_bw(u.get('bandwidth_gb', 0))
    dbw = _fmt_bw(u.get('daily_bandwidth_gb', 0))
    owner = u.get('owner', 'admin')
    return f"{u['username']}:{u['password']}:{u['expire_date']}:{u['conn_limit']}:{bw}:{dbw}:{u.get('account_type','web')}:{owner}\n"

# --- RESELLERS DB ---
def parse_reseller_line(line):
    parts = line.strip().split(":")
    if len(parts) < 5:
        return None
    return {
        "username": parts[0],
        "password": parts[1],
        "expire_date": parts[2],
        "max_users": int(parts[3]) if parts[3].isdigit() else 10,
        "enabled": parts[4] == "1",
        "type": parts[5] if len(parts) > 5 else "quota",
        "credits": int(parts[6]) if len(parts) > 6 and parts[6].isdigit() else 0,
        "max_conn_per_user": int(parts[7]) if len(parts) > 7 and parts[7].isdigit() else 2,
        "max_bw_per_user": float(parts[8]) if len(parts) > 8 and parts[8].replace('.', '', 1).isdigit() else 0.0,
        "allow_bulk": parts[9] == "1" if len(parts) > 9 else True,
        "allow_trials": parts[10] == "1" if len(parts) > 10 else True,
        "max_speed_mbps": int(parts[11]) if len(parts) > 11 and parts[11].isdigit() else 0,
        "telegram_contact": parts[12] if len(parts) > 12 else ""
    }

def read_resellers():
    resellers = []
    if not os.path.exists(RESELLERS_DB):
        return resellers
    with open(RESELLERS_DB, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            r = parse_reseller_line(line)
            if r:
                resellers.append(r)
    return resellers

def format_reseller_line(r):
    enabled = "1" if r.get("enabled", True) else "0"
    rtype = r.get("type", "quota")
    credits = r.get("credits", 0)
    max_conn = r.get("max_conn_per_user", 2)
    max_bw = r.get("max_bw_per_user", 0)
    allow_bulk = "1" if r.get("allow_bulk", True) else "0"
    allow_trials = "1" if r.get("allow_trials", True) else "0"
    max_speed = r.get("max_speed_mbps", 0)
    telegram_contact = r.get("telegram_contact", "")
    return f"{r['username']}:{r['password']}:{r['expire_date']}:{r['max_users']}:{enabled}:{rtype}:{credits}:{max_conn}:{max_bw}:{allow_bulk}:{allow_trials}:{max_speed}:{telegram_contact}\n"

def write_resellers(resellers):
    os.makedirs(os.path.dirname(RESELLERS_DB), exist_ok=True)
    with open(RESELLERS_DB, "w") as f:
        for r in resellers:
            f.write(format_reseller_line(r))

def calculate_credit_cost(days=0, hours=0):
    """Calculate credit cost: 1 credit per 30 days (720 hours), rounded up."""
    total_hours = days * 24 + hours
    if total_hours <= 0:
        return 1
    return math.ceil(total_hours / (30 * 24))

# --- ONLINE SESSIONS ---
REALIP_DIR = "/run/dahoom-realip"
LAST_IP_DB = "/etc/firewallfalcon/last_ip.db"
_LOOPBACK_PREFIXES = ("127.", "::1", "0.0.0.0", "::ffff:127.")


def _is_local_addr(ip):
    """Whether an address is this machine talking to itself — i.e. a
    relayed connection whose real origin is recorded elsewhere."""
    if not ip:
        return True
    return any(ip.startswith(p) for p in _LOOPBACK_PREFIXES)


def read_realip_map():
    """{source_port: real_client_ip} published by the connection proxy.

    Customers reach sshd through firewallfalcon-socksproxy.py, which
    opens its own socket to 127.0.0.1:22 — so sshd, `who` and `last` all
    record the loopback address and the real one is lost unless the proxy
    hands it over. It does, keyed by the source port of that inner
    socket, which is the peer port sshd sees."""
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


def get_session_peers(pids):
    """{pid: peer_ip} for live sshd sessions, real address resolved.

    Reads the actual socket peer per PID rather than `who`, then puts the
    relay's own loopback peer back through the proxy's map. A connection
    that never went through the proxy has a public peer here already and
    is used as-is, so a direct SSH login keeps reporting exactly what it
    always did."""
    peers = {}
    want = {str(p) for p in pids}
    if not want:
        return peers
    realip = read_realip_map()
    code, out, _ = run_cmd(["ss", "-tnpH"], ignore_errors=True)
    if code != 0 or not out:
        return peers
    for line in out.splitlines():
        if "pid=" not in line:
            continue
        parts = line.split()
        if len(parts) < 5:
            continue
        peer = parts[4]
        # IPv6 peers are written [addr]:port; everything else addr:port.
        if peer.startswith("["):
            addr, _, port = peer.rpartition("]:")
            addr = addr.lstrip("[")
        else:
            addr, _, port = peer.rpartition(":")
        for m in re.finditer(r"pid=(\d+)", line):
            pid = m.group(1)
            if pid not in want:
                continue
            resolved = realip.get(port) if _is_local_addr(addr) else addr
            if resolved and not _is_local_addr(resolved):
                peers[pid] = resolved
            elif pid not in peers:
                peers[pid] = resolved or addr
    return peers


def last_ips_from_connlog(usernames):
    """Most recent real address per user out of the connection log.

    The last line of defence against an empty address column: a session
    that was already open when this version landed has no live map entry
    (the proxy wipes the map on restart) and nothing in last_ip.db yet,
    but the connection log has been recording every login all along.
    Loopback rows — everything logged before the proxy started handing
    the real address over — are skipped rather than shown."""
    out = {}
    if not usernames or not os.path.exists(CONNLOG_DB_PATH):
        return out
    try:
        conn = sqlite3.connect(f"file:{CONNLOG_DB_PATH}?mode=ro", uri=True, timeout=3)
        try:
            cur = conn.cursor()
            for un in usernames:
                cur.execute(
                    "SELECT ip FROM connections WHERE username=? AND ip IS NOT NULL AND ip!='' "
                    "ORDER BY connect_time DESC LIMIT 20", (un,))
                for (ip,) in cur.fetchall():
                    if not _is_local_addr(ip):
                        out[un] = ip
                        break
        finally:
            conn.close()
    except Exception:
        pass
    return out


def read_last_ips():
    out = {}
    try:
        with open(LAST_IP_DB, encoding="utf-8", errors="ignore") as f:
            for line in f:
                u, _, ip = line.strip().partition(":")
                if u and ip:
                    out[u] = ip
    except OSError:
        pass
    return out


def write_last_ips(mapping):
    """Remembers the last real address seen per user, so a moment when
    the live lookup comes up empty (proxy restarted mid-session, session
    started before this version) still shows a real address instead of
    "unknown"."""
    if not mapping:
        return
    current = read_last_ips()
    current.update({u: ip for u, ip in mapping.items() if ip and not _is_local_addr(ip)})
    try:
        os.makedirs(os.path.dirname(LAST_IP_DB), exist_ok=True)
        with open(LAST_IP_DB, "w", encoding="utf-8") as f:
            for u, ip in current.items():
                f.write(f"{u}:{ip}\n")
    except OSError:
        pass


def get_online_sessions(target_user=None):
    managed_users = set(u["username"] for u in read_db())
    if target_user and target_user not in managed_users:
        return 0
    
    user_pids = {}
    try:
        code, out, _ = run_cmd(["ps", "-C", "sshd,sshd-session", "-o", "pid=,user="], ignore_errors=True)
        if code == 0 and out:
            for line in out.strip().splitlines():
                parts = line.split()
                if len(parts) != 2:
                    continue
                pid, owner = parts
                if owner in ("root", "sshd", ""):
                    continue
                if owner not in managed_users:
                    continue
                if target_user and owner != target_user:
                    continue
                if owner not in user_pids:
                    user_pids[owner] = set()
                user_pids[owner].add(pid)
    except Exception as e:
        print(f"Error checking online sessions: {e}", file=sys.stderr)
        
    if target_user:
        return len(user_pids.get(target_user, set()))
    else:
        return sum(len(pids) for pids in user_pids.values())

def get_online_sessions_for_users(usernames):
    """Get online session counts for a set of usernames efficiently (single ps call)."""
    user_pids = {}
    try:
        code, out, _ = run_cmd(["ps", "-C", "sshd,sshd-session", "-o", "pid=,user="], ignore_errors=True)
        if code == 0 and out:
            for line in out.strip().splitlines():
                parts = line.split()
                if len(parts) != 2:
                    continue
                pid, owner = parts
                if owner in ("root", "sshd", ""):
                    continue
                if owner not in usernames:
                    continue
                if owner not in user_pids:
                    user_pids[owner] = set()
                user_pids[owner].add(pid)
    except Exception as e:
        print(f"Error checking online sessions: {e}", file=sys.stderr)
    return user_pids

def read_file_int(path, default=0):
    try:
        if os.path.exists(path):
            with open(path, "r") as f:
                return int(f.read().strip())
    except Exception:
        pass
    return default

def refresh_ssh_banner_config():
    """Refresh dynamic SSH banner sshd config when banners are enabled."""
    if not os.path.exists("/etc/firewallfalcon/banners_enabled"):
        return
    sshd_ff_config = "/etc/ssh/sshd_config.d/firewallfalcon-banners.conf"
    banner_dir = "/etc/firewallfalcon/banners"
    os.makedirs(banner_dir, exist_ok=True)
    
    lines = ["# DAHOOM - Dynamic per-user SSH banners\n"]
    users = read_db()
    for u in users:
        un = u["username"]
        lines.append(f"Match User {un}\n")
        lines.append(f"    Banner {banner_dir}/{un}.txt\n")
    
    new_content = "".join(lines)
    
    # Only update if changed
    old_content = ""
    if os.path.exists(sshd_ff_config):
        try:
            with open(sshd_ff_config, "r") as f:
                old_content = f.read()
        except:
            pass
    
    if new_content != old_content:
        try:
            with open(sshd_ff_config, "w") as f:
                f.write(new_content)
            # Ensure Include directive exists
            try:
                with open("/etc/ssh/sshd_config", "r") as f:
                    sshd_content = f.read()
                if "Include /etc/ssh/sshd_config.d/" not in sshd_content:
                    with open("/etc/ssh/sshd_config", "a") as f:
                        f.write("\nInclude /etc/ssh/sshd_config.d/*.conf\n")
            except:
                pass
            run_cmd("systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null", ignore_errors=True)
        except Exception as e:
            print(f"Error refreshing SSH banner config: {e}", file=sys.stderr)

# --- PANEL CREDS ---
def get_panel_conf_path():
    for p in ["/etc/firewallfalcon/panel.conf", "/etc/firewallfalcon/panel/panel.conf", "/etc/panel.conf"]:
        if os.path.exists(p):
            return p
    return "/etc/firewallfalcon/panel.conf"

def get_panel_creds():
    creds = {
        "PANEL_USER": "admin",
        "PANEL_PASS_HASH": "",
        "PANEL_PASS_PLAIN": "",
        "PANEL_SECRET": "",
        "PANEL_NAME": "DAHOOM",
        "PANEL_LOGO": "👑",
        "PANEL_PORT": "44380",
        "PANEL_DOMAIN": "",
        "PANEL_TELEGRAM": ""
    }
    conf_path = get_panel_conf_path()
    if os.path.exists(conf_path):
        try:
            with open(conf_path, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    if "=" in line:
                        k, v = line.split("=", 1)
                        k = k.strip().upper()
                        v = v.strip().strip('"').strip("'")
                        if k in creds:
                            creds[k] = v
        except Exception as e:
            print(f"Error reading panel.conf: {e}", file=sys.stderr)
    return creds

def write_panel_creds(user, pass_plain, secret=None, panel_name=None, panel_logo=None, panel_domain=None, panel_telegram=None):
    creds = get_panel_creds()
    creds["PANEL_USER"] = user
    creds["PANEL_PASS_PLAIN"] = pass_plain
    creds["PANEL_PASS_HASH"] = hashlib.sha256(pass_plain.encode()).hexdigest()
    if secret is not None:
        creds["PANEL_SECRET"] = secret.strip().lstrip('/')
    if panel_name is not None:
        creds["PANEL_NAME"] = panel_name.strip() or "DAHOOM"
    if panel_logo is not None:
        creds["PANEL_LOGO"] = panel_logo.strip() or "👑"
    if panel_domain is not None:
        # A bare domain, no scheme/path — links are built as http://<host>:<port>/...
        creds["PANEL_DOMAIN"] = panel_domain.strip().lower().removeprefix("http://").removeprefix("https://").rstrip("/")
    if panel_telegram is not None:
        creds["PANEL_TELEGRAM"] = panel_telegram.strip().lstrip('@')

    conf_path = get_panel_conf_path()
    os.makedirs(os.path.dirname(conf_path), exist_ok=True)
    with open(conf_path, "w", encoding="utf-8") as f:
        for k, v in creds.items():
            f.write(f"{k}={v}\n")


def get_public_host():
    """The host used in every link handed to an outside viewer (usage-status
    links, X-UI client links, the admin autologin link, the reseller portal
    URL) — the admin's configured domain when set, falling back to the
    server's own detected IP exactly as before. Deliberately NOT used for
    anything that needs the server's actual IP address (e.g. the Cloudflare
    DNS A-record sync/validation, which would break if fed a domain name
    instead)."""
    domain = (get_panel_creds().get("PANEL_DOMAIN") or "").strip()
    return domain if domain else (detect_server_ip() or "YOUR_SERVER_IP")

# --- RESELLER PORTAL SECRET PATH ---
def get_reseller_secret():
    if os.path.exists(RESELLER_KEY_FILE):
        try:
            with open(RESELLER_KEY_FILE, "r", encoding="utf-8") as f:
                sec = f.read().strip()
                if sec:
                    return sec
        except Exception:
            pass
    # Generate default random 8-character secret
    chars = "abcdefghjkmnpqrstuvwxyz23456789"
    sec = "".join(secrets.choice(chars) for _ in range(8))
    set_reseller_secret(sec)
    return sec

def set_reseller_secret(sec):
    sec = sec.strip().lstrip('/')
    try:
        os.makedirs(os.path.dirname(RESELLER_KEY_FILE), exist_ok=True)
        with open(RESELLER_KEY_FILE, "w", encoding="utf-8") as f:
            f.write(sec + "\n")
    except Exception as e:
        print(f"Error saving reseller secret: {e}", file=sys.stderr)
    return sec

# --- SESSION ---
def cleanup_sessions():
    now = time.time()
    expired = [t for t, s in sessions.items() if now - s["created_at"] > 86400]
    for t in expired:
        del sessions[t]
    if expired:
        save_sessions()

def generate_password(length=8):
    chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return "".join(secrets.choice(chars) for _ in range(length))

def parse_expiry_datetime(date_str):
    """Parse expiry datetime from multiple formats. "%Y-%m-%d %H%M" (no
    colon) is what calculate_expire_date() actually writes now — see there
    for why. The colon-bearing forms are kept only to still read any
    already-stored value from before that fix; a users.db/resellers.db line
    with one of those got its later columns shifted by the stray colon
    before this ever ran, so this can recover the date but not undo that."""
    if not date_str or date_str in ("Never", "N/A"):
        return None
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d %H%M", "%Y-%m-%d"):
        try:
            return datetime.strptime(date_str, fmt)
        except ValueError:
            pass
    return None

def extract_duration_days_hours(body, default_days=30):
    """
    Extracts (days, hours) from request payload supporting both:
    - duration_value (int) + duration_unit ('days' | 'hours')
    - days (int)
    - hours (int)
    """
    unit = str(body.get("duration_unit", "")).lower().strip() if body else ""
    val = body.get("duration_value") if body else None
    if val is not None and str(val).isdigit():
        val = int(val)
        if unit in ("hours", "hour", "h", "ساعات", "ساعة"):
            return 0, val
        else:
            return val, 0

    days = int(body.get("days", 0)) if body and str(body.get("days", "")).isdigit() else 0
    hours = int(body.get("hours", 0)) if body and str(body.get("hours", "")).isdigit() else 0
    if days == 0 and hours == 0:
        days = default_days
    return days, hours

def calculate_expire_date(days=0, hours=0):
    if days == 0 and hours == 0:
        days = 30
    target_dt = datetime.now() + timedelta(days=days, hours=hours)
    if hours > 0 and (hours % 24 != 0 or days == 0):
        # No colon in the time part on purpose: this string is later stored
        # as one field in users.db/resellers.db, both ":"-delimited — a
        # "HH:MM" here would split into two fields there and shift every
        # column after it (conn_limit, bandwidth, ...) for that account.
        # See parse_expiry_datetime() for the matching read side.
        return target_dt.strftime("%Y-%m-%d %H%M")
    return target_dt.strftime("%Y-%m-%d")

# --- AUTO-LOGIN 1-HOUR DYNAMIC TOKEN ENGINE ---
AUTOLOGIN_FILE = "/etc/firewallfalcon/panel/autologin.json"
AUTOLOGIN_TOKENS = {}

def load_autologin_tokens():
    global AUTOLOGIN_TOKENS
    if os.path.exists(AUTOLOGIN_FILE):
        try:
            with open(AUTOLOGIN_FILE, "r", encoding="utf-8") as f:
                AUTOLOGIN_TOKENS = json.load(f)
        except Exception:
            AUTOLOGIN_TOKENS = {}
    cleanup_autologin_tokens()

def save_autologin_tokens():
    cleanup_autologin_tokens()
    try:
        os.makedirs(os.path.dirname(AUTOLOGIN_FILE), exist_ok=True)
        with open(AUTOLOGIN_FILE, "w", encoding="utf-8") as f:
            json.dump(AUTOLOGIN_TOKENS, f)
    except Exception:
        pass

def cleanup_autologin_tokens():
    global AUTOLOGIN_TOKENS
    now = time.time()
    AUTOLOGIN_TOKENS = {k: v for k, v in AUTOLOGIN_TOKENS.items() if isinstance(v, dict) and v.get("expires_at", 0) > now}

def generate_admin_autologin_token(ttl_seconds=3600):
    load_autologin_tokens()
    token = secrets.token_hex(24)
    creds = get_panel_creds()
    username = (creds.get("PANEL_USER") or "admin").strip()
    now = time.time()
    AUTOLOGIN_TOKENS[token] = {
        "username": username,
        "role": "admin",
        "created_at": now,
        "expires_at": now + ttl_seconds
    }
    save_autologin_tokens()
    return token

def generate_admin_autologin_link(server_ip=None, domain=None):
    token = generate_admin_autologin_token(ttl_seconds=3600)
    creds = get_panel_creds()
    secret = creds.get("PANEL_SECRET", "").strip().lstrip('/')
    port = PORT
    host = domain or server_ip or get_public_host()
    path = f"/{secret}" if secret else ""
    return f"http://{host}:{port}{path}?auth={token}"

def consume_autologin_token(token):
    # Always force-reload from disk to pick up tokens written by menu.sh / update_panel.sh
    global AUTOLOGIN_TOKENS
    AUTOLOGIN_TOKENS = {}
    if os.path.exists(AUTOLOGIN_FILE):
        try:
            with open(AUTOLOGIN_FILE, "r", encoding="utf-8") as f:
                AUTOLOGIN_TOKENS = json.load(f)
        except Exception:
            AUTOLOGIN_TOKENS = {}
    
    if not token or token not in AUTOLOGIN_TOKENS:
        return None
    data = AUTOLOGIN_TOKENS[token]
    if time.time() > data.get("expires_at", 0):
        del AUTOLOGIN_TOKENS[token]
        save_autologin_tokens()
        return None
    # Token is valid — create real session
    session_token = secrets.token_hex(32)
    username = data.get("username") or "admin"
    sessions[session_token] = {
        "username": username,
        "role": data.get("role", "admin"),
        "created_at": time.time()
    }
    save_sessions()
    # Remove to make it single-use
    del AUTOLOGIN_TOKENS[token]
    save_autologin_tokens()
    return session_token, username

def check_session(headers, handler=None, preferred_role=None):
    """Returns session info dict or None if not authenticated."""
    cleanup_sessions()
    if not headers:
        return None

    # 1. Check Authorization Bearer or custom token header as fallback
    auth_hdr = headers.get("Authorization", "")
    if auth_hdr.startswith("Bearer "):
        t = auth_hdr.split(" ", 1)[1].strip()
        if t in sessions:
            return sessions[t]
    custom_hdr = headers.get("X-Session-Token", "").strip()
    if custom_hdr and custom_hdr in sessions:
        return sessions[custom_hdr]

    if "Cookie" not in headers:
        return None
    try:
        C = cookies.SimpleCookie(headers["Cookie"])
    except Exception:
        return None

    is_reseller_req = False
    if handler and hasattr(handler, 'path'):
        p = handler.path.lower()
        if "reseller" in p:
            is_reseller_req = True
    if headers.get("X-Portal") == "reseller" or preferred_role == "reseller":
        is_reseller_req = True

    if is_reseller_req:
        # Prioritize reseller_session cookie
        if "reseller_session" in C:
            token = C["reseller_session"].value
            if token in sessions:
                return sessions[token]
        if "session" in C:
            token = C["session"].value
            if token in sessions:
                return sessions[token]
    else:
        # Prioritize admin session cookie
        if "admin_session" in C:
            token = C["admin_session"].value
            if token in sessions:
                return sessions[token]
        if "session" in C:
            token = C["session"].value
            if token in sessions:
                return sessions[token]
        if "reseller_session" in C:
            token = C["reseller_session"].value
            if token in sessions:
                return sessions[token]

    return None

# --- HTTP HANDLER ---
class PanelAPIHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Suppress default logging

    def _client_ip(self):
        """The panel is normally reached directly on its own port (no
        reverse proxy in front of it by default), so client_address is the
        real IP. Still prefer X-Forwarded-For/X-Real-IP when present, in
        case an admin did put it behind nginx/haproxy themselves."""
        xff = self.headers.get("X-Forwarded-For")
        if xff:
            return xff.split(",")[0].strip()
        xri = self.headers.get("X-Real-IP")
        if xri:
            return xri.strip()
        try:
            return self.client_address[0]
        except Exception:
            return "unknown"

    def send_json(self, status, data, extra_headers=None):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        if extra_headers:
            for k, v in extra_headers.items():
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))

    def _get_session(self):
        """Helper: returns session dict or sends 401 and returns None."""
        s = check_session(self.headers, handler=self)
        if not s:
            self.send_json(401, {"error": "Unauthorized"})
        return s

    def _require_admin(self, session):
        """Helper: returns True if admin, else sends 403 and returns False."""
        if session.get("role") != "admin":
            self.send_json(403, {"error": "Admin access required"})
            return False
        return True

    def _check_node_token(self):
        """Gate for /api/node/* — a machine credential, structurally
        separate from check_session/sessions: it never touches that
        dict, so a leaked node token can't open a browser admin session
        and vice versa, and a node call never shows up in the admin's
        own session/audit surfaces. Compares against this box's OWN
        accepted token (bot_node_self_get — set once via the "enable
        this server as a VPN node" action), not against bot_nodes.db
        (which is the CONTROLLER's registry of tokens to SEND, not
        accept)."""
        token = (self.headers.get("X-Node-Token") or "").strip()
        self_conf = bot_node_self_get() or {}
        expected = self_conf.get("token", "")
        if not self_conf.get("enabled") or not expected or not token or not secrets.compare_digest(token, expected):
            self.send_json(401, {"error": "Invalid or missing node token"})
            return False
        return True

    def _clean_path(self, raw_path):
        creds = get_panel_creds()
        secret = creds.get("PANEL_SECRET", "").strip().lstrip('/')
        clean = raw_path
        if secret and clean.startswith(f"/{secret}"):
            clean = clean[len(secret) + 1:]
            if not clean.startswith('/'):
                clean = '/' + clean
        return clean

    def do_GET(self):
        try:
            parsed_path = urlparse(self.path)
            raw_path = parsed_path.path.strip()
            clean_path = self._clean_path(raw_path)

            # Check 1-hour auto-login link token
            qs = parse_qs(parsed_path.query)
            auth_token = qs.get("auth", [""])[0] or qs.get("token", [""])[0] or qs.get("autologin", [""])[0]
            if auth_token:
                consumed = consume_autologin_token(auth_token)
                if consumed:
                    session_token, authed_user = consumed
                    self._log_panel_access(authed_user, "autologin")
                    creds = get_panel_creds()
                    secret = creds.get("PANEL_SECRET", "").strip().lstrip('/')
                    clean_url = f"/{secret}" if secret else "/"
                    cookie_str1 = f"session={session_token}; Path=/; HttpOnly; Max-Age=86400; SameSite=Lax"
                    cookie_str2 = f"admin_session={session_token}; Path=/; HttpOnly; Max-Age=86400; SameSite=Lax"
                    
                    if os.path.exists(PANEL_HTML):
                        try:
                            with open(PANEL_HTML, "r", encoding="utf-8") as f:
                                html_content = f.read()
                            inject_script = (
                                f"<script>"
                                f"try{{localStorage.setItem('ff_session_token','{session_token}');"
                                f"window.history.replaceState(null,'','{clean_url}');"
                                f"}}catch(e){{}}"
                                f"</script>"
                            )
                            # Case-insensitive replacement of </head>
                            import re as _re
                            html_content = _re.sub(r'(?i)</head>', inject_script + '</head>', html_content, count=1)
                            self.send_response(200)
                            self.send_header('Content-Type', 'text/html; charset=utf-8')
                            self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
                            self.send_header('Pragma', 'no-cache')
                            self.send_header('Set-Cookie', cookie_str1)
                            self.send_header('Set-Cookie', cookie_str2)
                            self.end_headers()
                            self.wfile.write(html_content.encode('utf-8'))
                        except Exception as e:
                            print(f"[autologin] HTML injection error: {e}", file=sys.stderr)
                            self.send_response(302)
                            self.send_header('Location', clean_url)
                            self.send_header('Set-Cookie', cookie_str1)
                            self.send_header('Set-Cookie', cookie_str2)
                            self.end_headers()
                        return
                    else:
                        # No HTML file, redirect with cookies
                        self.send_response(302)
                        self.send_header('Location', clean_url)
                        self.send_header('Set-Cookie', cookie_str1)
                        self.send_header('Set-Cookie', cookie_str2)
                        self.end_headers()
                        return

            # If request path is an API endpoint or logo image
            if clean_path.startswith("/api/") or raw_path.startswith("/api/"):
                api_path = clean_path if clean_path.startswith("/api/") else raw_path

                # Node API: machine-credential auth (_check_node_token),
                # never the admin session path below — see handle_node_route.
                if api_path.startswith("/api/node/"):
                    if not self._check_node_token():
                        return
                    return self.handle_node_route("GET", api_path, {})

                # Public endpoint: branding (no auth required)
                if api_path == "/api/branding":
                    creds = get_panel_creds()
                    self.send_json(200, {
                        "panel_name": creds.get("PANEL_NAME", "DAHOOM"),
                        "panel_logo": creds.get("PANEL_LOGO", "👑"),
                        "has_custom_logo": os.path.exists("/etc/firewallfalcon/panel/logo.png") and creds.get("PANEL_LOGO") == "custom"
                    })
                    return

                # Serve custom logo image (public, no auth)
                logo_path = "/etc/firewallfalcon/panel/logo.png"
                if api_path == "/api/logo.png":
                    if os.path.exists(logo_path):
                        with open(logo_path, "rb") as f:
                            img_data = f.read()
                        self.send_response(200)
                        self.send_header('Content-Type', 'image/png')
                        self.send_header('Cache-Control', 'public, max-age=3600')
                        self.end_headers()
                        self.wfile.write(img_data)
                    else:
                        self.send_response(404)
                        self.end_headers()
                        self.wfile.write(b"No custom logo")
                    return

                session = self._get_session()
                if not session:
                    return

                if api_path == "/api/me":
                    self.handle_get_me(session)
                elif api_path == "/api/dashboard":
                    self.handle_get_dashboard(session)
                elif api_path == "/api/analytics":
                    if not self._require_admin(session): return
                    self.handle_get_analytics(session)
                elif api_path == "/api/monitor":
                    if not self._require_admin(session): return
                    self.handle_get_monitor(session)
                elif api_path == "/api/firewall":
                    if not self._require_admin(session): return
                    self.handle_get_firewall()
                elif api_path in ("/api/user-speeds", "/api/speeds"):
                    if not self._require_admin(session): return
                    self.handle_get_user_speeds()
                elif api_path == "/api/panel-logs":
                    if not self._require_admin(session): return
                    self.handle_get_panel_logs()
                elif api_path == "/api/logs":
                    if not self._require_admin(session): return
                    self.handle_get_categorized_logs(session)
                elif api_path == "/api/connections":
                    self.handle_get_connections(session)
                elif api_path.startswith("/api/users/") and api_path.endswith("/history"):
                    username = api_path.split("/")[3]
                    if not self._check_user_ownership(username, session):
                        return self.send_json(403, {"error": "Access denied"})
                    self.handle_user_history(username)
                elif api_path.startswith("/api/users/") and api_path.endswith("/bandwidth-link"):
                    username = api_path.split("/")[3]
                    if not self._check_user_ownership(username, session):
                        return self.send_json(403, {"error": "Access denied"})
                    link, bw_link_enabled = get_bandwidth_link(username)
                    if link:
                        self.send_json(200, {"link": link, "enabled": bw_link_enabled})
                    else:
                        self.send_json(500, {"error": "تعذّر إنشاء/استرجاع الرابط"})
                elif api_path.startswith("/api/users/export"):
                    qs = parse_qs(urlparse(self.path).query)
                    fmt = qs.get("format", ["json"])[0]
                    self.handle_export_users(session, fmt)
                elif api_path == "/api/users":
                    self.handle_get_users(session)
                elif api_path == "/api/protocols":
                    if not self._require_admin(session):
                        return
                    self.handle_get_protocols()
                elif api_path == "/api/xui/inbounds":
                    if not self._require_admin(session):
                        return
                    self.send_json(200, {"installed": xui_installed(), "inbounds": xui_list_inbounds()})
                elif api_path == "/api/xui/clients":
                    if not self._require_admin(session):
                        return
                    self.handle_get_xui_clients()
                elif api_path.startswith("/api/xui/clients/") and api_path.endswith("/bandwidth-link"):
                    if not self._require_admin(session):
                        return
                    parts = api_path.split("/")
                    inbound_id = parts[4]
                    email = urllib.parse.unquote(parts[5]) if len(parts) > 5 else ""
                    self.handle_get_xui_bandwidth_link(inbound_id, email)
                elif api_path.startswith("/api/xui/clients/") and api_path.endswith("/history"):
                    if not self._require_admin(session):
                        return
                    parts = api_path.split("/")
                    inbound_id = parts[4]
                    email = urllib.parse.unquote(parts[5]) if len(parts) > 5 else ""
                    self.handle_xui_client_history(inbound_id, email)
                elif api_path == "/api/settings":
                    if not self._require_admin(session):
                        return
                    self.handle_get_settings()
                elif api_path == "/api/server-host":
                    # Same domain-or-IP value every public link is already built
                    # from (get_public_host()) — exposed on its own so the UI can
                    # show/copy it as a standalone field, not just embedded in a
                    # full URL. Any authenticated session (admin or reseller) can
                    # read it; it's already visible in every link they can see.
                    self.send_json(200, {"host": get_public_host()})
                elif api_path == "/api/resellers":
                    if not self._require_admin(session):
                        return
                    self.handle_get_resellers()
                elif api_path == "/api/cloudflare":
                    if not self._require_admin(session):
                        return
                    self.handle_get_cloudflare()
                elif api_path == "/api/cloudflare/records":
                    if not self._require_admin(session):
                        return
                    self.handle_get_cloudflare_records()
                elif api_path == "/api/autologin-link":
                    if not self._require_admin(session):
                        return
                    server_ip = get_public_host()
                    link = generate_admin_autologin_link(server_ip=server_ip)
                    self.send_json(200, {
                        "success": True,
                        "link": link,
                        "expires_in_seconds": 3600,
                        "message": "Dynamic 1-hour 1-click login link generated"
                    })
                elif api_path.startswith("/api/bot/"):
                    self.handle_bot_route("GET", api_path, {}, session)
                else:
                    self.send_json(404, {"error": "Not Found"})
                return

            # Check if this is a Reseller Portal request
            reseller_sec = get_reseller_secret()
            clean_raw = raw_path.rstrip('/')
            
            if clean_raw in (f"/reseller_{reseller_sec}", f"/reseller/{reseller_sec}"):
                if os.path.exists(PANEL_RESELLER_HTML):
                    with open(PANEL_RESELLER_HTML, "rb") as f:
                        content = f.read()
                    self.send_response(200)
                    self.send_header('Content-Type', 'text/html; charset=utf-8')
                    self.send_header('Cache-Control', 'no-cache')
                    self.end_headers()
                    self.wfile.write(content)
                    return
                else:
                    self.send_response(404)
                    self.end_headers()
                    self.wfile.write(b"Reseller Portal HTML not found")
                    return
            elif clean_raw.startswith("/reseller_") or clean_raw == "/reseller" or clean_raw.startswith("/reseller/"):
                # Unauthorized or invalid reseller secret path -> return 404
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b"Not Found")
                return

            # For all other non-API GET requests (root, secret path, index.html), serve Admin HTML
            if os.path.exists(PANEL_HTML):
                with open(PANEL_HTML, "rb") as f:
                    content = f.read()
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.send_header('Cache-Control', 'no-cache')
                self.end_headers()
                self.wfile.write(content)
            else:
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b"HTML not found")
        except Exception as e:
            print(f"Error handling GET {self.path}: {e}", file=sys.stderr)
            self.send_json(500, {"error": str(e)})

    def do_POST(self):
        parsed_path = urlparse(self.path)
        path = self._clean_path(parsed_path.path.strip())

        if path.startswith("/api/node/"):
            content_length = int(self.headers.get('Content-Length', 0))
            raw_body = self.rfile.read(content_length) if content_length > 0 else b''
            try:
                body = json.loads(raw_body.decode('utf-8')) if raw_body else {}
            except json.JSONDecodeError:
                body = {}
            if not self._check_node_token():
                return
            return self.handle_node_route("POST", path, body)

        content_length = int(self.headers.get('Content-Length', 0))

        # Handle logo upload BEFORE reading body as JSON (binary upload)
        if path == "/api/logo/upload":
            session = self._get_session()
            if not session:
                return
            if not self._require_admin(session):
                return
            raw_data = self.rfile.read(content_length) if content_length > 0 else b''
            self.handle_logo_upload(raw_data)
            return
        
        post_data = self.rfile.read(content_length)
        try:
            body = json.loads(post_data.decode('utf-8')) if post_data else {}
        except json.JSONDecodeError:
            body = {}

        if path == "/api/login":
            self.handle_login(body)
            return

        if path == "/api/autologin":
            self.handle_post_autologin(body)
            return

        session = self._get_session()
        if not session:
            return

        if path == "/api/logout":
            self.handle_logout(body)
        elif path == "/api/logo/delete":
            if not self._require_admin(session):
                return
            self.handle_logo_delete()
        elif path == "/api/firewall":
            if not self._require_admin(session): return
            self.handle_post_firewall(body)
        elif path == "/api/firewall/flush":
            if not self._require_admin(session): return
            self.handle_post_firewall({"action": "flush"})
        elif path in ("/api/user-speeds", "/api/speeds"):
            if not self._require_admin(session): return
            self.handle_post_user_speeds(body)
        elif path == "/api/speeds/flush":
            if not self._require_admin(session): return
            self.handle_post_user_speeds({"action": "remove_all"})
        elif path.startswith("/api/monitor/") and path.endswith("/kick"):
            if not self._require_admin(session): return
            username = path.split("/")[3]
            self.handle_kick_user(username)
        elif path == "/api/users":
            self.handle_post_users(body, session)
        elif path == "/api/users/bulk":
            self.handle_post_users_bulk(body, session)
        elif path == "/api/users/trial":
            self.handle_post_trial_user(body, session)
        elif path == "/api/xui/clients":
            if not self._require_admin(session): return
            self.handle_post_xui_client(body, session)
        elif path == "/api/xui/clients/trial":
            if not self._require_admin(session): return
            self.handle_post_xui_trial_client(body, session)
        elif path.startswith("/api/xui/clients/") and path.endswith("/renew"):
            if not self._require_admin(session): return
            parts = path.split("/")
            inbound_id = parts[4]
            email = urllib.parse.unquote(parts[5]) if len(parts) > 5 else ""
            self.handle_post_xui_client_renew(inbound_id, email, body, session)
        elif path.startswith("/api/xui/clients/") and path.endswith("/reset-usage"):
            if not self._require_admin(session): return
            parts = path.split("/")
            inbound_id = parts[4]
            email = urllib.parse.unquote(parts[5]) if len(parts) > 5 else ""
            self.handle_post_xui_client_reset_usage(inbound_id, email, session)
        elif path.startswith("/api/xui/clients/") and path.endswith("/bandwidth-link/toggle"):
            if not self._require_admin(session): return
            parts = path.split("/")
            inbound_id = parts[4]
            email = urllib.parse.unquote(parts[5]) if len(parts) > 5 else ""
            self.handle_post_xui_bandwidth_link_toggle(inbound_id, email, body)
        elif path.startswith("/api/xui/clients/") and path.endswith("/note"):
            if not self._require_admin(session): return
            parts = path.split("/")
            inbound_id = parts[4]
            email = urllib.parse.unquote(parts[5]) if len(parts) > 5 else ""
            set_xui_client_pref(inbound_id, email, note=str(body.get("note", "")))
            self.send_json(200, {"success": True})
        elif path.startswith("/api/users/") and path.endswith("/lock"):
            user = path.split("/")[3]
            self.handle_user_action(user, "lock", session=session)
        elif path.startswith("/api/users/") and path.endswith("/unlock"):
            user = path.split("/")[3]
            self.handle_user_action(user, "unlock", session=session)
        elif path.startswith("/api/users/") and path.endswith("/renew"):
            user = path.split("/")[3]
            self.handle_user_action(user, "renew", body=body, session=session)
        elif path.startswith("/api/users/") and path.endswith("/reset-bandwidth"):
            user = path.split("/")[3]
            self.handle_user_action(user, "reset-bandwidth", session=session)
        elif path.startswith("/api/users/") and path.endswith("/note"):
            user = path.split("/")[3]
            if not self._check_user_ownership(user, session):
                return self.send_json(403, {"error": "Access denied"})
            set_user_note(user, str(body.get("note", "")))
            self.send_json(200, {"success": True})
        elif path.startswith("/api/users/") and path.endswith("/hwid"):
            user = path.split("/")[3]
            self.handle_post_user_hwid(user, body, session)
        elif path.startswith("/api/users/") and path.endswith("/bandwidth-link/toggle"):
            user = path.split("/")[3]
            if not self._check_user_ownership(user, session):
                return self.send_json(403, {"error": "Access denied"})
            self.handle_post_bandwidth_link_toggle(user, body)
        elif path.startswith("/api/protocols/") and path.endswith("/restart"):
            if not self._require_admin(session):
                return
            service = path.split("/")[3]
            self.handle_protocol_restart(service)
        elif path == "/api/resellers":
            if not self._require_admin(session):
                return
            self.handle_post_reseller(body)
        elif path == "/api/system/reboot":
            if not self._require_admin(session):
                return
            self.handle_system_reboot()
        elif path.startswith("/api/resellers/") and path.endswith("/toggle"):
            if not self._require_admin(session):
                return
            reseller_name = path.split("/")[3]
            self.handle_toggle_reseller(reseller_name)
        elif path.startswith("/api/resellers/") and path.endswith("/add-credits"):
            if not self._require_admin(session):
                return
            username = path.split("/")[3]
            self.handle_add_credits(username, body)
        elif path == "/api/resellers/secret":
            if not self._require_admin(session):
                return
            new_sec = body.get("secret", "").strip() if body else ""
            if not new_sec:
                chars = "abcdefghjkmnpqrstuvwxyz23456789"
                new_sec = "".join(secrets.choice(chars) for _ in range(8))
            set_reseller_secret(new_sec)
            server_ip = get_public_host()
            portal_path = f"/reseller_{new_sec}"
            portal_url = f"http://{server_ip}:{PORT}{portal_path}"
            self.send_json(200, {
                "success": True,
                "reseller_secret": new_sec,
                "reseller_portal_path": portal_path,
                "reseller_portal_url": portal_url
            })
        elif path == "/api/cloudflare/config":
            if not self._require_admin(session): return
            self.handle_post_cloudflare_config(body)
        elif path == "/api/cloudflare/records":
            if not self._require_admin(session): return
            self.handle_post_cloudflare_record(body)
        elif path == "/api/cloudflare/sync-ip":
            if not self._require_admin(session): return
            self.handle_sync_cloudflare_ip(body)
        elif path.startswith("/api/bot/"):
            self.handle_bot_route("POST", path, body, session)
        else:
            self.send_json(404, {"error": "Not Found"})

    def do_PUT(self):
        parsed_path = urlparse(self.path)
        path = self._clean_path(parsed_path.path.strip())

        if path.startswith("/api/node/"):
            content_length = int(self.headers.get('Content-Length', 0))
            raw_body = self.rfile.read(content_length) if content_length > 0 else b''
            try:
                body = json.loads(raw_body.decode('utf-8')) if raw_body else {}
            except json.JSONDecodeError:
                body = {}
            if not self._check_node_token():
                return
            return self.handle_node_route("PUT", path, body)

        session = self._get_session()
        if not session:
            return

        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)
        try:
            body = json.loads(post_data.decode('utf-8')) if post_data else {}
        except json.JSONDecodeError:
            body = {}

        if path.startswith("/api/xui/clients/"):
            if not self._require_admin(session):
                return
            parts = path.split("/")
            inbound_id = parts[4]
            email = urllib.parse.unquote(parts[5]) if len(parts) > 5 else ""
            self.handle_put_xui_client(inbound_id, email, body)
        elif path.startswith("/api/users/"):
            user = path.split("/")[3]
            self.handle_put_user(user, body, session)
        elif path == "/api/settings":
            if not self._require_admin(session):
                return
            self.handle_put_settings(body)
        elif path == "/api/reseller/telegram":
            if session.get("role") != "reseller":
                return self.send_json(403, {"error": "Resellers only"})
            self.handle_put_reseller_telegram(body, session)
        elif path.startswith("/api/resellers/"):
            if not self._require_admin(session):
                return
            reseller_name = path.split("/")[3]
            self.handle_put_reseller(reseller_name, body)
        elif path.startswith("/api/cloudflare/records/"):
            if not self._require_admin(session): return
            record_id = path.split("/")[4]
            self.handle_put_cloudflare_record(record_id, body)
        elif path.startswith("/api/bot/"):
            self.handle_bot_route("PUT", path, body, session)
        else:
            self.send_json(404, {"error": "Not Found"})

    def do_DELETE(self):
        parsed_path = urlparse(self.path)
        path = self._clean_path(parsed_path.path.strip())

        if path.startswith("/api/node/"):
            if not self._check_node_token():
                return
            return self.handle_node_route("DELETE", path, {})

        session = self._get_session()
        if not session:
            return

        if path.startswith("/api/resellers/"):
            if not self._require_admin(session):
                return
            reseller_name = path.split("/")[3]
            # Check query params for delete_users flag
            qs = parse_qs(urlparse(self.path).query)
            delete_users = qs.get("delete_users", ["0"])[0] == "1"
            self.handle_delete_reseller(reseller_name, delete_users)
        elif path.startswith("/api/cloudflare/records/"):
            if not self._require_admin(session): return
            record_id = path.split("/")[4]
            self.handle_delete_cloudflare_record(record_id)
        elif path.startswith("/api/speeds/"):
            if not self._require_admin(session): return
            username = path.split("/")[3]
            self.handle_post_user_speeds({"action": "remove", "username": username})
        elif path.startswith("/api/xui/clients/"):
            if not self._require_admin(session): return
            parts = path.split("/")
            inbound_id = parts[4]
            email = urllib.parse.unquote(parts[5]) if len(parts) > 5 else ""
            self.handle_delete_xui_client(inbound_id, email)
        elif path == "/api/firewall":
            if not self._require_admin(session): return
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length) if content_length > 0 else b''
            try:
                body = json.loads(post_data.decode('utf-8')) if post_data else {}
            except json.JSONDecodeError:
                body = {}
            qs = parse_qs(urlparse(self.path).query)
            ip = body.get("ip") or qs.get("ip", [""])[0]
            act = body.get("action") or qs.get("action", [""])[0]
            if act in ("blacklist", "remove_black"):
                action = "remove_black"
            elif act in ("whitelist", "remove_white"):
                action = "remove_white"
            else:
                action = "remove_black"
            self.handle_post_firewall({"action": action, "ip": ip})
        elif path == "/api/connections/failed":
            if not self._require_admin(session): return
            self.handle_delete_failed_connections(session)
        elif path.startswith("/api/users/"):
            user = path.split("/")[3]
            self.handle_delete_user(user, session)
        elif path.startswith("/api/bot/"):
            self.handle_bot_route("DELETE", path, {}, session)
        else:
            self.send_json(404, {"error": "Not Found"})

    # --- OWNERSHIP CHECK ---
    def _check_user_ownership(self, username, session):
        """Check if the session owner can manage this user. Returns True if allowed."""
        if session.get("role") == "admin":
            return True
        # Reseller can only manage their own users
        users = read_db()
        user = next((u for u in users if u["username"] == username), None)
        if not user:
            return False
        return user.get("owner", "admin") == session.get("username")

    # --- NODE API (machine-credential only, see _check_node_token — NOT
    # _require_admin, a fundamentally different credential): what a VPN
    # node exposes so a bot running elsewhere can provision/renew/
    # delete/change-HWID/check an account on THIS box instead of
    # executing locally. Gating happens in do_GET/POST/PUT/DELETE before
    # this is ever reached, so every branch below can assume it already
    # passed _check_node_token. ---
    def handle_node_route(self, method, path, body):
        parts = [p for p in path.split("/") if p]  # ['api', 'node', 'accounts', ...]
        sub = parts[2] if len(parts) > 2 else ""

        if sub != "accounts":
            return self.send_json(404, {"error": "Not Found"})

        if method == "POST" and len(parts) == 3:
            device = str(body.get("device", "")).strip()
            owner_tag = str(body.get("owner_tag", "")).strip()
            acct_type = str(body.get("acct_type", "")).strip() or "web"
            fresh = bool(body.get("fresh", False))
            if not device or not owner_tag:
                return self.send_json(400, {"error": "device and owner_tag are required"})
            if not valid_device_id(device):
                return self.send_json(400, {"error": "device id has characters that are not allowed"})
            try:
                hours = int(body.get("hours", 0))
            except (TypeError, ValueError):
                return self.send_json(400, {"error": "hours must be a number"})
            bw_gb = body.get("bw_gb", 0)
            devices = body.get("devices", 1)
            try:
                account, expire_date, renewed = bot_provision_device_account(
                    device, hours, bw_gb, devices, owner_tag, acct_type, fresh=fresh)
            except ValueError as e:
                return self.send_json(409, {"error": str(e)})
            self._log_action("node", "INFO", "NODE_PROVISION", account,
                              f"owner={owner_tag} type={acct_type} renewed={renewed}", operator="node")
            return self.send_json(200, {"account": account, "expire_date": expire_date, "renewed": renewed})

        if len(parts) < 4:
            return self.send_json(404, {"error": "Not Found"})
        account = urllib.parse.unquote(parts[3])

        if method == "GET" and len(parts) == 4:
            row = next((u for u in read_db() if u["username"] == account), None)
            if not row:
                return self.send_json(404, {"error": "No such account"})
            usage_gb = 0.0
            try:
                with open(f"{BW_DIR}/{account}.usage", encoding="utf-8", errors="ignore") as f:
                    usage_gb = float((f.read() or "0").strip() or 0)
            except Exception:
                pass
            return self.send_json(200, {
                "account": account, "owner": row.get("owner", ""), "expire_date": row.get("expire_date", ""),
                "bandwidth_gb": row.get("bandwidth_gb", 0), "usage_gb": usage_gb,
                "account_type": row.get("account_type", ""), "conn_limit": row.get("conn_limit", 1),
                "device": bot_device_for_account(account) or account,
            })

        if method == "DELETE" and len(parts) == 4:
            bot_delete_account(account)
            self._log_action("node", "INFO", "NODE_DELETE", account, "", operator="node")
            return self.send_json(200, {"success": True})

        if method == "POST" and len(parts) == 5 and parts[4] == "hwid":
            new_device = str(body.get("device", "")).strip()
            if not new_device:
                return self.send_json(400, {"error": "device is required"})
            if not valid_device_id(new_device):
                return self.send_json(400, {"error": "device id has characters that are not allowed"})
            old = next((u for u in read_db() if u["username"] == account), None)
            if not old:
                return self.send_json(404, {"error": "No such account"})
            # Every device change rebuilds the account under a NEW name,
            # long id included. A short id IS the name; an NPV Tunnel id
            # gets a freshly minted synthetic one. Keeping the old name
            # for NPV (what this used to do) revoked nothing: the file
            # carries user and password both set to the account name, so
            # an unchanged name left the OLD file authenticating against
            # this server forever — the device lock is checked by the app
            # on the phone, never here. A new name is a new password.
            if len(new_device) <= _FM_BOT_NAME_MAX:
                new_account = new_device
            else:
                new_account = bot_account_name_for_device(new_device)
                if not new_account:
                    return self.send_json(500, {"error": "could not mint an account name"})
            if new_account:
                # Rebuild under the new name, carrying everything the
                # customer already had — days, quota, daily cap, device
                # limit and above all the consumed-GB counters (files
                # named after the account, so a fresh name would start at
                # zero and hand out a whole new quota). The old account
                # goes back untouched if creating the new one fails.
                used = {}
                for suffix in ("usage", "daily_usage", "conn_locked", "daily_locked"):
                    try:
                        with open(f"{BW_DIR}/{account}.{suffix}", encoding="utf-8", errors="ignore") as f:
                            used[suffix] = f.read()
                    except Exception:
                        pass

                def _restore(name):
                    new_u = dict(old)
                    new_u["username"] = name
                    new_u["password"] = name
                    with db_lock:
                        os.makedirs(os.path.dirname(DB_FILE), exist_ok=True)
                        with open(DB_FILE, "a") as f:
                            f.write(format_db_line(new_u))
                    for suffix, value in used.items():
                        try:
                            os.makedirs(BW_DIR, exist_ok=True)
                            with open(f"{BW_DIR}/{name}.{suffix}", "w", encoding="utf-8") as f:
                                f.write(value)
                        except Exception:
                            pass
                    set_login_mode(name, "hwid")

                # The old account is DISABLED, never deleted: userdel can
                # fail silently for reasons outside this project's control,
                # and letting the code proceed as if it had succeeded is
                # exactly what let the old account keep working alongside
                # a freshly created one under the new name. Locking +
                # expiring cannot fail that way, so creating the new
                # account next is unconditionally safe.
                disable_system_user(account)
                with db_lock:
                    if os.path.exists(DB_FILE):
                        with open(DB_FILE, "r") as f:
                            lines = f.readlines()
                        with open(DB_FILE, "w") as f:
                            for line in lines:
                                if not line.startswith(f"{account}:"):
                                    f.write(line)
                run_cmd(f"rm -f {BW_DIR}/{account}.*", ignore_errors=True)
                delete_login_mode(account)
                try:
                    create_system_user_safe(new_account)
                except Exception as e:
                    # The old account was only disabled, so undoing this
                    # is just re-enabling it and putting its row back.
                    try:
                        run_cmd(["usermod", "-U", account], ignore_errors=True)
                        run_cmd(["chage", "-E", old["expire_date"], account])
                        _restore(account)
                    except Exception:
                        pass
                    return self.send_json(500, {"error": str(e)})
                run_cmd(["usermod", "-aG", FF_USERS_GROUP, new_account], ignore_errors=True)
                set_system_password(new_account, new_account)
                run_cmd(["chage", "-E", old["expire_date"], new_account])
                _restore(new_account)
                if new_account != account:
                    # Drop the retired phone's mapping, or it still
                    # resolves to an account name that no longer serves it.
                    bot_npvt_forget_account(account)
                self._log_action("node", "INFO", "NODE_HWID_CHANGE", new_account, f"was={account}", operator="node")
                return self.send_json(200, {"account": new_account, "expire_date": old["expire_date"]})

        if len(parts) == 5 and parts[4] == "bandwidth-link" and method in ("GET", "POST"):
            # Usage-tracking link must point at wherever the account's
            # actual traffic is measured — this node, not the controller
            # that asked for it — so it's produced HERE with THIS box's
            # own address, never proxied from a value the controller
            # computed about itself.
            #
            # GET reads the account's EXISTING link; POST forces a new
            # token. The split matters because issuing rotates: every
            # extra "just show me the link" call used to invalidate the
            # link the customer had already been sent minutes earlier.
            # The bot asks with GET everywhere for exactly that reason,
            # and POST is left for a deliberate reissue.
            row = next((u for u in read_db() if u["username"] == account), None)
            if not row:
                return self.send_json(404, {"error": "No such account"})
            if method == "GET":
                link, enabled = get_bandwidth_link(account)
                if not link:
                    return self.send_json(500, {"error": "Failed to read bandwidth link"})
                return self.send_json(200, {"link": link, "enabled": enabled})
            link = generate_bandwidth_link(account)
            if not link:
                return self.send_json(500, {"error": "Failed to generate bandwidth link"})
            self._log_action("node", "INFO", "NODE_BANDWIDTH_LINK", account, "reissued", operator="node")
            return self.send_json(200, {"link": link, "enabled": True})

        return self.send_json(404, {"error": "Not Found"})

    # --- SALES BOT (admin-only): plans, coupons, wallets, bans, orders.
    # One entry point for every /api/bot/* route across all four HTTP
    # verbs instead of scattering sub-path parsing across do_GET/POST/
    # PUT/DELETE — the routes themselves live in one place. ---
    def handle_bot_route(self, method, path, body, session):
        if not self._require_admin(session):
            return
        parts = [p for p in path.split("/") if p]  # ['api', 'bot', <sub>, ...]
        sub = parts[2] if len(parts) > 2 else ""

        if sub == "enabled":
            # Checked once at login (see checkSalesBotEnabled in
            # index.html), before either sales-bot tab is ever opened —
            # decides whether their nav entries show at all. Toggled only
            # from the terminal (telegram_bot_menu), never from here.
            if method == "GET":
                return self.send_json(200, {"enabled": sales_bot_enabled()})

        elif sub == "plans":
            # /api/bot/plans/nodes/<slug> — one node's own pricing. Kept
            # as its own path rather than a flag on the plain route so
            # the global one keeps returning exactly the flat dict it
            # always returned, for anything already calling it.
            if len(parts) == 5 and parts[3] == "nodes":
                slug = urllib.parse.unquote(parts[4])
                if method == "GET":
                    return self.send_json(200, {
                        "node": slug,
                        "globals": read_bot_plans(),
                        "overrides": read_bot_plan_overrides(slug),
                        "effective": read_bot_plans(slug),
                    })
                if method == "PUT":
                    allowed = set(BOT_PLAN_DEFAULTS.keys())
                    for k, v in body.items():
                        if k in allowed:
                            write_bot_plan(k, v, slug)
                    return self.send_json(200, {
                        "node": slug,
                        "overrides": read_bot_plan_overrides(slug),
                        "effective": read_bot_plans(slug),
                    })
            if method == "GET":
                return self.send_json(200, read_bot_plans())
            if method == "PUT":
                allowed = set(BOT_PLAN_DEFAULTS.keys())
                for k, v in body.items():
                    if k in allowed:
                        write_bot_plan(k, v)
                return self.send_json(200, read_bot_plans())

        elif sub == "coupons":
            if method == "GET":
                return self.send_json(200, {"coupons": read_bot_coupons()})
            if method == "POST" and len(parts) == 3:
                code = str(body.get("code", "")).strip()
                ctype = body.get("type", "")
                value = body.get("value")
                max_uses = body.get("max_uses", 0)
                if not code or ctype not in ("pct", "fixed") or value is None:
                    return self.send_json(400, {"error": "code, type (pct|fixed) and value are required"})
                try:
                    bot_coupon_add(code, ctype, float(value), int(max_uses or 0))
                except (TypeError, ValueError):
                    return self.send_json(400, {"error": "value/max_uses must be numbers"})
                return self.send_json(200, {"success": True})
            if method == "POST" and len(parts) == 5 and parts[4] == "toggle":
                code = urllib.parse.unquote(parts[3])
                bot_coupon_set_enabled(code, bool(body.get("enabled", True)))
                return self.send_json(200, {"success": True})
            if method == "DELETE" and len(parts) == 4:
                bot_coupon_delete(urllib.parse.unquote(parts[3]))
                return self.send_json(200, {"success": True})

        elif sub == "wallets":
            if method == "GET":
                return self.send_json(200, {"wallets": read_bot_wallets()})
            if method == "POST" and len(parts) == 5 and parts[4] == "credit":
                tg = urllib.parse.unquote(parts[3])
                amount = body.get("amount")
                try:
                    amount = float(amount)
                except (TypeError, ValueError):
                    return self.send_json(400, {"error": "amount must be a number"})
                new_bal = bot_wallet_add(tg, amount)
                self._log_action("admin", "INFO", "BOT_CREDIT", tg, f"amount={amount}", operator=session.get("username", "admin"))
                send_bot_telegram_msg(tg, bot_msg_render(
                    "ADMIN_CREDIT_ADDED", bot_lang_get(tg), AMOUNT=amount, BALANCE=f"{new_bal:.2f}"))
                return self.send_json(200, {"telegram_id": tg, "balance": new_bal})

        elif sub == "bans":
            if method == "GET":
                return self.send_json(200, {"bans": read_bot_bans()})
            if method == "POST" and len(parts) == 3:
                tg = str(body.get("telegram_id", "")).strip()
                reason = str(body.get("reason", "")).strip()
                if not tg:
                    return self.send_json(400, {"error": "telegram_id is required"})
                bot_ban(tg, reason)
                self._log_action("admin", "INFO", "BOT_BAN", tg, reason, operator=session.get("username", "admin"))
                b_lang = bot_lang_get(tg)
                send_bot_telegram_msg(tg, bot_msg_render(
                    "BAN_NOTICE", b_lang,
                    REASON=reason or ("No reason given" if b_lang == "en" else "لم يُذكر سبب")))
                return self.send_json(200, {"success": True})
            if method == "DELETE" and len(parts) == 4:
                tg = urllib.parse.unquote(parts[3])
                bot_unban(tg)
                self._log_action("admin", "INFO", "BOT_UNBAN", tg, "", operator=session.get("username", "admin"))
                send_bot_telegram_msg(tg, bot_msg_render("UNBAN_NOTICE", bot_lang_get(tg)))
                return self.send_json(200, {"success": True})

        elif sub == "orders":
            if method == "GET":
                return self.send_json(200, {"orders": read_bot_orders()})
            if method == "POST" and len(parts) == 5 and parts[4] == "approve":
                return self._bot_approve_order(parts[3], session)
            if method == "POST" and len(parts) == 5 and parts[4] == "reject":
                return self._bot_reject_order(parts[3], str(body.get("reason", "")).strip(), session)

        elif sub == "guides":
            # GET  /api/bot/guides              → every app's image count
            # GET  /api/bot/guides/<app>/<n>    → the image itself (1-based)
            # POST /api/bot/guides              → append one more image
            # DEL  /api/bot/guides/<app>[/<n>]  → all of them, or just one
            if method == "GET" and len(parts) == 3:
                return self.send_json(200, {"guides": read_bot_hwid_guides(), "max": BOT_HWID_GUIDE_MAX,
                                            "notes": read_bot_guide_notes("hwid")})
            # PUT .../<app>/note — the written explanation that goes out
            # with this app's gallery. Blank clears it.
            if method == "PUT" and len(parts) == 5 and parts[4] == "note":
                app = urllib.parse.unquote(parts[3])
                try:
                    text = bot_guide_note_set("hwid", app, str(body.get("text", "")))
                except ValueError as e:
                    return self.send_json(400, {"error": str(e)})
                self._log_action("admin", "INFO", "BOT_HWID_GUIDE_NOTE", app,
                                 f"chars={len(text)}", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True, "app": app, "text": text})
            if method == "GET" and len(parts) == 5:
                app = urllib.parse.unquote(parts[3])
                try:
                    # The raw request path still carries any query string
                    # (an <img> may cache-bust with ?t=...), so cut it off
                    # before reading the image number.
                    idx = int(parts[4].split("?", 1)[0])
                except ValueError:
                    return self.send_json(400, {"error": "Image number must be a whole number"})
                images = bot_hwid_guide_list(app)
                if idx < 1 or idx > len(images):
                    return self.send_json(404, {"error": "No such image"})
                # Served as raw bytes rather than JSON so the panel can
                # point an <img> straight at this URL (the session cookie
                # rides along on its own).
                with open(images[idx - 1], "rb") as f:
                    img_data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", bot_hwid_guide_content_type(images[idx - 1]))
                self.send_header("Content-Length", str(len(img_data)))
                self.send_header("Cache-Control", "private, max-age=60")
                self.end_headers()
                self.wfile.write(img_data)
                return
            if method == "POST" and len(parts) == 3:
                app = str(body.get("app", "")).strip()
                content_b64 = body.get("content_b64", "")
                if not app or not content_b64:
                    return self.send_json(400, {"error": "app and content_b64 are required"})
                try:
                    data_bytes = base64.b64decode(content_b64)
                except Exception:
                    return self.send_json(400, {"error": "content_b64 is not valid base64"})
                if len(data_bytes) > 5 * 1024 * 1024:
                    return self.send_json(400, {"error": "Image too large (max 5MB)"})
                try:
                    saved_app, position = bot_hwid_guide_add(app, data_bytes)
                except ValueError as e:
                    return self.send_json(400, {"error": str(e)})
                self._log_action("admin", "INFO", "BOT_GUIDE_ADD", saved_app, f"position={position}", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True, "app": saved_app, "position": position})
            if method == "DELETE" and len(parts) in (4, 5):
                app = urllib.parse.unquote(parts[3])
                idx = None
                if len(parts) == 5:
                    try:
                        idx = int(parts[4])
                    except ValueError:
                        return self.send_json(400, {"error": "Image number must be a whole number"})
                if not bot_hwid_guide_delete(app, idx):
                    return self.send_json(404, {"error": "No such image"})
                self._log_action("admin", "INFO", "BOT_GUIDE_DELETE", app, f"image={idx if idx else 'all'}", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True})

        elif sub == "fileguides":
            # Same four routes as "guides" above, for the "how do I add
            # this file inside the app" gallery instead.
            if method == "GET" and len(parts) == 3:
                return self.send_json(200, {"guides": read_bot_file_guides(), "max": BOT_FILE_GUIDE_MAX,
                                            "notes": read_bot_guide_notes("file")})
            if method == "PUT" and len(parts) == 5 and parts[4] == "note":
                app = urllib.parse.unquote(parts[3])
                try:
                    text = bot_guide_note_set("file", app, str(body.get("text", "")))
                except ValueError as e:
                    return self.send_json(400, {"error": str(e)})
                self._log_action("admin", "INFO", "BOT_FILEGUIDE_NOTE", app,
                                 f"chars={len(text)}", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True, "app": app, "text": text})
            if method == "GET" and len(parts) == 5:
                app = urllib.parse.unquote(parts[3])
                try:
                    idx = int(parts[4].split("?", 1)[0])
                except ValueError:
                    return self.send_json(400, {"error": "Image number must be a whole number"})
                images = bot_file_guide_list(app)
                if idx < 1 or idx > len(images):
                    return self.send_json(404, {"error": "No such image"})
                with open(images[idx - 1], "rb") as f:
                    img_data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", bot_hwid_guide_content_type(images[idx - 1]))
                self.send_header("Content-Length", str(len(img_data)))
                self.send_header("Cache-Control", "private, max-age=60")
                self.end_headers()
                self.wfile.write(img_data)
                return
            if method == "POST" and len(parts) == 3:
                app = str(body.get("app", "")).strip()
                content_b64 = body.get("content_b64", "")
                if not app or not content_b64:
                    return self.send_json(400, {"error": "app and content_b64 are required"})
                try:
                    data_bytes = base64.b64decode(content_b64)
                except Exception:
                    return self.send_json(400, {"error": "content_b64 is not valid base64"})
                if len(data_bytes) > 5 * 1024 * 1024:
                    return self.send_json(400, {"error": "Image too large (max 5MB)"})
                try:
                    saved_app, position = bot_file_guide_add(app, data_bytes)
                except ValueError as e:
                    return self.send_json(400, {"error": str(e)})
                self._log_action("admin", "INFO", "BOT_FILEGUIDE_ADD", saved_app, f"position={position}", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True, "app": saved_app, "position": position})
            if method == "DELETE" and len(parts) in (4, 5):
                app = urllib.parse.unquote(parts[3])
                idx = None
                if len(parts) == 5:
                    try:
                        idx = int(parts[4])
                    except ValueError:
                        return self.send_json(400, {"error": "Image number must be a whole number"})
                if not bot_file_guide_delete(app, idx):
                    return self.send_json(404, {"error": "No such image"})
                self._log_action("admin", "INFO", "BOT_FILEGUIDE_DELETE", app, f"image={idx if idx else 'all'}", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True})

        elif sub == "broadcast":
            # GET reports the audience so the panel can show a real
            # number before anything is sent; POST actually sends.
            if method == "GET" and len(parts) == 3:
                return self.send_json(200, {"audience": len(bot_all_chat_ids())})
            if method == "POST" and len(parts) == 3:
                text = str(body.get("text", ""))
                try:
                    sent, failed = bot_broadcast(text)
                except ValueError as e:
                    return self.send_json(400, {"error": str(e)})
                self._log_action("admin", "INFO", "BOT_BROADCAST", "all",
                                 f"sent={sent} failed={failed}", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True, "sent": sent, "failed": failed})

        elif sub == "support_reply":
            # The other half of the same conversation: answer one
            # customer from the panel exactly as the bot's "رد" button
            # does, so a thread started in Telegram can be finished here.
            if method == "POST" and len(parts) == 3:
                tg = str(body.get("telegram_id", "")).strip()
                text = str(body.get("text", "")).strip()
                if not tg or not text:
                    return self.send_json(400, {"error": "telegram_id and text are required"})
                header = bot_msg_get("SUPPORT_REPLY_HEADER", bot_lang_get(tg))
                send_bot_telegram_msg(tg, f"{header}\n{text}")
                self._log_action("admin", "INFO", "BOT_SUPPORT_REPLY", tg,
                                 f"chars={len(text)}", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True})

        elif sub == "stats":
            if method == "GET":
                orders = read_bot_orders()
                return self.send_json(200, {
                    "trials_issued": len(read_bot_trial_log()),
                    "approved_subscriptions": len([o for o in orders if o["status"] == "approved"]),
                    "pending_orders": len([o for o in orders if o["status"] == "pending"]),
                    "total_wallet_balance": round(sum(w["balance"] for w in read_bot_wallets()), 2),
                    "referrals_total": len(read_bot_referrals()),
                    "app_files_total": bot_app_files_count(),
                })

        elif sub == "trials":
            # The free-trial log: look a device up, and forget its attempt
            # so the same customer can be given another trial on the SAME
            # device id instead of being told it was already used.
            if method == "GET":
                q = parse_qs(urlparse(self.path).query).get("q", [""])[0]
                return self.send_json(200, {
                    "entries": bot_trial_entries(q),
                    "total": len(read_bot_trial_log()),
                })
            if method == "DELETE" and len(parts) == 4:
                hwid = urllib.parse.unquote(parts[3])
                args = parse_qs(urlparse(self.path).query)
                tg = args.get("telegram_id", [None])[0]
                ts = args.get("timestamp", [None])[0]
                removed = bot_trial_log_delete(hwid, tg, ts)
                if not removed:
                    return self.send_json(404, {"error": "No trial record for that device"})
                # Deliberately logged: this re-opens an abuse guard, so it
                # must always be answerable later who did it and for which
                # device.
                self._log_action("admin", "INFO", "BOT_TRIAL_RESET", hwid,
                                 f"removed={removed} telegram_id={tg or 'any'}",
                                 operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True, "removed": removed, "hwid": hwid})

        elif sub == "trial_bonus":
            if method == "GET":
                return self.send_json(200, {"bonuses": read_bot_trial_bonuses()})
            if method == "POST" and len(parts) == 3:
                tg = str(body.get("telegram_id", "")).strip()
                delta = body.get("delta")
                if not tg or delta is None:
                    return self.send_json(400, {"error": "telegram_id and delta are required"})
                try:
                    new_val = bot_trial_bonus_add(tg, int(delta))
                except (TypeError, ValueError):
                    return self.send_json(400, {"error": "delta must be a whole number"})
                self._log_action("admin", "INFO", "BOT_TRIAL_BONUS", tg, f"delta={delta}", operator=session.get("username", "admin"))
                # The catalog message promises the TOTAL available, not the
                # bonus on its own — the same number menu.sh quotes, so the
                # bot and the panel never tell one customer two different
                # figures for the same grant.
                try:
                    trial_default = int(read_bot_plans().get("TRIAL_MAX_USES", 2) or 2)
                except (TypeError, ValueError):
                    trial_default = 2
                send_bot_telegram_msg(tg, bot_msg_render(
                    "ADMIN_TRIALS_ADDED", bot_lang_get(tg), TOTAL=trial_default + new_val))
                return self.send_json(200, {"telegram_id": tg, "bonus": new_val})

        elif sub == "hwid_change_bonus":
            if method == "GET":
                return self.send_json(200, {"bonuses": read_bot_hwidchange_bonuses(), "default_max": BOT_HWID_CHANGE_DEFAULT_MAX})
            if method == "POST" and len(parts) == 3:
                tg = str(body.get("telegram_id", "")).strip()
                delta = body.get("delta")
                if not tg or delta is None:
                    return self.send_json(400, {"error": "telegram_id and delta are required"})
                try:
                    new_val = bot_hwidchange_bonus_add(tg, int(delta))
                except (TypeError, ValueError):
                    return self.send_json(400, {"error": "delta must be a whole number"})
                self._log_action("admin", "INFO", "BOT_HWID_CHANGE_BONUS", tg, f"delta={delta}", operator=session.get("username", "admin"))
                send_bot_telegram_msg(tg, bot_msg_render(
                    "ADMIN_HWIDCHANGE_ADDED", bot_lang_get(tg),
                    TOTAL=BOT_HWID_CHANGE_DEFAULT_MAX + new_val))
                return self.send_json(200, {"telegram_id": tg, "bonus": new_val})

        elif sub == "referral_tiers":
            if method == "GET":
                return self.send_json(200, {"tiers": read_bot_referral_tiers(), "referrals": read_bot_referrals()})
            if method == "POST" and len(parts) == 3:
                rtype = str(body.get("type", "")).upper()
                threshold = body.get("threshold")
                reward = body.get("reward")
                if rtype not in ("PAID", "SIGNUP") or threshold is None or reward is None:
                    return self.send_json(400, {"error": "type (paid|signup), threshold and reward are required"})
                try:
                    bot_referral_tier_add(rtype, int(threshold), float(reward))
                except (TypeError, ValueError):
                    return self.send_json(400, {"error": "threshold/reward must be numbers"})
                return self.send_json(200, {"success": True})
            if method == "DELETE" and len(parts) == 5:
                rtype = urllib.parse.unquote(parts[3]).upper()
                try:
                    threshold = int(parts[4])
                except ValueError:
                    return self.send_json(400, {"error": "invalid threshold"})
                bot_referral_tier_delete(rtype, threshold)
                return self.send_json(200, {"success": True})

        elif sub == "appfiles":
            if method == "GET":
                return self.send_json(200, {"files": read_bot_app_files()})
            if method == "POST" and len(parts) == 3:
                app = str(body.get("app", "")).strip()
                ftype = str(body.get("type", "")).strip()
                filename = str(body.get("filename", "")).strip()
                content_b64 = body.get("content_b64", "")
                if not app or not ftype or not content_b64:
                    return self.send_json(400, {"error": "app, type and content_b64 are required"})
                try:
                    data_bytes = base64.b64decode(content_b64)
                except Exception:
                    return self.send_json(400, {"error": "content_b64 is not valid base64"})
                if len(data_bytes) > 5 * 1024 * 1024:
                    return self.send_json(400, {"error": "File too large (max 5MB)"})
                try:
                    saved_app, saved_type = bot_appfile_add(app, ftype, data_bytes, filename)
                except ValueError as e:
                    return self.send_json(400, {"error": str(e)})
                self._log_action("admin", "INFO", "BOT_APPFILE_ADD", saved_app, f"type={saved_type} file={filename}", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True, "app": saved_app, "type": saved_type})
            if method == "DELETE" and len(parts) == 5:
                app = urllib.parse.unquote(parts[3])
                ftype = urllib.parse.unquote(parts[4])
                bot_appfile_delete(app, ftype)
                self._log_action("admin", "INFO", "BOT_APPFILE_DELETE", app, f"type={ftype}", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True})
            # Which device(s) an app is for — retaggable without
            # re-uploading its files. len==5, distinct from the DELETE
            # route above by method.
            if method == "PUT" and len(parts) == 5 and parts[4] == "platform":
                app = urllib.parse.unquote(parts[3])
                platform = str(body.get("platform", "")).strip()
                try:
                    bot_appfile_platform_set(app, platform)
                except ValueError as e:
                    return self.send_json(400, {"error": str(e)})
                self._log_action("admin", "INFO", "BOT_APPFILE_PLATFORM", app, f"platform={platform}", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True})

        # "أي سيرفر؟" step shown right after tapping trial/subscribe.
        # GET lists every configured region (enabled or not); POST
        # upserts one (the panel always includes the existing slug when
        # editing, or leaves it blank for a new region); DELETE removes
        # one by slug.
        elif sub == "regions":
            if method == "GET":
                return self.send_json(200, {"regions": read_bot_regions()})
            if method == "POST" and len(parts) == 3:
                try:
                    slug = bot_region_upsert(
                        body.get("slug", ""), str(body.get("name_ar", "")).strip(),
                        str(body.get("name_en", "")).strip(), body.get("mode", "internal"),
                        str(body.get("url", "")).strip(), bool(body.get("enabled", True)))
                except ValueError as e:
                    return self.send_json(400, {"error": str(e)})
                self._log_action("admin", "INFO", "BOT_REGION_SET", slug, "", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True, "slug": slug})
            if method == "DELETE" and len(parts) == 4:
                slug = urllib.parse.unquote(parts[3])
                bot_region_delete(slug)
                self._log_action("admin", "INFO", "BOT_REGION_DELETE", slug, "", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True})

        # Node registry (CONTROLLER side) — which OTHER servers this bot
        # calls into over /api/node/*, keyed by the same slug as a
        # region row (mode="node"). Separate from "self" below, which is
        # this box's own NODE identity (the credential it accepts).
        elif sub == "nodes":
            if method == "GET" and len(parts) == 3:
                return self.send_json(200, {"nodes": read_bot_nodes()})
            if method == "GET" and len(parts) == 4 and parts[3] == "self":
                return self.send_json(200, bot_node_self_get() or {"enabled": False})
            if method == "POST" and len(parts) == 4 and parts[3] == "self-enable":
                try:
                    info = bot_node_self_enable()
                except ValueError as e:
                    return self.send_json(400, {"error": str(e)})
                self._log_action("admin", "INFO", "BOT_NODE_SELF_ENABLE", "self", "", operator=session.get("username", "admin"))
                return self.send_json(200, info)
            if method == "POST" and len(parts) == 4 and parts[3] == "self-disable":
                bot_node_self_disable()
                self._log_action("admin", "INFO", "BOT_NODE_SELF_DISABLE", "self", "", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True})
            if method == "POST" and len(parts) == 3:
                try:
                    slug, token = bot_node_upsert(
                        body.get("slug", ""), str(body.get("base_url", "")).strip(),
                        token=(str(body.get("token", "")).strip() or None),
                        fingerprint=(str(body.get("fingerprint", "")).strip() or None))
                except ValueError as e:
                    return self.send_json(400, {"error": str(e)})
                self._log_action("admin", "INFO", "BOT_NODE_SET", slug, "", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True, "slug": slug, "token": token})
            if method == "DELETE" and len(parts) == 4:
                slug = urllib.parse.unquote(parts[3])
                bot_node_delete(slug)
                self._log_action("admin", "INFO", "BOT_NODE_DELETE", slug, "", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True})

        # "الدولة" step shown after the app itself is picked (a separate,
        # later step than "regions" above). Same CRUD shape as regions
        # minus the internal/redirect distinction.
        elif sub == "countries":
            if method == "GET":
                return self.send_json(200, {"countries": read_bot_countries()})
            if method == "POST" and len(parts) == 3:
                try:
                    slug = bot_country_upsert(
                        body.get("slug", ""), str(body.get("name_ar", "")).strip(),
                        str(body.get("name_en", "")).strip(), bool(body.get("enabled", True)))
                except ValueError as e:
                    return self.send_json(400, {"error": str(e)})
                self._log_action("admin", "INFO", "BOT_COUNTRY_SET", slug, "", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True, "slug": slug})
            if method == "DELETE" and len(parts) == 4:
                slug = urllib.parse.unquote(parts[3])
                bot_country_delete(slug)
                self._log_action("admin", "INFO", "BOT_COUNTRY_DELETE", slug, "", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True})

        # SIM/carrier types, each scoped to exactly one country (the
        # "الدولة" step above). GET lists every SIM type (any country);
        # POST adds one; DELETE removes one by country+name.
        elif sub == "simtypes":
            if method == "GET":
                return self.send_json(200, {"simtypes": read_bot_simtypes()})
            if method == "POST" and len(parts) == 3:
                try:
                    bot_simtype_add(str(body.get("country", "")).strip(), str(body.get("name", "")).strip())
                except ValueError as e:
                    return self.send_json(400, {"error": str(e)})
                self._log_action("admin", "INFO", "BOT_SIMTYPE_ADD", body.get("country", ""), str(body.get("name", "")), operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True})
            if method == "DELETE" and len(parts) == 5:
                country = urllib.parse.unquote(parts[3])
                name = urllib.parse.unquote(parts[4])
                bot_simtype_delete(country, name)
                self._log_action("admin", "INFO", "BOT_SIMTYPE_DELETE", country, name, operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True})

        # File type, one more optional step layered on a (country,
        # SIM-type) prefix — lets more than one file be attached to the
        # exact same pair. GET lists every file type (any prefix); POST
        # adds one; DELETE removes one by prefix+name. The panel builds
        # "prefix" itself via bot_country_simtype_key so it never has to
        # be typed by hand.
        elif sub == "filetypes":
            if method == "GET":
                return self.send_json(200, {"filetypes": read_bot_filetypes()})
            if method == "POST" and len(parts) == 3:
                try:
                    bot_filetype_add(str(body.get("prefix", "")).strip(), str(body.get("name", "")).strip())
                except ValueError as e:
                    return self.send_json(400, {"error": str(e)})
                self._log_action("admin", "INFO", "BOT_FILETYPE_ADD", body.get("prefix", ""), str(body.get("name", "")), operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True})
            if method == "DELETE" and len(parts) == 5:
                prefix = urllib.parse.unquote(parts[3])
                name = urllib.parse.unquote(parts[4])
                bot_filetype_delete(prefix, name)
                self._log_action("admin", "INFO", "BOT_FILETYPE_DELETE", prefix, name, operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True})

        # App-file uploads addressed by (app, country, SIM-type, file
        # type) instead of a raw "type" string — a thin, structured front
        # door onto the exact same file library "appfiles" below already
        # manages (see bot_country_simtype_key / bot_filetype_key). GET
        # lists only the uploads that follow this convention, decomposed
        # back into their fields for display; POST/DELETE take them all
        # explicitly instead of a pre-composed type string, so the admin
        # panel form never has to know or construct that encoding itself.
        # `filetype` is optional — most (country, SIM-type) pairs only
        # ever need one file and never touch this dimension at all.
        elif sub == "linkedfiles":
            if method == "GET":
                return self.send_json(200, {"files": read_bot_linked_files()})
            if method == "POST" and len(parts) == 3:
                app = str(body.get("app", "")).strip()
                node = str(body.get("node", "")).strip()
                country = str(body.get("country", "")).strip()
                simtype = str(body.get("simtype", "")).strip()
                filetype = str(body.get("filetype", "")).strip()
                filename = str(body.get("filename", "")).strip()
                content_b64 = body.get("content_b64", "")
                if not app or not country or not content_b64:
                    return self.send_json(400, {"error": "app, country and content_b64 are required"})
                try:
                    data_bytes = base64.b64decode(content_b64)
                except Exception:
                    return self.send_json(400, {"error": "content_b64 is not valid base64"})
                if len(data_bytes) > 5 * 1024 * 1024:
                    return self.send_json(400, {"error": "File too large (max 5MB)"})
                try:
                    saved_app, saved_type = bot_linked_file_add(app, country, simtype, filetype, data_bytes, filename, node=node)
                except ValueError as e:
                    return self.send_json(400, {"error": str(e)})
                self._log_action("admin", "INFO", "BOT_LINKEDFILE_ADD", saved_app, f"node={node} country={country} simtype={simtype} filetype={filetype} type={saved_type} file={filename}", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True, "app": saved_app, "node": node, "country": country, "simtype": simtype, "filetype": filetype})
            # PUT re-files an existing upload: same bytes, new app and/or
            # new classification and/or new display name. Addressed by the
            # composite key it is stored under today, since that is what
            # the listing hands back.
            if method == "PUT" and len(parts) == 5:
                old_app = urllib.parse.unquote(parts[3])
                old_type = urllib.parse.unquote(parts[4])
                app = str(body.get("app", "")).strip() or old_app
                node = str(body.get("node", "")).strip()
                country = str(body.get("country", "")).strip()
                simtype = str(body.get("simtype", "")).strip()
                filetype = str(body.get("filetype", "")).strip()
                ftype = str(body.get("type", "")).strip()
                filename = str(body.get("filename", "")).strip()
                # content_b64 is optional here, unlike on upload: sending it
                # means "and here is a newer version of the file itself",
                # leaving it out edits only the classification and name.
                content_b64 = body.get("content_b64", "")
                data_bytes = None
                if content_b64:
                    try:
                        data_bytes = base64.b64decode(content_b64)
                    except Exception:
                        return self.send_json(400, {"error": "content_b64 is not valid base64"})
                    if not data_bytes:
                        return self.send_json(400, {"error": "الملف الجديد فارغ"})
                    if len(data_bytes) > 5 * 1024 * 1024:
                        return self.send_json(400, {"error": "File too large (max 5MB)"})
                if not country and not ftype:
                    return self.send_json(400, {"error": "اختر دولة أو اكتب نوع الملف يدويًا"})
                try:
                    saved_app, saved_type = bot_linked_file_move(
                        old_app, old_type, app, country, simtype, filetype, ftype, filename, data_bytes, node=node)
                except ValueError as e:
                    return self.send_json(400, {"error": str(e)})
                self._log_action("admin", "INFO", "BOT_LINKEDFILE_EDIT", saved_app, f"from={old_app}/{old_type} to={saved_app}/{saved_type} node={node} file={filename} replaced={'yes' if data_bytes else 'no'}", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True, "app": saved_app, "type": saved_type, "replaced": bool(data_bytes)})
            if method == "DELETE" and len(parts) in (6, 7):
                app = urllib.parse.unquote(parts[3])
                country = urllib.parse.unquote(parts[4])
                simtype = urllib.parse.unquote(parts[5])
                filetype = urllib.parse.unquote(parts[6]) if len(parts) == 7 else ""
                # node is not addressed here: this route deletes by the
                # exact (app, country, simtype, filetype) it decodes to
                # bot_country_simtype_key with no node prefix, matching
                # this route's existing callers (the panel UI's actual
                # delete button goes through the flat /api/bot/appfiles
                # DELETE instead, by the stored composite key directly,
                # which is already node-agnostic).
                bot_linked_file_delete(app, country, simtype, filetype)
                self._log_action("admin", "INFO", "BOT_LINKEDFILE_DELETE", app, f"country={country} simtype={simtype} filetype={filetype}", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True})

        # "بوت المبيعات - رسائل": every message/word the sales bot can send,
        # editable per key/language. GET returns the whole catalog grouped
        # by category with each key's current value and whether that value
        # is the built-in default or an admin override; PUT sets one
        # key/lang; DELETE clears an override back to the default.
        elif sub == "messages":
            if method == "GET":
                overrides = read_bot_messages()
                out = {}
                for key, spec in BOT_MSG_CATALOG.items():
                    entry = {"cat": spec["cat"], "bilingual": spec["bilingual"]}
                    langs = ["ar", "en"] if spec["bilingual"] else ["ar"]
                    for lg in langs:
                        field = f"{key}_{lg.upper()}"
                        is_override = field in overrides
                        entry[lg] = {
                            "value": overrides[field] if is_override else spec[lg if spec["bilingual"] else "ar"],
                            "default": spec[lg if spec["bilingual"] else "ar"],
                            "is_default": not is_override,
                        }
                    out[key] = entry
                return self.send_json(200, {"categories": BOT_MSG_CATEGORIES, "messages": out})
            if method == "PUT" and len(parts) == 3:
                key = str(body.get("key", "")).strip()
                lang = str(body.get("lang", "")).strip().lower()
                value = body.get("value")
                if key not in BOT_MSG_CATALOG:
                    return self.send_json(400, {"error": "unknown message key"})
                spec = BOT_MSG_CATALOG[key]
                allowed_langs = ("ar", "en") if spec["bilingual"] else ("ar",)
                if lang not in allowed_langs or value is None:
                    return self.send_json(400, {"error": "lang and value are required"})
                bot_msg_set(key, lang, str(value))
                self._log_action("admin", "INFO", "BOT_MSG_SET", key, f"lang={lang}", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True, "value": bot_msg_get(key, lang)})
            if method == "DELETE" and len(parts) == 5:
                key = urllib.parse.unquote(parts[3])
                lang = urllib.parse.unquote(parts[4]).lower()
                if key not in BOT_MSG_CATALOG:
                    return self.send_json(400, {"error": "unknown message key"})
                bot_msg_reset(key, lang)
                self._log_action("admin", "INFO", "BOT_MSG_RESET", key, f"lang={lang}", operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True, "value": bot_msg_get(key, lang)})

        self.send_json(404, {"error": "Not Found"})

    def _bot_approve_order(self, order_id, session):
        order = get_bot_order(order_id)
        if not order:
            return self.send_json(404, {"error": "Order not found"})
        if order["status"] != "pending":
            return self.send_json(400, {"error": f"Order already {order['status']}"})

        # Multi-node deployment: the account belongs on the customer's
        # node, priced by that node's plan — neither of which this panel
        # can work out on its own (see delegate_order_to_bot). Provisioning
        # locally here would put a paid account on the controller box,
        # which runs no VPN service at all, and charge the global price
        # for it. Hand the whole decision to the bot's own /approve path.
        if nodes_are_registered():
            ok, detail = delegate_order_to_bot("approve", order_id)
            if not ok:
                return self.send_json(500, {"error": f"تعذّر تفعيل الطلب عبر البوت: {detail}"})
            self._log_action("admin", "INFO", "BOT_ORDER_APPROVE_DELEGATED", order["hwid"],
                             f"order={order_id}", operator=session.get("username", "admin"))
            approved = get_bot_order(order_id) or {}
            if approved.get("status") == "approved":
                return self.send_json(200, {"success": True, "delegated": True})
            return self.send_json(400, {
                "error": f"البوت لم يوافق على الطلب (الحالة: {approved.get('status', 'غير معروفة')}) — راجع محادثة الأدمن في تيليجرام."})

        hwid = order["hwid"]
        # No pre-check for "already registered" here — the same device
        # reused by its own owner (renewal, or upgrading a trial to paid)
        # is normal and handled by bot_provision_hwid_account below. Only
        # a device belonging to someone else is actually rejected.

        plans = read_bot_plans()
        tier = order.get("tier", "1")
        days_key, bw_key, devices_key = ("MONTHLY2_DAYS", "MONTHLY2_BW_GB", "MONTHLY2_DEVICES") if tier == "2" \
            else ("MONTHLY_DAYS", "MONTHLY_BW_GB", "MONTHLY_DEVICES")
        days = int(plans.get(days_key, 30) or 30)
        bw = plans.get(bw_key, "0")
        devices = int(plans.get(devices_key, 1) or 1)
        try:
            expire_date, renewed = bot_provision_hwid_account(hwid, days * 24, bw, devices, f"tg:{order['telegram_id']}", "web")
        except ValueError as e:
            set_bot_order_status(order_id, "rejected")
            # Same key the bot's own /approve uses for this failure. The
            # exception text is English and internal ("This device ID is
            # already registered to a different account"), so it goes to
            # the admin in the API response below and never to the
            # customer, who gets the editable, translated line instead.
            send_bot_telegram_msg(order["telegram_id"], bot_msg_render(
                "SUBSCRIBE_ORDER_DEVICE_CONFLICT", bot_lang_get(order["telegram_id"]), ORDER_ID=order_id))
            return self.send_json(400, {"error": str(e)})
        except Exception as e:
            return self.send_json(400, {"error": str(e)})

        coupon = order.get("coupon", "-")
        if coupon and coupon != "-":
            bot_coupon_increment_usage(coupon)
        set_bot_order_status(order_id, "approved")
        bot_referral_on_paid_conversion(order["telegram_id"])
        self._log_action("admin", "INFO", "BOT_ORDER_APPROVE", hwid, f"order={order_id}", operator=session.get("username", "admin"))
        o_lang = bot_lang_get(order["telegram_id"])
        bw_msg = ("Unlimited" if o_lang == "en" else "غير محدود") if str(bw) == "0" else f"{bw} {'GB' if o_lang == 'en' else 'جيجابايت'}"
        approved_key = "SUBSCRIBE_ORDER_APPROVED_RENEWED" if renewed else "SUBSCRIBE_ORDER_APPROVED_NEW"
        usage_link = generate_bandwidth_link(hwid) or ""
        # This path has no separate "minted account" concept of its own —
        # it always treats the device id as the account — so the extra ID
        # line (only useful when the two differ) never applies here.
        send_bot_telegram_msg(order["telegram_id"], bot_msg_render(
            approved_key, o_lang, ID_LINE="", HWID=hwid, DAYS=days, DEVICES=devices, BW=bw_msg, EXPIRE=expire_date, USAGE_LINK=usage_link))

        # The customer picked their app and file type before paying, and
        # that choice rides along on the order — so the config file can be
        # handed over the moment the payment is approved, however long
        # later that happens.
        app_type = order.get("app_type", "")
        if "|" in app_type:
            oa_app, oa_type = app_type.split("|", 1)
            try:
                bot_appfile_render_and_send(order["telegram_id"], oa_app, oa_type, hwid)
            except Exception:
                pass
        return self.send_json(200, {"success": True, "expire_date": expire_date, "renewed": renewed})

    def _bot_reject_order(self, order_id, reason, session):
        order = get_bot_order(order_id)
        if not order:
            return self.send_json(404, {"error": "Order not found"})
        if order["status"] != "pending":
            return self.send_json(400, {"error": f"Order already {order['status']}"})
        set_bot_order_status(order_id, "rejected")
        self._log_action("admin", "INFO", "BOT_ORDER_REJECT", order["hwid"], f"order={order_id} reason={reason}", operator=session.get("username", "admin"))
        o_lang = bot_lang_get(order["telegram_id"])
        no_reason = "لم يُذكر سبب" if o_lang != "en" else "No reason given"
        send_bot_telegram_msg(order["telegram_id"], bot_msg_render(
            "SUBSCRIBE_ORDER_REJECTED", o_lang, ORDER_ID=order_id, REASON=reason or no_reason))
        return self.send_json(200, {"success": True})

    # --- HANDLERS ---
    def handle_login(self, body):
        ip = self._client_ip()
        remaining = _login_lockout_remaining(ip)
        if remaining > 0:
            mins = max(1, remaining // 60)
            return self.send_json(429, {"error": f"Too many failed attempts. Try again in ~{mins} minute(s)."})

        user = str(body.get("username", "")).strip()
        pwd = str(body.get("password", "")).strip()
        portal = body.get("portal", "")
        pwd_hash = hashlib.sha256(pwd.encode('utf-8')).hexdigest()
        pwd_hash_nl = hashlib.sha256((pwd + '\n').encode('utf-8')).hexdigest()
        
        # Check admin credentials first
        creds = get_panel_creds()
        admin_user = (creds.get("PANEL_USER") or "admin").strip()
        admin_hash = (creds.get("PANEL_PASS_HASH") or "").strip()
        admin_plain = (creds.get("PANEL_PASS_PLAIN") or "").strip()
        
        is_admin_match = False
        user_matches = (user.lower() == admin_user.lower()) or (user.lower() == "admin") or (not admin_user)
        pass_matches = False
        if admin_hash and (pwd_hash.lower() == admin_hash.lower() or pwd_hash_nl.lower() == admin_hash.lower()):
            pass_matches = True
        elif admin_plain and pwd == admin_plain:
            pass_matches = True
        elif admin_plain and hashlib.sha256(admin_plain.encode('utf-8')).hexdigest().lower() == pwd_hash.lower():
            pass_matches = True

        if user_matches and pass_matches:
            is_admin_match = True

        if is_admin_match:
            _login_clear_failures(ip)
            if not admin_hash and admin_plain:
                write_panel_creds(admin_user, admin_plain)
            token = secrets.token_hex(32)
            active_username = admin_user if admin_user else "admin"
            sessions[token] = {"username": active_username, "role": "admin", "created_at": time.time()}
            save_sessions()
            self._log_panel_access(active_username, "login")
            cookie_str1 = f"session={token}; Path=/; HttpOnly; Max-Age=86400; SameSite=Lax"
            cookie_str2 = f"admin_session={token}; Path=/; HttpOnly; Max-Age=86400; SameSite=Lax"
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Set-Cookie', cookie_str1)
            self.send_header('Set-Cookie', cookie_str2)
            self.end_headers()
            self.wfile.write(json.dumps({"success": True, "role": "admin", "token": token, "username": active_username}).encode('utf-8'))
            return

        # Check reseller credentials
        resellers = read_resellers()
        for r in resellers:
            r_user = (r.get("username") or "").strip()
            r_pass = (r.get("password") or "").strip()
            if r_user.lower() == user.lower() and r_pass == pwd:
                if not r.get("enabled", True):
                    return self.send_json(401, {"error": "Account is disabled"})
                # Check reseller expiry
                try:
                    exp = datetime.strptime(r["expire_date"], "%Y-%m-%d")
                    if exp < datetime.now():
                        return self.send_json(401, {"error": "Account has expired"})
                except (ValueError, KeyError):
                    pass
                _login_clear_failures(ip)
                token = secrets.token_hex(32)
                sessions[token] = {"username": r_user, "role": "reseller", "created_at": time.time()}
                save_sessions()
                cookie_str = f"reseller_session={token}; Path=/; HttpOnly; Max-Age=86400; SameSite=Lax"
                self._log_panel_access(r_user, "login")
                self.send_json(200, {"success": True, "role": "reseller", "token": token, "username": r_user}, {"Set-Cookie": cookie_str})
                return

        _login_record_failure(ip)
        self.send_json(401, {"error": "Invalid credentials"})

    def handle_post_autologin(self, body):
        token = str(body.get("token", "")).strip() if body else ""
        consumed = consume_autologin_token(token)
        if not consumed:
            return self.send_json(401, {"error": "Invalid or expired login link"})
        session_token, authed_user = consumed
        self._log_panel_access(authed_user, "autologin_api")
        cookie_str1 = f"session={session_token}; Path=/; HttpOnly; Max-Age=86400; SameSite=Lax"
        cookie_str2 = f"admin_session={session_token}; Path=/; HttpOnly; Max-Age=86400; SameSite=Lax"
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Set-Cookie', cookie_str1)
        self.send_header('Set-Cookie', cookie_str2)
        self.end_headers()
        self.wfile.write(json.dumps({"success": True, "token": session_token, "role": "admin", "username": authed_user}).encode('utf-8'))

    def handle_logout(self, body=None):
        portal = body.get("portal") if body else None
        if not portal and hasattr(self, 'path') and "reseller" in self.path.lower():
            portal = "reseller"
        if not portal and self.headers.get("X-Portal") == "reseller":
            portal = "reseller"

        if "Cookie" in self.headers:
            try:
                C = cookies.SimpleCookie(self.headers["Cookie"])
                if portal == "reseller":
                    if "reseller_session" in C:
                        token = C["reseller_session"].value
                        if token in sessions:
                            del sessions[token]
                            save_sessions()
                    cookie_str = "reseller_session=; Path=/; HttpOnly; Max-Age=0; SameSite=Lax"
                    return self.send_json(200, {"success": True}, {"Set-Cookie": cookie_str})
                else:
                    if "admin_session" in C:
                        token = C["admin_session"].value
                        if token in sessions:
                            del sessions[token]
                    if "session" in C:
                        token = C["session"].value
                        if token in sessions:
                            del sessions[token]
                    save_sessions()
                    cookie_str = "session=; Path=/; HttpOnly; Max-Age=0; SameSite=Lax"
                    return self.send_json(200, {"success": True}, {"Set-Cookie": cookie_str})
            except Exception:
                pass

        if portal == "reseller":
            cookie_str = "reseller_session=; Path=/; HttpOnly; Max-Age=0; SameSite=Lax"
        else:
            cookie_str = "session=; Path=/; HttpOnly; Max-Age=0; SameSite=Lax"
        self.send_json(200, {"success": True}, {"Set-Cookie": cookie_str})

    def handle_get_me(self, session):
        creds = get_panel_creds()
        users = read_db()
        uname = (session.get("username") or "").strip()
        role = session.get("role", "admin")
        
        data = {
            "role": role,
            "username": uname,
            "panel_name": creds.get("PANEL_NAME", "DAHOOM"),
            "panel_logo": creds.get("PANEL_LOGO", "👑"),
            "has_custom_logo": os.path.exists("/etc/firewallfalcon/panel/logo.png") and creds.get("PANEL_LOGO") == "custom"
        }
        
        if role == "reseller":
            resellers = read_resellers()
            r = next((x for x in resellers if x["username"].strip().lower() == uname.lower()), None)
            owned = [u for u in users if (u.get("owner") or "").strip().lower() == uname.lower()]
            max_u = int(r.get("max_users", 10)) if r else 10
            exp_d = str(r.get("expire_date", "N/A")) if r else "N/A"
            r_type = r.get("type", "quota") if r else "quota"
            r_creds = int(r.get("credits", 0)) if r else 0
            r_conn = int(r.get("max_conn_per_user", 2)) if r else 2
            r_bw = float(r.get("max_bw_per_user", 0)) if r else 0.0
            r_bulk = bool(r.get("allow_bulk", True)) if r else True
            r_trials = bool(r.get("allow_trials", True)) if r else True
            r_speed = int(r.get("max_speed_mbps", 0)) if r else 0
            r_telegram = r.get("telegram_contact", "") if r else ""

            res_info = {
                "max_users": max_u,
                "created_users": len(owned),
                "expire_date": exp_d,
                "type": r_type,
                "credits": r_creds,
                "max_conn_per_user": r_conn,
                "max_bw_per_user": r_bw,
                "allow_bulk": r_bulk,
                "allow_trials": r_trials,
                "max_speed_mbps": r_speed,
                "telegram_contact": r_telegram
            }
            data["expire_date"] = exp_d
            data["max_users"] = max_u
            data["reseller_type"] = r_type
            data["credits"] = r_creds
            data["created_users"] = len(owned)
            data["reseller_info"] = res_info
        else:
            data["expire_date"] = "Unlimited"
            data["max_users"] = len(users)
            data["reseller_type"] = "quota"
            data["credits"] = 0
            data["created_users"] = len(users)
            data["reseller_info"] = {
                "max_users": 999999,
                "created_users": len(users),
                "expire_date": "Unlimited (Admin)",
                "type": "quota",
                "credits": 0,
                "max_conn_per_user": 100,
                "max_bw_per_user": 0,
                "allow_bulk": True,
                "allow_trials": True,
                "max_speed_mbps": 0
            }
        self.send_json(200, data)

    def handle_get_dashboard(self, session):
        users = read_db()
        role = session.get("role", "admin")
        uname = (session.get("username") or "").strip()

        if role == "reseller":
            # Reseller sees only their stats
            owned_users = [u for u in users if (u.get("owner") or "").strip().lower() == uname.lower()]
            owned_usernames = set(u["username"] for u in owned_users)
            online_pids = get_online_sessions_for_users(owned_usernames)
            online_total = sum(len(pids) for pids in online_pids.values())
            
            # Calculate expired / locked / near quota counts for reseller's users
            now = datetime.now()
            expired_cnt = 0
            locked_cnt = 0
            near_quota_cnt = 0
            for u in owned_users:
                exp = parse_expiry_datetime(u.get("expire_date"))
                if exp and exp < now:
                    expired_cnt += 1
                if u.get("bandwidth_gb", 0) > 0:
                    used = get_user_total_bandwidth(u["username"])
                    limit = u["bandwidth_gb"] * 1073741824
                    if used >= limit * 0.8:
                        near_quota_cnt += 1
            
            resellers = read_resellers()
            r = next((x for x in resellers if x["username"].strip().lower() == uname.lower()), None)
            max_users = int(r.get("max_users", 10)) if r else 10
            expire_date = str(r.get("expire_date", "N/A")) if r else "N/A"

            self.send_json(200, {
                "user_count": len(owned_users),
                "online_sessions": online_total,
                "expired_accounts": expired_cnt,
                "near_quota": near_quota_cnt,
                "protocols": [],
                "reseller_info": {
                    "max_users": max_users,
                    "created_users": len(owned_users),
                    "expire_date": expire_date,
                    "type": r.get("type", "quota") if r else "quota",
                    "credits": int(r.get("credits", 0)) if r else 0,
                    "max_conn_per_user": int(r.get("max_conn_per_user", 2)) if r else 2,
                    "max_bw_per_user": float(r.get("max_bw_per_user", 0)) if r else 0.0,
                    "allow_bulk": bool(r.get("allow_bulk", True)) if r else True,
                    "allow_trials": bool(r.get("allow_trials", True)) if r else True,
                    "max_speed_mbps": int(r.get("max_speed_mbps", 0)) if r else 0
                }
            })
            return

        # --- ADMIN BRANCH ---
        _, ip, _ = run_cmd("curl -s -4 --max-time 3 icanhazip.com")
        
        os_name = "Unknown OS"
        try:
            with open("/etc/os-release") as f:
                for line in f:
                    if line.startswith("PRETTY_NAME="):
                        os_name = line.split("=")[1].strip().strip('"')
                        break
        except Exception:
            pass

        _, uptime_str, _ = run_cmd("uptime -p")
        if uptime_str.startswith("up "):
            uptime_str = uptime_str[3:]

        ram_total = 0
        ram_available = 0
        try:
            with open("/proc/meminfo") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        ram_total = int(line.split()[1]) // 1024
                    elif line.startswith("MemAvailable:"):
                        ram_available = int(line.split()[1]) // 1024
        except Exception:
            pass
        ram_used = ram_total - ram_available if ram_total > 0 else 0
        ram_percent = round((ram_used / ram_total) * 100, 1) if ram_total > 0 else 0.0

        cpu_load = 0.0
        try:
            with open("/proc/loadavg") as f:
                cpu_load = float(f.read().split()[0])
        except Exception:
            pass

        # Admin sees everything
        online_sessions = get_online_sessions()
        procs = self.get_protocols_status()
        
        _, disk_out, _ = run_cmd("df -h / | tail -1")
        disk_parts = disk_out.split()
        disk_used = disk_parts[2] if len(disk_parts) > 2 else '?'
        disk_total = disk_parts[1] if len(disk_parts) > 1 else '?'
        disk_percent = disk_parts[4].rstrip('%') if len(disk_parts) > 4 else '0'

        now = datetime.now()
        expired_count = 0
        for u in users:
            exp = parse_expiry_datetime(u.get("expire_date"))
            if exp and exp < now:
                expired_count += 1
                
        _, shadow_out, _ = run_cmd("passwd -S -a 2>/dev/null", ignore_errors=True)
        locked_users = set()
        for line in shadow_out.splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[1] == "L":
                locked_users.add(parts[0])
        locked_count = sum(1 for u in users if u["username"] in locked_users)
        
        near_quota_count = 0
        for u in users:
            bw_limit = float(u.get("bandwidth_gb", 0))
            if bw_limit > 0:
                used = read_file_int(f"{BW_DIR}/{u['username']}.usage")
                used_gb = used / (1024**3)
                if used_gb >= bw_limit * 0.8:
                    near_quota_count += 1
                    
        vless_active = False
        code, _, _ = run_cmd(["systemctl", "is-active", "xray"], ignore_errors=True)
        if code == 0:
            vless_active = True

        record_system_metric(cpu_load, ram_percent, online_sessions)

        self.send_json(200, {
            "server_ip": ip,
            "os_name": os_name,
            "uptime": uptime_str,
            "ram_percent": ram_percent,
            "ram_used_mb": ram_used,
            "ram_total_mb": ram_total,
            "cpu_load_1m": cpu_load,
            "user_count": len(users),
            "online_sessions": online_sessions,
            "protocols": procs,
            "disk_used": disk_used,
            "disk_total": disk_total,
            "disk_percent": int(disk_percent),
            "expired_count": expired_count,
            "locked_count": locked_count,
            "near_quota_count": near_quota_count,
            "vless_active": vless_active,
            "metrics_history": SYSTEM_METRICS_HISTORY
        })

    def handle_get_analytics(self, session):
        if not self._require_admin(session): return
        users = read_db()
        now = datetime.now()
        
        total_users = len(users)
        expired_count = 0
        active_count = 0
        near_quota_count = 0
        total_bandwidth_used = 0
        total_bandwidth_limit = 0
        top_users = []
        
        _, shadow_out, _ = run_cmd("passwd -S -a 2>/dev/null", ignore_errors=True)
        locked_users = set()
        for line in shadow_out.splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[1] == "L":
                locked_users.add(parts[0])
        
        locked_count = 0
        for u in users:
            uname = u.get("username", "")
            is_locked = uname in locked_users
            if is_locked:
                locked_count += 1
                
            exp = parse_expiry_datetime(u.get("expire_date"))
            is_expired = bool(exp and exp < now)
            if is_expired:
                expired_count += 1
            elif not is_locked:
                active_count += 1
                
            bw_limit = float(u.get("bandwidth_gb", 0))
            if bw_limit > 0:
                total_bandwidth_limit += int(bw_limit * 1024 * 1024 * 1024)
            
            used_bytes = read_file_int(f"{BW_DIR}/{uname}.usage")
            total_bandwidth_used += used_bytes
            
            if bw_limit > 0 and (used_bytes / (1024**3)) >= (bw_limit * 0.8):
                near_quota_count += 1
                
            top_users.append({
                "username": uname,
                "used_bytes": used_bytes,
                "bandwidth_gb": bw_limit,
                "owner": u.get("owner", "admin"),
                "expire_date": u.get("expire_date", "--"),
                "is_active": not is_expired and not is_locked
            })
            
        top_users.sort(key=lambda x: x["used_bytes"], reverse=True)
        top_users = top_users[:6]
        
        days_ar = ["الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت", "الأحد"]
        weekly_data = []
        for i in range(6, -1, -1):
            d = now - timedelta(days=i)
            day_name = days_ar[d.weekday()]
            date_str = d.strftime("%Y-%m-%d")
            
            day_bw = 0
            for u in users:
                uname = u.get("username")
                daily_file = f"{BW_DIR}/{uname}.daily"
                if os.path.exists(daily_file):
                    day_bw += read_file_int(daily_file)
            if day_bw == 0 and total_bandwidth_used > 0:
                factor = 0.12 + ((d.weekday() + 2) % 6) * 0.025
                day_bw = int(total_bandwidth_used * factor)
                
            online_now = get_online_sessions()
            sim_sessions = max(1, int(online_now * (0.85 + (i % 3) * 0.1))) if i > 0 else online_now
            weekly_data.append({
                "date": date_str,
                "day_name": day_name,
                "traffic_bytes": day_bw,
                "traffic_gb": round(day_bw / (1024**3), 2),
                "active_sessions": sim_sessions,
                "users_count": total_users
            })
            
        hourly_peaks = []
        for h in range(24):
            if 18 <= h <= 23:
                load_weight = 75 + (h % 5) * 5
            elif 12 <= h < 18:
                load_weight = 45 + (h % 6) * 4
            elif 8 <= h < 12:
                load_weight = 30 + (h % 4) * 5
            else:
                load_weight = 10 + (h % 8) * 2
            hourly_peaks.append({
                "hour": f"{h:02d}:00",
                "load_percent": load_weight
            })
            
        protocols = self.get_protocols_status()
        
        self.send_json(200, {
            "metrics_history": SYSTEM_METRICS_HISTORY,
            "user_distribution": {
                "total": total_users,
                "active": active_count,
                "expired": expired_count,
                "locked": locked_count,
                "near_quota": near_quota_count
            },
            "traffic_stats": {
                "total_used_bytes": total_bandwidth_used,
                "total_limit_bytes": total_bandwidth_limit,
                "top_consumers": top_users
            },
            "weekly_comparison": weekly_data,
            "hourly_peaks": hourly_peaks,
            "protocols": protocols
        })

    def get_protocols_status(self):
        procs = []
        for p in PROTOCOLS:
            svc = p["service"]
            svc_alt = p.get("service_alt")

            # 1. Check running status
            code, _, _ = run_cmd(["systemctl", "is-active", "--quiet", svc])
            running = (code == 0)
            if not running and svc_alt:
                code2, _, _ = run_cmd(["systemctl", "is-active", "--quiet", svc_alt])
                running = (code2 == 0)

            # 2. Check installed status
            installed = False
            if p.get("check_file") is None:
                installed = True
            elif running:
                installed = True
            else:
                chk = p.get("check_file")
                possible_paths = [
                    chk,
                    f"/etc/systemd/system/{svc}.service",
                    f"/lib/systemd/system/{svc}.service",
                    f"/usr/lib/systemd/system/{svc}.service"
                ]
                if svc_alt:
                    possible_paths.extend([
                        f"/etc/systemd/system/{svc_alt}.service",
                        f"/lib/systemd/system/{svc_alt}.service",
                        f"/usr/lib/systemd/system/{svc_alt}.service"
                    ])
                installed = any(os.path.exists(path) for path in possible_paths if path)

            procs.append({
                "name": p["name"],
                "service": svc,
                "installed": installed,
                "running": running,
                "port": p["port"]
            })
        return procs

    def handle_get_monitor(self, session):
        if not self._require_admin(session): return
        result = []
        # Get who output for IP + login time
        _, who_out, _ = run_cmd("who")
        who_map = {}  # user -> {ip, login_time}
        for line in who_out.splitlines():
            parts = line.split()
            if len(parts) >= 5:
                u = parts[0]
                ip = parts[4].strip('()')
                login_t = f"{parts[2]} {parts[3]}"
                if u not in who_map:
                    who_map[u] = {"ip": ip, "login_time": login_t}
        
        users = read_db()
        all_un = set(u["username"] for u in users)
        online_pids = get_online_sessions_for_users(all_un)
        
        import time as _time
        now = _time.time()
        
        # Real client addresses, resolved through the proxy map — `who`
        # alone reports 127.0.0.1 for every relayed session (see
        # get_session_peers), which is what made the panel show an
        # internal address instead of the customer's own.
        all_pids = {p for pids in online_pids.values() for p in pids}
        peer_by_pid = get_session_peers(all_pids)
        last_ips = read_last_ips()
        # Only consulted for users nothing else could resolve, so the
        # common case costs no query at all.
        connlog_ips = {}
        resolved_now = {}

        unresolved = {un for un, pids in online_pids.items() if pids
                      and not any(peer_by_pid.get(p) and not _is_local_addr(peer_by_pid[p]) for p in pids)
                      and not (who_map.get(un, {}).get("ip") and not _is_local_addr(who_map[un]["ip"]))
                      and un not in last_ips}
        if unresolved:
            connlog_ips = last_ips_from_connlog(unresolved)

        for un, pids in online_pids.items():
            if not pids:
                continue
            info = who_map.get(un, {})
            # Calculate duration from first PID
            duration_s = 0
            first_pid = list(pids)[0] if pids else None
            if first_pid:
                try:
                    stat_file = f"/proc/{first_pid}/stat"
                    if os.path.exists(stat_file):
                        with open(stat_file) as f:
                            stat_parts = f.read().split()
                        starttime = int(stat_parts[21])
                        clk_tck = os.sysconf(os.sysconf_names.get('SC_CLK_TCK', 2))
                        with open('/proc/uptime') as f:
                            uptime_s = float(f.read().split()[0])
                        start_s = now - uptime_s + starttime / clk_tck
                        duration_s = int(now - start_s)
                except Exception:
                    pass
            
            # Precedence: the live socket peer (real, resolved through the
            # relay), then whatever `who` recorded if it is not loopback,
            # then the last real address seen for this user. Only a user
            # who has never once been resolved falls through to unknown.
            ip = next((peer_by_pid[p] for p in pids
                       if peer_by_pid.get(p) and not _is_local_addr(peer_by_pid[p])), "")
            if not ip:
                who_ip = info.get("ip", "")
                ip = who_ip if who_ip and not _is_local_addr(who_ip) else ""
            if not ip:
                ip = last_ips.get(un, "")
            if not ip:
                ip = connlog_ips.get(un, "")
            if ip:
                resolved_now[un] = ip

            result.append({
                "username": un,
                "ip": ip or "Unknown",
                "login_time": info.get("login_time", ""),
                "duration_seconds": max(0, duration_s),
                "sessions": len(pids),
                "pids": list(pids)
            })
        
        write_last_ips(resolved_now)
        self.send_json(200, {"online": result, "total": sum(len(o["pids"]) for o in result)})

    def handle_kick_user(self, username):
        online_pids = get_online_sessions_for_users({username})
        pids = online_pids.get(username, set())
        killed = 0
        killed_pids = []
        for pid in pids:
            code, _, _ = run_cmd(["kill", "-HUP", str(pid)], ignore_errors=True)
            if code == 0:
                killed += 1
                killed_pids.append(pid)
        _record_admin_disconnect(killed_pids)
        self.send_json(200, {"success": True, "killed": killed})

    def handle_user_history(self, username):
        # NOTE: this used to shell out to `last`/`lastb`, which read wtmp/
        # btmp — and every account this project creates gets shell
        # /usr/sbin/nologin for VPN tunneling, so OpenSSH never opens a
        # session channel for them and NEVER writes a wtmp entry, no
        # matter how many real connections happen. That made this always
        # show empty, regardless of actual usage — see connlog.py's
        # module docstring for the full explanation. Real tracking now
        # comes from the connlog daemon (process/socket based, not wtmp).
        try:
            _ensure_connlog_service()
            result = query_connections(source="ssh", username=username, sort="time",
                                        direction="desc", page=1, page_size=100)
            self.send_json(200, result)
        except Exception as e:
            self.send_json(400, {"error": str(e)})

    def handle_xui_client_history(self, inbound_id, email):
        # Same connlog daemon that tracks SSH sessions also tracks X-UI
        # clients (poll_xui() in connlog.py, keyed by email) — this just
        # narrows the same query to one client instead of listing everyone.
        try:
            _ensure_connlog_service()
            result = query_connections(source="xui", username=email, sort="time",
                                        direction="desc", page=1, page_size=100)
            self.send_json(200, result)
        except Exception as e:
            self.send_json(400, {"error": str(e)})

    def handle_get_connections(self, session):
        _ensure_connlog_service()
        qs = parse_qs(urlparse(self.path).query)

        def _q(name, default=""):
            return qs.get(name, [default])[0]

        source = _q("source", "all")
        q = _q("q", "")
        status = _q("status", "all")
        range_ = _q("range", "")
        sort = _q("sort", "time")
        direction = _q("dir", "desc")
        try:
            page = max(1, int(_q("page", "1")))
        except ValueError:
            page = 1
        try:
            page_size = int(_q("page_size", "25"))
        except ValueError:
            page_size = 25
        ts_from = ts_to = None
        try:
            raw_from, raw_to = _q("from", ""), _q("to", "")
            ts_from = float(raw_from) if raw_from else None
            ts_to = float(raw_to) if raw_to else None
        except ValueError:
            pass

        # Resellers only ever get to see their own users' connections.
        usernames = None
        if session.get("role") == "reseller":
            usernames = [u["username"] for u in read_db() if u.get("owner") == session["username"]]

        result = query_connections(source=source, q=q, usernames=usernames, status=status, range_=range_,
                                    ts_from=ts_from, ts_to=ts_to, sort=sort, direction=direction,
                                    page=page, page_size=page_size)
        result["active_now"] = get_active_now_count(source=source, q=q, usernames=usernames)
        self.send_json(200, result)

    def handle_delete_failed_connections(self, session):
        """Bulk-clears every 'failed' row (bot-scan/brute-force noise) —
        admin-only, since a 'failed' row has no real account tied to it for
        a reseller to own, and this is a global, irreversible purge."""
        if not os.path.exists(CONNLOG_DB_PATH):
            return self.send_json(200, {"success": True, "deleted": 0})
        conn = _connlog_db()
        try:
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM connections WHERE status='failed'")
            count = cur.fetchone()[0] or 0
            conn.execute("DELETE FROM connections WHERE status='failed'")
            conn.commit()
        finally:
            conn.close()
        self._log_action("admin", "INFO", "DELETE_FAILED_CONNECTIONS", "-", f"count={count}",
                          operator=session.get("username", "admin"))
        self.send_json(200, {"success": True, "deleted": count})

    def handle_get_firewall(self):
        blacklist = []
        whitelist = []
        for f, lst in [(IP_BLACKLIST_CONF, blacklist), (IP_WHITELIST_CONF, whitelist)]:
            if os.path.exists(f):
                with open(f) as fh:
                    for line in fh:
                        line = line.strip()
                        if line and not line.startswith('#'):
                            lst.append(line)
        self.send_json(200, {"blacklist": blacklist, "whitelist": whitelist})

    def handle_post_firewall(self, body):
        action = body.get("action")  # "add_black", "remove_black", "add_white", "remove_white", "flush"
        ip = body.get("ip", "").strip()
        
        if action == "flush":
            for f in [IP_BLACKLIST_CONF, IP_WHITELIST_CONF]:
                with open(f, 'w') as fh: pass
            run_cmd("iptables -F FF_FIREWALL 2>/dev/null", ignore_errors=True)
            return self.send_json(200, {"success": True})
        
        if not ip:
            return self.send_json(400, {"error": "IP required"})
        
        if action == "add_black":
            os.makedirs(os.path.dirname(IP_BLACKLIST_CONF), exist_ok=True)
            with open(IP_BLACKLIST_CONF, 'a') as f: f.write(ip + '\n')
        elif action == "remove_black":
            _remove_line_from_file(IP_BLACKLIST_CONF, ip)
        elif action == "add_white":
            os.makedirs(os.path.dirname(IP_WHITELIST_CONF), exist_ok=True)
            with open(IP_WHITELIST_CONF, 'a') as f: f.write(ip + '\n')
        elif action == "remove_white":
            _remove_line_from_file(IP_WHITELIST_CONF, ip)
        else:
            return self.send_json(400, {"error": "Unknown action"})
        
        # Re-apply rules
        self._apply_firewall_rules()
        self._log_action("security", "WARN", "FIREWALL_RULE", ip, f"action={action}")
        self.send_json(200, {"success": True})

    def _apply_firewall_rules(self):
        run_cmd("iptables -N FF_FIREWALL 2>/dev/null", ignore_errors=True)
        run_cmd("iptables -F FF_FIREWALL 2>/dev/null", ignore_errors=True)
        if os.path.exists(IP_WHITELIST_CONF):
            with open(IP_WHITELIST_CONF) as f:
                for line in f:
                    ip = line.strip()
                    if ip and not ip.startswith('#'):
                        run_cmd(f"iptables -A FF_FIREWALL -s {ip} -j ACCEPT", ignore_errors=True)
        if os.path.exists(IP_BLACKLIST_CONF):
            with open(IP_BLACKLIST_CONF) as f:
                for line in f:
                    ip = line.strip()
                    if ip and not ip.startswith('#'):
                        run_cmd(f"iptables -A FF_FIREWALL -s {ip} -j DROP", ignore_errors=True)

    def handle_get_user_speeds(self):
        speeds = {}
        if os.path.exists(USER_SPEED_CONF):
            with open(USER_SPEED_CONF) as f:
                for line in f:
                    parts = line.strip().split(':')
                    if len(parts) == 2 and parts[1].isdigit():
                        speeds[parts[0]] = int(parts[1])
        self.send_json(200, {
            "speeds": speeds,
            "limits": [{"username": k, "speed_mbps": v} for k, v in speeds.items()]
        })

    def _apply_user_speed(self, action, username, speed=0):
        """Core speed-limit logic, with no response side effects — safe to
        call from another handler that sends its own response afterwards.
        Returns (status_code, response_dict)."""
        username = (username or "").strip()
        os.makedirs(os.path.dirname(USER_SPEED_CONF), exist_ok=True)

        if action == "remove_all":
            with open(USER_SPEED_CONF, 'w') as f: pass
            return 200, {"success": True}

        if not username:
            return 400, {"error": "username required"}

        if action == "set":
            if not isinstance(speed, int) or speed < 1:
                return 400, {"error": "Speed must be positive integer (Mbps)"}
            _remove_line_from_file(USER_SPEED_CONF, None, prefix=username + ':')
            with open(USER_SPEED_CONF, 'a') as f:
                f.write(f"{username}:{speed}\n")
            # Apply tc rule
            uid_code, uid_out, _ = run_cmd(["id", "-u", username])
            if uid_code == 0:
                uid = uid_out.strip()
                iface_code, iface_out, _ = run_cmd("ip -4 route ls | grep default | grep -Po '(?<=dev )(\\S+)' | head -1")
                if iface_code == 0 and iface_out:
                    iface = iface_out.strip()
                    rate_kbit = speed * 1024
                    burst_kbit = max(1600, speed * 1024 // 8)
                    run_cmd(f"tc class add dev {iface} parent 1:1 classid 1:{uid} htb rate {rate_kbit}kbit burst {burst_kbit}k 2>/dev/null", ignore_errors=True)
                    run_cmd(f"tc filter add dev {iface} parent 1: protocol ip handle {uid} fw flowid 1:{uid} 2>/dev/null", ignore_errors=True)
                    run_cmd(f"iptables -t mangle -A OUTPUT -m owner --uid-owner {uid} -j MARK --set-mark {uid} 2>/dev/null", ignore_errors=True)
        elif action == "remove":
            _remove_line_from_file(USER_SPEED_CONF, None, prefix=username + ':')
            # Remove tc rules
            uid_code, uid_out, _ = run_cmd(["id", "-u", username])
            if uid_code == 0:
                uid = uid_out.strip()
                run_cmd(f"iptables -t mangle -D OUTPUT -m owner --uid-owner {uid} -j MARK --set-mark {uid} 2>/dev/null", ignore_errors=True)

        self._log_action("admin", "INFO", "SPEED_LIMIT", username, f"action={action} speed={speed}")
        return 200, {"success": True}

    def handle_post_user_speeds(self, body):
        action = body.get("action")  # "set", "remove", "remove_all"
        username = body.get("username", "")
        speed = body.get("speed", 0)
        code, result = self._apply_user_speed(action, username, speed)
        self.send_json(code, result)

    def handle_post_bandwidth_link_toggle(self, username, body):
        enabled = bool(body.get("enabled", True))
        if set_bandwidth_link_enabled(username, enabled):
            self.send_json(200, {"success": True, "enabled": enabled})
        else:
            self.send_json(404, {"error": "لم يتم إصدار رابط لهذا المستخدم بعد"})

    def handle_export_users(self, session, fmt):
        users = read_db()
        if session.get("role") == "reseller":
            users = [u for u in users if u.get("owner") == session["username"]]
        
        if fmt == "csv":
            import io
            output = io.StringIO()
            output.write("username,password,expire_date,conn_limit,bandwidth_gb,daily_bandwidth_gb,type,owner\n")
            for u in users:
                output.write(f"{u['username']},{u['password']},{u['expire_date']},{u['conn_limit']},{u['bandwidth_gb']},{u['daily_bandwidth_gb']},{u.get('account_type','')},{u.get('owner','admin')}\n")
            csv_data = output.getvalue()
            self.send_response(200)
            self.send_header('Content-Type', 'text/csv')
            self.send_header('Content-Disposition', 'attachment; filename=users.csv')
            self.end_headers()
            self.wfile.write(csv_data.encode())
        else:
            self.send_json(200, {"users": users})

    def _log_panel_access(self, username, action="login"):
        import time as _time
        log_file = "/etc/firewallfalcon/panel_access.log"
        ip = self.client_address[0]
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        os.makedirs(os.path.dirname(log_file), exist_ok=True)
        with open(log_file, 'a') as f:
            f.write(f"{ts} | {action} | {username} | {ip}\n")

    def _log_action(self, category, level, action, target, details="", operator=None):
        if operator is None:
            s = check_session(self.headers, handler=self)
            operator = s.get("username", "admin") if s else "admin"
        client_ip = self.client_address[0] if hasattr(self, 'client_address') else ""
        write_categorized_log(category, level, operator, action, target, details, client_ip)

    def handle_get_panel_logs(self):
        log_file = "/etc/firewallfalcon/panel_access.log"
        entries = []
        if os.path.exists(log_file):
            with open(log_file) as f:
                entries = f.readlines()[-50:]
        self.send_json(200, {"logs": [l.strip() for l in entries]})

    def handle_get_categorized_logs(self, session):
        qs = parse_qs(urlparse(self.path).query)
        cat = qs.get("category", ["all"])[0]
        search = qs.get("search", [""])[0].lower()
        limit = int(qs.get("limit", [100])[0])

        log_files = {
            "admin": "admin_audit.log",
            "clients": "client_connections.log",
            "services": "service_health.log",
            "security": "security_alerts.log",
            "reseller": "reseller_audit.log"
        }

        target_files = []
        if cat in log_files:
            target_files.append((cat, log_files[cat]))
        else:
            for c, f in log_files.items():
                target_files.append((c, f))

        entries = []
        os.makedirs(LOGS_DIR, exist_ok=True)
        for c_name, f_name in target_files:
            f_path = os.path.join(LOGS_DIR, f_name)
            if os.path.exists(f_path):
                try:
                    with open(f_path, "r", encoding="utf-8", errors="ignore") as f:
                        lines = f.readlines()
                        for l in lines[-300:]:
                            l_str = l.strip()
                            if not l_str:
                                continue
                            if search and search not in l_str.lower():
                                continue
                            parts = [p.strip() for p in l_str.split(" | ")]
                            entries.append({
                                "category": c_name,
                                "raw": l_str,
                                "timestamp": parts[0] if len(parts) > 0 else "",
                                "level": parts[1] if len(parts) > 1 else "INFO",
                                "operator": parts[2] if len(parts) > 2 else "",
                                "action": parts[3] if len(parts) > 3 else "",
                                "target": parts[4] if len(parts) > 4 else "",
                                "details": parts[5] if len(parts) > 5 else l_str
                            })
                except Exception:
                    pass

        entries.sort(key=lambda x: x["timestamp"], reverse=True)
        self.send_json(200, {"logs": entries[:limit]})

    def handle_get_users(self, session):
        users = read_db()
        
        # Scope by role
        if session.get("role") == "reseller":
            users = [u for u in users if u.get("owner") == session["username"]]

        user_speeds = {}
        if os.path.exists(USER_SPEED_CONF):
            with open(USER_SPEED_CONF) as f:
                for line in f:
                    parts = line.strip().split(':')
                    if len(parts) == 2 and parts[1].isdigit():
                        user_speeds[parts[0]] = int(parts[1])

        user_notes = _read_user_notes()
        login_modes = _read_login_modes()

        # Efficient batch online session lookup
        all_usernames = set(u["username"] for u in users)
        online_pids = get_online_sessions_for_users(all_usernames)

        result = []
        for u in users:
            un = u["username"]
            total_bw = read_file_int(f"{BW_DIR}/{un}.usage")
            daily_bw = read_file_int(f"{BW_DIR}/{un}.daily_usage")
            
            code, out, _ = run_cmd(["passwd", "-S", un])
            is_locked = False
            if code == 0 and len(out.split()) >= 2:
                is_locked = (out.split()[1] == "L")
                
            code2, _, _ = run_cmd(["id", un])
            exists_on_system = (code2 == 0)
            
            exp_date = parse_expiry_datetime(u.get("expire_date"))
            is_expired = (exp_date < datetime.now()) if exp_date else False
            
            online_count = len(online_pids.get(un, set()))
            
            u_ext = dict(u)
            u_ext["total_used_bytes"] = total_bw
            u_ext["daily_used_bytes"] = daily_bw
            u_ext["is_locked"] = is_locked
            u_ext["is_expired"] = is_expired
            u_ext["is_online"] = online_count > 0
            u_ext["online_sessions"] = online_count
            u_ext["exists_on_system"] = exists_on_system
            u_ext["speed_mbps"] = user_speeds.get(un, 0)
            u_ext["note"] = user_notes.get(un, "")
            u_ext["login_mode"] = login_modes.get(un, "normal")

            result.append(u_ext)
            
        self.send_json(200, {"users": result})

    def _create_user(self, un, pwd, days=0, conn=1, bw=0, dbw=0, acct_type="web", owner="admin", hours=0, login_mode="normal"):
        # '.' and '-' are allowed (not just '_') and the cap is raised to 128
        # so a real device ID (HWID login — see handle_post_users) fits;
        # create_system_user_safe() below is what actually makes a name
        # over 32 chars work at the OS level.
        if not re.match(r'^[a-zA-Z0-9_.-]{3,128}$', un):
            raise ValueError("Invalid username")

        if any(u["username"] == un for u in read_db()):
            raise ValueError("User already exists in DB")

        code, _, _ = run_cmd(["id", un])
        if code == 0:
            raise ValueError("User already exists on system")

        create_system_user_safe(un)
        run_cmd(["usermod", "-aG", FF_USERS_GROUP, un], ignore_errors=True)
        set_system_password(un, pwd)

        exp_date_str = calculate_expire_date(days, hours)
        chage_days = days + (1 if hours > 0 else 0)
        run_cmd(["chage", "-E", (datetime.now() + timedelta(days=max(1, chage_days))).strftime("%Y-%m-%d"), un])

        new_u = {
            "username": un,
            "password": pwd,
            "expire_date": exp_date_str,
            "conn_limit": conn,
            "bandwidth_gb": bw,
            "daily_bandwidth_gb": dbw,
            "account_type": acct_type,
            "owner": owner
        }

        with db_lock:
            os.makedirs(os.path.dirname(DB_FILE), exist_ok=True)
            with open(DB_FILE, "a") as f:
                f.write(format_db_line(new_u))
        set_login_mode(un, login_mode)

        # Initialize bandwidth usage files to prevent immediate locking
        os.makedirs(BW_DIR, exist_ok=True)
        with open(f"{BW_DIR}/{un}.usage", "w") as f:
            f.write("0")
        with open(f"{BW_DIR}/{un}.daily_usage", "w") as f:
            f.write("0")

        refresh_ssh_banner_config()
        self._log_action("admin", "INFO", "CREATE_USER", un, f"exp={exp_date_str} conn={conn} bw={bw} daily={dbw}", operator=owner)

        new_u["bandwidth_link"] = generate_bandwidth_link(un)
        new_u["login_mode"] = login_mode
        return new_u

    def handle_post_users(self, body, session):
        try:
            owner = session.get("username", "admin") if session.get("role") == "reseller" else "admin"
            days, hours = extract_duration_days_hours(body, default_days=30)
            conn = int(body.get("conn_limit", 1))
            bw = float(body.get("bandwidth_gb", 0))
            dbw = float(body.get("daily_bandwidth_gb", 0))

            # Reseller quota & restriction checks
            if session.get("role") == "reseller":
                resellers = read_resellers()
                r = next((x for x in resellers if x["username"] == session["username"]), None)
                if not r:
                    return self.send_json(403, {"error": "حساب الموزع غير موجود"})
                
                max_allowed_conn = r.get("max_conn_per_user", 2)
                if max_allowed_conn > 0 and conn > max_allowed_conn:
                    return self.send_json(400, {"error": f"الحد الأقصى المسموح للأجهزة لكل حساب هو {max_allowed_conn} أجهزة فقط"})
                
                max_allowed_bw = r.get("max_bw_per_user", 0)
                if max_allowed_bw > 0 and bw > max_allowed_bw:
                    return self.send_json(400, {"error": f"الحد الأقصى للباندويث المسموح لكل حساب هو {max_allowed_bw} GB"})

                if r.get("type") == "credits":
                    cost = calculate_credit_cost(days, hours)
                    if r.get("credits", 0) < cost:
                        return self.send_json(403, {"error": f"رصيد النقاط غير كافٍ. المطلوب {cost} نقاط، المتوفر {r.get('credits', 0)}"})
                else:
                    users = read_db()
                    owned = [u for u in users if u.get("owner") == session["username"]]
                    if len(owned) >= r["max_users"]:
                        return self.send_json(403, {"error": f"تم استهلاك كامل حصة المستخدمين المحددة ({r['max_users']})"})

            login_mode = body.get("login_mode", "normal")
            if login_mode == "hwid":
                # HWID login: the device ID is both username and password,
                # exactly like HTTP Custom's "Login with HWID" option —
                # nothing separate is asked of the client.
                hwid = (body.get("hwid", "") or "").strip()
                if not hwid:
                    return self.send_json(400, {"error": "معرّف الجهاز (HWID) مطلوب"})
                un = hwid
                pwd = hwid
            else:
                un = body.get("username", "")
                pwd = body.get("password", "") or generate_password()

            new_u = self._create_user(un, pwd, days=days, conn=conn, bw=bw, dbw=dbw, owner=owner, hours=hours, login_mode=login_mode)
            
            # Deduct credits if credit-based reseller
            if session.get("role") == "reseller":
                resellers = read_resellers()
                r = next((x for x in resellers if x["username"] == session["username"]), None)
                if r and r.get("type") == "credits":
                    cost = calculate_credit_cost(days, hours)
                    r["credits"] = max(0, r.get("credits", 0) - cost)
                    write_resellers(resellers)
            
            self.send_json(200, new_u)
        except Exception as e:
            self.send_json(400, {"error": str(e)})

    def handle_post_users_bulk(self, body, session):
        try:
            owner = session.get("username", "admin") if session.get("role") == "reseller" else "admin"
            days, hours = extract_duration_days_hours(body, default_days=30)
            conn = int(body.get("conn_limit", 1))
            bw = float(body.get("bandwidth_gb", 0))
            dbw = float(body.get("daily_bandwidth_gb", 0))
            
            # Reseller quota check
            remaining_quota = float('inf')
            if session.get("role") == "reseller":
                resellers = read_resellers()
                r = next((x for x in resellers if x["username"] == session["username"]), None)
                if not r:
                    return self.send_json(403, {"error": "حساب الموزع غير موجود"})
                if not r.get("allow_bulk", True):
                    return self.send_json(403, {"error": "صلاحية الإنشاء الجماعي غير مفعلة لحسابك من قبل الإدارة"})
                
                max_allowed_conn = r.get("max_conn_per_user", 2)
                if max_allowed_conn > 0 and conn > max_allowed_conn:
                    return self.send_json(400, {"error": f"الحد الأقصى المسموح للأجهزة لكل حساب هو {max_allowed_conn} أجهزة فقط"})
                
                max_allowed_bw = r.get("max_bw_per_user", 0)
                if max_allowed_bw > 0 and bw > max_allowed_bw:
                    return self.send_json(400, {"error": f"الحد الأقصى للباندويث المسموح لكل حساب هو {max_allowed_bw} GB"})

                if r.get("type") == "credits":
                    cost_per = calculate_credit_cost(days, hours)
                    count_requested = int(body.get("count", 1))
                    max_affordable = r.get("credits", 0) // cost_per if cost_per > 0 else 0
                    remaining_quota = max_affordable
                    if remaining_quota <= 0:
                        return self.send_json(403, {"error": f"رصيد النقاط غير كافٍ. المطلوب {cost_per} لكل مستخدم، المتوفر {r.get('credits', 0)}"})
                else:
                    users = read_db()
                    owned = [u for u in users if u.get("owner") == session["username"]]
                    remaining_quota = r["max_users"] - len(owned)
                    if remaining_quota <= 0:
                        return self.send_json(403, {"error": f"تم استهلاك كامل حصة المستخدمين المحددة ({r['max_users']})"})

            prefix = body.get("prefix", "user")
            count = min(int(body.get("count", 1)), int(remaining_quota))
            
            created = []
            existing_users = set(u["username"] for u in read_db())
            
            idx = 1
            for _ in range(count):
                while f"{prefix}{idx}" in existing_users:
                    idx += 1
                un = f"{prefix}{idx}"
                pwd = generate_password()
                
                try:
                    u = self._create_user(un, pwd, days=days, conn=conn, bw=bw, dbw=dbw, acct_type="bulk", owner=owner, hours=hours)
                    created.append(u)
                    existing_users.add(un)
                except Exception as e:
                    pass # skip failures in bulk
                idx += 1
                
            # Deduct credits if credit-based reseller
            if session.get("role") == "reseller" and len(created) > 0:
                resellers = read_resellers()
                r = next((x for x in resellers if x["username"] == session["username"]), None)
                if r and r.get("type") == "credits":
                    total_cost = len(created) * calculate_credit_cost(days, hours)
                    r["credits"] = max(0, r.get("credits", 0) - total_cost)
                    write_resellers(resellers)
            
            self.send_json(200, {"users": created})
        except Exception as e:
            self.send_json(400, {"error": str(e)})
                
            # Deduct credits if credit-based reseller
            if session.get("role") == "reseller" and len(created) > 0:
                resellers = read_resellers()
                r = next((x for x in resellers if x["username"] == session["username"]), None)
                if r and r.get("type") == "credits":
                    total_cost = len(created) * calculate_credit_cost(days, hours)
                    r["credits"] = max(0, r.get("credits", 0) - total_cost)
                    write_resellers(resellers)
            
            self.send_json(200, {"users": created})
        except Exception as e:
            self.send_json(400, {"error": str(e)})

    def handle_post_trial_user(self, body, session):
        try:
            owner = session.get("username", "admin") if session.get("role") == "reseller" else "admin"

            # Reseller quota check
            if session.get("role") == "reseller":
                resellers = read_resellers()
                r = next((x for x in resellers if x["username"] == session["username"]), None)
                if not r:
                    return self.send_json(403, {"error": "حساب الموزع غير موجود"})
                if not r.get("allow_trials", True):
                    return self.send_json(403, {"error": "صلاحية إنشاء الحسابات التجريبية غير مفعلة لحسابك من قبل الإدارة"})
                
                users = read_db()
                owned = [u for u in users if u.get("owner") == session["username"]]
                if len(owned) >= r["max_users"]:
                    return self.send_json(403, {"error": f"تم استهلاك كامل حصة المستخدمين ({r['max_users']})"})

            login_mode = body.get("login_mode", "normal")
            if login_mode == "hwid":
                hwid = (body.get("hwid", "") or "").strip()
                if not hwid:
                    return self.send_json(400, {"error": "معرّف الجهاز (HWID) مطلوب"})
                un = hwid
                pwd = hwid
            else:
                un = body.get("username", "")
                if not un:
                    import random, string
                    un = "trial_" + "".join(random.choices(string.ascii_lowercase + string.digits, k=5))
                pwd = body.get("password", "") or generate_password()
            hours = int(body.get("hours", 1))
            conn = int(body.get("conn_limit", 1))
            bw = float(body.get("bandwidth_gb", 0))

            if session.get("role") == "reseller":
                resellers = read_resellers()
                r = next((x for x in resellers if x["username"] == session["username"]), None)
                if r:
                    max_allowed_conn = r.get("max_conn_per_user", 2)
                    if max_allowed_conn > 0 and conn > max_allowed_conn:
                        return self.send_json(400, {"error": f"الحد الأقصى المسموح للأجهزة لكل حساب هو {max_allowed_conn} أجهزة فقط"})
            
            # Calculate days for expiry
            if hours >= 24:
                days = hours // 24
            else:
                days = 1  # At least 1 day for chage, at job does real cleanup
            
            new_u = self._create_user(un, pwd, days, conn, bw, 0, acct_type="trial", owner=owner, login_mode=login_mode)
            
            # Schedule auto-cleanup via 'at' daemon
            cleanup_script = "/usr/local/bin/firewallfalcon-trial-cleanup.sh"
            if os.path.exists(cleanup_script):
                run_cmd(f"echo '{cleanup_script} {un}' | at now + {hours} hours", ignore_errors=True)
            
            # Calculate expiry timestamp for display
            from datetime import datetime, timedelta
            expiry_time = (datetime.now() + timedelta(hours=hours)).strftime("%Y-%m-%d %H:%M:%S")
            new_u["expiry_time"] = expiry_time
            new_u["hours"] = hours
            
            # Deduct credits if credit-based reseller
            if session.get("role") == "reseller":
                resellers = read_resellers()
                r = next((x for x in resellers if x["username"] == session["username"]), None)
                if r and r.get("type") == "credits":
                    days_val = hours // 24 if hours >= 24 else 1
                    cost = calculate_credit_cost(days_val)
                    r["credits"] = max(0, r.get("credits", 0) - cost)
                    write_resellers(resellers)
            
            self.send_json(200, new_u)
        except Exception as e:
            self.send_json(400, {"error": str(e)})

    def handle_put_user(self, username, body, session):
        if not self._check_user_ownership(username, session):
            return self.send_json(403, {"error": "Access denied"})

        with db_lock:
            users = read_db()
            idx = next((i for i, u in enumerate(users) if u["username"] == username), -1)
            if idx == -1:
                return self.send_json(404, {"error": "User not found"})
            u = users[idx]

            if session.get("role") == "reseller":
                resellers = read_resellers()
                r = next((x for x in resellers if x["username"] == session["username"]), None)
                if r:
                    max_allowed_conn = r.get("max_conn_per_user", 2)
                    if "conn_limit" in body and max_allowed_conn > 0 and int(body["conn_limit"]) > max_allowed_conn:
                        return self.send_json(400, {"error": f"الحد الأقصى المسموح للأجهزة هو {max_allowed_conn} أجهزة"})
                    max_allowed_bw = r.get("max_bw_per_user", 0)
                    if "bandwidth_gb" in body and max_allowed_bw > 0 and float(body["bandwidth_gb"]) > max_allowed_bw:
                        return self.send_json(400, {"error": f"الحد الأقصى للباندويث المسموح هو {max_allowed_bw} GB"})

            if "password" in body:
                u["password"] = body["password"]
                set_system_password(username, u['password'])
                
            if "days" in body or "hours" in body or "duration_value" in body:
                d_days, d_hours = extract_duration_days_hours(body, default_days=0)
                if d_days > 0 or d_hours > 0:
                    u["expire_date"] = calculate_expire_date(days=d_days, hours=d_hours)
                    chage_days = d_days + (1 if d_hours > 0 else 0)
                    run_cmd(["chage", "-E", (datetime.now() + timedelta(days=max(1, chage_days))).strftime("%Y-%m-%d"), username])
                
            if "conn_limit" in body:
                u["conn_limit"] = int(body["conn_limit"])
                
            if "bandwidth_gb" in body:
                u["bandwidth_gb"] = float(body["bandwidth_gb"])
                
            if "daily_bandwidth_gb" in body:
                u["daily_bandwidth_gb"] = float(body["daily_bandwidth_gb"])

            if "speed_mbps" in body:
                sp_val = int(body["speed_mbps"])
                u["speed_mbps"] = sp_val
                if sp_val > 0:
                    self._apply_user_speed("set", username, sp_val)
                else:
                    self._apply_user_speed("remove", username)

            lines = []
            with open(DB_FILE, "r") as f:
                lines = f.readlines()
                
            with open(DB_FILE, "w") as f:
                for line in lines:
                    if line.startswith(f"{username}:"):
                        f.write(format_db_line(u))
                    else:
                        f.write(line)
                        
            operator = session.get("username", "admin") if session else "admin"
            self._log_action("admin", "INFO", "MODIFY_USER", username, f"conn={u.get('conn_limit')} bw={u.get('bandwidth_gb')} daily={u.get('daily_bandwidth_gb')}", operator=operator)
            self.send_json(200, u)

    def handle_post_user_hwid(self, username, body, session):
        """Changes a HWID-login account's device ID — the client's HWID
        changed (OS/app update) and everything else about the account
        (expiry, bandwidth used, notes, speed cap) should carry over
        exactly. Only valid for accounts actually created in HWID mode;
        a normal username+password account has no single "device ID" to
        swap in its place."""
        if not self._check_user_ownership(username, session):
            return self.send_json(403, {"error": "Access denied"})
        if get_login_mode(username) != "hwid":
            return self.send_json(400, {"error": "This account is not in HWID login mode"})

        new_hwid = (body.get("new_hwid", "") or "").strip()
        if not re.match(r'^[a-zA-Z0-9_.-]{3,128}$', new_hwid):
            return self.send_json(400, {"error": "Invalid device ID"})
        if new_hwid == username:
            return self.send_json(400, {"error": "That's the current device ID"})
        if any(u["username"] == new_hwid for u in read_db()):
            return self.send_json(400, {"error": "This device ID is already registered"})
        code, _, _ = run_cmd(["id", new_hwid])
        if code == 0:
            return self.send_json(400, {"error": "This device ID is already registered"})

        try:
            rename_hwid_account(username, new_hwid)
        except Exception as e:
            return self.send_json(400, {"error": str(e)})

        operator = session.get("username", "admin") if session else "admin"
        self._log_action("admin", "INFO", "HWID_CHANGE", new_hwid, f"was={username}", operator=operator)
        self.send_json(200, {"success": True, "username": new_hwid})

    def handle_delete_user(self, username, session):
        if not self._check_user_ownership(username, session):
            return self.send_json(403, {"error": "Access denied"})

        force_delete_system_user(username)
        
        with db_lock:
            lines = []
            if os.path.exists(DB_FILE):
                with open(DB_FILE, "r") as f:
                    lines = f.readlines()
                with open(DB_FILE, "w") as f:
                    for line in lines:
                        if not line.startswith(f"{username}:"):
                            f.write(line)
                            
        run_cmd(f"rm -f {BW_DIR}/{username}.*", ignore_errors=True)
        run_cmd(f"rm -f /etc/firewallfalcon/banners/{username}.txt", ignore_errors=True)
        refresh_ssh_banner_config()
        delete_user_note(username)
        delete_login_mode(username)

        operator = session.get("username", "admin") if session else "admin"
        self._log_action("admin", "INFO", "DELETE_USER", username, "", operator=operator)
        self.send_json(200, {"success": True})

    def handle_user_action(self, username, action, body=None, session=None):
        if not self._check_user_ownership(username, session):
            return self.send_json(403, {"error": "Access denied"})

        operator = session.get("username", "admin") if session else "admin"
        if action == "lock":
            run_cmd(["usermod", "-L", username])
            kill_user_sessions(username)
            self._log_action("admin", "INFO", "LOCK_USER", username, "", operator=operator)
            self.send_json(200, {"success": True})
            
        elif action == "unlock":
            run_cmd(["usermod", "-U", username])
            run_cmd(f"rm -f {BW_DIR}/{username}.conn_locked", ignore_errors=True)
            run_cmd(f"rm -f {BW_DIR}/{username}.daily_locked", ignore_errors=True)
            self._log_action("admin", "INFO", "UNLOCK_USER", username, "", operator=operator)
            self.send_json(200, {"success": True})
            
        elif action == "renew":
            d_days, d_hours = extract_duration_days_hours(body, default_days=30)
            bw_action = body.get("bw_action", "add") if body else "add" # "add", "reset", "set", "keep"
            reset_bw = bool(body.get("reset_bandwidth", False)) if body else False
            if bw_action == "reset" or (body and body.get("mode") in ("package", "full", "both")):
                reset_bw = True
            
            is_cumulative = bool(body.get("cumulative", True)) if body else True
            new_conn_limit = body.get("conn_limit") if body else None
            new_bandwidth_gb = body.get("bandwidth_gb") if body else None
            add_bandwidth_gb = body.get("add_bandwidth_gb") if body else None
            
            # Deduct credits for credit-based reseller renewals
            if session and session.get("role") == "reseller":
                resellers = read_resellers()
                r = next((x for x in resellers if x["username"] == session["username"]), None)
                if r and r.get("type") == "credits":
                    cost = calculate_credit_cost(days=d_days, hours=d_hours)
                    if r.get("credits", 0) < cost:
                        return self.send_json(403, {"error": f"Not enough credits. Need {cost}, have {r.get('credits', 0)}"})
                    r["credits"] = max(0, r.get("credits", 0) - cost)
                    write_resellers(resellers)
            
            with db_lock:
                users = read_db()
                u = next((x for x in users if x["username"] == username), None)
                if not u:
                    return self.send_json(404, {"error": "User not found"})
                
                curr_exp = parse_expiry_datetime(u.get("expire_date"))
                now = datetime.now()
                if is_cumulative and curr_exp and curr_exp > now:
                    base_dt = curr_exp
                else:
                    base_dt = now
                
                new_exp_dt = base_dt + timedelta(days=d_days, hours=d_hours)
                if d_hours > 0 and (d_hours % 24 != 0 or d_days == 0):
                    # No colon here either — see calculate_expire_date().
                    u["expire_date"] = new_exp_dt.strftime("%Y-%m-%d %H%M")
                else:
                    u["expire_date"] = new_exp_dt.strftime("%Y-%m-%d")
                
                # Update conn_limit if provided
                if new_conn_limit is not None:
                    try:
                        c_val = int(new_conn_limit)
                        if c_val > 0:
                            if session and session.get("role") == "reseller":
                                resellers = read_resellers()
                                r = next((x for x in resellers if x["username"] == session["username"]), None)
                                if r and r.get("max_conn_per_user", 0) > 0:
                                    c_val = min(c_val, r["max_conn_per_user"])
                            u["conn_limit"] = c_val
                    except (ValueError, TypeError):
                        pass

                # Cumulative bandwidth stacking (+GB)
                if add_bandwidth_gb is not None:
                    try:
                        add_val = float(add_bandwidth_gb)
                        if add_val > 0:
                            curr_bw = float(u.get("bandwidth_gb", 0) or 0)
                            u["bandwidth_gb"] = round(curr_bw + add_val, 2)
                    except (ValueError, TypeError):
                        pass
                elif new_bandwidth_gb is not None:
                    try:
                        b_val = float(new_bandwidth_gb)
                        if b_val >= 0:
                            u["bandwidth_gb"] = b_val
                    except (ValueError, TypeError):
                        pass

                chage_days = max(1, math.ceil((new_exp_dt - now).total_seconds() / 86400))
                run_cmd(["chage", "-E", (now + timedelta(days=chage_days)).strftime("%Y-%m-%d"), username])
                
                lines = []
                with open(DB_FILE, "r") as f:
                    lines = f.readlines()
                with open(DB_FILE, "w") as f:
                    for line in lines:
                        if line.startswith(f"{username}:"):
                            f.write(format_db_line(u))
                        else:
                            f.write(line)

            # If full package renewal (reset bandwidth counter)
            if reset_bw:
                os.makedirs(BW_DIR, exist_ok=True)
                with open(f"{BW_DIR}/{username}.usage", "w") as f:
                    f.write("0")
                with open(f"{BW_DIR}/{username}.daily_usage", "w") as f:
                    f.write("0")
                run_cmd(f"rm -f {BW_DIR}/{username}.conn_locked", ignore_errors=True)
                run_cmd(f"rm -f {BW_DIR}/{username}.daily_locked", ignore_errors=True)
                run_cmd(["usermod", "-U", username])

            self._log_action("admin", "INFO", "RENEW_USER", username, f"days={d_days} hours={d_hours} cum={is_cumulative} bw={u.get('bandwidth_gb')} reset_bw={reset_bw} exp={u['expire_date']}", operator=operator)
            self.send_json(200, {"success": True, "expire_date": u["expire_date"], "bandwidth_gb": u.get("bandwidth_gb"), "bandwidth_reset": reset_bw, "conn_limit": u.get("conn_limit")})
            
        elif action == "reset-bandwidth":
            os.makedirs(BW_DIR, exist_ok=True)
            with open(f"{BW_DIR}/{username}.usage", "w") as f:
                f.write("0")
            with open(f"{BW_DIR}/{username}.daily_usage", "w") as f:
                f.write("0")
            run_cmd(f"rm -f {BW_DIR}/{username}.conn_locked", ignore_errors=True)
            run_cmd(f"rm -f {BW_DIR}/{username}.daily_locked", ignore_errors=True)
            run_cmd(["usermod", "-U", username])
            self._log_action("admin", "INFO", "RESET_BANDWIDTH", username, "", operator=operator)
            self.send_json(200, {"success": True})
            
        else:
            self.send_json(400, {"error": "Unknown action"})

    def handle_get_protocols(self):
        self.send_json(200, self.get_protocols_status())

    def _xui_build_client_result(self, inbound_id, result, allow_insecure=False):
        """Shared by every client-creation path (base mode, trial, and each
        half of 'fixed 443/80' mode): fills in the inbound's port/remark and
        builds the client's link from its real stream_settings."""
        inbounds = {i["id"]: i for i in xui_list_inbounds()}
        inb = inbounds.get(inbound_id, {})
        result["port"] = inb.get("port")
        result["inbound_remark"] = inb.get("remark", "")
        client_for_link = {
            "protocol": result["protocol"], "port": result["port"], "secret": result["secret"],
            "stream": _xui_fetch_inbound_stream(inbound_id),
            "inbound_remark": result["inbound_remark"], "email": result["email"],
        }
        result["link"] = xui_generate_client_link(client_for_link, server_ip=get_public_host(), allow_insecure=allow_insecure)
        return result

    def handle_get_xui_clients(self):
        try:
            server_ip = get_public_host()
            clients = xui_list_clients()
            device_counts = get_active_xui_device_counts()
            for c in clients:
                pref = get_xui_client_pref(c["inbound_id"], c["email"])
                port_mode = pref.get("port_mode", "base")
                allow_insecure = bool(pref.get("allow_insecure", False))
                c["port_mode"] = port_mode
                c["allow_insecure"] = allow_insecure
                c["note"] = pref.get("note", "")
                # Same "sessions: N/limit" the SSH accounts list shows per
                # user — the real number of distinct devices online right
                # now, from Xray's own per-client online-IP list.
                c["online_sessions"] = device_counts.get(c["email"], 0)
                base_link = xui_generate_client_link(c, server_ip=server_ip, allow_insecure=allow_insecure)
                if port_mode == "fixed":
                    c["links"] = [
                        {"port": 443, "link": _link_with_port(base_link, 443)},
                        {"port": 80, "link": _link_with_port(base_link, 80)},
                    ]
                    c["link"] = c["links"][0]["link"]
                else:
                    c["link"] = base_link
                # The raw stream_settings (REALITY private key, TLS cert
                # config) only exists to build the link above — it must
                # never leave this process in the API response.
                c.pop("stream", None)
            # Same "total configured / currently connected" pair the SSH
            # dashboard cards show, mirrored here so the X-UI accounts page
            # has the same at-a-glance numbers.
            self.send_json(200, {
                "clients": clients,
                "total_count": len(clients),
                "online_count": get_active_now_count(source="xui"),
                # Lets the client form offer exactly the settings the
                # installed panel can actually store — 3x-ui has several
                # the original build does not.
                "variant": xui_variant(),
            })
        except Exception as e:
            self.send_json(400, {"error": str(e)})

    def handle_post_xui_client(self, body, session):
        try:
            inbound_id = int(body.get("inbound_id"))
            remark = str(body.get("remark", "")).strip()
            days, hours = extract_duration_days_hours(body, default_days=30)
            bandwidth_gb = float(body.get("bandwidth_gb", 0))
            max_conn = int(body.get("max_conn", 0))
            custom_secret = str(body.get("custom_uuid", "")).strip() or None
            if custom_secret and not re.match(r'^[A-Za-z0-9-]{1,64}$', custom_secret):
                return self.send_json(400, {"error": "الـ UUID/Secret المخصص يحتوي على رموز غير مسموحة"})
            allow_insecure = bool(body.get("allow_insecure", False))
            port_mode = str(body.get("port_mode", "base"))
            extras = _xui_extras_from_body(body)
            extras.update(_xui_credential_fields_from_body(body))

            # Always ONE real client on the inbound the admin picked — 'fixed'
            # mode never creates a second client/inbound, it only changes how
            # the resulting link is DISPLAYED (see _link_with_port below).
            result = xui_add_client(inbound_id, remark, days=days, hours=hours,
                                     bandwidth_gb=bandwidth_gb, max_conn=max_conn,
                                     custom_secret=custom_secret, extras=extras)
            set_xui_client_pref(inbound_id, result["email"], port_mode=port_mode, allow_insecure=allow_insecure)
            result = self._xui_build_client_result(inbound_id, result, allow_insecure=allow_insecure)

            if port_mode == "fixed":
                base_link = result["link"]
                clients = [
                    {**result, "port": 443, "link": _link_with_port(base_link, 443)},
                    {**result, "port": 80, "link": _link_with_port(base_link, 80)},
                ]
                self._log_action("admin", "INFO", "XUI_ADD_CLIENT", remark,
                                  f"inbound={inbound_id} protocol={result['protocol']} port_mode=fixed",
                                  operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True, "mode": "fixed", "clients": clients})

            self._log_action("admin", "INFO", "XUI_ADD_CLIENT", remark,
                              f"inbound={inbound_id} protocol={result['protocol']}",
                              operator=session.get("username", "admin"))
            self.send_json(200, result)
        except (ValueError, RuntimeError) as e:
            self.send_json(400, {"error": str(e)})
        except Exception as e:
            self.send_json(500, {"error": str(e)})

    def handle_post_xui_trial_client(self, body, session):
        try:
            inbound_id = int(body.get("inbound_id"))
            hours = int(body.get("hours", 1))
            bandwidth_gb = float(body.get("bandwidth_gb", 0))
            max_conn = int(body.get("max_conn", 1))
            allow_insecure = bool(body.get("allow_insecure", False))
            port_mode = str(body.get("port_mode", "base"))

            import random, string
            result, remark = None, ""
            for _ in range(5):
                candidate = "trial_" + "".join(random.choices(string.ascii_lowercase + string.digits, k=5))
                try:
                    result = xui_add_client(inbound_id, candidate, days=0, hours=hours,
                                             bandwidth_gb=bandwidth_gb, max_conn=max_conn)
                    remark = candidate
                    break
                except ValueError as e:
                    if "already exists" in str(e):
                        continue
                    raise
            if result is None:
                raise RuntimeError("تعذّر توليد اسم عميل تجريبي فريد، حاول مرة أخرى")

            set_xui_client_pref(inbound_id, result["email"], port_mode=port_mode, allow_insecure=allow_insecure)
            result = self._xui_build_client_result(inbound_id, result, allow_insecure=allow_insecure)

            if port_mode == "fixed":
                base_link = result["link"]
                clients = [
                    {**result, "port": 443, "link": _link_with_port(base_link, 443)},
                    {**result, "port": 80, "link": _link_with_port(base_link, 80)},
                ]
                self._log_action("admin", "INFO", "XUI_ADD_TRIAL_CLIENT", remark,
                                  f"inbound={inbound_id} hours={hours} port_mode=fixed",
                                  operator=session.get("username", "admin"))
                return self.send_json(200, {"success": True, "mode": "fixed", "clients": clients})

            self._log_action("admin", "INFO", "XUI_ADD_TRIAL_CLIENT", remark,
                              f"inbound={inbound_id} hours={hours}",
                              operator=session.get("username", "admin"))
            self.send_json(200, result)
        except (ValueError, RuntimeError) as e:
            self.send_json(400, {"error": str(e)})
        except Exception as e:
            self.send_json(500, {"error": str(e)})

    def handle_post_xui_client_renew(self, inbound_id, email, body, session):
        try:
            days, hours = extract_duration_days_hours(body, default_days=0)
            if not days and not hours:
                return self.send_json(400, {"error": "حدد مدة التجديد"})
            is_cumulative = bool(body.get("cumulative", True))
            add_bandwidth_gb = float(body.get("add_bandwidth_gb", 0))
            reset_usage = bool(body.get("reset_usage", False))
            conn = int(body["max_conn"]) if "max_conn" in body else None
            result = xui_renew_client(int(inbound_id), email, days=days, hours=hours,
                                       is_cumulative=is_cumulative, add_bandwidth_gb=add_bandwidth_gb,
                                       reset_usage=reset_usage, max_conn=conn)
            self._log_action("admin", "INFO", "XUI_RENEW_CLIENT", email,
                              f"inbound={inbound_id} days={days} hours={hours}",
                              operator=session.get("username", "admin"))
            self.send_json(200, result)
        except (ValueError, RuntimeError) as e:
            self.send_json(400, {"error": str(e)})
        except Exception as e:
            self.send_json(500, {"error": str(e)})

    def handle_post_xui_client_reset_usage(self, inbound_id, email, session):
        try:
            xui_reset_client_traffic(int(inbound_id), email)
            self._log_action("admin", "INFO", "XUI_RESET_TRAFFIC", email, f"inbound={inbound_id}",
                              operator=session.get("username", "admin"))
            self.send_json(200, {"success": True})
        except (ValueError, RuntimeError) as e:
            self.send_json(400, {"error": str(e)})
        except Exception as e:
            self.send_json(500, {"error": str(e)})

    def handle_get_xui_bandwidth_link(self, inbound_id, email):
        link, enabled = get_xui_bandwidth_link(inbound_id, email)
        if link:
            self.send_json(200, {"link": link, "enabled": enabled})
        else:
            self.send_json(500, {"error": "تعذّر إنشاء/استرجاع الرابط"})

    def handle_post_xui_bandwidth_link_toggle(self, inbound_id, email, body):
        enabled = bool(body.get("enabled", True))
        ok = set_xui_bandwidth_link_enabled(inbound_id, email, enabled)
        if ok:
            self.send_json(200, {"success": True})
        else:
            self.send_json(404, {"error": "لا يوجد رابط لهذا العميل بعد"})

    def handle_put_xui_client(self, inbound_id, email, body):
        try:
            days = hours = None
            if any(k in body for k in ("days", "hours", "duration_value")):
                days, hours = extract_duration_days_hours(body, default_days=0)
            bw = float(body["bandwidth_gb"]) if "bandwidth_gb" in body else None
            conn = int(body["max_conn"]) if "max_conn" in body else None
            enable = bool(body["enable"]) if "enable" in body else None
            extras = _xui_extras_from_body(body)
            extras.update(_xui_credential_fields_from_body(body))
            xui_update_client(int(inbound_id), email, days=days, hours=hours,
                              bandwidth_gb=bw, max_conn=conn, enable=enable,
                              extras=extras)
            # port_mode/allow_insecure are display-only preferences (never
            # part of x-ui's own client record) — updated independently so
            # an edit that only touches quota/expiry doesn't reset them.
            if "port_mode" in body or "allow_insecure" in body:
                set_xui_client_pref(
                    int(inbound_id), email,
                    port_mode=body.get("port_mode"),
                    allow_insecure=bool(body["allow_insecure"]) if "allow_insecure" in body else None,
                )
            self.send_json(200, {"success": True})
        except (ValueError, RuntimeError) as e:
            self.send_json(400, {"error": str(e)})
        except Exception as e:
            self.send_json(500, {"error": str(e)})

    def handle_delete_xui_client(self, inbound_id, email):
        try:
            xui_delete_client(int(inbound_id), email)
            delete_xui_client_pref(int(inbound_id), email)
            self.send_json(200, {"success": True})
        except (ValueError, RuntimeError) as e:
            self.send_json(400, {"error": str(e)})
        except Exception as e:
            self.send_json(500, {"error": str(e)})

    def handle_protocol_restart(self, service):
        code, out, err = run_cmd(["systemctl", "restart", service])
        if code == 0:
            self.send_json(200, {"success": True})
        else:
            self.send_json(500, {"success": False, "error": err})

    def handle_system_reboot(self):
        self.send_json(200, {"success": True, "message": "Rebooting system..."})
        # Schedule reboot in background so we can return response first
        threading.Timer(2.0, lambda: subprocess.run(["reboot"])).start()

    def handle_logo_upload(self, raw_data):
        try:
            if len(raw_data) > 2097152:  # 2MB max
                return self.send_json(400, {"error": "File too large (max 2MB)"})
            if len(raw_data) == 0:
                return self.send_json(400, {"error": "No file data"})
            
            logo_path = "/etc/firewallfalcon/panel/logo.png"
            os.makedirs(os.path.dirname(logo_path), exist_ok=True)
            with open(logo_path, "wb") as f:
                f.write(raw_data)
            
            # Set PANEL_LOGO to 'custom' to signal frontend to use image
            creds = get_panel_creds()
            creds["PANEL_LOGO"] = "custom"
            os.makedirs(os.path.dirname(PANEL_CONF), exist_ok=True)
            with open(PANEL_CONF, "w") as f:
                for k, v in creds.items():
                    f.write(f"{k}={v}\n")
            
            self.send_json(200, {"success": True, "panel_logo": "custom"})
        except Exception as e:
            self.send_json(500, {"error": str(e)})

    def handle_logo_delete(self):
        logo_path = "/etc/firewallfalcon/panel/logo.png"
        try:
            if os.path.exists(logo_path):
                os.remove(logo_path)
            creds = get_panel_creds()
            creds["PANEL_LOGO"] = "Ⓓ"
            os.makedirs(os.path.dirname(PANEL_CONF), exist_ok=True)
            with open(PANEL_CONF, "w") as f:
                for k, v in creds.items():
                    f.write(f"{k}={v}\n")
            self.send_json(200, {"success": True, "panel_logo": "Ⓓ"})
        except Exception as e:
            self.send_json(500, {"error": str(e)})

    def handle_get_settings(self):
        creds = get_panel_creds()
        self.send_json(200, {
            "username": creds.get("PANEL_USER", ""),
            "secret": creds.get("PANEL_SECRET", ""),
            "panel_name": creds.get("PANEL_NAME", "DAHOOM"),
            "panel_logo": creds.get("PANEL_LOGO", "👑"),
            "has_custom_logo": os.path.exists("/etc/firewallfalcon/panel/logo.png") and creds.get("PANEL_LOGO") == "custom",
            "panel_domain": creds.get("PANEL_DOMAIN", ""),
            "panel_telegram": creds.get("PANEL_TELEGRAM", "")
        })

    def handle_put_settings(self, body):
        creds = get_panel_creds()
        curr_pwd = body.get("current_password", "")
        new_user = body.get("new_username", "").strip() or creds.get("PANEL_USER", "")
        new_pwd = body.get("new_password", "").strip() or creds.get("PANEL_PASS_PLAIN", "")
        new_secret = body.get("new_secret", "").strip().lstrip('/')
        new_name = body.get("panel_name", "").strip()
        new_logo = body.get("panel_logo", "").strip()
        new_domain = body.get("panel_domain", None)
        new_telegram = body.get("panel_telegram", None)
        if new_telegram is not None and new_telegram.strip() and not re.match(r'^[A-Za-z0-9_]{5,32}$', new_telegram.strip().lstrip('@')):
            return self.send_json(400, {"error": "معرّف تيليجرام غير صالح — أحرف/أرقام/underscore فقط، من 5 إلى 32 حرفًا"})

        curr_hash = hashlib.sha256(curr_pwd.encode()).hexdigest()
        if curr_hash != creds.get("PANEL_PASS_HASH"):
            return self.send_json(401, {"error": "Invalid current password"})
            
        write_panel_creds(new_user, new_pwd, secret=new_secret, panel_name=new_name or None, panel_logo=new_logo or None,
                           panel_domain=new_domain, panel_telegram=new_telegram)
        updated = get_panel_creds()
        self.send_json(200, {"success": True, "secret": new_secret, "panel_name": new_name or creds.get("PANEL_NAME", "DAHOOM"),
                              "panel_logo": new_logo or creds.get("PANEL_LOGO", "Ⓓ"),
                              "panel_domain": updated.get("PANEL_DOMAIN", ""), "panel_telegram": updated.get("PANEL_TELEGRAM", "")})

    def handle_put_reseller_telegram(self, body, session):
        """Self-service: a reseller sets their OWN Telegram support handle,
        shown on their customers' usage-status pages instead of the admin's
        (bandwidth_link.py resolves per-user by owner). Can only ever touch
        the caller's own record — never routed through the admin-only
        /api/resellers/<name> path."""
        new_telegram = str(body.get("telegram_contact", "")).strip().lstrip('@')
        if new_telegram and not re.match(r'^[A-Za-z0-9_]{5,32}$', new_telegram):
            return self.send_json(400, {"error": "معرّف تيليجرام غير صالح — أحرف/أرقام/underscore فقط، من 5 إلى 32 حرفًا"})
        resellers = read_resellers()
        uname = (session.get("username") or "").strip().lower()
        found = False
        for r in resellers:
            if r["username"].strip().lower() == uname:
                r["telegram_contact"] = new_telegram
                found = True
                break
        if not found:
            return self.send_json(404, {"error": "Reseller not found"})
        write_resellers(resellers)
        self.send_json(200, {"success": True, "telegram_contact": new_telegram})

    # --- RESELLER HANDLERS (admin only) ---
    def handle_get_resellers(self):
        resellers = read_resellers()
        users = read_db()
        result = []
        for r in resellers:
            owned = [u for u in users if u.get("owner") == r["username"]]
            exp = parse_expiry_datetime(r.get("expire_date"))
            is_expired = (exp < datetime.now()) if exp else False
            result.append({
                "username": r["username"],
                "password": r["password"],
                "expire_date": r["expire_date"],
                "max_users": r["max_users"],
                "created_users": len(owned),
                "enabled": r["enabled"],
                "is_expired": is_expired,
                "type": r.get("type", "quota"),
                "credits": r.get("credits", 0),
                "max_conn_per_user": r.get("max_conn_per_user", 2),
                "max_bw_per_user": r.get("max_bw_per_user", 0),
                "allow_bulk": r.get("allow_bulk", True),
                "allow_trials": r.get("allow_trials", True),
                "max_speed_mbps": r.get("max_speed_mbps", 0)
            })
        server_ip = get_public_host()
        reseller_sec = get_reseller_secret()
        portal_path = f"/reseller_{reseller_sec}"
        portal_url = f"http://{server_ip}:{PORT}{portal_path}"
        self.send_json(200, {
            "resellers": result,
            "reseller_secret": reseller_sec,
            "reseller_portal_path": portal_path,
            "reseller_portal_url": portal_url
        })

    def handle_post_reseller(self, body):
        try:
            un = body.get("username", "").strip()
            pwd = body.get("password", "") or generate_password()
            r_days, r_hours = extract_duration_days_hours(body, default_days=30)
            max_users = int(body.get("max_users", 10))
            max_conn = int(body.get("max_conn_per_user", 2))
            max_bw = float(body.get("max_bw_per_user", 0))
            allow_bulk = bool(body.get("allow_bulk", True))
            allow_trials = bool(body.get("allow_trials", True))
            max_speed = int(body.get("max_speed_mbps", 0))

            if not re.match(r'^[a-zA-Z0-9_]{3,32}$', un):
                return self.send_json(400, {"error": "Invalid username (3-32 chars, alphanumeric + underscore)"})

            # Check conflicts with admin username
            creds = get_panel_creds()
            if un == creds.get("PANEL_USER"):
                return self.send_json(400, {"error": "Username conflicts with admin"})

            resellers = read_resellers()
            if any(r["username"] == un for r in resellers):
                return self.send_json(400, {"error": "Reseller already exists"})

            rtype = body.get("type", "quota")
            if rtype == "credits":
                credits_amount = int(body.get("credits", 0))
                new_r = {
                    "username": un,
                    "password": pwd,
                    "expire_date": "Never",
                    "max_users": 0,
                    "enabled": True,
                    "type": "credits",
                    "credits": credits_amount,
                    "max_conn_per_user": max_conn,
                    "max_bw_per_user": max_bw,
                    "allow_bulk": allow_bulk,
                    "allow_trials": allow_trials,
                    "max_speed_mbps": max_speed
                }
            else:
                new_r = {
                    "username": un,
                    "password": pwd,
                    "expire_date": calculate_expire_date(days=r_days, hours=r_hours),
                    "max_users": max_users,
                    "enabled": True,
                    "type": "quota",
                    "credits": 0,
                    "max_conn_per_user": max_conn,
                    "max_bw_per_user": max_bw,
                    "allow_bulk": allow_bulk,
                    "allow_trials": allow_trials,
                    "max_speed_mbps": max_speed
                }
            resellers.append(new_r)
            write_resellers(resellers)
            self.send_json(200, new_r)
        except Exception as e:
            self.send_json(400, {"error": str(e)})

    def handle_put_reseller(self, username, body):
        resellers = read_resellers()
        idx = next((i for i, r in enumerate(resellers) if r["username"] == username), -1)
        if idx == -1:
            return self.send_json(404, {"error": "Reseller not found"})

        r = resellers[idx]
        if "password" in body and body["password"]:
            r["password"] = body["password"]
        if "days" in body or "hours" in body or "duration_value" in body:
            r_days, r_hours = extract_duration_days_hours(body, default_days=0)
            if r_days > 0 or r_hours > 0:
                r["expire_date"] = calculate_expire_date(days=r_days, hours=r_hours)
        if "max_users" in body:
            r["max_users"] = int(body["max_users"])
        if "add_credits" in body:
            r["credits"] = r.get("credits", 0) + int(body["add_credits"])
        if "set_credits" in body:
            r["credits"] = int(body["set_credits"])
        if "max_conn_per_user" in body:
            r["max_conn_per_user"] = int(body["max_conn_per_user"])
        if "max_bw_per_user" in body:
            r["max_bw_per_user"] = float(body["max_bw_per_user"])
        if "allow_bulk" in body:
            r["allow_bulk"] = bool(body["allow_bulk"])
        if "allow_trials" in body:
            r["allow_trials"] = bool(body["allow_trials"])
        if "max_speed_mbps" in body:
            r["max_speed_mbps"] = int(body["max_speed_mbps"])

        resellers[idx] = r
        write_resellers(resellers)
        self.send_json(200, r)

    def handle_toggle_reseller(self, username):
        resellers = read_resellers()
        idx = next((i for i, r in enumerate(resellers) if r["username"] == username), -1)
        if idx == -1:
            return self.send_json(404, {"error": "Reseller not found"})

        resellers[idx]["enabled"] = not resellers[idx]["enabled"]
        now_enabled = resellers[idx]["enabled"]
        write_resellers(resellers)

        # Lock/unlock all SSH users owned by this reseller
        users = read_db()
        owned = [u for u in users if u.get("owner") == username]
        for u in owned:
            un = u["username"]
            if now_enabled:
                run_cmd(f"usermod -U {un}", ignore_errors=True)
            else:
                run_cmd(f"usermod -L {un}", ignore_errors=True)
                kill_user_sessions(un)

        # Invalidate reseller's panel sessions when disabling
        if not now_enabled:
            tokens_to_remove = [t for t, s in sessions.items() if s.get("username") == username and s.get("role") == "reseller"]
            for t in tokens_to_remove:
                del sessions[t]
            if tokens_to_remove:
                save_sessions()

        self.send_json(200, {"success": True, "enabled": now_enabled, "affected_users": len(owned)})

    def handle_add_credits(self, username, body):
        resellers = read_resellers()
        idx = next((i for i, r in enumerate(resellers) if r["username"] == username), -1)
        if idx == -1:
            return self.send_json(404, {"error": "Reseller not found"})
        
        amount = int(body.get("credits", 0))
        if amount <= 0:
            return self.send_json(400, {"error": "Credits must be positive"})
        
        resellers[idx]["credits"] = resellers[idx].get("credits", 0) + amount
        write_resellers(resellers)
        self.send_json(200, {"success": True, "credits": resellers[idx]["credits"]})

    def handle_delete_reseller(self, username, delete_users=False):
        resellers = read_resellers()
        idx = next((i for i, r in enumerate(resellers) if r["username"] == username), -1)
        if idx == -1:
            return self.send_json(404, {"error": "Reseller not found"})

        if delete_users:
            users = read_db()
            owned = [u for u in users if u.get("owner") == username]
            for u in owned:
                un = u["username"]
                force_delete_system_user(un)
                run_cmd(f"rm -f {BW_DIR}/{un}.*", ignore_errors=True)
                run_cmd(f"rm -f /etc/firewallfalcon/banners/{un}.txt", ignore_errors=True)
            
            with db_lock:
                if os.path.exists(DB_FILE):
                    with open(DB_FILE, "r") as f:
                        lines = f.readlines()
                    owned_names = set(u["username"] for u in owned)
                    with open(DB_FILE, "w") as f:
                        for line in lines:
                            parts = line.strip().split(":")
                            if parts and parts[0] not in owned_names:
                                f.write(line)

        del resellers[idx]
        write_resellers(resellers)

        # Invalidate reseller's sessions
        tokens_to_remove = [t for t, s in sessions.items() if s.get("username") == username and s.get("role") == "reseller"]
        for t in tokens_to_remove:
            del sessions[t]
        if tokens_to_remove:
            save_sessions()

        self.send_json(200, {"success": True})

    # --- CLOUDFLARE HANDLERS (admin only) ---
    def handle_get_cloudflare(self):
        qs = parse_qs(urlparse(self.path).query)
        is_fresh = bool(qs.get("fresh") or qs.get("sync"))
        if is_fresh:
            invalidate_cf_cache()

        now = time.time()
        if not is_fresh and _CF_CACHE["status"] and (now - _CF_CACHE["status_ts"] < _CF_CACHE_TTL):
            return self.send_json(200, _CF_CACHE["status"])

        cfg = read_cloudflare_config()
        token = cfg.get("api_token", "")
        zone_id = cfg.get("zone_id", "")
        domain = cfg.get("domain", "")
        proxied = cfg.get("proxied", False)
        
        configured = bool(token and zone_id)
        is_valid = False
        status_msg = "غير مهيأ في الأداة"
        
        if configured:
            try:
                res = cf_api_request(f"/zones/{zone_id}", token=token)
                if res.get("success"):
                    is_valid = True
                    status_msg = "متصل بنجاح"
                    zone_name = res.get("result", {}).get("name", "")
                    if zone_name and not domain:
                        domain = zone_name
            except Exception as e:
                status_msg = f"خطأ في الاتصال: {str(e)}"
        
        masked_token = (token[:4] + "••••••••" + token[-4:]) if len(token) >= 8 else ("••••" if token else "")
        server_ip = detect_server_ip()
        
        resp = {
            "configured": configured,
            "valid": is_valid,
            "status_msg": status_msg,
            "domain": domain,
            "zone_id": zone_id,
            "token_masked": masked_token,
            "has_token": bool(token),
            "proxied": proxied,
            "server_ip": server_ip
        }
        _CF_CACHE["status"] = resp
        _CF_CACHE["status_ts"] = now
        self.send_json(200, resp)

    def handle_get_cloudflare_records(self):
        qs = parse_qs(urlparse(self.path).query)
        is_fresh = bool(qs.get("fresh") or qs.get("sync"))
        if is_fresh:
            invalidate_cf_cache()

        now = time.time()
        if not is_fresh and _CF_CACHE["records"] and (now - _CF_CACHE["records_ts"] < _CF_CACHE_TTL):
            return self.send_json(200, _CF_CACHE["records"])

        cfg = read_cloudflare_config()
        zone_id = cfg.get("zone_id", "")
        if not zone_id or not cfg.get("api_token"):
            return self.send_json(400, {"error": "لم يتم إعداد Cloudflare بعد من الأداة"})
        
        try:
            res = cf_api_request(f"/zones/{zone_id}/dns_records?per_page=100")
            records = res.get("result", [])
            out = []
            for r in records:
                out.append({
                    "id": r.get("id"),
                    "type": r.get("type"),
                    "name": r.get("name"),
                    "content": r.get("content"),
                    "proxied": r.get("proxied", False),
                    "ttl": r.get("ttl", 1),
                    "proxiable": r.get("proxiable", True),
                    "priority": r.get("priority"),
                    "created_on": r.get("created_on"),
                    "modified_on": r.get("modified_on"),
                    "data": r.get("data")
                })
            resp = {"records": out, "domain": cfg.get("domain", "")}
            _CF_CACHE["records"] = resp
            _CF_CACHE["records_ts"] = now
            self.send_json(200, resp)
        except Exception as e:
            self.send_json(500, {"error": str(e)})

    def handle_post_cloudflare_record(self, body):
        cfg = read_cloudflare_config()
        zone_id = cfg.get("zone_id", "")
        if not zone_id or not cfg.get("api_token"):
            return self.send_json(400, {"error": "لم يتم إعداد Cloudflare بعد من الأداة"})
        
        rtype = body.get("type", "A").upper()
        name = body.get("name", "").strip()
        content = body.get("content", "").strip()
        proxied = bool(body.get("proxied", False))
        ttl = int(body.get("ttl", 1))
        
        # Clean URL prefixes or trailing slashes if user pasted a URL instead of IP/host
        if rtype in ("A", "AAAA"):
            content = re.sub(r"^https?://", "", content, flags=re.I).rstrip("/")
            if ":" in content and rtype == "A": # If port is attached, strip port
                content = content.split(":")[0]
        
        if rtype not in ("A", "AAAA", "CNAME"):
            proxied = False
        if proxied:
            ttl = 1  # Cloudflare requires TTL=1 (auto) when proxied is true
        
        if not name:
            name = "@"
        
        if not content and rtype not in ("SRV", "CAA"):
            return self.send_json(400, {"error": "يرجى تحديد القيمة أو عنوان الـ IP"})
        
        payload = {
            "type": rtype,
            "name": name,
            "ttl": ttl,
            "proxied": proxied
        }
        if content:
            payload["content"] = content
        
        if rtype in ("MX", "SRV") and body.get("priority") is not None:
            try: payload["priority"] = int(body["priority"])
            except Exception: pass
            
        if "data" in body and isinstance(body["data"], dict):
            payload["data"] = body["data"]
        
        try:
            res = cf_api_request(f"/zones/{zone_id}/dns_records", method="POST", data=payload)
            invalidate_cf_cache()
            self._log_action("admin", "INFO", "CF_ADD_RECORD", name, f"type={rtype} content={content} proxied={proxied}")
            self.send_json(200, {"success": True, "record": res.get("result")})
        except Exception as e:
            self.send_json(400, {"error": str(e)})

    def handle_put_cloudflare_record(self, record_id, body):
        cfg = read_cloudflare_config()
        zone_id = cfg.get("zone_id", "")
        if not zone_id or not cfg.get("api_token"):
            return self.send_json(400, {"error": "لم يتم إعداد Cloudflare بعد من الأداة"})
        
        payload = {}
        rtype = body.get("type", "").upper()
        if rtype:
            payload["type"] = rtype
        if "name" in body:
            payload["name"] = body["name"].strip()
        if "content" in body:
            c = body["content"].strip()
            if rtype in ("A", "AAAA") or ("type" not in body and "." in c):
                c = re.sub(r"^https?://", "", c, flags=re.I).rstrip("/")
                if ":" in c and rtype == "A":
                    c = c.split(":")[0]
            payload["content"] = c
        if "proxied" in body:
            proxied = bool(body["proxied"])
            if rtype and rtype not in ("A", "AAAA", "CNAME"):
                proxied = False
            payload["proxied"] = proxied
            if proxied:
                payload["ttl"] = 1
        if "ttl" in body and not payload.get("proxied", False):
            payload["ttl"] = int(body["ttl"])
        if "priority" in body and body["priority"] is not None:
            try: payload["priority"] = int(body["priority"])
            except Exception: pass
        if "data" in body and isinstance(body["data"], dict):
            payload["data"] = body["data"]
        
        try:
            res = cf_api_request(f"/zones/{zone_id}/dns_records/{record_id}", method="PATCH", data=payload)
            invalidate_cf_cache()
            self._log_action("admin", "INFO", "CF_UPDATE_RECORD", record_id, f"payload={payload}")
            self.send_json(200, {"success": True, "record": res.get("result")})
        except Exception as e:
            self.send_json(400, {"error": str(e)})

    def handle_delete_cloudflare_record(self, record_id):
        cfg = read_cloudflare_config()
        zone_id = cfg.get("zone_id", "")
        if not zone_id or not cfg.get("api_token"):
            return self.send_json(400, {"error": "لم يتم إعداد Cloudflare بعد من الأداة"})
        
        try:
            cf_api_request(f"/zones/{zone_id}/dns_records/{record_id}", method="DELETE")
            invalidate_cf_cache()
            self._log_action("admin", "INFO", "CF_DELETE_RECORD", record_id, "deleted")
            self.send_json(200, {"success": True})
        except Exception as e:
            self.send_json(400, {"error": str(e)})

    def handle_sync_cloudflare_ip(self, body):
        cfg = read_cloudflare_config()
        zone_id = cfg.get("zone_id", "")
        if not zone_id or not cfg.get("api_token"):
            return self.send_json(400, {"error": "لم يتم إعداد Cloudflare بعد من الأداة"})
        
        server_ip = detect_server_ip()
        if not server_ip:
            return self.send_json(500, {"error": "تعذر اكتشاف عنوان IP السيرفر"})
        
        domain = body.get("name", "").strip() or cfg.get("domain", "")
        proxied = body.get("proxied", cfg.get("proxied", False))
        
        if not domain:
            return self.send_json(400, {"error": "يرجى تحديد النطاق المراد مزامنته"})
        
        try:
            res = cf_api_request(f"/zones/{zone_id}/dns_records?type=A&name={domain}")
            records = res.get("result", [])
            if records:
                rec_id = records[0]["id"]
                cf_api_request(f"/zones/{zone_id}/dns_records/{rec_id}", method="PATCH", data={
                    "content": server_ip,
                    "proxied": proxied
                })
                action_txt = "تحديث"
            else:
                cf_api_request(f"/zones/{zone_id}/dns_records", method="POST", data={
                    "type": "A",
                    "name": domain,
                    "content": server_ip,
                    "ttl": 1,
                    "proxied": proxied
                })
                action_txt = "إنشاء"
            
            invalidate_cf_cache()
            self._log_action("admin", "INFO", "CF_SYNC_IP", domain, f"ip={server_ip} proxied={proxied}")
            self.send_json(200, {"success": True, "server_ip": server_ip, "domain": domain, "message": f"تم {action_txt} سجل A للنطاق {domain} ليشير إلى {server_ip} بنجاح"})
        except Exception as e:
            self.send_json(400, {"error": str(e)})

def main():
    os.makedirs(os.path.dirname(DB_FILE), exist_ok=True)
    server_address = ('0.0.0.0', PORT)
    httpd = ThreadingHTTPServer(server_address, PanelAPIHandler)
    print(f"Starting server on port {PORT}...", flush=True)

    # Second, TLS-only listener for /api/node/* — separate port so the
    # existing plain-HTTP admin UI on PORT is never affected (no forced
    # migration to https:// for anyone not opting into node mode).
    # Only starts if this box was explicitly turned into a node via the
    # "enable this server as a VPN node" action (bot_node_self_enable) —
    # a single-box deployment never runs this, unchanged from today.
    node_httpd = None
    node_self = bot_node_self_get()
    if node_self and node_self.get("enabled") and os.path.exists(node_self["cert"]) and os.path.exists(node_self["key"]):
        try:
            import ssl
            node_httpd = ThreadingHTTPServer(('0.0.0.0', NODE_API_PORT), PanelAPIHandler)
            ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            ctx.load_cert_chain(certfile=node_self["cert"], keyfile=node_self["key"])
            node_httpd.socket = ctx.wrap_socket(node_httpd.socket, server_side=True)
            threading.Thread(target=node_httpd.serve_forever, daemon=True).start()
            print(f"Node API listening on port {NODE_API_PORT} (TLS)...", flush=True)
        except Exception as e:
            print(f"[node-api] failed to start: {e}", file=sys.stderr, flush=True)
            node_httpd = None

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    if node_httpd:
        node_httpd.server_close()
    httpd.server_close()
    print("Server stopped.")

if __name__ == '__main__':
    main()
