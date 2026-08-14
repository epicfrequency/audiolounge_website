#!/usr/bin/env bash
# release/install.sh — binary-only installer for HALO Endpoint.
#
# Installs a prebuilt halo-daemon for this machine's architecture. It never
# clones or downloads the source tree and never installs a compiler or build
# toolchain: the release binaries come from the GitHub Actions pipeline
# (linked against real libasound, stripped, checksummed) and are hosted at
# https://audiolounge.app/halo/releases/<version>/.
#
# Supported: DietPi, Raspberry Pi OS 64-bit, Ubuntu (anything with apt and
# systemd). Only runtime dependencies are installed when missing: ALSA
# runtime/tools and Avahi.
#
# Public install command (hosted copy):
#   curl -fsSL https://audiolounge.app/halo/install.sh | sudo bash
#
# Safe to re-run to upgrade: it replaces the binary and regenerates the
# systemd unit and Avahi advertisement from the same device/port values, so
# the two can never drift apart.
set -euo pipefail

# ------------------------------------------------------------------ config
# Where the release artifacts live. Overridable for mirrors / staging.
HALO_BASE_URL="${HALO_BASE_URL:-https://audiolounge.app/halo/releases}"
# Empty means "resolve from $HALO_BASE_URL/latest.txt".
HALO_VERSION="${HALO_VERSION:-}"

DEVICE=""
PORT="5555"
ASSUME_YES=0
SKIP_DEPS=0

usage() {
    cat <<USAGE
Usage: sudo ./install.sh [--device hw:CARD,DEV] [--port N] [--version X.Y.Z] [--yes] [--skip-deps]
       curl -fsSL https://audiolounge.app/halo/install.sh | sudo bash
       curl -fsSL https://audiolounge.app/halo/install.sh \\
         | sudo bash -s -- --device hw:CARD,DEV --yes

  --device    ALSA device, e.g. hw:1,0. Omit to choose interactively.
              Use hw: — not plughw:/default: — or ALSA silently converts
              formats and bit-perfect output is gone.
  --port      TCP port to listen on (default 5555).
  --version   Release version to install (default: \$HALO_BASE_URL/latest.txt).
  --yes       Don't prompt; auto-select the recommended device unless
              --device is given.
  --skip-deps Fail instead of installing missing runtime packages via apt.

  When run from a terminal — including via the curl pipe — the numbered
  device list is shown and you pick 1/2/3 as usual. With --yes, or with no
  terminal at all, the recommended device is auto-selected (first USB DSD
  device, else first USB device, else first device). --device overrides.
  HALO_BASE_URL / HALO_VERSION override where the binary is fetched from.

  Supported architectures: aarch64/arm64 and x86_64/amd64 only (no arm32).
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --device) DEVICE="${2:-}"; shift 2 ;;
        --port)   PORT="${2:-}";   shift 2 ;;
        --version) HALO_VERSION="${2:-}"; shift 2 ;;
        --yes)    ASSUME_YES=1;    shift ;;
        --skip-deps) SKIP_DEPS=1;  shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

[ "$(id -u)" -eq 0 ] || { echo "Must run as root: sudo ./install.sh (or directly, if already root)." >&2; exit 1; }
[[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] \
    || { echo "--port must be a number between 1 and 65535, got '$PORT'" >&2; exit 1; }
command -v systemctl >/dev/null 2>&1 \
    || { echo "systemd (systemctl) was not found — HALO Endpoint requires a systemd distro." >&2; exit 1; }

# ------------------------------------------------------- runtime deps only
ensure_runtime_dependencies() {
    local missing=()
    command -v curl >/dev/null 2>&1 || missing+=(curl)
    # The daemon links libasound.so.2; check the soname via ldconfig rather
    # than a package name (Debian trixie renamed libasound2 -> libasound2t64).
    ldconfig -p 2>/dev/null | grep -q 'libasound\.so\.2' || missing+=(libasound2)
    command -v aplay >/dev/null 2>&1 || missing+=(alsa-utils)
    # Avahi is the discovery mechanism — without it the endpoint runs but
    # never appears in the app, which is a miserable thing to diagnose.
    command -v avahi-daemon >/dev/null 2>&1 || missing+=(avahi-daemon)
    # TLS trust store for the https downloads below; present on virtually
    # every desktop install but not guaranteed on minimal images.
    [ -f /etc/ssl/certs/ca-certificates.crt ] || missing+=(ca-certificates)

    if [ ${#missing[@]} -eq 0 ]; then
        echo "==> Runtime dependencies present"
        return 0
    fi

    local uniq=()
    local pkg
    for pkg in "${missing[@]}"; do
        case " ${uniq[*]-} " in *" $pkg "*) ;; *) uniq+=("$pkg") ;; esac
    done

    if [ "$SKIP_DEPS" -eq 1 ]; then
        echo "Missing runtime packages: ${uniq[*]}" >&2
        echo "Re-run without --skip-deps, or install them yourself." >&2
        exit 1
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
        echo "Missing runtime packages: ${uniq[*]}" >&2
        echo "No apt-get here — on Debian-family systems install them first:" >&2
        echo "  apt-get install ${uniq[*]}" >&2
        exit 1
    fi

    echo "==> Installing runtime packages: ${uniq[*]}"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${uniq[@]}"
}

ensure_runtime_dependencies

# --------------------------------------------------------------- download
# Detect the architecture. arm32 (armv7l/armhf) is intentionally unsupported:
# only arm64 and x86_64 releases are built.
case "$(uname -m)" in
    aarch64|arm64)  ARCH=arm64;   BIN_NAME=halo-daemon-linux-arm64 ;;
    x86_64|amd64)   ARCH=x86_64;  BIN_NAME=halo-daemon-linux-x86_64 ;;
    *) echo "Unsupported architecture: $(uname -m) (only aarch64/arm64 and x86_64/amd64 are published)." >&2; exit 1 ;;
