FROM ubuntu:22.04

# ── Build arguments ───────────────────────────────────────────────────────────
# Override PROTON_VERSION to pin a specific GE-Proton release.
# Browse releases: https://github.com/GloriousEggroll/proton-ge-custom/releases
ARG PROTON_VERSION=GE-Proton9-20
ARG PUID=1000
ARG PGID=1000
ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="ASA Dedicated Server (Linux/Proton)"
LABEL org.opencontainers.image.description="ARK: Survival Ascended dedicated server running headlessly via Proton-GE on Linux"

# ── 32-bit architecture (SteamCMD + Wine 32-bit stubs) ───────────────────────
RUN dpkg --add-architecture i386

# ── System dependencies ───────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        # TLS / download tools
        ca-certificates \
        curl \
        wget \
        # Archive utilities
        tar \
        xz-utils \
        # 32/64-bit C runtime (SteamCMD requirement)
        lib32gcc-s1 \
        lib32stdc++6 \
        # Audio stubs — prevents Wine crashing on no-sound hosts
        libasound2 \
        libasound2:i386 \
        # Font libraries — needed by Wine subsystem internals
        libfreetype6 \
        libfreetype6:i386 \
        libfontconfig1 \
        libfontconfig1:i386 \
        # Vulkan stubs — prevents hard crash on headless/non-GPU hosts
        libvulkan1 \
        libvulkan1:i386 \
        # NSS/NSPR — TLS for Steam network calls
        libnss3 \
        libnspr4 \
        # Python 3 — required to execute the Proton launcher script
        python3 \
        # Utilities
        procps \
    && rm -rf /var/lib/apt/lists/*

# ── SteamCMD ──────────────────────────────────────────────────────────────────
RUN mkdir -p /opt/steamcmd && \
    curl -sSL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
        | tar -xzf - -C /opt/steamcmd && \
    ln -s /opt/steamcmd/steamcmd.sh /usr/local/bin/steamcmd

# ── Proton-GE ─────────────────────────────────────────────────────────────────
# GloriousEggroll's Proton fork ships patched Wine builds with superior UE5
# compatibility and performance (esync/fsync, DXVK, vkd3d-proton, etc.)
RUN mkdir -p /opt/proton && \
    curl -sSL \
      "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_VERSION}/${PROTON_VERSION}.tar.gz" \
      | tar -xzf - -C /opt/proton && \
    echo "${PROTON_VERSION}" > /opt/proton/.version

ENV PROTON_VERSION=${PROTON_VERSION}
ENV PROTON_HOME=/opt/proton/${PROTON_VERSION}

# ── Non-root user ─────────────────────────────────────────────────────────────
RUN groupadd -g "${PGID}" steam 2>/dev/null || true && \
    useradd -m -u "${PUID}" -g steam -s /bin/bash steam

# ── Server directory layout ───────────────────────────────────────────────────
# /ark/server       — ASA binaries, config, and saves (bind-mounted volume)
# /ark/proton-prefix — Wine prefix created at first run (persisted in volume)
RUN mkdir -p /ark/server /ark/proton-prefix && \
    chown -R steam:steam /ark /opt/steamcmd

# ── Scripts ───────────────────────────────────────────────────────────────────
COPY --chown=steam:steam scripts/ /opt/asa-scripts/
RUN chmod +x /opt/asa-scripts/*.sh

# ── Runtime user ─────────────────────────────────────────────────────────────
USER steam
WORKDIR /ark

# ── Exposed ports ─────────────────────────────────────────────────────────────
# 7777/udp  — Game port (clients connect here)
# 27015/udp — Steam server-browser query port
# 27020/tcp — RCON remote console (optional)
EXPOSE 7777/udp
EXPOSE 27015/udp
EXPOSE 27020/tcp

VOLUME ["/ark/server", "/ark/proton-prefix"]

ENTRYPOINT ["/opt/asa-scripts/start.sh"]
