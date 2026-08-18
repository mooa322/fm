# DAHOOM — Seller's licensing guide

This folder holds the tooling that controls who can install DAHOOM.
Everything here runs **on your own machine**, never on a client server.

## How protection works

- The real tool (`src/menu.sh`, `src/ssh`, `src/update_panel.sh`, `src/panel/*`)
  is **never** published in plaintext. `src/` is git-ignored.
- For each client you run `issue-client.sh`, which encrypts the current
  source into `clients/<id>.enc` (AES-256) under a key unique to that client.
- The public `install.sh` asks the client for their ID + key, downloads
  their `.enc`, decrypts it, and installs. No key → nothing installs.
- To cut a client off, delete their `.enc` (`revoke-client.sh`). Everyone
  else is unaffected.

## First-time setup

Keep two things safe and backed up — losing them loses control:

- **`src/`** — the plaintext master source you edit. Never commit it.
- **`tools/.clients.db`** — id→key ledger. Needed to re-issue updates.
  Chmod is 600. Back it up somewhere private (not the repo).

## Issue a license to a new client

```bash
./tools/issue-client.sh ahmed-vps1
# or pin your own passphrase:
./tools/issue-client.sh ahmed-vps1 'some-strong-pass'
```

It prints the two lines to hand the client, and writes `clients/ahmed-vps1.enc`.
Publish it:

```bash
git add clients/ahmed-vps1.enc && git commit -m "license: ahmed-vps1" && git push
```

## Ship an update to everyone

After you edit anything under `src/`:

```bash
./tools/rebuild-all.sh          # re-encrypts current src/ for every active client
git add clients/ && git commit -m "release: <what changed>" && git push
```

Each client's server pulls the new encrypted bundle on its next update.

## Revoke a client

```bash
./tools/revoke-client.sh ahmed-vps1
git commit -am "revoke: ahmed-vps1" && git push
```

Their fresh installs and updates now fail with 404. **Note:** a server where
DAHOOM is *already running* keeps running until it next tries to update
(then it can't refresh and stays on its current copy). Stopping an
already-running install remotely would need an online activation server —
this model does not do that.

## Honest limits

- A client you gave a key to can decrypt their bundle and read the source.
  Encryption stops **non-clients**, not the buyer themselves.
- Keys can be shared by a client. Because each client has their own key,
  a leak is traceable and you revoke just that one.
- The repo is public; the `.enc` blobs are meaningless without a key.