esac

resolve_version() {
    if [ -n "$HALO_VERSION" ]; then
        case "$HALO_VERSION" in
            *[!0-9A-Za-z._-]*|"") echo "Invalid --version / HALO_VERSION: '$HALO_VERSION'" >&2; exit 1 ;;
        esac
        return
    fi
    echo "==> Resolving latest release version from ${HALO_BASE_URL}/latest.txt"
    HALO_VERSION="$(curl -fsSL "${HALO_BASE_URL}/latest.txt" | tr -d '[:space:]')"
    case "$HALO_VERSION" in
        *[!0-9A-Za-z._-]*|"") echo "Invalid version from latest.txt: '$HALO_VERSION'" >&2; exit 1 ;;
    esac
}

resolve_version
RELEASE_URL="${HALO_BASE_URL}/${HALO_VERSION}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Downloading HALO Endpoint ${HALO_VERSION} (${BIN_NAME})"
echo "    ${RELEASE_URL}/"
curl -fsSL "${RELEASE_URL}/SHA256SUMS" -o "$WORK/SHA256SUMS"
curl -fsSL "${RELEASE_URL}/${BIN_NAME}" -o "$WORK/${BIN_NAME}"

# Verify the SHA-256 from the published checksums before touching the system.
grep -q "^[0-9a-f]\{64\}  ${BIN_NAME}$" "$WORK/SHA256SUMS" \
    || { echo "SHA256SUMS has no entry for ${BIN_NAME} — refusing to install." >&2; exit 1; }
(
    cd "$WORK"
    sha256sum -c <(grep "${BIN_NAME}" SHA256SUMS)
)

