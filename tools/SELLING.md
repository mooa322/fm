# DAHOOM — Seller's licensing guide

The tool is gated by an **activation server** (a free Cloudflare Worker).
Each license binds to the **first server** that installs it; a second
server is refused. You can revoke any license instantly.

Everything here runs **on your own machine**, never on a client server.

---

## How it works

- The real tool lives only in `src/` (git-ignored) and ships as ONE
  encrypted file, `menu.enc`, on the public repo.
- The decryption key is **not** in the repo and **not** given to clients.
  It lives on your Worker as the `PAYLOAD_KEY` secret.
- When a client installs, `install.sh` sends their license id + the
  server's public IP to the Worker. The Worker binds the id to that IP
  (first time), and returns the key only for the bound IP. Another IP →
  refused. Revoked → refused.
- The client needs only ONE code (their id). No key to type, no second
  value.

---

## One-time setup (≈10 minutes)

You need a free Cloudflare account and Node.js installed.

1. **Get the code on your machine** and enter the repo:
   ```bash
   git clone https://github.com/mooa322/fm
   cd fm
   ```
   Then put your plaintext master source into `src/` (ask the provider of
   this build for the `src/` folder — it is never published). The layout is:
   `src/menu.sh  src/ssh  src/update_panel.sh  src/panel/*`.

2. **Create the KV namespace** (stores which id is bound to which IP):
   ```bash
   npx wrangler kv namespace create LICENSES
   ```
   Copy the printed `id` into `tools/worker/wrangler.toml`.

3. **Set the two secrets** on the Worker:
   ```bash
   # a strong master key (also used locally to build menu.enc)
   openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 44   # copy this
   npx wrangler secret put PAYLOAD_KEY   # paste it
   npx wrangler secret put ADMIN_TOKEN   # paste a long random admin password
   ```

4. **Deploy the Worker:**
   ```bash
   cd tools/worker && npx wrangler deploy && cd ../..
   ```
   Note the printed URL, e.g. `https://dahoom-activation.YOURNAME.workers.dev`.

5. **Fill `tools/.worker.env`** (copy from `.worker.env.example`):
   ```
   WORKER_URL=https://dahoom-activation.YOURNAME.workers.dev
   ADMIN_TOKEN=...the admin password from step 3...
   PAYLOAD_KEY=...the master key from step 3...
   ```

6. **Point the installer at your Worker.** In `install.sh` and
   `src/menu.sh` and `src/update_panel.sh`, replace the placeholder
   `https://dahoom-activation.CHANGE-ME.workers.dev` with your real URL.
   (Ask the provider to do this once if you prefer.)

7. **Build and publish the payload:**
   ```bash
   ./tools/build-payload.sh
   git add menu.enc install.sh && git commit -m "release" && git push
   ```

Keep **`src/`**, **`tools/.worker.env`**, and your Cloudflare account safe.
Losing them loses control.

---

## Daily use

**Issue a license to a client:**
```bash
./tools/issue-client.sh ahmed          # or omit the name for a random id
```
It prints the ONE line to send the client:
```
FM_ID=ahmed bash <(curl -sL https://raw.githubusercontent.com/mooa322/fm/main/install.sh)
```

**See all licenses and which server each is bound to:**
```bash
./tools/list-clients.sh
```

**Revoke a client (stops them everywhere, instantly):**
```bash
./tools/revoke-client.sh ahmed
```

**Client moved to a new server?** Clear the IP lock so their next install
binds to the new one:
```bash
./tools/unbind-client.sh ahmed
```

**Ship a new version to everyone:** edit `src/`, then:
```bash
./tools/build-payload.sh && git add menu.enc && git commit -m release && git push
```
Every client picks it up on their next update — re-checking their IP.

---

## Honest limits

- The IP binding and key release happen at **install/update time**. A
  server already running keeps running offline; there is no constant
  heartbeat (by your choice).
- A client can decrypt the payload on their bound server and read the
  source — encryption stops non-clients, not the buyer themselves.
- If the Worker is down, new installs and updates fail until it is back.
  Existing installs keep working.
