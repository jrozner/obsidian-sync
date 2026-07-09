# obsidian-headless in Docker

Runs [Obsidian Sync](https://obsidian.md/help/headless) headlessly in a
container — no Node or desktop app on the host. Wraps the beta
`obsidian-headless` package (binary: `ob`). Requires an active Obsidian Sync
subscription.

One image serves any number of vaults. Each vault is an independent Compose
*project* (`-p <name>`) with its own isolated config volume, login, and E2EE
key — so you never edit a shared file to add one.

## Build the image (once)

```bash
cp .env.example .env     # set PUID/PGID to `id -u` / `id -g`
docker compose build     # produces obsidian-headless:0.0.12, reused by every project
```

`.env` holds only the shared constants (`PUID`, `PGID`, `OB_VERSION`). The
per-vault path is supplied per project, below.

## Add a vault

A project is defined by two variables. Set them in your shell (or keep them in a
per-project file and `source` it):

```bash
export COMPOSE_PROJECT_NAME=whoop                            # names the container + volume
export VAULT_PATH=/home/jrozner/vuln-research/whoop/wiki     # the host vault directory
```

`COMPOSE_PROJECT_NAME` is the env-var form of `-p`: with it set, every
`docker compose` command below targets this project and its own
`whoop_obsidian-config` volume. Then run the one-time setup — the first three
are interactive:

```bash
# 1. Log in (prompts for email, password, 2FA) — once per project, since the volume is isolated
docker compose run --rm obsidian-sync ob login

# 2. Create the remote vault (prompts for an E2EE password — save it)
docker compose run --rm obsidian-sync ob sync-create-remote --name "whoop" --encryption e2ee

# 3. Link the local vault to it (re-enter the same E2EE password)
docker compose run --rm obsidian-sync ob sync-setup --vault "whoop"

# 4. First sync (non-interactive from here on)
docker compose run --rm obsidian-sync ob sync

# 5. Start the continuous daemon
docker compose up -d
```

If the remote vault already exists, skip step 2 and use
`ob sync-list-remote` to find its name for step 3.

To add another vault, open a fresh shell, set the two variables to new values,
and run the same steps. Nothing shared is edited; the projects are fully
independent (`acme_obsidian-config`, `acme-obsidian-sync-1`, …).

> Set `COMPOSE_PROJECT_NAME` **consistently** for a given vault. If it's unset,
> Compose falls back to the directory name (`obsidian`) and every command hits
> one shared volume — silently defeating the isolation.

`restart: unless-stopped` brings each daemon back after a reboot.

## Everyday use

Set `COMPOSE_PROJECT_NAME` (and `VAULT_PATH` for commands that touch the vault)
first, then:

```bash
docker compose logs -f                                # follow this project's daemon
docker compose down          / up -d                  # stop / start this project
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

- **Each project has its own config volume** (`<project>_obsidian-config`),
  holding that vault's `auth_token`, E2EE key, and sync state
  (`sync/<vaultId>/state.db`). Isolation is the point: one compromised or deleted
  volume affects only its vault. The cost is one `ob login` per project.
- **The E2EE key lives in that volume.** For unattended sync the container must
  decrypt without you, so `sync-setup` stores the derived key there. Whoever can
  read the volume can read the vault — keep it on encrypted disk. The password is
  still your recovery secret and what you re-enter on another device; don't lose it.
- **Back up the config volume, not just the vault.** Lose it and you redo login +
  `sync-setup`, and the next sync re-scans everything.
- **`PUID` must match the vault owner.** The container never chowns `/vault`, so a
  mismatch is `Permission denied` on first write. Check with
  `stat -c '%u:%g' "$VAULT_PATH"`.
- **Don't run two continuous syncs on one vault** — same rule as the desktop app
  plus this container against the same directory. (Separate vaults are fine; the
  sync lock lives inside each vault at `.obsidian/.sync.lock`.)
- **No file-creation-time preservation on Linux** (upstream ships that native
  addon only for macOS/Windows). Sync is otherwise unaffected.

## Upgrading

`obsidian-headless` is 0.0.x beta — pinned via `OB_VERSION` in `.env`. Bump deliberately:

```bash
curl -s https://registry.npmjs.org/obsidian-headless | \
  python3 -c 'import sys,json; print(json.load(sys.stdin)["dist-tags"])'   # latest version
# edit OB_VERSION in .env, rebuild the shared image, then restart each project:
docker compose build
COMPOSE_PROJECT_NAME=whoop VAULT_PATH=... docker compose up -d
```
