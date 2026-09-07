#!/usr/bin/env python3
import os
import sys
import json
import math
import time
import subprocess
import secrets
import hashlib
import threading
import re
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from http import cookies
from urllib.parse import urlparse, parse_qs
import urllib.request
import urllib.error
from datetime import datetime, timedelta

# Ensure local directories are in python search path
for _p in ["/etc/firewallfalcon/panel", "/usr/local/bin", os.path.dirname(os.path.abspath(__file__))]:
    if _p and _p not in sys.path:
        sys.path.insert(0, _p)

# --- CONSTANTS ---
DB_FILE = "/etc/firewallfalcon/users.db"
HWID_DB_FILE = "/etc/firewallfalcon/hwid.db"
RESELLERS_DB = "/etc/firewallfalcon/resellers.db"
BW_DIR = "/etc/firewallfalcon/bandwidth"
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
    {"name": "Falcon Proxy", "service": "falconproxy", "check_file": "/etc/systemd/system/falconproxy.service", "port": "8080"},
    {"name": "ZiVPN UDP", "service": "zivpn", "check_file": "/etc/systemd/system/zivpn.service", "port": "5667"},
    {"name": "X-UI / 3X-UI", "service": "x-ui", "service_alt": "3x-ui", "check_file": "/etc/systemd/system/x-ui.service", "port": "2053"},
    {"name": "Xray Core (V2Ray / Reality)", "service": "xray", "service_alt": "xray-core", "check_file": "/usr/local/bin/xray", "port": "8443/2052/2096"},
    {"name": "Multi-Login Limiter", "service": "firewallfalcon-limiter", "check_file": "/etc/systemd/system/firewallfalcon-limiter.service", "port": "Daemon"},
    {"name": "Bandwidth Monitor", "service": "firewallfalcon-bandwidth", "check_file": "/etc/systemd/system/firewallfalcon-bandwidth.service", "port": "Daemon"},
    {"name": "Outage & Health Guard", "service": "firewallfalcon-health", "check_file": "/etc/systemd/system/firewallfalcon-health.service", "port": "Daemon"},
]

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

def force_delete_system_user(username):
    """Kill all processes and force-delete a Linux system user."""
    import time as _time
    # Kill all processes owned by this user
    run_cmd(["pkill", "-9", "-u", username], ignore_errors=True)
    run_cmd(["killall", "-u", username, "-9"], ignore_errors=True)
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
        user["owner"] = parts[7] if parts[7] else "admin"
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
        "max_speed_mbps": int(parts[11]) if len(parts) > 11 and parts[11].isdigit() else 0
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
    return f"{r['username']}:{r['password']}:{r['expire_date']}:{r['max_users']}:{enabled}:{rtype}:{credits}:{max_conn}:{max_bw}:{allow_bulk}:{allow_trials}:{max_speed}\n"

def write_resellers(resellers):
    os.makedirs(os.path.dirname(RESELLERS_DB), exist_ok=True)
    with open(RESELLERS_DB, "w") as f:
        for r in resellers:
            f.write(format_reseller_line(r))

