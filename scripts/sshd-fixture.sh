#!/usr/bin/env bash
# Local sshd fixture for integration tests. A disposable container — never
# a live host. Writes .fixtures/sshd.env at the repo root; the tests read
# connection facts from it and don't know which fixture they got.
#
# Usage: scripts/sshd-fixture.sh start | stop | status

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$REPO_ROOT/.fixtures"
CONTAINER=palana-sshd-fixture
PORT=2223
IMAGE=linuxserver/openssh-server:latest

start() {
    mkdir -p "$FIXTURES"
    [ -f "$FIXTURES/id_fixture" ] || ssh-keygen -t ed25519 -N "" -C palana-fixture \
        -f "$FIXTURES/id_fixture" -q
    [ -f "$FIXTURES/id_denied" ] || ssh-keygen -t ed25519 -N "" -C palana-denied \
        -f "$FIXTURES/id_denied" -q

    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    docker run -d --name "$CONTAINER" \
        -e PUID=1000 -e PGID=1000 -e USER_NAME=palana \
        -e PUBLIC_KEY="$(cat "$FIXTURES/id_fixture.pub")" \
        -p "$PORT":2222 \
        "$IMAGE" >/dev/null

    # Wait for sshd, then pin the host key.
    for _ in $(seq 1 30); do
        if ssh-keyscan -p "$PORT" -T 2 localhost 2>/dev/null \
            | grep -v '^#' > "$FIXTURES/known_hosts" && [ -s "$FIXTURES/known_hosts" ]; then
            break
        fi
        sleep 1
    done
    [ -s "$FIXTURES/known_hosts" ] || { echo "sshd never answered on :$PORT" >&2; exit 1; }

    # ho-06.1: the container learns rsync and how to reach itself, so a
    # "cross-host" transfer has a real remote end with one container.
    docker exec -u root "$CONTAINER" apk add --no-cache --quiet rsync
    docker cp "$FIXTURES/id_fixture" "$CONTAINER:/config/.ssh/id_fixture" >/dev/null
    docker exec -u root "$CONTAINER" sh -c '
        cat > /config/.ssh/config <<CONF
Host fixture-self
    HostName localhost
    Port 2222
    User palana
    IdentityFile /config/.ssh/id_fixture
    StrictHostKeyChecking accept-new
    UserKnownHostsFile /config/.ssh/known_hosts
CONF
        chown -R 1000:1000 /config/.ssh
        chmod 600 /config/.ssh/id_fixture /config/.ssh/config
    '

    # Operator-side aliases: both names reach the container. Tests and
    # the proxy pipeline halves resolve them via -F.
    cat > "$FIXTURES/ssh_config" <<EOF
Host fixture fixture-self
    HostName localhost
    Port $PORT
    User palana
    IdentityFile $FIXTURES/id_fixture
    UserKnownHostsFile $FIXTURES/known_hosts
    StrictHostKeyChecking accept-new
    IdentitiesOnly yes
    ConnectTimeout 5
EOF

    cat > "$FIXTURES/sshd.env" <<EOF
PALANA_FIXTURE_HOST=palana@localhost
PALANA_FIXTURE_PORT=$PORT
PALANA_FIXTURE_IDENTITY=$FIXTURES/id_fixture
PALANA_FIXTURE_IDENTITY_DENIED=$FIXTURES/id_denied
PALANA_FIXTURE_KNOWN_HOSTS=$FIXTURES/known_hosts
PALANA_FIXTURE_SSH_CONFIG=$FIXTURES/ssh_config
PALANA_FIXTURE_ALIAS=fixture
PALANA_FIXTURE_SELF=fixture-self
EOF
    echo "fixture up: palana@localhost:$PORT — facts in .fixtures/sshd.env"
}

stop() {
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    rm -f "$FIXTURES/sshd.env"
    echo "fixture down"
}

status() {
    docker ps --filter "name=$CONTAINER" --format '{{.Names}} {{.Status}}'
    [ -f "$FIXTURES/sshd.env" ] && cat "$FIXTURES/sshd.env" || echo "no env file"
}

case "${1:-}" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    *) echo "usage: $0 start|stop|status" >&2; exit 64 ;;
esac
