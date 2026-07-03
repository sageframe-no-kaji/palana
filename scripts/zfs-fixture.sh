#!/usr/bin/env bash
# The ZFS fixture: a file-backed throwaway pool in a Lima VM. This is the
# ONLY place mutating zfs operations run during development — never a live
# host. Deferred decision 2 (ho-02): Lima over OrbStack — open source,
# brew-installable, scriptable. Docker Desktop's VM has no ZFS module.
#
# Usage: scripts/zfs-fixture.sh start | stop | destroy | status | shell-env
#
# start   — create/start the VM, install zfsutils, create pool `palana`
# stop    — stop the VM (pool survives)
# destroy — delete the VM whole, pool and all
# status  — VM state + zpool status
# shell-env — print connection facts for conduit-driven integration (ho-06)

set -euo pipefail

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
    echo "fixture up: pool '$POOL' in VM '$VM'"
}

stop() {
    limactl stop "$VM"
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