def read_hwid_db():
    """Read HWID database: {hwid: {'username': str, 'account_type': str, 'created_at': float}}"""
    hwid_map = {}
    if not os.path.exists(HWID_DB_FILE):
        return hwid_map
    try:
        with open(HWID_DB_FILE, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split(":")
                if len(parts) >= 3:
                    hwid, username, acct_type = parts[0], parts[1], parts[2]
                    created_at = float(parts[3]) if len(parts) > 3 and parts[3].replace('.', '', 1).isdigit() else time.time()
                    hwid_map[hwid] = {
                        "username": username,
                        "account_type": acct_type,
                        "created_at": created_at
                    }
    except Exception:
        pass
    return hwid_map

def write_hwid_db(hwid_map):
    """Write HWID database."""
    os.makedirs(os.path.dirname(HWID_DB_FILE), exist_ok=True)
    with open(HWID_DB_FILE, "w") as f:
        for hwid, data in hwid_map.items():
            f.write(f"{hwid}:{data['username']}:{data.get('account_type', '')}:{data.get('created_at', time.time())}\n")

def check_hwid_allowed(hwid, account_type, users_list):
    """
    Check if HWID can be used for new account.
    Rules:
    - Trial accounts: allowed only if HWID not used before
    - Paid accounts (monthly/etc): allowed if HWID not used, OR if used by a trial account (upgrade case)
    - Cannot create paid account if HWID already used by another paid account
    Returns: (allowed: bool, error_msg: str or None)
    """
    if not hwid:
        return True, None  # No HWID provided, skip check
    
    hwid_data = read_hwid_db()
    
    if hwid not in hwid_data:
        # HWID not used before, always allowed
        return True, None
    
    existing = hwid_data[hwid]
    existing_acct_type = existing.get("account_type", "")
    
    # If new account is trial
    if account_type == "trial":
        # Trial not allowed if HWID was ever used
        return False, "❌ لا يمكن إتمام الطلب: هذا الجهاز (HWID) مستخدم بالفعل على حساب آخر. يرجى استخدام جهاز آخر أو التواصل مع الدعم."
    
    # If new account is paid (monthly, bulk, web, etc.)
    # Check if existing account on this HWID is also paid
    if existing_acct_type and existing_acct_type != "trial":
        # HWID already used by a paid account
        return False, "❌ لا يمكن إتمام الطلب: هذا الجهاز (HWID) مستخدم بالفعل على حساب شهري. يرجى استخدام جهاز آخر أو التواصل مع الدعم."
    
    # Existing account is trial, new account is paid -> upgrade allowed
    return True, None

def update_hwid_db(hwid, username, account_type):
    """Add or update HWID entry in database."""
    if not hwid:
        return
    hwid_map = read_hwid_db()
    hwid_map[hwid] = {
        "username": username,
        "account_type": account_type,
        "created_at": time.time()
    }
    write_hwid_db(hwid_map)

def calculate_credit_cost(days=0, hours=0):
    """Calculate credit cost: 1 credit per 30 days (720 hours), rounded up."""
    total_hours = days * 24 + hours
    if total_hours <= 0:
        return 1
    return math.ceil(total_hours / (30 * 24))

# --- ONLINE SESSIONS ---
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
        "PANEL_PORT": "44380"
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

def write_panel_creds(user, pass_plain, secret=None, panel_name=None, panel_logo=None):
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
    
    conf_path = get_panel_conf_path()
    os.makedirs(os.path.dirname(conf_path), exist_ok=True)
    with open(conf_path, "w", encoding="utf-8") as f:
        for k, v in creds.items():
            f.write(f"{k}={v}\n")

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
    """Parse expiry datetime from multiple formats (YYYY-MM-DD, YYYY-MM-DD HH:MM, YYYY-MM-DD HH:MM:SS)."""
    if not date_str or date_str in ("Never", "N/A"):
        return None
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d"):
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
        return target_dt.strftime("%Y-%m-%d %H:%M")
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
    host = domain or server_ip or detect_server_ip() or "YOUR_SERVER_IP"
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
                elif api_path.startswith("/api/users/") and api_path.endswith("/history"):
                    username = api_path.split("/")[3]
                    if not self._check_user_ownership(username, session):
                        return self.send_json(403, {"error": "Access denied"})
                    self.handle_user_history(username)
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
                elif api_path == "/api/settings":
                    if not self._require_admin(session):
                        return
                    self.handle_get_settings()
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
                    server_ip = detect_server_ip()
                    link = generate_admin_autologin_link(server_ip=server_ip)
                    self.send_json(200, {
                        "success": True,
                        "link": link,
                        "expires_in_seconds": 3600,
                        "message": "Dynamic 1-hour 1-click login link generated"
                    })
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
            server_ip = detect_server_ip()
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
        else:
            self.send_json(404, {"error": "Not Found"})

    def do_PUT(self):
        parsed_path = urlparse(self.path)
        path = self._clean_path(parsed_path.path.strip())
        
        session = self._get_session()
        if not session:
            return

        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)
        try:
            body = json.loads(post_data.decode('utf-8')) if post_data else {}
        except json.JSONDecodeError:
            body = {}

        if path.startswith("/api/users/"):
            user = path.split("/")[3]
            self.handle_put_user(user, body, session)
        elif path == "/api/settings":
            if not self._require_admin(session):
                return
            self.handle_put_settings(body)
        elif path.startswith("/api/resellers/"):
            if not self._require_admin(session):
                return
            reseller_name = path.split("/")[3]
            self.handle_put_reseller(reseller_name, body)
        elif path.startswith("/api/cloudflare/records/"):
            if not self._require_admin(session): return
            record_id = path.split("/")[4]
            self.handle_put_cloudflare_record(record_id, body)
        else:
            self.send_json(404, {"error": "Not Found"})

    def do_DELETE(self):
        parsed_path = urlparse(self.path)
        path = self._clean_path(parsed_path.path.strip())
        
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
        elif path.startswith("/api/users/"):
            user = path.split("/")[3]
            self.handle_delete_user(user, session)
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

    # --- HANDLERS ---
    def handle_login(self, body):
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
                token = secrets.token_hex(32)
                sessions[token] = {"username": r_user, "role": "reseller", "created_at": time.time()}
                save_sessions()
                cookie_str = f"reseller_session={token}; Path=/; HttpOnly; Max-Age=86400; SameSite=Lax"
                self._log_panel_access(r_user, "login")
                self.send_json(200, {"success": True, "role": "reseller", "token": token, "username": r_user}, {"Set-Cookie": cookie_str})
                return

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
                "max_speed_mbps": r_speed
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
            
            result.append({
                "username": un,
                "ip": info.get("ip", "Unknown"),
                "login_time": info.get("login_time", ""),
                "duration_seconds": max(0, duration_s),
                "sessions": len(pids),
                "pids": list(pids)
            })
        
        self.send_json(200, {"online": result, "total": sum(len(o["pids"]) for o in result)})

    def handle_kick_user(self, username):
        online_pids = get_online_sessions_for_users({username})
        pids = online_pids.get(username, set())
        killed = 0
        for pid in pids:
            code, _, _ = run_cmd(["kill", "-HUP", str(pid)], ignore_errors=True)
            if code == 0:
                killed += 1
        self.send_json(200, {"success": True, "killed": killed})

    def handle_user_history(self, username):
        _, last_out, _ = run_cmd(["last", username, "-n", "50", "-a"])
        _, fail_out, _ = run_cmd(["lastb", username, "-n", "20"], ignore_errors=True)
        entries = []
        for line in last_out.splitlines():
            line = line.strip()
            if not line or 'wtmp' in line or 'btmp' in line:
                continue
            entries.append(line)
        failed = []
        for line in (fail_out or '').splitlines():
            line = line.strip()
            if not line or 'btmp' in line:
                continue
            failed.append(line)
        self.send_json(200, {"history": entries[:50], "failed": failed[:20]})

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

    def handle_post_user_speeds(self, body):
        action = body.get("action")  # "set", "remove", "remove_all"
        username = body.get("username", "").strip()
        speed = body.get("speed", 0)
        
        os.makedirs(os.path.dirname(USER_SPEED_CONF), exist_ok=True)
        
        if action == "remove_all":
            with open(USER_SPEED_CONF, 'w') as f: pass
            return self.send_json(200, {"success": True})
        
        if not username:
            return self.send_json(400, {"error": "username required"})
        
        if action == "set":
            if not isinstance(speed, int) or speed < 1:
                return self.send_json(400, {"error": "Speed must be positive integer (Mbps)"})
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
        self.send_json(200, {"success": True})

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
            
            result.append(u_ext)
            
        self.send_json(200, {"users": result})

    def _create_user(self, un, pwd, days=0, conn=1, bw=0, dbw=0, acct_type="web", owner="admin", hours=0):
        if not re.match(r'^[a-zA-Z0-9_]{3,32}$', un):
            raise ValueError("Invalid username")
            
        if any(u["username"] == un for u in read_db()):
            raise ValueError("User already exists in DB")
            
        code, _, _ = run_cmd(["id", un])
        if code == 0:
            raise ValueError("User already exists on system")

        run_cmd(["useradd", "-m", "-s", "/usr/sbin/nologin", un])
        run_cmd(["usermod", "-aG", FF_USERS_GROUP, un], ignore_errors=True)
        run_cmd(f"echo '{un}:{pwd}' | chpasswd")
        
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
        
        # Initialize bandwidth usage files to prevent immediate locking
        os.makedirs(BW_DIR, exist_ok=True)
        with open(f"{BW_DIR}/{un}.usage", "w") as f:
            f.write("0")
        with open(f"{BW_DIR}/{un}.daily_usage", "w") as f:
            f.write("0")
                
        refresh_ssh_banner_config()
        self._log_action("admin", "INFO", "CREATE_USER", un, f"exp={exp_date_str} conn={conn} bw={bw} daily={dbw}", operator=owner)
        return new_u

    def handle_post_users(self, body, session):
        try:
            owner = session.get("username", "admin") if session.get("role") == "reseller" else "admin"
            days, hours = extract_duration_days_hours(body, default_days=30)
            conn = int(body.get("conn_limit", 1))
            bw = float(body.get("bandwidth_gb", 0))
            dbw = float(body.get("daily_bandwidth_gb", 0))
            hwid = body.get("hwid", "")

            # HWID check BEFORE any processing
            allowed, hwid_error = check_hwid_allowed(hwid, "web", [])
            if not allowed:
                return self.send_json(400, {"error": hwid_error})

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

            un = body.get("username", "")
            pwd = body.get("password", "") or generate_password()
            
            new_u = self._create_user(un, pwd, days=days, conn=conn, bw=bw, dbw=dbw, owner=owner, hours=hours)
            
            # Update HWID database after successful creation
            update_hwid_db(hwid, un, "web")
            
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
            hwid = body.get("hwid", "")

            # HWID check BEFORE any processing for trial accounts
            allowed, hwid_error = check_hwid_allowed(hwid, "trial", [])
            if not allowed:
                return self.send_json(400, {"error": hwid_error})

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
            
            new_u = self._create_user(un, pwd, days, conn, bw, 0, acct_type="trial", owner=owner)
            
            # Update HWID database after successful creation
            update_hwid_db(hwid, un, "trial")
            
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
                run_cmd(f"echo '{username}:{u['password']}' | chpasswd")
                
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
                    self.handle_post_user_speeds({"action": "set", "username": username, "speed": sp_val})
                else:
                    self.handle_post_user_speeds({"action": "remove", "username": username})

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
        
        operator = session.get("username", "admin") if session else "admin"
        self._log_action("admin", "INFO", "DELETE_USER", username, "", operator=operator)
        self.send_json(200, {"success": True})

    def handle_user_action(self, username, action, body=None, session=None):
        if not self._check_user_ownership(username, session):
            return self.send_json(403, {"error": "Access denied"})

        operator = session.get("username", "admin") if session else "admin"
        if action == "lock":
            run_cmd(["usermod", "-L", username])
            run_cmd(["killall", "-u", username, "-9"], ignore_errors=True)
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
                    u["expire_date"] = new_exp_dt.strftime("%Y-%m-%d %H:%M")
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
            creds["PANEL_LOGO"] = "🦅"
            os.makedirs(os.path.dirname(PANEL_CONF), exist_ok=True)
            with open(PANEL_CONF, "w") as f:
                for k, v in creds.items():
                    f.write(f"{k}={v}\n")
            self.send_json(200, {"success": True, "panel_logo": "🦅"})
        except Exception as e:
            self.send_json(500, {"error": str(e)})

    def handle_get_settings(self):
        creds = get_panel_creds()
        self.send_json(200, {
            "username": creds.get("PANEL_USER", ""),
            "secret": creds.get("PANEL_SECRET", ""),
            "panel_name": creds.get("PANEL_NAME", "DAHOOM"),
            "panel_logo": creds.get("PANEL_LOGO", "👑"),
            "has_custom_logo": os.path.exists("/etc/firewallfalcon/panel/logo.png") and creds.get("PANEL_LOGO") == "custom"
        })

    def handle_put_settings(self, body):
        creds = get_panel_creds()
        curr_pwd = body.get("current_password", "")
        new_user = body.get("new_username", "").strip() or creds.get("PANEL_USER", "")
        new_pwd = body.get("new_password", "").strip() or creds.get("PANEL_PASS_PLAIN", "")
        new_secret = body.get("new_secret", "").strip().lstrip('/')
        new_name = body.get("panel_name", "").strip()
        new_logo = body.get("panel_logo", "").strip()
        
        curr_hash = hashlib.sha256(curr_pwd.encode()).hexdigest()
        if curr_hash != creds.get("PANEL_PASS_HASH"):
            return self.send_json(401, {"error": "Invalid current password"})
            
        write_panel_creds(new_user, new_pwd, secret=new_secret, panel_name=new_name or None, panel_logo=new_logo or None)
        self.send_json(200, {"success": True, "secret": new_secret, "panel_name": new_name or creds.get("PANEL_NAME", "DAHOOM"), "panel_logo": new_logo or creds.get("PANEL_LOGO", "🦅")})

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
        server_ip = detect_server_ip()
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
                run_cmd(f"killall -u {un} -9", ignore_errors=True)

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
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()
    print("Server stopped.")

if __name__ == '__main__':
    main()
