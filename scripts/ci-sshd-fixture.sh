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

cat > "$FIXTURES/sshd.env" <<EOF
PALANA_FIXTURE_HOST=$(whoami)@localhost
PALANA_FIXTURE_PORT=22
PALANA_FIXTURE_IDENTITY=$FIXTURES/id_fixture
PALANA_FIXTURE_IDENTITY_DENIED=$FIXTURES/id_denied
PALANA_FIXTURE_KNOWN_HOSTS=$FIXTURES/known_hosts
EOF
echo "runner fixture up: $(whoami)@localhost:22"
