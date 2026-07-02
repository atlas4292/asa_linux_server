#!/usr/bin/env bash
# =============================================================================
# ASA Dedicated Server — Container Entry Point
# Runs headlessly on Linux via Proton-GE (Wine-based compatibility layer).
#
# Flow:
#   1. Set headless Wine environment (Wine 6+ null display driver, no Xvfb)
#   2. SteamCMD: download / validate ASA server files (Windows app, forced)
#   3. Generate GameUserSettings.ini and Game.ini from game.env variables
#   4. Initialise Proton Wine-prefix on first run
#   5. Build the launch command and exec the server
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

# ── INI file generator ───────────────────────────────────────────────────────
# Reads game.env variables (injected by Docker via env_file) and writes them
# into the ASA config directory on every startup.  game.env is the single
# source of truth — manual ini edits will be overwritten on next restart.
write_ini_files() {
    local cfg="${SERVER_DIR}/ShooterGame/Saved/Config/WindowsServer"
    mkdir -p "${cfg}"
    # ASA ini booleans must be Title Case
    ini_bool() { [[ "${1,,}" == "true" ]] && echo "True" || echo "False"; }

    info "Writing GameUserSettings.ini from game.env..."
    {
        echo "[ServerSettings]"
        # XP & Leveling
        echo "XPMultiplier=${XP_MULTIPLIER:-1.0}"
        echo "KillXPMultiplier=${KILL_XP_MULTIPLIER:-1.0}"
        echo "HarvestXPMultiplier=${HARVEST_XP_MULTIPLIER:-1.0}"
        echo "CraftXPMultiplier=${CRAFT_XP_MULTIPLIER:-1.0}"
        # Gathering
        echo "HarvestAmountMultiplier=${HARVEST_AMOUNT:-1.0}"
        echo "ResourcesRespawnPeriodMultiplier=${RESOURCE_RESPAWN_PERIOD:-1.0}"
        echo "GlobalSpoilingTimeMultiplier=${GLOBAL_SPOILING_TIME:-1.0}"
        echo "GlobalItemDecompositionTimeMultiplier=${GLOBAL_ITEM_DECOMP:-1.0}"
        echo "GlobalCorpseDecompositionTimeMultiplier=${GLOBAL_CORPSE_DECOMP:-1.0}"
        # Taming & Breeding
        echo "TamingSpeedMultiplier=${TAMING_SPEED:-1.0}"
        echo "LayEggIntervalMultiplier=${LAY_EGG_INTERVAL:-1.0}"
        echo "MatingIntervalMultiplier=${MATING_INTERVAL:-1.0}"
        echo "EggHatchSpeedMultiplier=${EGG_HATCH_SPEED:-1.0}"
        echo "BabyMatureSpeedMultiplier=${BABY_MATURE_SPEED:-1.0}"
        echo "BabyFoodConsumptionSpeedMultiplier=${BABY_FOOD_CONSUMPTION:-1.0}"
        # Player
        echo "PlayerDamageMultiplier=${PLAYER_DAMAGE:-1.0}"
        echo "PlayerResistanceMultiplier=${PLAYER_RESISTANCE:-1.0}"
        echo "PlayerCharacterHealthRecoveryMultiplier=${PLAYER_HEALTH_RECOVERY:-1.0}"
        echo "PlayerCharacterStaminaDrainMultiplier=${PLAYER_STAMINA_DRAIN:-1.0}"
        echo "PlayerCharacterFoodDrainMultiplier=${PLAYER_FOOD_DRAIN:-1.0}"
        echo "PlayerCharacterWaterDrainMultiplier=${PLAYER_WATER_DRAIN:-1.0}"
        # Dino
        echo "DinoHarvestingDamageMultiplier=${DINO_DAMAGE:-1.0}"
        echo "DinoResistanceMultiplier=${DINO_RESISTANCE:-1.0}"
        echo "DinoCharacterHealthRecoveryMultiplier=${DINO_HEALTH_RECOVERY:-1.0}"
        echo "DinoCharacterStaminaDrainMultiplier=${DINO_STAMINA_DRAIN:-1.0}"
        echo "DinoCharacterFoodDrainMultiplier=${DINO_FOOD_DRAIN:-1.0}"
        # World
        echo "CropGrowthSpeedMultiplier=${CROP_GROWTH_SPEED:-1.0}"
        echo "CropDecaySpeedMultiplier=${CROP_DECAY_SPEED:-1.0}"
        echo "FuelConsumptionIntervalMultiplier=${FUEL_CONSUMPTION:-1.0}"
        # Server rules
        echo "AllowThirdPersonPlayer=$(ini_bool "${ALLOW_THIRD_PERSON:-true}")"
        echo "AllowFlyerCarryPvE=$(ini_bool "${ALLOW_FLYER_CARRY_PVE:-false}")"
        echo "DisableDinoDecayPvE=$(ini_bool "${DISABLE_DINO_DECAY_PVE:-false}")"
        echo "AllowCaveBuildingPvE=$(ini_bool "${ALLOW_CAVE_BUILDING_PVE:-false}")"
        echo "AlwaysAllowStructurePickup=$(ini_bool "${ALWAYS_ALLOW_STRUCTURE_PICKUP:-true}")"
        echo "StructurePickupHoldDuration=${STRUCTURE_PICKUP_HOLD_DURATION:-0.5}"
        echo "AdminLogging=$(ini_bool "${ADMIN_LOGGING:-false}")"
        echo "ShowFloatingDamageText=$(ini_bool "${SHOW_DAMAGE_TEXT:-true}")"
        echo "AllowHitMarkers=$(ini_bool "${ALLOW_HIT_MARKERS:-true}")"
        echo "IdlePlayerKickInterval=${IDLE_KICK_INTERVAL:-0}"
        echo "MaxTribeLogEntries=${MAX_TRIBE_LOG_ENTRIES:-100}"
        echo "MaxNumberOfPlayersInTribe=${MAX_PLAYERS_IN_TRIBE:-0}"
        [[ -n "${ACTIVE_EVENT:-}" ]] && echo "ActiveEvent=${ACTIVE_EVENT}"
        echo ""
        echo "[MessageOfTheDay]"
        echo "Message=${MOTD_MESSAGE:-Welcome to the server!}"
        echo "Duration=${MOTD_DURATION:-20}"
    } > "${cfg}/GameUserSettings.ini"

    info "Writing Game.ini from game.env..."
    {
        echo "[/Script/ShooterGame.ShooterGameMode]"
        echo "OverrideOfficialDifficulty=${OVERRIDE_OFFICIAL_DIFFICULTY:-5.0}"
        echo "DifficultyOffset=${DIFFICULTY_OFFSET:-1.0}"
        echo "SupplyCrateLootQualityMultiplier=${SUPPLY_LOOT_QUALITY:-1.0}"
        echo "FishingLootQualityMultiplier=${FISHING_LOOT_QUALITY:-1.0}"
    } > "${cfg}/Game.ini"
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — Headless Wine / Proton environment
# Wine 6+ ships a built-in null display driver that activates automatically
# when DISPLAY is unset — no Xvfb needed.  ASA also passes -nullrhi so the
# game engine never attempts to initialise any rendering pipeline.
#
# Fallback: if the server exits with X11/display errors, install xvfb in the
# Dockerfile and add the following before this block:
#   Xvfb :99 -screen 0 320x240x8 -nolisten tcp &; export DISPLAY=:99
# ─────────────────────────────────────────────────────────────────────────────
unset DISPLAY
export SDL_VIDEODRIVER="dummy"   # SDL headless dummy driver
export SDL_AUDIODRIVER="dummy"   # SDL headless audio stub

# ── Graceful shutdown handler ─────────────────────────────────────────────────
SERVER_PID=""
cleanup() {
    info "Shutdown signal received — stopping server gracefully..."
    if [[ -n "${SERVER_PID}" ]]; then
        # SIGTERM gives ASA time to flush saves (stop_grace_period in compose)
        kill -TERM "${SERVER_PID}" 2>/dev/null || true
        wait "${SERVER_PID}" 2>/dev/null || true
    fi
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
# STEP 3 — Generate ini files from game.env
# ─────────────────────────────────────────────────────────────────────────────
write_ini_files

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — Proton / Wine-prefix initialisation
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
# STEP 5 — Build launch parameters and start the server
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
