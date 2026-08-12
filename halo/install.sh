#!/usr/bin/env bash
set -euo pipefail
BASE_URL="${HALO_BASE_URL:-https://audiolounge.app/halo/releases}"
VERSION="${HALO_VERSION:-$(curl -fsSL "$BASE_URL/latest.txt" | tr -d '[:space:]')}"
PORT="${HALO_PORT:-5555}"
[[ "${EUID:-$(id -u)}" -eq 0 ]] || { echo "Run with sudo (or as root on DietPi)."; exit 1; }
case "$(uname -m)" in aarch64|arm64) ASSET=halo-daemon-linux-arm64;; x86_64|amd64) ASSET=halo-daemon-linux-x86_64;; *) echo "HALO supports ARM64 and x86-64."; exit 1;; esac
if command -v apt-get >/dev/null; then
  apt-get update -qq
  apt-get install -y --no-install-recommends ca-certificates curl alsa-utils avahi-daemon avahi-utils >/dev/null
  ldconfig -p 2>/dev/null | grep -q 'libasound\.so\.2' || (apt-get install -y --no-install-recommends libasound2 >/dev/null 2>&1 || apt-get install -y --no-install-recommends libasound2t64 >/dev/null)
fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
URL="$BASE_URL/$VERSION"
curl -fL --retry 3 "$URL/$ASSET" -o "$TMP/$ASSET"
curl -fL --retry 3 "$URL/SHA256SUMS" -o "$TMP/SHA256SUMS"
(cd "$TMP"; grep "  $ASSET\$" SHA256SUMS > expected; sha256sum -c expected)
echo "Available ALSA playback devices:"; aplay -l || true
read -r -p "Enter HALO ALSA device (example hw:1,0): " DEVICE
[[ -n "$DEVICE" ]] || { echo "A device is required."; exit 1; }
id halo >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin halo
usermod -aG audio halo
install -m 0755 "$TMP/$ASSET" /usr/local/bin/halo-daemon
cat >/etc/systemd/system/halo-daemon.service <<EOF
[Unit]
Description=HALO Network Audio Endpoint
After=network-online.target sound.target
Wants=network-online.target
[Service]
Type=simple
User=halo
Group=halo
SupplementaryGroups=audio
ExecStart=/usr/local/bin/halo-daemon $DEVICE $PORT
Restart=on-failure
RestartSec=2
[Install]
WantedBy=multi-user.target
EOF
mkdir -p /etc/avahi/services
cat >/etc/avahi/services/halo-daemon.service <<EOF
<?xml version="1.0" standalone='no'?><!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group><name replace-wildcards="yes">HALO Endpoint on %h</name><service><type>_halo._tcp</type><port>$PORT</port></service></service-group>
EOF
systemctl daemon-reload
systemctl enable --now avahi-daemon >/dev/null 2>&1 || true
systemctl enable --now halo-daemon
echo "HALO Endpoint $VERSION is ready on $DEVICE, port $PORT."
