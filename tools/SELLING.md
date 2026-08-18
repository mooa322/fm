# DAHOOM — Seller's licensing guide

No live server. Access is controlled by a plain file on this same repo,
`licenses.json`, which only you (or someone you push to the repo) can edit —
GitHub already prevents anyone else from writing to it.

## How it works

- The real tool (`src/menu.sh`, `src/ssh`, `src/update_panel.sh`, `src/panel/*`)
  is never published in plaintext. `src/` is git-ignored, and ships as one
  encrypted file, `menu.enc`, on the repo.
- `licenses.json` lists each client: `{"ip": "...", "issued": "...", "revoked": false}`.
- The public `install.sh` reads `licenses.json` before installing:
  - the license id must exist and not be revoked
  - if you set an `ip` for it, the requesting server's IP must match
- `src/menu.sh` re-checks the same file on every launch, and re-downloads
  `menu.enc` on update — so a revoke takes effect the next time the tool runs.

## Honest limits (read this once)

- **The decryption key is embedded in `install.sh` and inside `menu.sh`.**
  There is no live secret-holder, so this can't be hidden from a technically
  capable person who reads the code — they could bypass the checks entirely.
  What this system *does* give you: a clear audit trail, instant revocation
  for anyone using the tool normally, and a real IP lock for licenses you
  pre-register — which stops casual reuse and misuse, just not a determined
  reverse-engineer.
- **Nobody but you can edit `licenses.json` or `menu.enc`** — that's GitHub's
  own repo permissions, unrelated to encryption.
- **Real IP-locking requires you to know the client's server IP up front.**
  Ask for it before issuing the license (`issue <id> <ip>`). A license issued
  without an IP works on any server until you set one.

## Daily use

```bash
./tools/manage-license.sh issue ahmed 203.0.113.9   # locked to that IP
./tools/manage-license.sh issue sara                # open until you set an IP
./tools/manage-license.sh list
./tools/manage-license.sh revoke ahmed              # blocks it everywhere
./tools/manage-license.sh unbind ahmed              # let it re-bind to a new server
```

Every command edits `licenses.json` locally — you still need to publish it:
```bash
git add licenses.json && git commit -m "license: ..." && git push
```

Give the client just their id, e.g.:
```
FM_ID=ahmed bash <(curl -sL https://raw.githubusercontent.com/mooa322/fm/main/install.sh)
```

## Shipping an update

After changing anything under `src/`:
```bash
./tools/build-payload.sh
git add menu.enc && git commit -m release && git push
```