# Cheap sanity checks on the downloaded file: ELF magic, then the e_machine
# field (62 = x86_64, 183 = AArch64) so a wrong-arch binary can never be
# installed even if the URL/name ever disagreed.
[ "$(head -c 4 "$WORK/$BIN_NAME" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] \
    || { echo "Downloaded file is not an ELF binary." >&2; exit 1; }
MACHINE="$(od -An -tu2 -j 18 -N 2 "$WORK/$BIN_NAME" | tr -d ' ')"
if [ "$ARCH" = arm64 ]; then
    EXPECTED_MACHINE=183
else
    EXPECTED_MACHINE=62
fi
[ "$MACHINE" = "$EXPECTED_MACHINE" ] \
    || { echo "Binary architecture mismatch (e_machine=${MACHINE}, expected ${EXPECTED_MACHINE} for ${ARCH})." >&2; exit 1; }

# ----------------------------------------------------------------- device
# Enumerate every ALSA playback device as "hw:C,D<TAB>label". Reads
# /proc/asound directly rather than parsing `aplay -l`: the proc layout is
# stable and machine-readable. cardN/usbid exists only for USB cards, which
# cleanly separates a USB DAC from onboard outputs.
enumerate_playback_devices() {
    local cardpath card name pcm dev bus dsd
    [ -d /proc/asound ] || return 0
    for cardpath in /proc/asound/card[0-9]*; do
        [ -d "$cardpath" ] || continue
        card="${cardpath##*/card}"
        name="$(cat "$cardpath/id" 2>/dev/null || echo "card $card")"
        if [ -e "$cardpath/usbid" ]; then bus="USB"; else bus="onboard"; fi
        if grep -qi 'DSD' "$cardpath/stream0" 2>/dev/null; then dsd=", DSD"; else dsd=""; fi
        for pcm in "$cardpath"/pcm*p; do
            [ -d "$pcm" ] || continue
            dev="${pcm##*/pcm}"; dev="${dev%p}"
            printf 'hw:%s,%s\t%s (%s%s)\n' "$card" "$dev" "$name" "$bus" "$dsd"
        done
    done
}

# Reads one line from the user; falls back to /dev/tty for curl-piped runs.
prompt_read() {
    local prompt="$1"
    if [ -t 0 ]; then
        read -rp "$prompt" REPLY
    elif { exec 3< /dev/tty; } 2>/dev/null; then
        read -rp "$prompt" REPLY <&3
        exec 3<&-
    else
        return 1
    fi
}

if [ -z "$DEVICE" ]; then
    DEV_LINES=()
    while IFS= read -r line; do DEV_LINES+=("$line"); done < <(enumerate_playback_devices)
    if [ "${#DEV_LINES[@]}" -eq 0 ]; then
        echo "No ALSA playback devices found under /proc/asound." >&2
        echo "Is the DAC plugged in, and is alsa-utils installed?" >&2
        aplay -l || true
        exit 1
    fi

    # Recommend the first USB device that advertises DSD, else the first USB
    # device, else the first device at all.
    RECOMMENDED=1
    for i in "${!DEV_LINES[@]}"; do
        case "${DEV_LINES[$i]}" in *", DSD)"*) RECOMMENDED=$((i + 1)); break ;; esac
    done
    if [ "$RECOMMENDED" -eq 1 ]; then
        for i in "${!DEV_LINES[@]}"; do
            case "${DEV_LINES[$i]}" in *"(USB"*) RECOMMENDED=$((i + 1)); break ;; esac
        done
    fi

    echo "==> Playback devices"
    for i in "${!DEV_LINES[@]}"; do
        n=$((i + 1))
        hw="${DEV_LINES[$i]%%$'\t'*}"
        label="${DEV_LINES[$i]#*$'\t'}"
        if [ "$n" -eq "$RECOMMENDED" ]; then
            printf '  %d) %-10s %s  <- recommended\n' "$n" "$hw" "$label"
        else
            printf '  %d) %-10s %s\n' "$n" "$hw" "$label"
        fi
    done
    echo

    CHOICE="$RECOMMENDED"
    if [ "$ASSUME_YES" -eq 0 ] && prompt_read "Choose [${RECOMMENDED}]: "; then
        [ -n "$REPLY" ] && CHOICE="$REPLY"
    elif [ "$ASSUME_YES" -eq 0 ]; then
        echo "    (non-interactive: auto-selecting recommended device)"
    fi
    [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#DEV_LINES[@]}" ] \
        || { echo "Not a listed choice: $CHOICE" >&2; exit 1; }

    DEVICE="${DEV_LINES[$((CHOICE - 1))]%%$'\t'*}"
    echo "    Using $DEVICE"
fi

case "$DEVICE" in
    plughw:*|default*)
        echo
        echo "WARNING: '$DEVICE' goes through ALSA's conversion layer."
        echo "         Output will NOT be bit-perfect, and native DSD will not work."
        [ "$ASSUME_YES" -eq 1 ] || { prompt_read "Continue anyway? [y/N] " && [ "$REPLY" = y ] || exit 1; }
        ;;
esac

echo
echo "==> Capabilities reported by $DEVICE"
aplay --dump-hw-params -D "$DEVICE" /dev/null 2>&1 | sed -n '/FORMAT:/,/^$/p' || true

# ------------------------------------------------------------------ user
if ! id -u halo >/dev/null 2>&1; then
    echo "==> Creating system user 'halo'"
    useradd --system --no-create-home --shell /usr/sbin/nologin halo
fi
# Idempotent; also repairs an existing install whose user lost audio access.
usermod -aG audio halo

# --------------------------------------------------------------- install
if systemctl is-active --quiet halo-daemon.service 2>/dev/null; then
    echo "==> Stopping running halo-daemon"
    systemctl stop halo-daemon.service
fi

echo "==> Installing HALO Endpoint ${HALO_VERSION} to /usr/local/bin/halo-daemon"
install -m 0755 "$WORK/$BIN_NAME" /usr/local/bin/halo-daemon

# systemd unit. ExecStart and the Avahi port below are generated from the
# same two values (device + port) so they can never drift apart.
echo "==> Writing systemd unit (device=$DEVICE port=$PORT)"
cat > /etc/systemd/system/halo-daemon.service <<EOF
[Unit]
Description=HALO Endpoint (hi-res PCM/DSD network audio receiver)
# sound.target exists on most distros incl. Raspberry Pi OS; harmless if
# it doesn't, systemd just treats it as an ordering-only dependency.
After=network-online.target sound.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/halo-daemon ${DEVICE} ${PORT}
Restart=on-failure
RestartSec=1

