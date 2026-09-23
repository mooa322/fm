# DAHOOM — Seller's licensing guide

No live server. Access is controlled by a license database that lives in a
**second, unrelated repo** (`mooa322/instalasi`, `config/reg.json`) — kept
out of this repo on purpose so it isn't sitting next to the tool's own code.
Only you (or someone you push to that repo) can edit it — GitHub's own repo
permissions are what actually enforce that, not encryption.

## How it works

- The real tool (`src/menu.sh`, `src/ssh`, `src/update_panel.sh`, `src/panel/*`)
  is never published in plaintext. `src/` is git-ignored, and ships as one
  encrypted file, `menu.enc`, on this repo.
- The database lists each client: `{"ip": "...", "issued": "...", "revoked": false}`.
- The public `install.sh` reads the database before installing:
  - the license id must exist and not be revoked
  - if you set an `ip` for it, the requesting server's IP must match
- `src/menu.sh` re-checks the same database on every launch, and re-downloads
  `menu.enc` on update — so a revoke takes effect the next time the tool runs.

## Honest limits (read this once)

- **The decryption key isn't embedded in plaintext anywhere in this repo**
  — it's fetched from `instalasi` at first use, and even there it's stored
  obfuscated, not as a plain string. This raises the bar against someone
  skimming the code, but it can't be hidden from a technically capable
  person who reads `_fm_pkey()` and follows the fetch — there is no live
  secret-holder, so this can't stop a determined reverse-engineer, only
  slow down a casual one. What this system *does* give you: a clear audit
  trail, instant revocation for anyone using the tool normally, and a real
  IP lock for licenses you pre-register — which stops casual reuse and
  misuse.
- **Nobody but you can edit the license database or `menu.enc`** — that's
  GitHub's own repo permissions, unrelated to encryption or obfuscation.
- **Real IP-locking requires you to know the client's server IP up front.**
  Ask for it before issuing the license. A license issued without an IP
  works on any server until you set one.

## Daily use

Run the interactive panel — no commands to memorize:
```bash
./tools/license-panel.sh
```
It walks you through issuing, revoking, unbinding, and listing licenses,
and offers to `git commit` + `git push` automatically after every change —
against a local working clone of `instalasi` it manages for you under
`.license-data/` (gitignored, invisible to this repo's own history).

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
