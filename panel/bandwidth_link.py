#!/usr/bin/env python3
"""
DAHOOM · User Bandwidth Status Link
────────────────────────────────────
A tiny, dependency-free HTTP service (stdlib only) that gives every user a
private, unguessable link to check their own usage — nothing more.

Security notes:
  - The password field in users.db is never read by this file, at all —
    not "hidden from the page", structurally absent from every code path.
  - Access requires BOTH the username and a random per-user token; a wrong
    or missing token, or an unknown user, both return a plain 404 so an
    outside caller can't tell which one was wrong.
  - Requests are not logged (the URL contains the secret token).
"""
import os
import re
import json
import sqlite3
import subprocess
from datetime import datetime
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

DB_FILE = "/etc/firewallfalcon/users.db"
BW_DIR = "/etc/firewallfalcon/bandwidth"
TOKENS_DB = "/etc/firewallfalcon/bandwidth_tokens.db"
XUI_DB_FILE = "/etc/x-ui/x-ui.db"
XUI_TOKENS_DB = "/etc/firewallfalcon/xui_bandwidth_tokens.db"
PANEL_CONF_FILE = "/etc/firewallfalcon/panel.conf"
RESELLERS_DB_FILE = "/etc/firewallfalcon/resellers.db"
PORT = int(os.environ.get("BW_LINK_PORT", "47653"))


def read_file_int(path, default=0):
    try:
        if os.path.exists(path):
            with open(path) as f:
                return int(f.read().strip())
    except Exception:
        pass
    return default


def _isfloat(s):
    try:
        float(s)
        return True
    except Exception:
        return False


def load_tokens():
    """username -> (token, enabled). Legacy 2-field lines (from before the
    enable/disable toggle existed) are treated as enabled."""
    tokens = {}
    if os.path.exists(TOKENS_DB):
        try:
            with open(TOKENS_DB) as f:
                for line in f:
                    line = line.strip()
                    if not line or ":" not in line:
                        continue
                    parts = line.split(":")
                    if len(parts) < 2:
                        continue
                    u, t = parts[0], parts[1]
                    enabled = (len(parts) < 3) or (parts[2] != "0")
                    tokens[u] = (t, enabled)
        except Exception:
            pass
    return tokens


def find_user(username):
    """Read only the fields the status page needs. parts[1] (password) is
    intentionally never touched."""
    if not os.path.exists(DB_FILE):
        return None
    try:
        with open(DB_FILE) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split(":")
                if len(parts) < 5 or parts[0] != username:
                    continue
                return {
                    "username": parts[0],
                    "expire_date": parts[2],
                    "conn_limit": int(parts[3]) if parts[3].isdigit() else 1,
                    "bandwidth_gb": float(parts[4]) if _isfloat(parts[4]) else 0.0,
                    "daily_bandwidth_gb": float(parts[5]) if len(parts) > 5 and _isfloat(parts[5]) else 0.0,
                    "owner": parts[7].strip() if len(parts) > 7 and parts[7].strip() else "admin",
                }
    except Exception:
        pass
    return None


