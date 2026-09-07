#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DAHOOM - V2Ray / Xray Core Management & Subscription Engine
Provides dedicated user database, dynamic inbounds, config generator, and subscription links.
"""

import os
import sys
import json
import uuid
import time
import base64
import shutil
import urllib.parse
import subprocess
import threading
from datetime import datetime, timedelta

# --- CONSTANTS & PATHS ---
DATA_DIR = "/etc/firewallfalcon"
V2RAY_USERS_DB = os.path.join(DATA_DIR, "v2ray_users.db")
V2RAY_INBOUNDS_CONF = os.path.join(DATA_DIR, "v2ray_inbounds.json")
V2RAY_NODES_CONF = os.path.join(DATA_DIR, "v2ray_nodes.json")
XRAY_CONFIG_DIR = "/etc/xray"
XRAY_CONFIG_FILE = os.path.join(XRAY_CONFIG_DIR, "config.json")
ALT_XRAY_CONFIG = "/usr/local/etc/xray/config.json"

v2ray_db_lock = threading.Lock()

def ensure_v2ray_dirs():
    os.makedirs(DATA_DIR, exist_ok=True)
    os.makedirs(XRAY_CONFIG_DIR, exist_ok=True)
    if not os.path.exists(V2RAY_USERS_DB):
        try:
            with open(V2RAY_USERS_DB, "w", encoding="utf-8") as f:
                f.write("# DAHOOM V2Ray/Xray Users Database\n")
                f.write("# uuid:username:email:expire_date:bandwidth_gb:used_bw_bytes:is_active:created_date:owner:protocols:max_conn:sub_token:notes:allowed_nodes:restrictions:mode\n")
        except Exception:
            pass

ensure_v2ray_dirs()

# --- NODES FEDERATION MANAGEMENT ---
def get_default_nodes():
    return [
        {
            "id": "local",
            "name": "الخادم الرئيسي (المحلي)",
            "flag": "🇸🇦",
            "host": "",
            "is_local": True,
            "enabled": True,
            "reality_dest": "www.microsoft.com:443",
            "reality_sni": "www.microsoft.com"
        }
    ]

def read_v2ray_nodes():
    """Reads all server nodes configuration."""
    ensure_v2ray_dirs()
    if os.path.exists(V2RAY_NODES_CONF):
        try:
            with open(V2RAY_NODES_CONF, "r", encoding="utf-8") as f:
                nodes = json.load(f)
                if isinstance(nodes, list) and len(nodes) > 0:
                    return nodes
        except Exception:
            pass
    defaults = get_default_nodes()
    write_v2ray_nodes(defaults)
    return defaults

def write_v2ray_nodes(nodes):
    """Writes server nodes configuration."""
    ensure_v2ray_dirs()
    try:
        with open(V2RAY_NODES_CONF, "w", encoding="utf-8") as f:
            json.dump(nodes, f, indent=2, ensure_ascii=False)
        return True
    except Exception as e:
        print(f"Error saving nodes: {e}", file=sys.stderr)
        return False

# --- DATABASE CRUD ---
def read_v2ray_users():
    """Reads all V2Ray users from v2ray_users.db."""
    users = []
    if not os.path.exists(V2RAY_USERS_DB):
        return users
    with v2ray_db_lock:
        try:
            with open(V2RAY_USERS_DB, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    parts = line.split(":")
                    if len(parts) >= 6:
                        u_id = parts[0].strip()
                        un = parts[1].strip()
                        email = parts[2].strip() if len(parts) > 2 else f"{un}@ff.local"
                        exp = parts[3].strip() if len(parts) > 3 else "2099-12-31"
                        bw = float(parts[4].strip()) if (len(parts) > 4 and parts[4].strip()) else 0.0
                        used = int(parts[5].strip()) if (len(parts) > 5 and parts[5].strip()) else 0
                        is_active = (parts[6].strip().lower() in ("1", "true", "yes")) if len(parts) > 6 else True
                        created = parts[7].strip() if len(parts) > 7 else datetime.now().strftime("%Y-%m-%d")
                        owner = parts[8].strip() if len(parts) > 8 else "admin"
                        protos = parts[9].strip() if len(parts) > 9 and parts[9].strip() else "vless_reality,vmess_ws"
                        max_conn = int(parts[10].strip()) if (len(parts) > 10 and parts[10].strip().isdigit()) else 2
                        sub_token = parts[11].strip() if len(parts) > 11 and parts[11].strip() else uuid.uuid4().hex[:16]
                        notes = parts[12].strip() if len(parts) > 12 else ""
                        allowed_nodes_str = parts[13].strip() if len(parts) > 13 and parts[13].strip() else "*"
                        restrictions_str = parts[14].strip() if len(parts) > 14 and parts[14].strip() else "block_torrent=1,block_ads=1"
                        mode = parts[15].strip() if len(parts) > 15 and parts[15].strip() else "roaming"

                        allowed_nodes = [n.strip() for n in allowed_nodes_str.split(",") if n.strip()]
                        
                        # Parse restrictions
                        restr_dict = {}
                        for r_item in restrictions_str.split(","):
                            if "=" in r_item:
                                k, v = r_item.split("=", 1)
                                restr_dict[k.strip()] = (v.strip() in ("1", "true", "yes"))

                        users.append({
                            "uuid": u_id,
                            "username": un,
                            "email": email,
                            "expire_date": exp,
                            "bandwidth_gb": bw,
                            "used_bw_bytes": used,
                            "is_active": is_active,
                            "created_date": created,
                            "owner": owner,
                            "protocols": [p.strip() for p in protos.split(",") if p.strip()],
                            "max_conn": max_conn,
                            "sub_token": sub_token,
                            "notes": notes,
                            "allowed_nodes": allowed_nodes,
                            "restrictions": restr_dict,
                            "mode": mode
                        })
        except Exception as e:
            print(f"Error reading v2ray users db: {e}", file=sys.stderr)
    return users

def write_v2ray_users(users):
    """Atomically writes all V2Ray users to v2ray_users.db."""
    with v2ray_db_lock:
        ensure_v2ray_dirs()
        tmp_path = V2RAY_USERS_DB + ".tmp"
        try:
            with open(tmp_path, "w", encoding="utf-8") as f:
                f.write("# DAHOOM V2Ray/Xray Users Database\n")
                f.write("# uuid:username:email:expire_date:bandwidth_gb:used_bw_bytes:is_active:created_date:owner:protocols:max_conn:sub_token:notes:allowed_nodes:restrictions:mode\n")
                for u in users:
                    protos_str = ",".join(u.get("protocols", ["vless_reality"]))
                    act_str = "1" if u.get("is_active", True) else "0"
                    nodes_str = ",".join(u.get("allowed_nodes", ["*"]))
                    
                    restr = u.get("restrictions", {})
                    restr_parts = []
                    for rk, rv in restr.items():
                        restr_parts.append(f"{rk}={'1' if rv else '0'}")
                    restr_str = ",".join(restr_parts) if restr_parts else "block_torrent=1,block_ads=1"
                    mode_str = u.get("mode", "roaming")

                    line = f"{u['uuid']}:{u['username']}:{u.get('email', '')}:{u['expire_date']}:{u.get('bandwidth_gb', 0)}:{u.get('used_bw_bytes', 0)}:{act_str}:{u.get('created_date', '')}:{u.get('owner', 'admin')}:{protos_str}:{u.get('max_conn', 2)}:{u.get('sub_token', '')}:{u.get('notes', '')}:{nodes_str}:{restr_str}:{mode_str}\n"
                    f.write(line)
            shutil.move(tmp_path, V2RAY_USERS_DB)
            return True
        except Exception as e:
            print(f"Error writing v2ray users db: {e}", file=sys.stderr)
            if os.path.exists(tmp_path):
                try: os.remove(tmp_path)
                except Exception: pass
            return False

def find_v2ray_user(identifier):
    """Find a user by UUID, username, or sub_token."""
    users = read_v2ray_users()
    identifier_low = identifier.strip().lower()
    for u in users:
        if u["uuid"].lower() == identifier_low or u["username"].lower() == identifier_low or u.get("sub_token", "").lower() == identifier_low:
            return u
    return None

def create_v2ray_user(username, days=30, hours=0, bandwidth_gb=0, protocols=None, max_conn=2, owner="admin", notes="", custom_uuid=None, allowed_nodes=None, restrictions=None, mode="roaming"):
    """Creates a new V2Ray user and triggers config synchronization."""
    username = username.strip()
    if not username:
        raise ValueError("Username cannot be empty")
    
    users = read_v2ray_users()
    for u in users:
        if u["username"].lower() == username.lower():
            raise ValueError(f"User '{username}' already exists in V2Ray database")

    user_uuid = custom_uuid if custom_uuid else str(uuid.uuid4())
    sub_token = uuid.uuid4().hex[:16]
    
    target_dt = datetime.now() + timedelta(days=int(days), hours=int(hours))
    if hours > 0 and (hours % 24 != 0 or days == 0):
        exp_str = target_dt.strftime("%Y-%m-%d %H:%M")
    else:
        exp_str = target_dt.strftime("%Y-%m-%d")

    if not protocols:
        protocols = ["vless_reality", "vmess_ws"]

    if allowed_nodes is None:
        allowed_nodes = ["*"]

    if restrictions is None:
        restrictions = {"block_torrent": True, "block_ads": True, "block_porn": False}

    new_u = {
        "uuid": user_uuid,
        "username": username,
        "email": f"{username}@ff.local",
        "expire_date": exp_str,
        "bandwidth_gb": float(bandwidth_gb),
        "used_bw_bytes": 0,
        "is_active": True,
        "created_date": datetime.now().strftime("%Y-%m-%d"),
        "owner": owner,
        "protocols": protocols,
        "max_conn": int(max_conn),
        "sub_token": sub_token,
        "notes": notes,
        "allowed_nodes": allowed_nodes,
        "restrictions": restrictions,
        "mode": mode
    }
    users.append(new_u)
    if write_v2ray_users(users):
        apply_xray_config_safe()
        return new_u
    raise RuntimeError("Failed to write user to database")

def update_v2ray_user(user_uuid, data):
    """Updates user properties."""
    users = read_v2ray_users()
    found = False
    for u in users:
        if u["uuid"].lower() == user_uuid.strip().lower() or u["username"].lower() == user_uuid.strip().lower():
            if "expire_date" in data: u["expire_date"] = data["expire_date"]
            if "bandwidth_gb" in data: u["bandwidth_gb"] = float(data["bandwidth_gb"])
            if "used_bw_bytes" in data: u["used_bw_bytes"] = int(data["used_bw_bytes"])
            if "is_active" in data: u["is_active"] = bool(data["is_active"])
            if "protocols" in data: u["protocols"] = data["protocols"]
            if "max_conn" in data: u["max_conn"] = int(data["max_conn"])
            if "notes" in data: u["notes"] = str(data["notes"])
            if "allowed_nodes" in data: u["allowed_nodes"] = data["allowed_nodes"]
            if "restrictions" in data: u["restrictions"] = data["restrictions"]
            if "mode" in data: u["mode"] = data["mode"]
            found = True
            break
    if found and write_v2ray_users(users):
        apply_xray_config_safe()
        return True
    return False

def delete_v2ray_user(user_uuid):
    """Deletes a user."""
    users = read_v2ray_users()
    init_len = len(users)
    users = [u for u in users if u["uuid"].lower() != user_uuid.strip().lower() and u["username"].lower() != user_uuid.strip().lower()]
    if len(users) < init_len:
        if write_v2ray_users(users):
            apply_xray_config_safe()
            return True
    return False

def renew_v2ray_user(user_uuid, days=30, hours=0, is_cumulative=True, bw_action="keep", add_bw_gb=0):
    """Renews a V2Ray user subscription."""
    users = read_v2ray_users()
    for u in users:
        if u["uuid"].lower() == user_uuid.strip().lower() or u["username"].lower() == user_uuid.strip().lower():
            now = datetime.now()
            curr_exp_str = u.get("expire_date", "")
            base_dt = now

            if is_cumulative and curr_exp_str:
                try:
                    if " " in curr_exp_str:
                        parsed = datetime.strptime(curr_exp_str, "%Y-%m-%d %H:%M")
                    else:
                        parsed = datetime.strptime(curr_exp_str, "%Y-%m-%d")
                    if parsed > now:
                        base_dt = parsed
                except Exception:
                    base_dt = now

            new_dt = base_dt + timedelta(days=int(days), hours=int(hours))
            if hours > 0 and (hours % 24 != 0 or days == 0):
                u["expire_date"] = new_dt.strftime("%Y-%m-%d %H:%M")
            else:
                u["expire_date"] = new_dt.strftime("%Y-%m-%d")

            if bw_action == "reset":
                u["used_bw_bytes"] = 0
            elif bw_action == "add":
                u["bandwidth_gb"] = round(float(u.get("bandwidth_gb", 0)) + float(add_bw_gb), 2)
            
            u["is_active"] = True
            if write_v2ray_users(users):
                apply_xray_config_safe()
                return u
    return None

def import_ssh_users_to_v2ray(ssh_db_path="/etc/firewallfalcon/users.db"):
    """Imports existing SSH users into the isolated V2Ray database."""
    if not os.path.exists(ssh_db_path):
        return {"imported": 0, "total_existing": 0, "users": []}

    existing_v2 = read_v2ray_users()
    existing_un_map = {u["username"].lower(): u for u in existing_v2}
    
    imported_list = []
    with v2ray_db_lock:
        try:
            with open(ssh_db_path, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    parts = line.split(":")
                    if len(parts) >= 3:
                        un = parts[0].strip()
                        if not un or un.lower() in existing_un_map:
                            continue
                        exp = parts[2].strip() if len(parts) > 2 else "2099-12-31"
                        max_conn = int(parts[3].strip()) if len(parts) > 3 and parts[3].strip().isdigit() else 2
                        bw = float(parts[4].strip()) if len(parts) > 4 and parts[4].strip().replace('.', '', 1).isdigit() else 0.0
                        owner = parts[6].strip() if len(parts) > 6 and parts[6].strip() else "admin"

                        new_u = {
                            "uuid": str(uuid.uuid4()),
                            "username": un,
                            "email": f"{un}@ff.local",
                            "expire_date": exp if exp else "2099-12-31",
                            "bandwidth_gb": bw,
                            "used_bw_bytes": 0,
                            "is_active": True,
                            "created_date": datetime.now().strftime("%Y-%m-%d"),
                            "owner": owner,
                            "protocols": ["vless_reality", "vmess_ws", "vless_ws", "trojan_grpc"],
                            "max_conn": max_conn if max_conn > 0 else 2,
                            "sub_token": uuid.uuid4().hex[:16],
                            "notes": "Imported from SSH",
                            "allowed_nodes": ["*"],
                            "restrictions": {"block_torrent": True, "block_ads": True, "block_porn": False},
                            "mode": "roaming"
                        }
                        existing_v2.append(new_u)
                        existing_un_map[un.lower()] = new_u
                        imported_list.append(new_u)
        except Exception as e:
            print(f"Error importing SSH users: {e}", file=sys.stderr)

    if imported_list:
        write_v2ray_users(existing_v2)
        apply_xray_config_safe()

    return {
        "imported": len(imported_list),
        "total_v2ray": len(existing_v2),
        "users": imported_list
    }

# --- INBOUNDS CONFIGURATION ---
def get_default_inbounds():
    """Returns default inbounds structure."""
    return {
        "vless_reality": {
            "enabled": True,
            "port": 8443,
            "dest": "www.microsoft.com:443",
            "serverNames": ["www.microsoft.com", "azure.microsoft.com"],
            "privateKey": "",
            "publicKey": "",
            "shortIds": ["0123456789abcdef", ""]
        },
        "vmess_ws": {
            "enabled": True,
            "port": 2052,
            "path": "/vmess-ws",
            "security": "none"
        },
        "vless_ws": {
            "enabled": True,
            "port": 2082,
            "path": "/vless-ws",
            "security": "none"
        },
        "trojan_grpc": {
            "enabled": True,
            "port": 2096,
            "serviceName": "trojan-grpc"
        },
        "shadowsocks": {
            "enabled": False,
            "port": 8388,
            "method": "2022-blake3-aes-128-gcm",
            "password": str(uuid.uuid4().hex[:16])
        }
    }

# RFC 7748 Curve25519 Implementation for Xray REALITY Key Generation
_P25519 = 2**255 - 19
_A24 = 121665

def _cswap25519(swap, x_2, x_3):
    dummy = swap * ((x_2 - x_3) % _P25519)
    x_2 = (x_2 - dummy) % _P25519
    x_3 = (x_3 + dummy) % _P25519
    return x_2, x_3

def _x25519_mul(k_bytes, u_bytes):
    k = bytearray(k_bytes)
    k[0] &= 248
    k[31] &= 127
    k[31] |= 64
    k_int = int.from_bytes(k, 'little')
    u = int.from_bytes(u_bytes, 'little') % _P25519
    x_1 = u; x_2 = 1; z_2 = 0; x_3 = u; z_3 = 1; swap = 0
    for t in range(254, -1, -1):
        k_t = (k_int >> t) & 1
        swap ^= k_t
        x_2, x_3 = _cswap25519(swap, x_2, x_3)
        z_2, z_3 = _cswap25519(swap, z_2, z_3)
        swap = k_t
        A = (x_2 + z_2) % _P25519
        AA = (A * A) % _P25519
        B = (x_2 - z_2) % _P25519
        BB = (B * B) % _P25519
        E = (AA - BB) % _P25519
        C = (x_3 + z_3) % _P25519
        D = (x_3 - z_3) % _P25519
        DA = (D * A) % _P25519
        CB = (C * B) % _P25519
        x_3 = ((DA + CB) ** 2) % _P25519
        z_3 = (x_1 * ((DA - CB) ** 2)) % _P25519
        x_2 = (AA * BB) % _P25519
        z_2 = (E * (AA + _A24 * E)) % _P25519
    x_2, x_3 = _cswap25519(swap, x_2, x_3)
    z_2, z_3 = _cswap25519(swap, z_2, z_3)
    res = (x_2 * pow(z_2, _P25519 - 2, _P25519)) % _P25519
    return res.to_bytes(32, 'little')

def is_valid_x25519_key(k_str):
    if not k_str or not isinstance(k_str, str):
        return False
    s = k_str.strip()
    if len(s) not in (43, 44):
        return False
    if s.startswith("NzcwZjlk"):
        return False
    padded = s + "=" * ((4 - len(s) % 4) % 4)
    try:
        raw = base64.urlsafe_b64decode(padded)
        return len(raw) == 32
    except Exception:
        try:
            raw = base64.b64decode(padded)
            return len(raw) == 32
        except Exception:
            return False

def generate_x25519_keypair():
    """Generates a cryptographically valid Xray x25519 reality keypair using xray CLI or RFC 7748."""
    for cmd in ["xray", "/usr/local/bin/xray", "/usr/bin/xray"]:
        if shutil.which(cmd) or os.path.exists(cmd):
            try:
                res = subprocess.run([cmd, "x25519"], capture_output=True, text=True, timeout=5)
                if res.returncode == 0:
                    priv = ""
                    pub = ""
                    for line in res.stdout.strip().splitlines():
                        l = line.strip()
                        if l.lower().startswith("private") and ":" in l:
                            priv = l.split(":", 1)[1].strip()
                        elif (l.lower().startswith("public") or l.lower().startswith("password")) and ":" in l:
                            pub = l.split(":", 1)[1].strip()
                    if is_valid_x25519_key(priv) and is_valid_x25519_key(pub):
                        return {"privateKey": priv, "publicKey": pub}
            except Exception:
                pass

    # Pure Python RFC 7748 standard key derivation
    try:
        priv_raw = os.urandom(32)
        k = bytearray(priv_raw)
        k[0] &= 248
        k[31] &= 127
        k[31] |= 64
        basepoint = (9).to_bytes(32, 'little')
        pub_raw = _x25519_mul(k, basepoint)
        priv_b64 = base64.urlsafe_b64encode(bytes(k)).decode('ascii').rstrip('=')
        pub_b64 = base64.urlsafe_b64encode(pub_raw).decode('ascii').rstrip('=')
        return {"privateKey": priv_b64, "publicKey": pub_b64}
    except Exception as e:
        print(f"Error generating fallback x25519: {e}", file=sys.stderr)
        return {"privateKey": "", "publicKey": ""}

def read_v2ray_inbounds():
    """Reads inbound config from disk or initializes defaults, repairing invalid keys."""
    ensure_v2ray_dirs()
    data = None
    if os.path.exists(V2RAY_INBOUNDS_CONF):
        try:
            with open(V2RAY_INBOUNDS_CONF, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            data = None
    if not isinstance(data, dict):
        data = get_default_inbounds()
    else:
        defaults = get_default_inbounds()
        for k, v in defaults.items():
            if k not in data or not isinstance(data[k], dict):
                data[k] = v

    # Validate and auto-repair Reality keypair
    vr = data.setdefault("vless_reality", {})
    priv = vr.get("privateKey", "")
    pub = vr.get("publicKey", "")
    if not is_valid_x25519_key(priv) or not is_valid_x25519_key(pub):
        keys = generate_x25519_keypair()
        if keys.get("privateKey") and keys.get("publicKey"):
            vr["privateKey"] = keys["privateKey"]
            vr["publicKey"] = keys["publicKey"]
            write_v2ray_inbounds(data)

    return data

def write_v2ray_inbounds(inbounds):
    """Writes inbounds configuration."""
    ensure_v2ray_dirs()
    try:
        with open(V2RAY_INBOUNDS_CONF, "w", encoding="utf-8") as f:
            json.dump(inbounds, f, indent=2)
        apply_xray_config_safe()
        return True
    except Exception as e:
        print(f"Error saving inbounds: {e}", file=sys.stderr)
        return False

# --- XRAY CONFIG JSON BUILDER ---
def build_xray_config():
    """Generates complete Xray JSON configuration for active inbounds & users."""
    inbounds_cfg = read_v2ray_inbounds()
    users = read_v2ray_users()

    now = datetime.now()
    active_users = []
    for u in users:
        if not u.get("is_active", True):
            continue
        exp_str = u.get("expire_date", "")
        if exp_str:
            try:
                exp_dt = datetime.strptime(exp_str.split()[0], "%Y-%m-%d")
                if exp_dt < now:
                    continue
            except Exception:
                pass
        active_users.append(u)

    inbounds_list = []

    # 1. VLESS Reality Inbound
    vr = inbounds_cfg.get("vless_reality", {})
    if vr.get("enabled", True):
        vless_clients = []
        for u in active_users:
            if "vless_reality" in u.get("protocols", []):
                vless_clients.append({
                    "id": u["uuid"],
                    "flow": "xtls-rprx-vision",
                    "email": u.get("email", f"{u['username']}@ff.local")
                })
        
        priv_key = vr.get("privateKey", "")
        if not is_valid_x25519_key(priv_key):
            kp = generate_x25519_keypair()
            if kp.get("privateKey"):
                priv_key = kp["privateKey"]
                vr["privateKey"] = priv_key
                vr["publicKey"] = kp.get("publicKey", "")
                try:
                    with open(V2RAY_INBOUNDS_CONF, "w", encoding="utf-8") as f:
                        json.dump(inbounds_cfg, f, indent=2)
                except Exception:
                    pass

        inbounds_list.append({
            "tag": "vless-reality-in",
            "port": int(vr.get("port", 8443)),
            "protocol": "vless",
            "settings": {
                "clients": vless_clients,
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": False,
                    "dest": vr.get("dest", "www.microsoft.com:443"),
                    "xver": 0,
                    "serverNames": vr.get("serverNames", ["www.microsoft.com"]),
                    "privateKey": priv_key,
                    "shortIds": vr.get("shortIds", ["0123456789abcdef", ""])
                }
            },
            "sniffing": {
                "enabled": True,
                "destOverride": ["http", "tls", "quic"]
            }
        })

    # 2. VMess WebSocket Inbound
    vm = inbounds_cfg.get("vmess_ws", {})
    if vm.get("enabled", True):
        vmess_clients = []
        for u in active_users:
            if "vmess_ws" in u.get("protocols", []):
                vmess_clients.append({
                    "id": u["uuid"],
                    "alterId": 0,
                    "email": u.get("email", f"{u['username']}@ff.local")
                })
        
        inbounds_list.append({
            "tag": "vmess-ws-in",
            "port": int(vm.get("port", 2052)),
            "protocol": "vmess",
            "settings": {
                "clients": vmess_clients
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": vm.get("path", "/vmess-ws")
                }
            },
            "sniffing": {
                "enabled": True,
                "destOverride": ["http", "tls", "quic"]
            }
        })

    # 3. VLESS WebSocket Inbound
    vl_ws = inbounds_cfg.get("vless_ws", {})
    if vl_ws.get("enabled", True):
        vl_clients = []
        for u in active_users:
            if "vless_ws" in u.get("protocols", []):
                vl_clients.append({
                    "id": u["uuid"],
                    "email": u.get("email", f"{u['username']}@ff.local")
                })
        
        inbounds_list.append({
            "tag": "vless-ws-in",
            "port": int(vl_ws.get("port", 2082)),
            "protocol": "vless",
            "settings": {
                "clients": vl_clients,
                "decryption": "none"
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": vl_ws.get("path", "/vless-ws")
                }
            },
            "sniffing": {
                "enabled": True,
                "destOverride": ["http", "tls", "quic"]
            }
        })

    # 4. Trojan Inbound
    tr = inbounds_cfg.get("trojan_grpc", {})
    if tr.get("enabled", True):
        tr_clients = []
        for u in active_users:
            if "trojan_grpc" in u.get("protocols", []):
                tr_clients.append({
                    "password": u["uuid"],
                    "email": u.get("email", f"{u['username']}@ff.local")
                })
        
        inbounds_list.append({
            "tag": "trojan-grpc-in",
            "port": int(tr.get("port", 2096)),
            "protocol": "trojan",
            "settings": {
                "clients": tr_clients
            },
            "streamSettings": {
                "network": "grpc",
                "grpcSettings": {
                    "serviceName": tr.get("serviceName", "trojan-grpc")
                }
            },
            "sniffing": {
                "enabled": True,
                "destOverride": ["http", "tls", "quic"]
            }
        })

    # Outbounds & Core Policy
    cfg = {
        "log": {
            "loglevel": "warning",
            "access": "/var/log/xray/access.log",
            "error": "/var/log/xray/error.log"
        },
        "api": {
            "tag": "api",
            "services": ["HandlerService", "StatsService"]
        },
        "stats": {},
        "policy": {
            "levels": {
                "0": {
                    "handshake": 4,
                    "connIdle": 300,
                    "uplinkOnly": 2,
                    "downlinkOnly": 5,
                    "statsUserUplink": True,
                    "statsUserDownlink": True
                }
            },
            "system": {
                "statsInboundUplink": True,
                "statsInboundDownlink": True
            }
        },
        "inbounds": inbounds_list,
        "outbounds": [
            {
                "tag": "direct",
                "protocol": "freedom",
                "settings": {}
            },
            {
                "tag": "blocked",
                "protocol": "blackhole",
                "settings": {}
            }
        ],
        "routing": {
            "domainStrategy": "IPIfNonMatch",
            "rules": [
                {
                    "type": "field",
                    "inboundTag": ["api"],
                    "outboundTag": "api"
                },
                {
                    "type": "field",
                    "ip": ["geoip:private"],
                    "outboundTag": "blocked"
                }
            ]
        }
    }
    return cfg

def apply_xray_config_safe():
    """Generates config and tests with xray before applying."""
    cfg = build_xray_config()
    os.makedirs(XRAY_CONFIG_DIR, exist_ok=True)
    os.makedirs("/usr/local/etc/xray", exist_ok=True)
    os.makedirs("/var/log/xray", exist_ok=True)
    
    target_files = [XRAY_CONFIG_FILE, ALT_XRAY_CONFIG]

    for tf in target_files:
        try:
            with open(tf, "w", encoding="utf-8") as f:
                json.dump(cfg, f, indent=2)
        except Exception:
            pass

    xray_bin = shutil.which("xray") or "/usr/local/bin/xray"
    if os.path.exists(xray_bin):
        try:
            res = subprocess.run([xray_bin, "-test", "-config", XRAY_CONFIG_FILE], capture_output=True, text=True, timeout=5)
            if res.returncode == 0:
                subprocess.run(["systemctl", "restart", "xray"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return True
        except Exception:
            pass
    return True

# --- LINK & SUBSCRIPTION BUILDERS ---
def generate_user_protocol_links(user, server_ip="", domain="", inbounds=None, nodes=None):
    """Generates direct client links (vless://, vmess://, trojan://) across authorized server nodes."""
    if not inbounds:
        inbounds = read_v2ray_inbounds()
    if not nodes:
        nodes = read_v2ray_nodes()
    
    default_host = domain if domain else server_ip
    uuid_val = user["uuid"]
    username = user["username"]
    user_protos = user.get("protocols", ["vless_reality", "vmess_ws"])
    user_nodes = user.get("allowed_nodes", ["*"])
    
    links = []

    # Filter nodes allowed for this user
    active_nodes = []
    for n in nodes:
        if not n.get("enabled", True):
            continue
        n_id = n.get("id", "local")
        if "*" in user_nodes or n_id in user_nodes:
            active_nodes.append(n)

    if not active_nodes:
        # Fallback to local node if nothing matched
        active_nodes = [{
            "id": "local",
            "name": "الخادم الرئيسي",
            "flag": "🇸🇦",
            "host": default_host,
            "is_local": True
        }]

    for node in active_nodes:
        n_name = node.get("name", "الخادم")
        n_flag = node.get("flag", "🌐")
        n_host = node.get("host") or default_host
        n_reality_sni = node.get("reality_sni") or inbounds.get("vless_reality", {}).get("serverNames", ["www.microsoft.com"])[0]

        # 1. VLESS Reality
        vr = inbounds.get("vless_reality", {})
        if vr.get("enabled", True) and "vless_reality" in user_protos:
            port = vr.get("port", 8443)
            pbk = vr.get("publicKey", "")
            sni = n_reality_sni
            sid = vr.get("shortIds", [""])[0]
            remark = urllib.parse.quote(f"🚀 Reality | {n_flag} {n_name} | {username}")
            vless_link = f"vless://{uuid_val}@{n_host}:{port}?security=reality&encryption=none&pbk={pbk}&headerType=none&fp=chrome&spx=%2F&type=tcp&sni={sni}&sid={sid}&flow=xtls-rprx-vision#{remark}"
            links.append({
                "type": f"VLESS Reality ({n_name})",
                "protocol": "vless",
                "node_id": node.get("id", "local"),
                "node_name": n_name,
                "node_flag": n_flag,
                "link": vless_link,
                "port": port,
                "security": "Reality (No-SSL)"
            })

        # 2. VMess WebSocket (CDN / Cloudflare)
        vm = inbounds.get("vmess_ws", {})
        if vm.get("enabled", True) and "vmess_ws" in user_protos:
            port = vm.get("port", 2052)
            path = vm.get("path", "/vmess-ws")
            remark = f"☁️ VMess-CDN | {n_flag} {n_name} | {username}"
            vmess_obj = {
                "v": "2",
                "ps": remark,
                "add": n_host,
                "port": str(port),
                "id": uuid_val,
                "aid": "0",
                "net": "ws",
                "type": "none",
                "host": domain if domain else "",
                "path": path,
                "tls": "none"
            }
            b64_str = base64.b64encode(json.dumps(vmess_obj).encode()).decode()
            vmess_link = f"vmess://{b64_str}"
            links.append({
                "type": f"VMess CDN ({n_name})",
                "protocol": "vmess",
                "node_id": node.get("id", "local"),
                "node_name": n_name,
                "node_flag": n_flag,
                "link": vmess_link,
                "port": port,
                "security": "WS + CDN"
            })

        # 3. VLESS WebSocket
        vl_ws = inbounds.get("vless_ws", {})
        if vl_ws.get("enabled", True) and "vless_ws" in user_protos:
            port = vl_ws.get("port", 2082)
            path = urllib.parse.quote(vl_ws.get("path", "/vless-ws"))
            remark = urllib.parse.quote(f"⚡ VLESS-WS | {n_flag} {n_name} | {username}")
            vless_ws_link = f"vless://{uuid_val}@{n_host}:{port}?path={path}&security=none&encryption=none&type=ws&host={domain}#{remark}"
            links.append({
                "type": f"VLESS WS ({n_name})",
                "protocol": "vless",
                "node_id": node.get("id", "local"),
                "node_name": n_name,
                "node_flag": n_flag,
                "link": vless_ws_link,
                "port": port,
                "security": "WebSocket"
            })

        # 4. Trojan gRPC
        tr = inbounds.get("trojan_grpc", {})
        if tr.get("enabled", True) and "trojan_grpc" in user_protos:
            port = tr.get("port", 2096)
            svc = tr.get("serviceName", "trojan-grpc")
            remark = urllib.parse.quote(f"🔐 Trojan-gRPC | {n_flag} {n_name} | {username}")
            trojan_link = f"trojan://{uuid_val}@{n_host}:{port}?security=tls&type=grpc&serviceName={svc}&sni={domain}#{remark}"
            links.append({
                "type": f"Trojan gRPC ({n_name})",
                "protocol": "trojan",
                "node_id": node.get("id", "local"),
                "node_name": n_name,
                "node_flag": n_flag,
                "link": trojan_link,
                "port": port,
                "security": "gRPC + TLS"
            })

    return links

def generate_subscription_raw(sub_token, server_ip="", domain=""):
    """Generates standard Base64 raw subscription feed for client apps."""
    user = find_v2ray_user(sub_token)
    if not user:
        return ""
    
    links_data = generate_user_protocol_links(user, server_ip, domain)
    raw_lines = [l["link"] for l in links_data if l.get("link")]
    all_text = "\n".join(raw_lines)
    return base64.b64encode(all_text.encode("utf-8")).decode("utf-8")

def get_v2ray_core_status():
    """Returns real-time status of the Xray-core engine."""
    installed = shutil.which("xray") is not None
    active = False
    version = "N/A"
    
    if installed:
        try:
            res = subprocess.run(["xray", "version"], capture_output=True, text=True, timeout=3)
            if res.returncode == 0 and res.stdout:
                version = res.stdout.splitlines()[0]
        except Exception:
            pass
        
        try:
            res = subprocess.run(["systemctl", "is-active", "xray"], capture_output=True, text=True, timeout=3)
            active = (res.stdout.strip() == "active")
        except Exception:
            pass

    users = read_v2ray_users()
    inbounds = read_v2ray_inbounds()
    
    active_inbounds_count = sum(1 for v in inbounds.values() if isinstance(v, dict) and v.get("enabled", True))
    
    return {
        "installed": installed,
        "active": active,
        "version": version,
        "user_count": len(users),
        "active_users": sum(1 for u in users if u.get("is_active", True)),
        "inbounds_count": active_inbounds_count,
        "inbounds": inbounds
    }
