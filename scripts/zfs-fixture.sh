#!/usr/bin/env bash
# The ZFS fixture: a file-backed throwaway pool in a Lima VM. This is the
# ONLY place mutating zfs operations run during development — never a live
# host. Deferred decision 2 (ho-02): Lima over OrbStack — open source,
# brew-installable, scriptable. Docker Desktop's VM has no ZFS module.
#
# Usage: scripts/zfs-fixture.sh start | stop | destroy | status | shell-env
#
# start   — create/start the VM, install zfsutils, create pool `palana`,
#           create the dataset shapes (ho-03), write .fixtures/zfs.env
# stop    — stop the VM (pool survives), remove the env file
# destroy — delete the VM whole, pool and all
# status  — VM state + zpool status
# shell-env — print connection facts for conduit-driven integration (ho-06)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$REPO_ROOT/.fixtures"
VM=palana-zfs
POOL=palana
POOL_IMG=/var/tmp/palana-pool.img
POOL_SIZE=1G

start() {
    if ! limactl list --format '{{.Name}}' 2>/dev/null | grep -qx "$VM"; then
        limactl start --name="$VM" --tty=false template://ubuntu-lts
    elif [ "$(limactl list --format '{{.Status}}' "$VM")" != "Running" ]; then
        limactl start --tty=false "$VM"
    fi
    limactl shell "$VM" -- bash -c '
        set -e
        if ! command -v zpool >/dev/null; then
            sudo apt-get update -q
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q zfsutils-linux
        fi
    '
    limactl shell "$VM" -- sudo bash -c "
        set -e
        if ! zpool list $POOL >/dev/null 2>&1; then
            truncate -s $POOL_SIZE $POOL_IMG
            zpool create $POOL $POOL_IMG
        fi
        zpool status $POOL
    "
    datasets
    selfreach
    write_env
    echo "fixture up: pool '$POOL' in VM '$VM' — facts in .fixtures/zfs.env"
}

# ho-06.2: the VM learns to reach itself as zfs-self, and the pool
# delegates to the VM user — send/receive enact as pālana would run
# them, no sudo in any composed command.
selfreach() {
    limactl shell "$VM" -- bash -c '
        set -e
        if [ ! -f ~/.ssh/palana_fixture ]; then
            ssh-keygen -t ed25519 -N "" -f ~/.ssh/palana_fixture -q
            cat ~/.ssh/palana_fixture.pub >> ~/.ssh/authorized_keys
            cat >> ~/.ssh/config <<CONF
Host zfs-self
    HostName localhost
    Port 22
    IdentityFile ~/.ssh/palana_fixture
    StrictHostKeyChecking accept-new
CONF
            chmod 600 ~/.ssh/config
        fi
        # Property names ride along: creating with -o canmount=noauto —
        # and receiving a -R stream that carries it — needs the property
        # itself delegated, not just the verb.
        sudo zfs allow -u "$(whoami)" \
            send,snapshot,hold,create,receive,mount,destroy,rename,rollback,canmount,mountpoint palana
    '
}

# The dataset shapes the ho-03 boundary battery runs against: nesting,
# an out-of-tree mountpoint, legacy, and a created-but-unmounted dataset.
datasets() {
    limactl shell "$VM" -- sudo bash -c '
        set -e
        ensure() {
            name="$1"; shift
            zfs list "$name" >/dev/null 2>&1 || zfs create "$@" "$name"
        }
        # ensure only ever CREATES. reconcile puts a dataset back at the
        # mountpoint the fixture designed for it, because a hands session can
        # move one and the drift is then silent until the boundary battery
        # fails against a shape nobody meant. Seen 2026-07-29: photos had been
        # set to /palana/children-moved, and a stray dataset sat mounted at /
        # where it shadowed every path lookup in the pool.
        reconcile() {
            name="$1"; want="$2"
            if [ "$(zfs get -H -o value mountpoint "$name")" = "$want" ]; then
                return 0
            fi
            echo "reconciling $name -> $want" >&2
            zfs set mountpoint="$want" "$name"
        }
        ensure palana/tank
        ensure palana/tank/media
        ensure palana/tank/media/photos
        ensure palana/svc -o mountpoint=/opt/services
        ensure palana/svc/baserow
        ensure palana/legacy -o mountpoint=legacy
        ensure palana/detached -o canmount=noauto
        reconcile palana                   /palana
        reconcile palana/tank              /palana/tank
        reconcile palana/tank/media        /palana/tank/media
        reconcile palana/tank/media/photos /palana/tank/media/photos
        reconcile palana/svc               /opt/services
        reconcile palana/svc/baserow       /opt/services/baserow
        reconcile palana/legacy            legacy
        reconcile palana/detached          /palana/detached
        zfs mount -a 2>/dev/null || true
        # Datasets the fixture never made are NAMED, never destroyed. A
        # leftover from a hands session is the operator to remove, not a
        # script — but it should never be able to hide either.
        designed=" palana palana/tank palana/tank/media palana/tank/media/photos"
        designed="$designed palana/svc palana/svc/baserow palana/legacy palana/detached "
        for found in $(zfs list -H -o name -r palana); do
            case "$designed" in
                *" $found "*) ;;
                *) echo "note: $found is not part of the fixture shape (at $(zfs get -H -o value mountpoint "$found"))" >&2 ;;
            esac
        done
        # The operator writes through the panes as the ssh user — root-owned
        # mountpoints turn every pane transfer into EACCES (the yank round).
        chown -R atmarcus:atmarcus /palana /opt/services
    '
}

write_env() {
    mkdir -p "$FIXTURES"
    # lima maintains this config; `limactl show-ssh` is deprecated in its favor.
    # The Host line learns a second name so zfs-self resolves operator-side too.
    sed "s/^Host lima-$VM\$/Host lima-$VM zfs-self/" \
        "$HOME/.lima/$VM/ssh.config" > "$FIXTURES/zfs-ssh-config"
    cat > "$FIXTURES/zfs.env" <<EOF
PALANA_ZFS_HOST=lima-$VM
PALANA_ZFS_SELF=zfs-self
PALANA_ZFS_SSH_CONFIG=$FIXTURES/zfs-ssh-config
PALANA_ZFS_POOL=$POOL
EOF
}

stop() {
    limactl stop "$VM"
    rm -f "$FIXTURES/zfs.env"
}

destroy() {
    limactl delete -f "$VM" 2>/dev/null || true
    echo "fixture destroyed"
}

status() {
    limactl list "$VM" 2>/dev/null || echo "no VM"
    limactl shell "$VM" -- sudo zpool status "$POOL" 2>/dev/null || echo "no pool"
}

shellenv() {
    # ho-06 wires the Conduit into the VM through lima's ssh config.
    limactl show-ssh --format config "$VM"
}

case "${1:-}" in
    start) start ;;
    stop) stop ;;
    destroy) destroy ;;
    status) status ;;
    shell-env) shellenv ;;
    *) echo "usage: $0 start|stop|destroy|status|shell-env" >&2; exit 64 ;;
esac
