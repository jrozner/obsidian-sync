# obsidian-headless in Docker

Runs [Obsidian Sync](https://obsidian.md/help/headless) headlessly in a
container — no Node or desktop app on the host. Wraps the beta
`obsidian-headless` package (binary: `ob`). Requires an active Obsidian Sync
subscription.

## Setup

```bash
cp .env.example .env     # set VAULT_PATH, and PUID/PGID to `id -u` / `id -g`
docker compose build
```

Then run these once, in order. The first three are interactive.

```bash
# 1. Log in (prompts for email, password, 2FA)
docker compose run --rm obsidian-sync ob login

# 2. Create the remote vault (prompts for an E2EE password — save it)
docker compose run --rm obsidian-sync ob sync-create-remote --name "whoop" --encryption e2ee

# 3. Link your local vault to it (re-enter the same E2EE password)
docker compose run --rm obsidian-sync ob sync-setup --vault "whoop"

# 4. First sync (non-interactive from here on)
docker compose run --rm obsidian-sync ob sync

# 5. Start the continuous daemon
docker compose up -d
```

If the remote vault already exists, skip step 2 and use
`ob sync-list-remote` to find its name for step 3.

`restart: unless-stopped` brings the daemon back after a reboot.

## Everyday use

```bash
docker compose logs -f                                # follow the daemon
docker compose down          / up -d                  # stop / start
docker compose run --rm obsidian-sync ob sync-status  # what's linked
docker compose run --rm obsidian-sync ob sync         # one-shot sync
docker compose run --rm obsidian-sync ob --help       # full CLI
```

Anything after `obsidian-sync` is passed straight to `ob`.

**Pull-only / backup server** (never push local edits):

```bash
docker compose run --rm obsidian-sync ob sync-config --mode pull-only      # ignore local edits
docker compose run --rm obsidian-sync ob sync-config --mode mirror-remote  # revert local edits
```

## Things to know

- **The E2EE key lives in the config volume.** For unattended sync the container
  must decrypt without you, so `sync-setup` stores the derived key in
  `obsidian_obsidian-config`. Whoever can read that volume can read the vault —
  keep it on encrypted disk. The password is still your recovery secret and what
  you re-enter to set up another device; don't lose it.
- **Back up the config volume, not just the vault.** It holds `auth_token`, the
  E2EE key, and per-vault sync state (`sync/<vaultId>/state.db`). Lose it and you
  redo login + `sync-setup`, and the next sync re-scans everything.
- **`PUID` must match the vault owner.** The container never chowns `/vault`, so
  a mismatch is `Permission denied` on first write. Check with
  `stat -c '%u:%g' "$VAULT_PATH"`.
- **Don't run two continuous syncs on one vault** — same rule as the desktop app
  plus this container against the same directory.
- **No file-creation-time preservation on Linux** (upstream ships that native
  addon only for macOS/Windows). Sync is otherwise unaffected.

## Upgrading

`obsidian-headless` is 0.0.x beta — pinned via `OB_VERSION` in `.env`. Bump deliberately:

```bash
curl -s https://registry.npmjs.org/obsidian-headless | \
  python3 -c 'import sys,json; print(json.load(sys.stdin)["dist-tags"])'   # latest version
# edit OB_VERSION in .env, then:
docker compose build && docker compose up -d
```
