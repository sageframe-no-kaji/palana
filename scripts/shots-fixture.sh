#!/usr/bin/env bash
# Screenshot fixture: two throwaway Linux hosts, `jodo` and `koan`, with ZFS
# pools and made-up files, reachable from a Tart macOS guest that runs pālana.
# Used only to take product screenshots. Nothing here touches a live host.
#
# Usage: scripts/shots-fixture.sh up | seed | guest | down | destroy
#
#   up       start the Lima VMs palana-jodo and palana-koan (clones of the
#            palana-zfs fixture; made once with `limactl clone palana-zfs
#            palana-jodo` and an ssh.localPort edit, see SHOTS.md) and the
#            relays that put their ssh ports on the Tart bridge
#   seed     (re)create pool `tank` on jodo and `rpool` on koan, the
#            datasets, snapshots and files the screenshots show, and the
#            jodo → koan ssh route
#   guest    install the shots key, ssh config and Palana.app into the Tart
#            guest `palana-shots` (PALANA_SHOTS_VM to change it)
#   down     stop the relays and the two VMs (pools survive)
#   destroy  down, then delete both VMs
#
# Network. Lima publishes each VM's sshd on the host's loopback only
# (62201 jodo, 62202 koan). The Tart guest cannot reach the host loopback, so
# socat relays listen on the Tart bridge address (bridge100, 192.168.64.1)
# only — never on 0.0.0.0 — at 2201 and 2202. jodo reaches koan through
# host.lima.internal:62202, so a jodo → koan copy runs host to host, as on a
# real network.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/.fixtures/shots"
KEY="$DIR/id_shots"
VM="${PALANA_SHOTS_VM:-palana-shots}"
GUEST_USER="${PALANA_SHOTS_VM_USER:-admin}"
BRIDGE_IP="192.168.64.1"

relay_start() {
    mkdir -p "$DIR"
    local port target
    for pair in "2201:62201" "2202:62202"; do
        port="${pair%%:*}"
        target="${pair##*:}"
        if [[ -f "$DIR/relay-$port.pid" ]] && kill -0 "$(cat "$DIR/relay-$port.pid")" 2>/dev/null; then
            continue
        fi
        socat "TCP-LISTEN:$port,bind=$BRIDGE_IP,reuseaddr,fork" "TCP:127.0.0.1:$target" \
            </dev/null >/dev/null 2>&1 &
        echo $! >"$DIR/relay-$port.pid"
        disown
    done
}

relay_stop() {
    for port in 2201 2202; do
        if [[ -f "$DIR/relay-$port.pid" ]]; then
            kill "$(cat "$DIR/relay-$port.pid")" 2>/dev/null || true
            rm -f "$DIR/relay-$port.pid"
        fi
    done
}

on() {  # on <vm> <bash script on stdin>
    limactl shell "palana-$1" -- bash -s
}

seed_jodo() {
    on jodo <<'EOF'
set -euo pipefail
sudo hostnamectl set-hostname jodo
sudo zpool destroy -f tank 2>/dev/null || true
sudo rm -f /var/lib/shots-tank.img
sudo truncate -s 4G /var/lib/shots-tank.img
sudo zpool create -f -o ashift=12 -O compression=lz4 -O atime=off tank /var/lib/shots-tank.img
for ds in tank/media tank/media/camera tank/media/camera/cold tank/media/photos \
          tank/backups tank/backups/koan tank/home tank/vm; do
    sudo zfs create "$ds"
done
sudo zfs set quota=2T tank/media/photos
sudo chown -R "$USER": /tank
cd /tank/media/camera
truncate -s 38100M archive-2024
truncate -s 41300M archive-2025
head -c 1258291 /dev/urandom > camera.db
mkdir -p clips exports
truncate -s 2100M clips/2026-11-14-north.mp4
truncate -s 1900M clips/2026-11-14-south.mp4
truncate -s 640M exports/timelapse-october.mp4
cat > notes.md <<'MD'
# camera

Archive rotation: keep two years on tank, older years go cold.

- 2024 archive moved to cold on 2026-01-12
- 2025 archive copies to koan:/rpool/cold before the January rotation
- camera.db is the index; back it up with the archives
MD
for i in $(seq 1 120); do printf 'line %d of the camera notes\n' "$i"; done >> notes.md
head -c 9000 /dev/urandom | base64 > README
cd /tank/media/photos
mkdir -p 2024 2025 2026
truncate -s 12G 2024/library.tar; truncate -s 15G 2025/library.tar; truncate -s 6G 2026/library.tar
cd /tank/media/camera/cold
truncate -s 36G archive-2023
for snap in auto-2026-11-01 auto-2026-11-08 auto-2026-11-14 auto-2026-11-15; do
    sudo zfs snapshot -r "tank/media@$snap"
done
sudo zfs snapshot tank/backups@weekly-2026-11-09
sudo zfs snapshot tank/home@before-upgrade
EOF
}