def _read_panel_telegram():
    """The admin's own default support contact from panel.conf — same
    plain key=value file the main panel process reads/writes."""
    if not os.path.exists(PANEL_CONF_FILE):
        return ""
    try:
        with open(PANEL_CONF_FILE) as f:
            for line in f:
                line = line.strip()
                if line.startswith("PANEL_TELEGRAM="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
    except Exception:
        pass
    return ""


def _read_reseller_telegram(owner):
    """A reseller's own support contact, if they've set one — field 13 of
    resellers.db's colon-delimited format (username:password:expire_date:
    max_users:enabled:type:credits:max_conn:max_bw:allow_bulk:allow_trials:
    max_speed:telegram_contact)."""
    if not owner or owner == "admin" or not os.path.exists(RESELLERS_DB_FILE):
        return ""
    try:
        with open(RESELLERS_DB_FILE) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split(":")
                if parts and parts[0] == owner and len(parts) > 12:
                    return parts[12].strip()
    except Exception:
        pass
    return ""


def resolve_telegram_contact(owner=None):
    """The reseller's own contact if the account belongs to one and they've
    set it, else the admin's configured default, else '' — an unset
    contact hides the 'need help' block entirely rather than falling back
    to a value hardcoded for this project's own developer."""
    return _read_reseller_telegram(owner) or _read_panel_telegram()


def load_xui_tokens():
    """(inbound_id, email) -> (token, enabled). Line format is
    '<inbound_id>:<email>:<token>:<enabled>' — inbound_id and email never
    contain ':' themselves (email is restricted to [A-Za-z0-9_.-] on
    creation), so a plain split is safe."""
    tokens = {}
    if os.path.exists(XUI_TOKENS_DB):
        try:
            with open(XUI_TOKENS_DB) as f:
                for line in f:
                    line = line.strip()
                    if not line or ":" not in line:
                        continue
                    parts = line.split(":")
                    if len(parts) < 3:
                        continue
                    iid, email, t = parts[0], parts[1], parts[2]
                    enabled = (len(parts) < 4) or (parts[3] != "0")
                    tokens[(iid, email)] = (t, enabled)
        except Exception:
            pass
    return tokens


def find_xui_client(inbound_id, email):
    """Reads only what the status page needs straight out of X-UI's own
    SQLite database — this service never touches the client's UUID/password
    field, at all."""
    if not os.path.exists(XUI_DB_FILE):
        return None
    try:
        conn = sqlite3.connect(f"file:{XUI_DB_FILE}?mode=ro", uri=True, timeout=5)
        try:
            cur = conn.cursor()
            cur.execute(
                "SELECT remark, protocol, port, settings FROM inbounds WHERE id=?",
                (inbound_id,),
            )
            row = cur.fetchone()
            if not row:
                return None
            remark, protocol, port, settings_str = row
            settings = json.loads(settings_str) if settings_str else {}
            client = next((c for c in settings.get("clients", []) if c.get("email") == email), None)
            if client is None:
                return None
            up, down = 0, 0
            try:
                cur.execute(
                    "SELECT up, down FROM client_traffics WHERE inbound_id=? AND email=?",
                    (inbound_id, email),
                )
                trow = cur.fetchone()
                if trow:
                    up, down = trow
            except Exception:
                pass
            return {
                "inbound_remark": remark or f"Inbound-{inbound_id}",
                "protocol": protocol,
                "port": port,
                "email": email,
                "enable": bool(client.get("enable", True)),
                "expiry_time": int(client.get("expiryTime", 0) or 0),
                "total_bytes": int(client.get("totalGB", 0) or 0),
                "max_conn": int(client.get("limitIp", 0) or 0),
                "up": up or 0,
                "down": down or 0,
            }
        finally:
            conn.close()
    except Exception:
        return None


def online_sessions(username):
    try:
        out = subprocess.run(
            ["ps", "-C", "sshd,sshd-session", "-o", "pid=,user="],
            capture_output=True, text=True, timeout=5,
        ).stdout
    except Exception:
        return 0
    count = 0
    for line in out.strip().splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1] == username:
            count += 1
    return count


def const_time_eq(a, b):
    if len(a) != len(b):
        return False
    r = 0
    for x, y in zip(a, b):
        r |= ord(x) ^ ord(y)
    return r == 0


