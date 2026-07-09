# syntax=docker/dockerfile:1

# obsidian-headless is beta software; pin the version and bump deliberately.
ARG OB_VERSION=0.0.12
ARG NODE_VERSION=22

FROM node:${NODE_VERSION}-alpine
ARG OB_VERSION

# su-exec drops from root to the caller's uid/gid after the entrypoint fixes
# ownership on /config. ca-certificates for TLS to the Obsidian API.
RUN apk add --no-cache su-exec ca-certificates

# better-sqlite3 is a native module, but prebuild-install fetches a matching
# binary for linux musl x64/arm64, so no compiler is needed here.
RUN npm install -g --omit=dev "obsidian-headless@${OB_VERSION}" \
    && npm cache clean --force

# On Linux `ob` resolves its state dir to $XDG_CONFIG_HOME/obsidian-headless.
# Everything durable lives there: auth_token (0600) and sync/<vaultId>/state.db.
ENV XDG_CONFIG_HOME=/config \
    HOME=/config

VOLUME ["/config"]
WORKDIR /vault

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["ob", "sync", "--continuous"]
