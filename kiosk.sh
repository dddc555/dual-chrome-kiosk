#!/usr/bin/env bash
set -uo pipefail

# Log everything to a plain file for easy FE debugging
exec > /tmp/kiosk.log 2>&1

LEFT_URL="https://lwc-node-red1.u2kikaku.com/dashboard/ws"
RIGHT_URL="https://lwc-hakuba-kibana.u2kikaku.com/s/ropeway-ops/app/dashboards#/view/81475900-53ec-11f1-b459-5d0056afb5a6?_g=(filters:!())"

LEFT_PROFILE="$HOME/.config/chromium-left"
RIGHT_PROFILE="$HOME/.config/chromium-right"
PAUSE_FILE="/tmp/kiosk-pause"
LEFT_W=300

export DISPLAY="${DISPLAY:-:0}"

LPID=""
RPID=""

cleanup() {
  echo "[$(date)] Stopping kiosk browsers..."
  kill "$LPID" "$RPID" 2>/dev/null || true
  wait "$LPID" "$RPID" 2>/dev/null || true
}
trap 'cleanup; exit 0' INT TERM

# Wait for X11
until xrandr --current >/dev/null 2>&1; do
  sleep 1
done

xset s off -dpms
xset s noblank
command -v unclutter >/dev/null 2>&1 && unclutter -idle 1 &

CHROME_BIN="$(command -v chromium || command -v chromium-browser)"
mkdir -p "$LEFT_PROFILE/Default" "$RIGHT_PROFILE/Default"

COMMON_OPTS=(
  --noerrdialogs
  --no-first-run
  --disable-session-crashed-bubble
  --disable-features=TranslateUI
  --check-for-update-interval=31536000
  --disk-cache-size=52428800
)

launch_window() {
  local url="$1" profile="$2" cache_dir="$3" x="$4" y="$5" w="$6" h="$7"

  "$CHROME_BIN" \
    --app="$url" \
    --user-data-dir="$profile" \
    --disk-cache-dir="$cache_dir" \
    --window-position="${x},${y}" \
    --window-size="${w},${h}" \
    "${COMMON_OPTS[@]}" &
  LAST_PID=$!

  local wid=""
  for _ in {1..40}; do
    wid="$(xdotool search --onlyvisible --pid "$LAST_PID" 2>/dev/null | head -n1 || true)"
    [[ -n "$wid" ]] && break
    sleep 0.5
  done

  if [[ -n "$wid" ]]; then
    xdotool windowsize "$wid" "$w" "$h"
    xdotool windowmove "$wid" "$x" "$y"
  else
    echo "[$(date)] Warning: Window for $url (PID $LAST_PID) timed out"
  fi
}

while true; do
  # Allow FEs to pause auto-relaunch during maintenance
  if [[ -f "$PAUSE_FILE" ]]; then
    sleep 2
    continue
  fi

  # Wait for network/DNS before launching
  until curl -s -o /dev/null --max-time 3 "https://lwc-node-red1.u2kikaku.com"; do
    echo "[$(date)] Waiting for network..."
    sleep 2
  done

  # Clear stale locks and crash flags
  rm -f "$LEFT_PROFILE"/Singleton{Lock,Cookie,Socket} \
        "$RIGHT_PROFILE"/Singleton{Lock,Cookie,Socket}

  for prof in "$LEFT_PROFILE" "$RIGHT_PROFILE"; do
    if [[ -f "$prof/Default/Preferences" ]]; then
      sed -i 's/"exited_cleanly":false/"exited_cleanly":true/; s/"exit_type":"Crashed"/"exit_type":"Normal"/' \
        "$prof/Default/Preferences"
    fi
  done

  RES="$(xrandr --current | awk '/\*/{print $1; exit}')"
  IFS='x' read -r SCREEN_W SCREEN_H <<<"$RES"
  RIGHT_W=$(( SCREEN_W - LEFT_W ))

  echo "[$(date)] Launching Chromium windows (${SCREEN_W}x${SCREEN_H})..."
  launch_window "$LEFT_URL"  "$LEFT_PROFILE"  "/tmp/chrome-cache-left"  0         0 "$LEFT_W"  "$SCREEN_H"
  LPID=$LAST_PID

  launch_window "$RIGHT_URL" "$RIGHT_PROFILE" "/tmp/chrome-cache-right" "$LEFT_W" 0 "$RIGHT_W" "$SCREEN_H"
  RPID=$LAST_PID

  # Wait until either browser crashes or is killed, then restart both cleanly
  wait -n "$LPID" "$RPID" 2>/dev/null || true
  echo "[$(date)] A Chromium window exited. Cleaning up before relaunch..."
  cleanup
  sleep 3
done
