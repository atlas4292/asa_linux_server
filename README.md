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

### Advanced Config (ini files)

Game and server settings can be tuned via ini files inside the volume:

```
ark_server/ShooterGame/Saved/Config/WindowsServer/
├── GameUserSettings.ini
└── Game.ini
```

---

## How It Works

| Component | Why |
|-----------|-----|
| **SteamCMD** `+@sSteamCmdForcePlatformType windows` | Downloads the Windows-only ASA depot on a Linux host |
| **Proton-GE** | Wine fork with UE5/DX12 patches (DXVK, vkd3d-proton, esync/fsync) |
| **Xvfb** | Wine needs a display socket to initialise internally; Xvfb provides a tiny in-memory virtual screen (no GPU, no physical display) |
| **`-nullrhi -nosound -nographics`** | Tells UE5 to skip all rendering, audio, and graphics subsystems — server is pure game logic |

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