def esc(s):
    return (
        str(s)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


_BASE_STYLE = """
  :root {
    --bg1: #0a0e17; --bg2: #121a2b;
    --cyan: #22d3ee; --violet: #a78bfa;
    --card: #141c2e; --border: rgba(148,163,184,.14);
    --text: #e6edf7; --dim: #8b96ab;
    --green: #34d399; --red: #f87171; --track: #1c2740;
    --tg: #2aabee;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh; background: linear-gradient(160deg, var(--bg1), var(--bg2));
    color: var(--text); font-family: "Segoe UI", Tahoma, "Noto Sans Arabic", -apple-system, BlinkMacSystemFont, Roboto, sans-serif;
    display: flex; align-items: center; justify-content: center; padding: 24px;
  }
  .card {
    width: 100%; max-width: 420px; background: var(--card);
    border: 1px solid var(--border); border-radius: 20px;
    padding: 26px 24px 24px; box-shadow: 0 20px 60px rgba(0,0,0,.4);
  }
  .head { display: flex; align-items: center; gap: 10px; margin-bottom: 2px; }
  .head .logo {
    font-size: 1.3rem; width: 36px; height: 36px; flex: none;
    display: flex; align-items: center; justify-content: center;
    border-radius: 50%; background: rgba(148,163,184,.08); border: 1px solid var(--border);
  }
  .head h1 {
    font-size: 1.1rem; margin: 0; font-weight: 700;
    background: linear-gradient(90deg, var(--cyan), var(--violet));
    -webkit-background-clip: text; background-clip: text; color: transparent;
  }
  .head .sub { font-size: .74rem; color: var(--dim); margin-top: 1px; }

  .intro {
    margin: 16px 0 18px; padding: 12px 14px; border-radius: 12px;
    background: rgba(34,211,238,.06); border: 1px solid rgba(34,211,238,.16);
    font-size: .78rem; line-height: 1.7; color: var(--dim);
  }
  .intro b { color: var(--text); font-weight: 600; }

  .username { color: var(--dim); font-size: .85rem; margin: 0 0 18px; word-break: break-all; }
  .username b { color: var(--text); direction: ltr; unicode-bidi: isolate; }

  .badge {
    display: inline-flex; align-items: center; gap: 6px; padding: 4px 12px;
    border-radius: 999px; font-size: .78rem; font-weight: 600; margin-bottom: 22px;
  }
  .badge.online  { background: rgba(52,211,153,.12); color: var(--green); border: 1px solid rgba(52,211,153,.3); }
  .badge.offline { background: rgba(248,113,113,.10); color: var(--red);  border: 1px solid rgba(248,113,113,.28); }
  .badge.paused  { background: rgba(251,191,36,.10); color: #fbbf24; border: 1px solid rgba(251,191,36,.28); }
  .dot { width: 7px; height: 7px; border-radius: 50%; background: currentColor; }

  .section-label {
    font-size: .68rem; font-weight: 700; letter-spacing: .04em; color: var(--dim);
    text-transform: uppercase; margin: 0 0 12px; display: flex; align-items: center; gap: 8px;
  }
  .section-label::after { content: ""; flex: 1; height: 1px; background: var(--border); }

  .stat { margin-bottom: 20px; }
  .stat-row { display: flex; justify-content: space-between; align-items: baseline; font-size: .82rem; margin-bottom: 7px; }
  .stat-row .label { color: var(--dim); }
  .stat-row .val { color: var(--text); font-weight: 700; direction: ltr; unicode-bidi: isolate; }
  .stat-row .val .of { color: var(--dim); font-weight: 400; }
  .bar { height: 8px; border-radius: 999px; background: var(--track); overflow: hidden; }
  .bar-fill { height: 100%; border-radius: 999px; background: linear-gradient(90deg, var(--cyan), var(--violet)); }
  .bar-fill.warn { background: linear-gradient(90deg, #fbbf24, var(--red)); }

  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-top: 4px; margin-bottom: 20px; }
  .tile { background: rgba(148,163,184,.05); border: 1px solid var(--border); border-radius: 12px; padding: 12px 14px; }
  .tile .t-label { color: var(--dim); font-size: .72rem; margin-bottom: 4px; }
  .tile .t-val { font-size: .95rem; font-weight: 700; direction: ltr; unicode-bidi: isolate; }

  .support {
    display: flex; align-items: center; gap: 12px; margin-top: 4px; padding: 12px 14px;
    border-radius: 12px; background: rgba(42,171,238,.08); border: 1px solid rgba(42,171,238,.22);
  }
  .support .tg-icon {
    flex: none; width: 34px; height: 34px; border-radius: 50%; background: var(--tg);
    display: flex; align-items: center; justify-content: center;
  }
  .support .tg-icon svg { width: 18px; height: 18px; }
  .support .txt { flex: 1; min-width: 0; }
  .support .txt .t1 { font-size: .78rem; color: var(--text); font-weight: 600; margin-bottom: 2px; }
  .support .txt .t2 { font-size: .72rem; color: var(--dim); }
  .support a.handle {
    color: var(--tg); font-weight: 700; text-decoration: none; direction: ltr; unicode-bidi: isolate;
  }

  .foot { text-align: center; margin-top: 20px; color: var(--dim); font-size: .7rem; line-height: 1.6; }

  .paused-box {
    display: flex; flex-direction: column; align-items: center; text-align: center;
    padding: 34px 10px 10px; gap: 10px;
  }
  .paused-box .icon {
    width: 56px; height: 56px; border-radius: 50%; display: flex; align-items: center;
    justify-content: center; font-size: 1.6rem; background: rgba(251,191,36,.10);
    border: 1px solid rgba(251,191,36,.28); color: #fbbf24; margin-bottom: 6px;
  }
  .paused-box h2 { font-size: 1.05rem; margin: 0; color: var(--text); }
  .paused-box p { font-size: .82rem; color: var(--dim); line-height: 1.8; margin: 0; max-width: 300px; }

  .lang-switch { display: flex; gap: 5px; margin-inline-start: auto; }
  .lang-btn {
    background: rgba(148,163,184,.08); border: 1px solid var(--border); color: var(--dim);
    font-size: .62rem; font-weight: 700; padding: 4px 7px; border-radius: 6px; cursor: pointer;
    letter-spacing: .03em; line-height: 1;
  }
  .lang-btn.active { background: var(--cyan); color: #04121a; border-color: var(--cyan); }
  html[dir="ltr"] .username b, html[dir="ltr"] .stat-row .val, html[dir="ltr"] .tile .t-val,
  html[dir="ltr"] .support a.handle { direction: ltr; }
"""

_TG_ICON_SVG = (
    '<svg viewBox="0 0 24 24" fill="white"><path d="M21.95 5.4 18.6 20.8c-.25 1.1-.9 1.37-1.83.86'
    'l-5.06-3.73-2.44 2.35c-.27.27-.5.5-1.02.5l.36-5.16 9.4-8.49c.41-.36-.09-.56-.63-.2L6.02 13.1 '
    '1 11.53c-1.1-.34-1.11-1.1.22-1.62L20.6 4.03c.9-.34 1.7.2 1.35 1.37Z"/></svg>'
)

def _support_box_html(telegram_handle):
    """Renders the 'need help?' box for whichever Telegram contact applies
    to this account (the owning reseller's own handle, or the admin's
    default — see resolve_telegram_contact()). Returns '' — the box is
    omitted entirely — rather than a hardcoded fallback contact, since a
    fresh install with nothing configured has no one specific to point at."""
    if not telegram_handle:
        return ""
    handle = esc(telegram_handle)
    return f"""    <div class="support">
      <div class="tg-icon">{_TG_ICON_SVG}</div>
      <div class="txt">
        <div class="t1"><span data-i18n="b11">تحتاج مساعدة أو عندك استفسار؟</span></div>
        <div class="t2"><span data-i18n="b12">تواصل معنا على تيليجرام</span> <a class="handle" href="https://t.me/{handle}" target="_blank" rel="noopener">@{handle}</a></div>
      </div>
    </div>
"""

# Self-contained AR/EN/FR switcher: no external service, no network call —
# same mechanism as the admin panel's language switcher (data-i18n markers
# + a tiny runtime), scaled down for this single static page.
_LANG_SWITCH_HTML = """      <div class="lang-switch">
        <button class="lang-btn" data-lang="ar" onclick="applyLanguage('ar')">AR</button>
        <button class="lang-btn" data-lang="en" onclick="applyLanguage('en')">EN</button>
        <button class="lang-btn" data-lang="fr" onclick="applyLanguage('fr')">FR</button>
      </div>
"""

_I18N_DICT_JS = """const I18N={
ar:{b1:"DAHOOM · الاستخدام",b2:"لوحة معلومات المستخدم",b3:"هذه صفحتك الخاصة لمتابعة استهلاكك الحالي فقط — <b>رابط شخصي وآمن</b> ولا يعرض أي معلومات حساسة (لا كلمة المرور ولا أي بيانات أخرى). لا تشارك هذا الرابط مع أي شخص غير موثوق.",b4:"الحساب:",b5:"الاستهلاك",b6:"إجمالي الاستخدام",b7:"اليوم",b8:"تاريخ الانتهاء",b9:"الأجهزة المتصلة",b10:"تحديث مباشر — أعد تحميل الصفحة في أي وقت لرؤية آخر استخدام.",b11:"تحتاج مساعدة أو عندك استفسار؟",b12:"تواصل معنا على تيليجرام",b13:"هذا الرابط متوقف مؤقتًا",b14:"أوقف مزوّد الخدمة هذا الرابط مؤقتًا. تواصل معه لمعرفة السبب أو لإعادة تفعيله.",b15:"متصل",b16:"غير متصل",b17:"غير محدود",b18:"البروتوكول",b19:"المنفذ",b20:"الحد الأقصى للأجهزة",b21:"مُفعّل",b22:"موقوف"},
en:{b1:"DAHOOM · Usage",b2:"User Usage Dashboard",b3:"This is your private page to track your current usage only — <b>a personal, secure link</b> that shows no sensitive information (no password, no other data). Do not share this link with anyone you don't trust.",b4:"Account:",b5:"Usage",b6:"Total Usage",b7:"Today",b8:"Expiry Date",b9:"Connected Devices",b10:"Live updates — reload the page anytime to see the latest usage.",b11:"Need help or have a question?",b12:"Contact us on Telegram",b13:"This link is temporarily paused",b14:"The service provider has temporarily paused this link. Contact them to find out why or to re-enable it.",b15:"Online",b16:"Offline",b17:"Unlimited",b18:"Protocol",b19:"Port",b20:"Max Devices",b21:"Enabled",b22:"Disabled"},
fr:{b1:"DAHOOM · Utilisation",b2:"Tableau de bord d'utilisation",b3:"Ceci est votre page privée pour suivre uniquement votre utilisation actuelle — <b>un lien personnel et sécurisé</b> qui n'affiche aucune information sensible (ni mot de passe, ni autre donnée). Ne partagez ce lien avec personne en qui vous n'avez pas confiance.",b4:"Compte :",b5:"Utilisation",b6:"Utilisation totale",b7:"Aujourd'hui",b8:"Date d'expiration",b9:"Appareils connectés",b10:"Mise à jour en direct — actualisez la page à tout moment pour voir la dernière utilisation.",b11:"Besoin d'aide ou une question ?",b12:"Contactez-nous sur Telegram",b13:"Ce lien est temporairement suspendu",b14:"Le fournisseur de service a temporairement suspendu ce lien. Contactez-le pour en connaître la raison ou pour le réactiver.",b15:"En ligne",b16:"Hors ligne",b17:"Illimité",b18:"Protocole",b19:"Port",b20:"Appareils max",b21:"Activé",b22:"Désactivé"}
};"""

_I18N_SCRIPT = f"""<script>
{_I18N_DICT_JS}
let currentLang=(function(){{try{{return localStorage.getItem('dahoom_lang')||'ar';}}catch(e){{return 'ar';}}}})();
function __i18n(k){{var d=I18N[currentLang]||I18N.ar;return (d&&d[k]!==undefined)?d[k]:((I18N.ar[k]!==undefined)?I18N.ar[k]:k);}}
function applyLanguage(lang){{
  if(!I18N[lang])lang='ar';
  currentLang=lang;
  try{{localStorage.setItem('dahoom_lang',lang);}}catch(e){{}}
  document.documentElement.setAttribute('lang',lang);
  document.documentElement.setAttribute('dir',lang==='ar'?'rtl':'ltr');
  document.querySelectorAll('[data-i18n]').forEach(function(el){{el.textContent=__i18n(el.getAttribute('data-i18n'));}});
  document.querySelectorAll('[data-i18n-html]').forEach(function(el){{el.innerHTML=__i18n(el.getAttribute('data-i18n-html'));}});
  document.querySelectorAll('.lang-btn').forEach(function(b){{b.classList.toggle('active',b.getAttribute('data-lang')===lang);}});
}}
document.addEventListener('DOMContentLoaded',function(){{applyLanguage(currentLang);}});
</script>
"""

PAGE_TEMPLATE = """<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title data-i18n="b1">DAHOOM · الاستخدام</title>
<style>""" + _BASE_STYLE + """</style>
</head>
<body>
  <div class="card">
    <div class="head">
      <span class="logo">Ⓓ</span>
      <div>
        <h1 data-i18n="b1">DAHOOM · الاستخدام</h1>
        <div class="sub" data-i18n="b2">لوحة معلومات المستخدم</div>
      </div>
""" + _LANG_SWITCH_HTML + """    </div>

    <div class="intro" data-i18n-html="b3">
      هذه صفحتك الخاصة لمتابعة استهلاكك الحالي فقط — <b>رابط شخصي وآمن</b> ولا يعرض أي معلومات حساسة (لا كلمة المرور ولا أي بيانات أخرى). لا تشارك هذا الرابط مع أي شخص غير موثوق.
    </div>

    <div class="username"><span data-i18n="b4">الحساب:</span> <b>__USERNAME__</b></div>

    <span class="badge __STATUS_CLASS__"><span class="dot"></span>__STATUS__</span>

    <div class="section-label" data-i18n="b5">الاستهلاك</div>

    <div class="stat">
      <div class="stat-row"><span class="label" data-i18n="b6">إجمالي الاستخدام</span><span class="val">__USED_GB__ <span class="of">/ __QUOTA_GB__</span></span></div>
      <div class="bar"><div class="bar-fill __PCT_CLASS__" style="width:__PCT__%"></div></div>
    </div>

    <div class="stat">
      <div class="stat-row"><span class="label" data-i18n="b7">اليوم</span><span class="val">__DAILY_USED_GB__ <span class="of">/ __DAILY_QUOTA_GB__</span></span></div>
      <div class="bar"><div class="bar-fill __DAILY_PCT_CLASS__" style="width:__DAILY_PCT__%"></div></div>
    </div>

    <div class="grid">
      <div class="tile"><div class="t-label" data-i18n="b8">تاريخ الانتهاء</div><div class="t-val">__EXPIRE__</div></div>
      <div class="tile"><div class="t-label" data-i18n="b9">الأجهزة المتصلة</div><div class="t-val">__SESSIONS__ / __CONN_LIMIT__</div></div>
    </div>
__SUPPORT_BOX__
    <div class="foot" data-i18n="b10">تحديث مباشر — أعد تحميل الصفحة في أي وقت لرؤية آخر استخدام.</div>
  </div>
""" + _I18N_SCRIPT + """</body>
</html>
"""

# Same card, adapted for an X-UI (V2Ray) client instead of an SSH account:
# no daily quota (X-UI doesn't track one) and no live session count (that
# needs xray's own stats API, not just the sqlite file) — a protocol/port
# tile and the client's own enable/disable state stand in instead.
XUI_PAGE_TEMPLATE = """<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title data-i18n="b1">DAHOOM · الاستخدام</title>
<style>""" + _BASE_STYLE + """</style>
</head>
<body>
  <div class="card">
    <div class="head">
      <span class="logo">Ⓓ</span>
      <div>
        <h1 data-i18n="b1">DAHOOM · الاستخدام</h1>
        <div class="sub" data-i18n="b2">لوحة معلومات المستخدم</div>
      </div>
""" + _LANG_SWITCH_HTML + """    </div>

    <div class="intro" data-i18n-html="b3">
      هذه صفحتك الخاصة لمتابعة استهلاكك الحالي فقط — <b>رابط شخصي وآمن</b> ولا يعرض أي معلومات حساسة (لا كلمة المرور ولا أي بيانات أخرى). لا تشارك هذا الرابط مع أي شخص غير موثوق.
    </div>

    <div class="username"><span data-i18n="b4">الحساب:</span> <b>__USERNAME__</b></div>

    <span class="badge __STATUS_CLASS__"><span class="dot"></span>__STATUS__</span>

    <div class="section-label" data-i18n="b5">الاستهلاك</div>

    <div class="stat">
      <div class="stat-row"><span class="label" data-i18n="b6">إجمالي الاستخدام</span><span class="val">__USED_GB__ <span class="of">/ __QUOTA_GB__</span></span></div>
      <div class="bar"><div class="bar-fill __PCT_CLASS__" style="width:__PCT__%"></div></div>
    </div>

    <div class="grid">
      <div class="tile"><div class="t-label" data-i18n="b18">البروتوكول</div><div class="t-val">__PROTOCOL__</div></div>
      <div class="tile"><div class="t-label" data-i18n="b19">المنفذ</div><div class="t-val">__PORT__</div></div>
      <div class="tile"><div class="t-label" data-i18n="b8">تاريخ الانتهاء</div><div class="t-val">__EXPIRE__</div></div>
      <div class="tile"><div class="t-label" data-i18n="b20">الحد الأقصى للأجهزة</div><div class="t-val">__CONN_LIMIT__</div></div>
    </div>
__SUPPORT_BOX__
    <div class="foot" data-i18n="b10">تحديث مباشر — أعد تحميل الصفحة في أي وقت لرؤية آخر استخدام.</div>
  </div>
""" + _I18N_SCRIPT + """</body>
</html>
"""

DISABLED_PAGE_TEMPLATE = """<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title data-i18n="b1">DAHOOM · الاستخدام</title>
<style>""" + _BASE_STYLE + """</style>
</head>
<body>
  <div class="card">
    <div class="head">
      <span class="logo">Ⓓ</span>
      <div>
        <h1 data-i18n="b1">DAHOOM · الاستخدام</h1>
        <div class="sub" data-i18n="b2">لوحة معلومات المستخدم</div>
      </div>
""" + _LANG_SWITCH_HTML + """    </div>

    <div class="paused-box">
      <div class="icon">⏸</div>
      <h2 data-i18n="b13">هذا الرابط متوقف مؤقتًا</h2>
      <p data-i18n="b14">أوقف مزوّد الخدمة هذا الرابط مؤقتًا. تواصل معه لمعرفة السبب أو لإعادة تفعيله.</p>
    </div>

__SUPPORT_BOX__  </div>
""" + _I18N_SCRIPT + """</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    server_version = "DAHOOM-BW/1.0"

    def log_message(self, fmt, *args):
        # Deliberately silent: the URL path carries the secret token, and
        # the default BaseHTTPRequestHandler logger writes it to stderr
        # (systemd journal) on every request.
        pass

    def _not_found(self):
        body = b"<h1>404 Not Found</h1>"
        self.send_response(404)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _disabled(self, owner=None):
        # The token is valid (so this isn't a guessing attempt) — just paused
        # by the provider — so a friendly 200 page is fine here, unlike the
        # deliberately-uninformative 404 used for bad tokens/unknown users.
        html = DISABLED_PAGE_TEMPLATE.replace("__SUPPORT_BOX__", _support_box_html(resolve_telegram_contact(owner)))
        body = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        mx = re.match(r"^/xstatus/(\d+)/([A-Za-z0-9_.-]+)/([A-Za-z0-9]+)$", path)
        if mx:
            return self._serve_xui_status(mx.group(1), mx.group(2), mx.group(3))
        m = re.match(r"^/status/([A-Za-z0-9_.-]+)/([A-Za-z0-9]+)$", path)
        if not m:
            return self._not_found()
        username, token = m.group(1), m.group(2)

        entry = load_tokens().get(username)
        if not entry:
            return self._not_found()
        real_token, link_enabled = entry
        if not const_time_eq(real_token, token):
            return self._not_found()

        user = find_user(username)
        if not user:
            return self._not_found()

        if not link_enabled:
            return self._disabled(owner=user.get("owner"))

        used_bytes = read_file_int(f"{BW_DIR}/{username}.usage")
        daily_bytes = read_file_int(f"{BW_DIR}/{username}.daily_usage")
        sessions = online_sessions(username)

        used_gb = used_bytes / (1024 ** 3)
        daily_used_gb = daily_bytes / (1024 ** 3)
        quota_gb = user["bandwidth_gb"]
        daily_quota_gb = user["daily_bandwidth_gb"]

        pct = min(100.0, (used_gb / quota_gb) * 100.0) if quota_gb > 0 else 0.0
        daily_pct = min(100.0, (daily_used_gb / daily_quota_gb) * 100.0) if daily_quota_gb > 0 else 0.0

        html = PAGE_TEMPLATE
        repl = {
            "__USERNAME__": esc(user["username"]),
            "__STATUS__": '<span data-i18n="b15">متصل</span>' if sessions > 0 else '<span data-i18n="b16">غير متصل</span>',
            "__STATUS_CLASS__": "online" if sessions > 0 else "offline",
            "__USED_GB__": f"{used_gb:.2f} GB",
            "__QUOTA_GB__": '<span data-i18n="b17">غير محدود</span>' if quota_gb <= 0 else f"{quota_gb:g} GB",
            "__PCT__": f"{pct:.1f}",
            "__PCT_CLASS__": "warn" if pct >= 90 else "",
            "__DAILY_USED_GB__": f"{daily_used_gb:.2f} GB",
            "__DAILY_QUOTA_GB__": '<span data-i18n="b17">غير محدود</span>' if daily_quota_gb <= 0 else f"{daily_quota_gb:g} GB",
            "__DAILY_PCT__": f"{daily_pct:.1f}",
            "__DAILY_PCT_CLASS__": "warn" if daily_pct >= 90 else "",
            "__EXPIRE__": esc(user["expire_date"]),
            "__SESSIONS__": str(sessions),
            "__CONN_LIMIT__": str(user["conn_limit"]),
            "__SUPPORT_BOX__": _support_box_html(resolve_telegram_contact(user.get("owner"))),
        }
        for k, v in repl.items():
            html = html.replace(k, v)

        body = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _serve_xui_status(self, inbound_id, email, token):
        entry = load_xui_tokens().get((inbound_id, email))
        if not entry:
            return self._not_found()
        real_token, link_enabled = entry
        if not const_time_eq(real_token, token):
            return self._not_found()

        client = find_xui_client(inbound_id, email)
        if not client:
            return self._not_found()

        if not link_enabled:
            return self._disabled()

        used_bytes = client["up"] + client["down"]
        used_gb = used_bytes / (1024 ** 3)
        quota_gb = client["total_bytes"] / (1024 ** 3)
        pct = min(100.0, (used_gb / quota_gb) * 100.0) if quota_gb > 0 else 0.0

        expiry_ms = client["expiry_time"]
        expire_str = "—" if not expiry_ms else datetime.fromtimestamp(expiry_ms / 1000).strftime("%Y-%m-%d %H:%M")
        conn_limit = client["max_conn"]

        html = XUI_PAGE_TEMPLATE
        repl = {
            "__USERNAME__": esc(client["email"]),
            "__STATUS__": '<span data-i18n="b21">مُفعّل</span>' if client["enable"] else '<span data-i18n="b22">موقوف</span>',
            "__STATUS_CLASS__": "online" if client["enable"] else "paused",
            "__USED_GB__": f"{used_gb:.2f} GB",
            "__QUOTA_GB__": '<span data-i18n="b17">غير محدود</span>' if quota_gb <= 0 else f"{quota_gb:g} GB",
            "__PCT__": f"{pct:.1f}",
            "__PCT_CLASS__": "warn" if pct >= 90 else "",
            "__PROTOCOL__": esc(str(client["protocol"]).upper()),
            "__PORT__": esc(str(client["port"])),
            "__EXPIRE__": esc(expire_str) if expiry_ms else '<span data-i18n="b17">غير محدود</span>',
            "__CONN_LIMIT__": str(conn_limit) if conn_limit else '<span data-i18n="b17">غير محدود</span>',
            # X-UI clients have no reseller/owner concept in this codebase
            # (X-UI's own schema doesn't track one) — only the admin's own
            # default contact applies here.
            "__SUPPORT_BOX__": _support_box_html(resolve_telegram_contact(None)),
        }
        for k, v in repl.items():
            html = html.replace(k, v)

        body = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


def main():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