seed_koan() {
    on koan <<'EOF'
set -euo pipefail
sudo hostnamectl set-hostname koan
sudo zpool destroy -f rpool 2>/dev/null || true
sudo rm -f /var/lib/shots-rpool.img
sudo truncate -s 4G /var/lib/shots-rpool.img
sudo zpool create -f -o ashift=12 -O compression=lz4 -O atime=off rpool /var/lib/shots-rpool.img
for ds in rpool/cold rpool/cold/media rpool/data rpool/data/restic; do
    sudo zfs create "$ds"
done
sudo chown -R "$USER": /rpool
cd /rpool/cold
mkdir -p restore-test
head -c 3150000 /dev/urandom | base64 > parity.log
truncate -s 8G media/archive-2023
sudo zfs snapshot -r rpool/cold@auto-2026-11-14
EOF
}

route_jodo_to_koan() {
    limactl copy "$KEY" palana-jodo:/tmp/id_shots
    on jodo <<'EOF'
set -euo pipefail
install -m 600 /tmp/id_shots ~/.ssh/id_shots && rm /tmp/id_shots
touch ~/.ssh/config
grep -q '^Host koan$' ~/.ssh/config || cat >> ~/.ssh/config <<'CFG'

Host koan
    HostName host.lima.internal
    Port 62202
    IdentityFile ~/.ssh/id_shots
    StrictHostKeyChecking accept-new
CFG
chmod 600 ~/.ssh/config
ssh -o BatchMode=yes koan hostname
EOF
}

authorize() {
    local pub
    pub="$(cat "$KEY.pub")"
    for vm in jodo koan; do
        on "$vm" <<<"grep -qxF '$pub' ~/.ssh/authorized_keys || echo '$pub' >> ~/.ssh/authorized_keys"
    done
}

case "${1:-}" in
    up)
        limactl start palana-jodo --tty=false
        limactl start palana-koan --tty=false
        relay_start
        echo "relays: $BRIDGE_IP:2201 → jodo, $BRIDGE_IP:2202 → koan"
        ;;
    seed)
        mkdir -p "$DIR"
        [[ -f "$KEY" ]] || ssh-keygen -q -t ed25519 -N '' -C palana-shots -f "$KEY"
        authorize
        seed_jodo
        seed_koan
        route_jodo_to_koan
        echo "seeded"
        ;;
    guest)
        ip="$(tart ip "$VM" --wait 120)"
        lima_user="$(limactl shell palana-jodo -- whoami)"
        scp -q "$KEY" "$GUEST_USER@$ip:.ssh/id_shots"
        ssh "$GUEST_USER@$ip" "chmod 600 ~/.ssh/id_shots; cat > ~/.ssh/config" <<CFG
Host jodo
    HostName $BRIDGE_IP
    Port 2201
    User $lima_user
    IdentityFile ~/.ssh/id_shots
    StrictHostKeyChecking accept-new

Host koan
    HostName $BRIDGE_IP
    Port 2202
    User $lima_user
    IdentityFile ~/.ssh/id_shots
    StrictHostKeyChecking accept-new
CFG
        ssh "$GUEST_USER@$ip" 'ssh -o BatchMode=yes jodo hostname && ssh -o BatchMode=yes koan hostname'
        if [[ -d "$ROOT/dist/Palana.app" ]]; then
            ssh "$GUEST_USER@$ip" 'rm -rf /Applications/Palana.app'
            ditto -c --keepParent "$ROOT/dist/Palana.app" - | ssh "$GUEST_USER@$ip" 'ditto -x - /Applications'
            echo "installed Palana.app in $VM"
        fi
        ;;
    down)
        relay_stop
        limactl stop palana-jodo || true
        limactl stop palana-koan || true
        ;;
    destroy)
        relay_stop
        limactl delete -f palana-jodo palana-koan
        ;;
    *)
        sed -n '2,25p' "$0"
        exit 2
        ;;
esac
