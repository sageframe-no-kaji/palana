#!/usr/bin/env bash
# CI sshd fixture: the GitHub macOS runner's own sshd. The runner is a
# throwaway VM — enabling Remote Login and self-authorizing a generated
# key is exactly what it exists for. Writes the same .fixtures/sshd.env
# the container fixture writes locally; the tests can't tell the difference.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$REPO_ROOT/.fixtures"
mkdir -p "$FIXTURES" ~/.ssh
chmod 700 ~/.ssh

ssh-keygen -t ed25519 -N "" -C palana-ci -f "$FIXTURES/id_fixture" -q
ssh-keygen -t ed25519 -N "" -C palana-ci-denied -f "$FIXTURES/id_denied" -q
cat "$FIXTURES/id_fixture.pub" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

sudo systemsetup -setremotelogin on 2>/dev/null \
    || sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist

for _ in $(seq 1 30); do
    if ssh-keyscan -T 2 localhost 2>/dev/null | grep -v '^#' > "$FIXTURES/known_hosts" \
        && [ -s "$FIXTURES/known_hosts" ]; then
        break
    fi
    sleep 1
done
[ -s "$FIXTURES/known_hosts" ] || { echo "runner sshd never answered" >&2; exit 1; }

# ho-06.1 aliases: both names reach the runner. The remote half of a
# "cross-host" transfer resolves fixture-self through the runner user's
# own ssh config — the runner is the remote, so they are the same file
# world. The runner ships openrsync, so the rsync-direct live test
# skips itself there (no dotted rsync version fact); the tar proxy and
# the gate machinery run in full.
RUNNER_USER=$(whoami)
cat > "$FIXTURES/ssh_config" <<EOF
Host fixture fixture-self
    HostName localhost
    Port 22
    User $RUNNER_USER
    IdentityFile $FIXTURES/id_fixture
    UserKnownHostsFile $FIXTURES/known_hosts
    StrictHostKeyChecking accept-new
    IdentitiesOnly yes
    ConnectTimeout 5
EOF
touch ~/.ssh/config
cat >> ~/.ssh/config <<EOF

Host fixture-self
    HostName localhost
    Port 22
    User $RUNNER_USER
    IdentityFile $FIXTURES/id_fixture
    StrictHostKeyChecking accept-new
EOF
chmod 600 ~/.ssh/config

cat > "$FIXTURES/sshd.env" <<EOF
PALANA_FIXTURE_HOST=$(whoami)@localhost
PALANA_FIXTURE_PORT=22
PALANA_FIXTURE_IDENTITY=$FIXTURES/id_fixture
PALANA_FIXTURE_IDENTITY_DENIED=$FIXTURES/id_denied
PALANA_FIXTURE_KNOWN_HOSTS=$FIXTURES/known_hosts
PALANA_FIXTURE_SSH_CONFIG=$FIXTURES/ssh_config
PALANA_FIXTURE_ALIAS=fixture
PALANA_FIXTURE_SELF=fixture-self
EOF
echo "runner fixture up: $(whoami)@localhost:22"
