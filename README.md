# obsidian-sync

Headless [Obsidian Sync](https://obsidian.md/help/headless) in Docker — no Node
or desktop app on the host, and no docker-compose. A single self-contained
script (`obsidian-sync`) builds the image, manages one container per vault, and
wraps the beta `obsidian-headless` CLI (`ob`). Requires an active Obsidian Sync
subscription.

## Model

- **One vault per project directory.** Each project keeps its vault in `./wiki`,
  and the remote vault is named after the project directory (override with
  `-n <name>`).
- **Per-project isolation.** State (login, E2EE key, sync db) lives in
  `~/.config/obsidian-sync/<project>-<hash>` — a host directory outside the
  project, so keys never land in a project's own git repo. The hash is of the
  project's full path, so two projects with the same name in different places
  stay separate. The container is `obsidian-sync-<project>-<hash>`.
- **No entrypoint, no root.** The container runs as your uid via `docker run
  --user`, so files it writes to the vault are owned by you and the config
  directory needs no chown.
- **Image built on demand.** First run builds `obsidian-sync:<version>` from a
  Dockerfile embedded in the script, then reuses it.

Put `obsidian-sync` on your `PATH` (e.g. symlink into `~/.local/bin`).

## Set up a vault

From the project directory (or point at it with `-C <dir>`):

```bash
cd ~/projects/alpha          # vault is ~/projects/alpha/wiki
obsidian-sync setup
```

`setup` walks the one-time flow, skipping steps already done:

1. **login** — email, password, 2FA (interactive)
2. **create remote** — E2EE vault named after the directory (or `-n <name>`);
   you choose a password (interactive). If a remote with that name already
   exists you're asked to confirm linking to it — remote names are
   account-wide, so it may belong to another project. Answer no and rerun with
   `-n <name>` to use a different one.
3. **link** — connect `./wiki` to the remote; re-enter the E2EE password.
4. **first sync**, then starts the continuous daemon.

Steps 2–3 are skipped if the project is already linked.

Save the E2EE password: it's your only recovery secret and what you re-enter on
another device.

## Everyday use

All commands take an optional `-C <dir>` (default: current directory).

```bash
obsidian-sync start          # start / resume the daemon (restart=unless-stopped)
obsidian-sync stop           # stop + remove the container (state kept)
obsidian-sync logs           # follow the daemon
obsidian-sync status         # ob sync-status
obsidian-sync sync           # one-shot sync
obsidian-sync purge          # stop + delete this project's config (not the vault)
```

Arbitrary CLI passthrough (TTY only when interactive, so it works in cron too):

```bash
obsidian-sync ob sync-list-remote
obsidian-sync ob sync-config --mode pull-only      # backup box: ignore local edits
obsidian-sync ob sync-config --mode mirror-remote  # backup box: revert local edits
```

## Adding more vaults

Repeat `setup` in each project directory. Every vault is independent —
own container, own config directory, own login and E2EE key. Nothing shared is
edited.

```bash
obsidian-sync -C ~/projects/beta setup
obsidian-sync -C ~/work/alpha -n alpha-work setup   # name clash with ~/projects/alpha
```

## Updating

The image definition lives in the script's `build_image()` function.

- **Bump `obsidian-headless`:** run with a new version, which builds and tags a
  fresh image; then restart the daemon.

  ```bash
  # latest published version:
  curl -s https://registry.npmjs.org/obsidian-headless | \
    python3 -c 'import sys,json; print(json.load(sys.stdin)["dist-tags"])'

  OB_VERSION=0.0.15 obsidian-sync -C ~/projects/alpha restart
  ```

  Or change the `OB_VERSION` default at the top of the script.

- **Bump the base image** (Node/Alpine): edit the `FROM node:22-alpine` line in
  `build_image()`, then `obsidian-sync build` and `restart`.

## Notes

- **Moving a project directory** changes its hash, so it looks like a new
  project. Move its config directory to the new name (shown by `setup`) or run
  `setup` again. Each config dir records its path in `project-path`.
- **Upgrading from basename-keyed state:** an old `~/.config/obsidian-sync/<project>`
  is adopted automatically the first time the script runs from a project with
  that name, and its daemon is recreated under the new container name.

- **The E2EE key sits in `~/.config/obsidian-sync/<project>`.** For unattended
  sync the container must decrypt without you, so the derived key is stored
  there. Whoever can read that directory can read the vault — keep it on
  encrypted disk. Back it up: lose it and you redo login + link, and the next
  sync re-scans the vault.
- **Run as the vault's owner.** The container writes to the vault as your uid; if
  the `wiki` directory is owned by someone else the script warns and writes will
  fail.
- **Don't run two continuous syncs on one vault** (this daemon plus the desktop
  app against the same directory). Separate vaults are fine.
- **No file-creation-time preservation on Linux** — upstream ships that native
  addon only for macOS/Windows; sync is otherwise unaffected.
