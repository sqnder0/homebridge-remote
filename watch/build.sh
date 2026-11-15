#!/usr/bin/env bash
# Build the Garmin watch app and copy it to a connected watch.
#   ./build.sh            build for venusq and install if the watch is mounted
#   DEVICE=venusq2 ./build.sh   another model
#   ./build.sh --configure      ask for the Homebridge login again
set -euo pipefail
cd "$(dirname "$0")"

DEVICE="${DEVICE:-venusq}"
KEY="${KEY:-$HOME/.Garmin/ConnectIQ/developer_key.der}"
SDK="$(cat "$HOME/.Garmin/ConnectIQ/current-sdk.cfg")"

if [[ "${1:-}" == "--configure" || ! -f secrets/config.xml ]]; then
    python3 configure.py
fi

if [[ ! -f "$KEY" ]]; then
    echo "Creating a developer signing key at $KEY"
    tmp="$(mktemp)"
    openssl genrsa -out "$tmp" 4096 2>/dev/null
    openssl pkcs8 -topk8 -inform PEM -outform DER -in "$tmp" -out "$KEY" -nocrypt
    rm -f "$tmp"
    chmod 600 "$KEY"
fi

mkdir -p bin
"$SDK/bin/monkeyc" -f monkey.jungle -d "$DEVICE" -o bin/Airco.prg -y "$KEY" 2>&1 \
    | grep -v "Cannot determine if container access" || true
[[ -f bin/Airco.prg ]] || { echo "Build failed"; exit 1; }
echo "Built bin/Airco.prg"

# Find the watch's GARMIN folder (it mounts as a USB drive).
target=""
for m in /run/media/"$USER"/* /media/"$USER"/* /mnt/garmin; do
    [[ -d "$m/GARMIN/APPS" ]] && target="$m/GARMIN/APPS" && break
done
if [[ -z "$target" ]]; then
    echo "Watch not mounted. Plug it in, open it in your file manager, then run this again."
    echo "Or copy bin/Airco.prg into GARMIN/APPS on the watch yourself."
    exit 0
fi
cp bin/Airco.prg "$target/Airco.prg"
sync
echo "Installed to $target. Unplug the watch; the app appears as 'Airco'."