# --- run as an unprivileged, dedicated user, not root ---
User=halo
Group=halo
# needed for /dev/snd/* access without being in the audio group's default
# ACL setup on every distro; simplest is adding the \`halo\` user to audio.
SupplementaryGroups=audio

# --- let the process (specifically, its pthread_setschedparam(SCHED_FIFO)
#     calls) actually take effect without running as root ---
AmbientCapabilities=CAP_SYS_NICE
CapabilityBoundingSet=CAP_SYS_NICE
LimitRTPRIO=95
LimitMEMLOCK=infinity
NoNewPrivileges=yes

# Creates /run/halo-daemon owned by this service (and removes it on stop).
RuntimeDirectory=halo-daemon
RuntimeDirectoryMode=0755

# --- light hardening; nothing here touches the ALSA/network paths ---
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
# \`char-alsa\` is systemd's device-class name for ALSA character devices —
# NOT a path. DeviceAllow=/dev/snd would silently match nothing.
DeviceAllow=char-alsa rw
PrivateDevices=no

[Install]
WantedBy=multi-user.target
EOF

grep -q "^ExecStart=/usr/local/bin/halo-daemon ${DEVICE} ${PORT}$" \
    /etc/systemd/system/halo-daemon.service \
    || { echo "ExecStart substitution failed — check the generated unit" >&2; exit 1; }

# ---------------------------------------------------------------- avahi
avahi_present() {
    command -v avahi-daemon >/dev/null 2>&1 && return 0
    systemctl list-unit-files 2>/dev/null | grep -q '^avahi-daemon\.service' && return 0
    return 1
}
if ! avahi_present; then
    AVAHI_MISSING=1
    echo
    echo "WARNING: avahi-daemon is not installed."
    echo "         Audio Lounge will NOT discover this endpoint until Avahi is running."
    echo "         DietPi:  dietpi-software install 152"
    echo "         Debian:  apt install avahi-daemon"
    echo
elif ! systemctl is-active --quiet avahi-daemon 2>/dev/null; then
    echo "==> Enabling avahi-daemon (needed for discovery)"
    systemctl enable --now avahi-daemon || true
fi

echo "==> Writing Avahi advertisement (port=$PORT)"
mkdir -p /etc/avahi/services
cat > /etc/avahi/services/halo-daemon.service <<EOF
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<!--
  Static Avahi/mDNS service definition — this is the entire discovery
  mechanism. Avahi watches /etc/avahi/services/ and advertises whatever
  .service files it finds, picking up changes automatically.

  %h expands to the machine's hostname, so multiple units on a LAN show up
  with distinct, human-readable names instead of colliding.
-->
<service-group>
  <name replace-wildcards="yes">HALO Endpoint on %h</name>
  <service>
    <type>_halo._tcp</type>
    <port>${PORT}</port>
    <txt-record>proto_version=1</txt-record>
  </service>
</service-group>
EOF

# ----------------------------------------------------------------- start
echo "==> Enabling and starting"
systemctl daemon-reload
systemctl enable halo-daemon.service >/dev/null
systemctl restart halo-daemon.service

sleep 1
echo
if systemctl is-active --quiet halo-daemon.service; then
    echo "==> HALO Endpoint ${HALO_VERSION} is running on ${DEVICE}, port ${PORT}"
    echo
    systemctl --no-pager --lines=8 status halo-daemon.service || true
    echo
    echo "Follow the live status line with:"
    echo "    journalctl -u halo-daemon -f"
    echo
    if [ "${AVAHI_MISSING:-0}" -eq 1 ]; then
        echo "Discovery is NOT active (no avahi-daemon) — install it, then:"
        echo "    systemctl restart avahi-daemon"
    else
        echo "In Audio Lounge: Settings -> enable HALO, then pick"
        echo "    \"HALO Endpoint on $(hostname)\""
    fi
else
    echo "==> halo-daemon FAILED to start." >&2
    journalctl -u halo-daemon --no-pager --lines=40 || true
    echo >&2
    echo "Troubleshooting:" >&2
    echo "  1. Is the ALSA device present?  aplay -l" >&2
    echo "     (the service is configured for ${DEVICE})" >&2
    echo "  2. Try the binary directly (as root, to rule out the unit):" >&2
    echo "     /usr/local/bin/halo-daemon ${DEVICE} ${PORT}" >&2
    echo "  3. Is the port already in use?  ss -lntp | grep :${PORT} || true" >&2
    echo "  4. Full live log:               journalctl -u halo-daemon -f" >&2
    exit 1
fi
