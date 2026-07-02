#!/usr/bin/env bash
# =============================================================================
# ASA Dedicated Server — Manual Update Script
#
# Run against a running container to force an immediate SteamCMD update
# without restarting the server:
#
#   docker exec asa-server /opt/asa-scripts/update.sh
#
# NOTE: For a clean update with server restart, use:
#   docker compose restart
# (AUTO_UPDATE=true will trigger SteamCMD on the next startup)
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[UPDATE]${NC} $*"; }
die()  { echo -e "${RED}[FATAL]${NC} $*" >&2; exit 1; }

SERVER_DIR="${SERVER_DIR:-/ark/server}"
ASA_APP_ID="2430930"

info "Starting SteamCMD update for ASA Dedicated Server (AppID ${ASA_APP_ID})..."
info "Server directory: ${SERVER_DIR}"

/opt/steamcmd/steamcmd.sh \
    +@sSteamCmdForcePlatformType windows \
    +@sSteamCmdForcePlatformBitness 64 \
    +login anonymous \
    +force_install_dir "${SERVER_DIR}" \
    +app_update "${ASA_APP_ID}" validate \
    +quit \
|| die "SteamCMD update failed."

info "Update complete. Restart the container to load the new server version:"
info "  docker compose restart"
