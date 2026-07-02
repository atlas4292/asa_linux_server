# ASA Dedicated Server — Linux via Proton-GE

ARK: Survival Ascended dedicated server is Windows-only on Steam. This setup runs it on Linux using **Proton-GE** (Wine-based compatibility layer) inside Docker.

---

## Quick Start

```bash
# 1. Edit .env — change ADMIN_PASSWORD at minimum
# 2. Build (downloads Proton-GE ~300 MB)
docker compose build
# 3. Start — first run downloads ~30-40 GB of server files
docker compose up -d
# 4. Tail logs
docker compose logs -f
```

---

## Ports

| Port       | Protocol | Purpose              |
|------------|----------|----------------------|
| 7777       | UDP      | Game (client connect)|
| 27015      | UDP      | Steam server browser |
| 27020      | TCP      | RCON remote console  |

To run multiple instances on the same host, increment each port by ≥2 per instance and update `.env`.

---

## Configuration

All options live in `.env`. Key ones:

| Variable          | Default           | Notes                                      |
|-------------------|-------------------|--------------------------------------------|
| `MAP`             | `TheIsland_WP`    | Append `_WP` to all map names              |
| `SESSION_NAME`    | `My ASA Server`   | Shown in server browser                    |
| `ADMIN_PASSWORD`  | `changeme_now`    | **Change before first run**                |
| `SERVER_PASSWORD` | *(blank)*         | Leave blank for a public server            |
| `MAX_PLAYERS`     | `70`              |                                            |
| `AUTO_UPDATE`     | `true`            | Set `false` to skip SteamCMD on each start |
| `PROTON_VERSION`  | `GE-Proton9-20`   | Rebuild image after changing               |
| `DISABLE_BATTLEYE`| `true`            | BattlEye does not work under Wine — keep `true` |

### Available Maps

`TheIsland_WP` · `ScorchedEarth_WP` · `Aberration_WP` · `TheCenter_WP` · `Extinction_WP` · `Genesis_WP` · `Genesis2_WP`

### Game Settings (`game.env`)

Multipliers, server rules, difficulty, and other in-game settings are controlled via `game.env`. The container writes `GameUserSettings.ini` and `Game.ini` from these values on every startup — edit the file and `docker compose restart` to apply changes.

Key groups in `game.env`: XP & Leveling · Gathering · Taming & Breeding · Player/Dino modifiers · Server Rules · Difficulty · Loot Quality · Message of the Day

> **Note:** Because ini files are regenerated on every start, manual edits inside the volume will be overwritten. `game.env` is the single source of truth.

---

## How It Works

| Component | Why |
|-----------|-----|
| **SteamCMD** `+@sSteamCmdForcePlatformType windows` | Downloads the Windows-only ASA depot on a Linux host |
| **Proton-GE** | Wine fork with UE5/DX12 patches (DXVK, vkd3d-proton, esync/fsync) |
| **Wine null display driver** | Wine 6+ activates a built-in null display driver when `DISPLAY` is unset — no Xvfb or physical screen needed. `SDL_VIDEODRIVER=dummy` covers SDL-based Wine components. |
| **`-nullrhi -nosound -nographics`** | Tells UE5 to skip all rendering, audio, and graphics subsystems — server is pure game logic |

> **Fallback:** if a future Proton-GE version regresses on the null driver and the server exits with X11 errors, install `xvfb` in the Dockerfile and add `Xvfb :99 -screen 0 320x240x8 -nolisten tcp & export DISPLAY=:99` at the top of `scripts/start.sh`.

---

## Updating the Server

SteamCMD runs automatically on every start when `AUTO_UPDATE=true`. To force an update on a running container without restarting:

```bash
docker exec asa-server /opt/asa-scripts/update.sh
```

To update Proton-GE, change `PROTON_VERSION` in `.env` and rebuild:

```bash
docker compose build --no-cache && docker compose up -d
```

---

## Volumes

| Volume             | Contents                              |
|--------------------|---------------------------------------|
| `ark_server`       | Server binaries, world saves, configs |
| `ark_proton_prefix`| Wine prefix (created once, reused)    |

> The `ark_server` volume will grow to ~30-40 GB after the initial download.
