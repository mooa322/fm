/**
 * DAHOOM · License Activation Worker (Cloudflare)
 * ------------------------------------------------
 * Binds each license id to the FIRST server IP that activates it, and
 * releases the payload decryption key only to that bound IP. A second
 * server gets rejected. Revoking a license stops it everywhere.
 *
 * Bindings:
 *   KV namespace  -> LICENSES        (per-client state)
 *   Secret        -> PAYLOAD_KEY     (master key that decrypts menu.enc)
 *   Secret        -> ADMIN_TOKEN     (bearer token for /admin/* endpoints)
 *
 * Client endpoint (public):
 *   POST /activate            {id, ip}          -> {ok, key} | {ok:false, error}
 *
 * Admin endpoints (Authorization: Bearer <ADMIN_TOKEN>):
 *   POST /admin/issue         {id}              -> issue a new license
 *   POST /admin/revoke        {id}              -> disable a license everywhere
 *   POST /admin/unbind        {id}              -> clear its IP (client moved server)
 *   GET  /admin/list                            -> list all licenses + state
 */

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });

async function readBody(request) {
  try { return await request.json(); } catch { return {}; }
}

function requireAdmin(request, env) {
  const auth = request.headers.get("authorization") || "";
  const token = auth.replace(/^Bearer\s+/i, "");
  return env.ADMIN_TOKEN && token === env.ADMIN_TOKEN;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";

    // ── Public: activate ──────────────────────────────────────────────
    if (request.method === "POST" && path === "/activate") {
      const { id, ip } = await readBody(request);
      if (!id || !ip) return json({ ok: false, error: "missing id or ip" }, 400);

      const raw = await env.LICENSES.get("client:" + id);
      if (!raw) return json({ ok: false, error: "license not found" }, 403);

      const rec = JSON.parse(raw);
      if (rec.revoked) return json({ ok: false, error: "license revoked" }, 403);

      if (!rec.ip) {
        // first activation — bind to this server
        rec.ip = ip;
        rec.activated_at = new Date().toISOString();
        await env.LICENSES.put("client:" + id, JSON.stringify(rec));
        return json({ ok: true, key: env.PAYLOAD_KEY, bound: "new" });
      }
      if (rec.ip === ip) {
        return json({ ok: true, key: env.PAYLOAD_KEY, bound: "same" });
      }
      return json({ ok: false, error: "license already bound to another server" }, 403);
    }

    // ── Admin ────────────────────────────────────────────────────────
    if (path.startsWith("/admin/")) {
      if (!requireAdmin(request, env)) return json({ ok: false, error: "unauthorized" }, 401);

      if (request.method === "POST" && path === "/admin/issue") {
        const { id } = await readBody(request);
        if (!id) return json({ ok: false, error: "missing id" }, 400);
        const exists = await env.LICENSES.get("client:" + id);
        if (exists) return json({ ok: false, error: "id already exists" }, 409);
        const rec = { ip: null, revoked: false, created: new Date().toISOString() };
        await env.LICENSES.put("client:" + id, JSON.stringify(rec));
        return json({ ok: true, id });
      }

      if (request.method === "POST" && path === "/admin/revoke") {
        const { id } = await readBody(request);
        const raw = await env.LICENSES.get("client:" + id);
        if (!raw) return json({ ok: false, error: "not found" }, 404);
        const rec = JSON.parse(raw); rec.revoked = true;
        await env.LICENSES.put("client:" + id, JSON.stringify(rec));
        return json({ ok: true, id, revoked: true });
      }

      if (request.method === "POST" && path === "/admin/unbind") {
        const { id } = await readBody(request);
        const raw = await env.LICENSES.get("client:" + id);
        if (!raw) return json({ ok: false, error: "not found" }, 404);
        const rec = JSON.parse(raw); rec.ip = null; rec.activated_at = null;
        await env.LICENSES.put("client:" + id, JSON.stringify(rec));
        return json({ ok: true, id, unbound: true });
      }

      if (request.method === "GET" && path === "/admin/list") {
        const out = [];
        let cursor;
        do {
          const page = await env.LICENSES.list({ prefix: "client:", cursor });
          for (const k of page.keys) {
            const rec = JSON.parse((await env.LICENSES.get(k.name)) || "{}");
            out.push({ id: k.name.slice("client:".length), ip: rec.ip || null,
                       revoked: !!rec.revoked, created: rec.created || null });
          }
          cursor = page.cursor;
          if (page.list_complete) break;
        } while (cursor);
        return json({ ok: true, count: out.length, licenses: out });
      }

      return json({ ok: false, error: "unknown admin route" }, 404);
    }

    return json({ ok: false, error: "not found" }, 404);
  },
};
