#!/bin/sh
set -eu

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

if [ "$(id -u)" = "0" ]; then
    # The node image already owns uid/gid 1000; only create them when the
    # caller asks for something else. busybox `adduser -G` wants a group
    # *name*, so resolve it rather than passing the gid through.
    if getent group "$PGID" >/dev/null 2>&1; then
        group_name="$(getent group "$PGID" | cut -d: -f1)"
    else
        group_name=obsidian
        addgroup -g "$PGID" "$group_name"
    fi

    # A passwd entry isn't needed by su-exec, but node's os.userInfo()
    # throws without one.
    if ! getent passwd "$PUID" >/dev/null 2>&1; then
        adduser -u "$PUID" -G "$group_name" -h /config -H -D -s /sbin/nologin obsidian
    fi

    # /config is a named volume and is created root-owned on first run.
    # Recursive, so that changing PUID between runs doesn't strand the
    # sync/ and publish/ subtrees under the previous owner.
    # /vault is deliberately left alone: it is the user's real vault, and a
    # recursive chown across it would rewrite ownership on every file.
    mkdir -p /config
    chown -R "$PUID:$PGID" /config

    # su-exec resets HOME from the target user's passwd entry, clobbering the
    # image's ENV. Force it back so state stays under /config even if
    # XDG_CONFIG_HOME is ever unset.
    exec su-exec "$PUID:$PGID" env HOME=/config "$@"
fi

exec "$@"
