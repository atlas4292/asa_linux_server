#!/usr/bin/env bash
# =============================================================================
# ASA Dedicated Server — Container Entry Point
# Runs headlessly on Linux via Proton-GE (Wine-based compatibility layer).
#
# Flow:
#   1. Start Xvfb virtual framebuffer (Wine needs a display handle to init,
#      even though -nullrhi prevents any actual rendering by the game engine)
#   2. SteamCMD: download / validate ASA server files (Windows app, forced)
#   3. Initialise Proton Wine-prefix on first run
#   4. Build the launch command and exec the server
# =============================================================================
set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[ASA]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()   { echo -e "${RED}[FATAL]${NC} $*" >&2; exit 1; }

# ── Configuration (all overridable via environment variables) ─────────────────
SESSION_NAME="${SESSION_NAME:-My ASA Server}"
SERVER_PASSWORD="${SERVER_PASSWORD:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-changeme}"
MAP="${MAP:-TheIsland_WP}"
MAX_PLAYERS="${MAX_PLAYERS:-70}"
GAME_PORT="${GAME_PORT:-7777}"
QUERY_PORT="${QUERY_PORT:-27015}"
RCON_PORT="${RCON_PORT:-27020}"
RCON_ENABLED="${RCON_ENABLED:-True}"
DISABLE_BATTLEYE="${DISABLE_BATTLEYE:-true}"
AUTO_UPDATE="${AUTO_UPDATE:-true}"
EXTRA_FLAGS="${EXTRA_FLAGS:-}"

# ── Paths ─────────────────────────────────────────────────────────────────────
STEAMCMD="/opt/steamcmd/steamcmd.sh"
SERVER_DIR="/ark/server"
PROTON_PREFIX="/ark/proton-prefix"
PROTON="${PROTON_HOME}/proton"
SERVER_EXE="${SERVER_DIR}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe"
ASA_APP_ID="2430930"   # ASA Dedicated Server on Steam (Windows-only app)

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — Virtual framebuffer
# Wine/Proton initialises an invisible window manager session as part of its
# startup sequence.  This requires a live X display socket.  Xvfb provides an
# entirely in-memory virtual screen with no GPU or physical display required.
# The game server itself renders nothing because we pass -nullrhi below.
# ─────────────────────────────────────────────────────────────────────────────
XVFB_DISPLAY=":99"
info "Starting virtual framebuffer on display ${XVFB_DISPLAY}..."
Xvfb "${XVFB_DISPLAY}" -screen 0 320x240x8 -nolisten tcp -nolisten unix &
XVFB_PID=$!
export DISPLAY="${XVFB_DISPLAY}"

# Wait up to 10 s for Xvfb to become ready
for i in $(seq 1 10); do
    if kill -0 "${XVFB_PID}" 2>/dev/null; then
        break
    fi
    sleep 1
done
kill -0 "${XVFB_PID}" 2>/dev/null || die "Xvfb failed to start."
info "Xvfb running (PID ${XVFB_PID})."

# ── Graceful shutdown handler ─────────────────────────────────────────────────
SERVER_PID=""
cleanup() {
    info "Shutdown signal received — stopping server gracefully..."
    if [[ -n "${SERVER_PID}" ]]; then
        # SIGTERM gives ASA time to flush saves (stop_grace_period in compose)
        kill -TERM "${SERVER_PID}" 2>/dev/null || true
        wait "${SERVER_PID}" 2>/dev/null || true
    fi
    kill "${XVFB_PID}" 2>/dev/null || true
    info "Shutdown complete."
}
trap cleanup EXIT INT TERM HUP

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — SteamCMD: download / update server
# ASA Dedicated Server (AppID 2430930) is Windows-only on Steam.
# +@sSteamCmdForcePlatformType windows instructs SteamCMD to download the
# Windows depot even when running on a Linux host.
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${AUTO_UPDATE}" == "true" ]]; then
    info "Running SteamCMD — this can take a long time on first run (~30-40 GB)..."
    "${STEAMCMD}" \
        +@sSteamCmdForcePlatformType windows \
        +@sSteamCmdForcePlatformBitness 64 \
        +login anonymous \
        +force_install_dir "${SERVER_DIR}" \
        +app_update "${ASA_APP_ID}" validate \
        +quit \
    || die "SteamCMD failed. Check your network connection and available disk space."
    info "Server files are up to date."
else
    warn "AUTO_UPDATE=false — skipping SteamCMD update."
fi

[[ -f "${SERVER_EXE}" ]] || \
    die "Server executable not found at:\n  ${SERVER_EXE}\nSet AUTO_UPDATE=true and restart to download the server files."

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — Proton / Wine-prefix initialisation
# The prefix is a Wine 'C: drive' emulation directory.  It only needs to be
# created once; subsequent starts reuse the existing prefix.
# ─────────────────────────────────────────────────────────────────────────────
export STEAM_COMPAT_DATA_PATH="${PROTON_PREFIX}"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="/opt/steamcmd"

if [[ ! -d "${PROTON_PREFIX}/pfx" ]]; then
    info "Creating Proton Wine prefix at ${PROTON_PREFIX} (first run only)..."
    "${PROTON}" run wineboot --init 2>/dev/null || true
    info "Wine prefix initialised."
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — Build launch parameters and start the server
# ─────────────────────────────────────────────────────────────────────────────

# ── URL-style query parameters (first positional argument to the exe) ─────────
QUERY_PARAMS="${MAP}?listen"
QUERY_PARAMS+="?SessionName=${SESSION_NAME}"
QUERY_PARAMS+="?Port=${GAME_PORT}"
QUERY_PARAMS+="?QueryPort=${QUERY_PORT}"
QUERY_PARAMS+="?MaxPlayers=${MAX_PLAYERS}"
QUERY_PARAMS+="?ServerAdminPassword=${ADMIN_PASSWORD}"
QUERY_PARAMS+="?RCONEnabled=${RCON_ENABLED}"
QUERY_PARAMS+="?RCONPort=${RCON_PORT}"
[[ -n "${SERVER_PASSWORD}" ]] && QUERY_PARAMS+="?ServerPassword=${SERVER_PASSWORD}"

# ── Dash-flags ────────────────────────────────────────────────────────────────
FLAGS=()
FLAGS+=("-server")
FLAGS+=("-log")
FLAGS+=("-game")
FLAGS+=("-engine")
FLAGS+=("-nosteamclient")       # Don't require Steam client presence
FLAGS+=("-nullrhi")             # Disable Unreal rendering hardware interface
FLAGS+=("-nosound")             # Disable audio subsystem entirely
FLAGS+=("-nographics")          # Belt-and-suspenders: no graphics init
FLAGS+=("-NoEAC" "-noeac")      # Disable Easy Anti-Cheat (unsupported on Linux)
[[ "${DISABLE_BATTLEYE}" == "true" ]] && FLAGS+=("-NoBattlEye")
[[ -n "${EXTRA_FLAGS}" ]] && read -r -a EXTRA_ARRAY <<< "${EXTRA_FLAGS}" && FLAGS+=("${EXTRA_ARRAY[@]}")

# ── Proton / Wine environment ─────────────────────────────────────────────────
export PROTON_NO_ESYNC=0            # Enable esync (eventfd-based sync, faster)
export PROTON_NO_FSYNC=0            # Enable fsync if kernel supports it
export WINEDEBUG="-all"             # Silence verbose Wine debug output
export DXVK_LOG_LEVEL="none"        # Silence DXVK logging
export VKD3D_DEBUG="none"           # Silence vkd3d logging
export WINE_LARGE_ADDRESS_AWARE=1   # Allow 32-bit processes to use >2 GB RAM

info "============================================================"
info "  Map:         ${MAP}"
info "  Session:     ${SESSION_NAME}"
info "  Players:     ${MAX_PLAYERS}"
info "  Ports:       game=${GAME_PORT}  query=${QUERY_PORT}  rcon=${RCON_PORT}"
info "  BattlEye:    $([ "${DISABLE_BATTLEYE}" = "true" ] && echo "disabled" || echo "enabled")"
info "  Proton:      ${PROTON_VERSION}"
info "============================================================"

info "Launching ASA server..."
"${PROTON}" run "${SERVER_EXE}" "${QUERY_PARAMS}" "${FLAGS[@]}" &
SERVER_PID=$!
info "Server started (PID ${SERVER_PID}). Waiting..."

# Block until the server exits (normal shutdown, crash, or Docker stop)
wait "${SERVER_PID}"
EXIT_CODE=$?
info "Server exited with code ${EXIT_CODE}."
exit "${EXIT_CODE}"
