#!/usr/bin/env bash
# ==============================================================================
# shairport-sync-manager.sh
# AirPlay 1 Classic Receiver — On-Demand Only, PipeWire-Safe
# Version: 4.3
# Status: 🟢 GOLD (Production-Ready)
# Last updated: 2026-06-20
#
# Compiles shairport-sync from source and installs an on-demand AirPlay 1
# Classic receiver with embedded GTK3 Python GUI called AirPlay Solace.
# Never runs as a boot daemon — critical for PipeWire HDMI/aux stability.
#
# Shairport-sync Source:  https://github.com/mikebrady/shairport-sync
# Build guide:            https://github.com/mikebrady/shairport-sync/blob/master/BUILD.md
# PipeWire integration:   https://github.com/mikebrady/shairport-sync/blob/master/ADVANCED%20TOPICS/PulseAudioAndPipeWire.md
#
# Usage: bash shairport-sync-manager.sh   (do NOT run as root)
#
# Disclaimer:
#   This script is provided as-is for Raspberry Pi users. Not affiliated with
#   the shairport-sync project, Raspberry Pi Ltd, or Apple Inc. Use at your own
#   risk. Always keep a system backup before installing audio software.
# ==============================================================================
# AI REFERENCE NOTES
# ──────────────────────────────────────────────────────────────────────────────
#
# ⚠️  ARCHITECTURE: ON-DEMAND ONLY — NEVER AS A BOOT DAEMON
#
#   Running shairport-sync as a boot service broke PipeWire HDMI/aux enumeration
#   on Pi OS Trixie (HDMI audio disappeared every boot). Service unit has no
#   [Install] section by design — it cannot be accidentally enabled. loginctl
#   enable-linger is permanently forbidden. Do not reverse this.
#
# AUTOSTART AT LOGIN (v4.3) — XDG AUTOSTART, NOT SYSTEMD ENABLE
#   Uses ~/.config/autostart/ (fires after desktop + PipeWire are up, same as
#   ncspot/cava). NOT `systemctl --user enable` — that races PipeWire at boot.
#   Toggle: Gtk.CheckButton in AirPlay Solace. Writes/removes the .desktop file
#   immediately. Checkbox re-reads from disk on every _refresh() poll.
#   Wrapper (airplay-solace-autostart): self-heals (deletes own .desktop if
#   binary missing), waits 15s for PipeWire, refuses if linger on, logs to
#   autostart.log. Uninstall removes both files regardless of toggle state.
#   Refs: forums.raspberrypi.com/viewtopic.php?t=379393
#         forums.raspberrypi.com/viewtopic.php?t=381921
#
# KEY PATHS (all ~/.local / ~/.config — zero system footprint):
#   ~/.local/bin/shairport-sync                              # compiled binary
#   ~/.local/bin/airplay-solace                              # GTK3 GUI script
#   ~/.local/bin/airplay-solace-autostart                    # login wrapper (v4.3)
#   ~/.config/shairport-sync/shairport-sync.conf             # audio config
#   ~/.config/systemd/user/shairport-sync.service            # unit (never enabled)
#   ~/.config/autostart/airplay-solace-autostart.desktop     # autostart toggle
#   ~/.local/share/applications/airplay-solace.desktop
#   ~/.local/share/icons/hicolor/scalable/apps/airplay-solace.svg
#   ~/.local/share/man/man7/shairport-sync.7
#   ~/.local/share/shairport-sync-manager/autostart.log      # login wrapper log
#
# FOUR PIPEWIRE SAFETY RULES (baked in — non-negotiable):
#   1. No loginctl enable-linger — starts before PipeWire, breaks HDMI enum
#      Ref: github.com/mikebrady/shairport-sync/issues/1970
#   2. --sysconfdir=/etc at compile — baked into binary; wrong path = silence
#      Ref: github.com/mikebrady/shairport-sync/blob/master/BUILD.md
#   3. After=sound.target in service unit — After=pipewire.service fails on
#      Trixie/labwc (unit names absent from user session graph)
#   4. No --with-systemd-startup — triggers system-user creation in make install.
#      Skip make install entirely; copy binary manually (Trixie bug #2133).
#      Ref: github.com/mikebrady/shairport-sync/issues/2133
#
# BUILD FLAGS:
#   Active:  --sysconfdir=/etc --without-configfiles --with-pipewire --with-alsa
#            --with-soxr --with-avahi --with-ssl=openssl --with-ffmpeg
#   Omitted: --with-systemd-startup (make install only, we skip it)
#            --with-airplay-2 (requires NQPTP root daemon, breaks PipeWire BT)
#            --with-dbus-interface / --with-mpris-interface (write to /usr/share)
#
# CAVA INTEGRATION:
#   Detection: ~/.local/share/applications/cava-solace.desktop
#   Launcher:  ~/.local/bin/cava-solace
#   If cava-manager.sh ever changes these paths, update _is_cava_installed()
#   and _launch_cava() in the PYEOF heredoc to match.
#
# CRASH RECOVERY:
#   Marker-file pattern — if install/update dies mid-way, next run auto-restores
#   from backup silently. User re-runs operation from menu.
#
# KEY DECISION RULES (never violate):
#   1. Never run as boot daemon — breaks PipeWire HDMI enumeration (proven)
#   2. Never enable systemd service — no [Install] section by design
#   3. Never use make install — manually copy binary (Trixie bug #2133)
#   4. Always --sysconfdir=/etc — binary won't load config otherwise
#   5. Always After=sound.target — not pipewire.service/wireplumber.service
#   6. Always check linger before Start — check_linger_safety() guards every Start
#   7. Never loginctl enable-linger — breaks PipeWire audio enumeration
#   8. Cava paths are fixed — update here if cava-manager.sh ever changes them
#   9. Autostart toggle (v4.3) is XDG ~/.config/autostart only — never systemctl
#      enable. Uninstall must always remove wrapper + desktop file regardless of
#      toggle state.
#
# VERSION HISTORY:
#   v4.3 (Jun 2026) — Opt-in "start at login" via XDG autostart (NOT systemd
#                     enable). Gtk.CheckButton in AirPlay Solace writes/removes
#                     ~/.config/autostart/airplay-solace-autostart.desktop
#                     immediately. Wrapper airplay-solace-autostart: self-heals
#                     if binary missing, waits 15s for PipeWire, refuses if
#                     linger on, logs every run to autostart.log. Checkbox syncs
#                     from disk every _refresh() poll. Uninstall removes both
#                     files unconditionally. Autostart status line added to
#                     draw_menu. Untested on hardware — watch window height vs.
#                     Cava Solace side-by-side (window is resizable, should be ok).
#   v4.2 (Jun 2026) — Removed audio preview visualiser (VisArea, cairo helpers,
#                     colour constants). Layout: VERTICAL main_vbox, two-column
#                     top_row, full-width bottom_row. Window 480x260, min 340x250.
#   v3.4-v4.1       — GOLD baseline (on-demand, PipeWire-safe, AirPlay Solace,
#                     Cava integration, Trixie #2133 workaround), then menu
#                     renumbering, safety fixes, window sizing for 800x480,
#                     Pango ellipsizing. All resolved and present in current build.
#
# REFERENCES:
#   Source     : https://github.com/mikebrady/shairport-sync
#   Build      : https://github.com/mikebrady/shairport-sync/blob/master/BUILD.md
#   PipeWire   : https://github.com/mikebrady/shairport-sync/blob/master/ADVANCED%20TOPICS/PulseAudioAndPipeWire.md
#   Trixie bug : https://github.com/mikebrady/shairport-sync/issues/2133
#   Linger     : https://github.com/mikebrady/shairport-sync/issues/1970
#   Pi forums  : https://forums.raspberrypi.com/
#
# ==============================================================================

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ──────────────────────────────────────────────────────────────────────────────
REPO_URL="https://github.com/mikebrady/shairport-sync.git"
BUILD_DIR="${TMPDIR:-/tmp}/shairport-sync-build"
SCRIPT_VERSION="4.3"

INSTALL_PREFIX="${HOME}/.local"
BIN_DIR="${INSTALL_PREFIX}/bin"
CONFIG_DIR="${HOME}/.config/shairport-sync"
CONFIG_FILE="${CONFIG_DIR}/shairport-sync.conf"
VERSION_FILE="${CONFIG_DIR}/.installed_major_version"

# User systemd service unit — written but NEVER enabled.
# Used only for on-demand  systemctl --user start/stop.
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SYSTEMD_USER_DIR}/shairport-sync.service"

# ── GUI paths (AirPlay Solace GTK3 touch UI) ──────────────────────────────────
GUI_SCRIPT="${HOME}/.local/bin/airplay-solace"
GUI_ICON_DIR="${HOME}/.local/share/icons/hicolor/scalable/apps"
GUI_ICON="${GUI_ICON_DIR}/airplay-solace.svg"
GUI_DESKTOP_DIR="${HOME}/.local/share/applications"
GUI_DESKTOP="${GUI_DESKTOP_DIR}/airplay-solace.desktop"
MANAGER_SCRIPT="$(realpath "$0")"

# ── Autostart-at-login paths (v4.3) — XDG autostart, NOT systemd enable ──────
# AUTOSTART_LAUNCHER is the Exec= target: a small self-healing wrapper, not
# the main manager script, so the trigger never depends on where this .sh
# file happens to live. AUTOSTART_DESKTOP is the toggle itself — its mere
# existence in ~/.config/autostart is what turns autostart on; deleting it
# turns it off. Both are removed unconditionally on uninstall regardless of
# toggle state. See AI REFERENCE NOTES "AUTOSTART AT LOGIN" block above.
AUTOSTART_DIR="${HOME}/.config/autostart"
AUTOSTART_DESKTOP="${AUTOSTART_DIR}/airplay-solace-autostart.desktop"
AUTOSTART_LAUNCHER="${BIN_DIR}/airplay-solace-autostart"
AUTOSTART_LOG_DIR="${HOME}/.local/share/shairport-sync-manager"
AUTOSTART_LOG="${AUTOSTART_LOG_DIR}/autostart.log"

# ──────────────────────────────────────────────────────────────────────────────
# COLOURS & LOGGING
# ──────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() {
    echo ""
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}  $*${NC}"
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"
}

press_enter() { echo ""; read -rp "  Press [Enter] to continue…"; }

confirm() {
    local prompt="${1:-Are you sure?} [y/N] "
    read -r -p "$prompt" response
    [[ "$response" =~ ^[Yy]$ ]]
}

# ──────────────────────────────────────────────────────────────────────────────
# SANITY CHECKS
# ──────────────────────────────────────────────────────────────────────────────
refuse_root() {
    if [[ $EUID -eq 0 ]]; then
        echo -e "\n${RED}[ERROR]${NC} Do not run this script as root."
        echo -e "        Run it as your normal user:  ${BOLD}bash $0${NC}\n"
        exit 1
    fi
}

ensure_local_bin_on_path() {
    if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
        log_warn "${BIN_DIR} is not on your PATH — adding to ~/.bashrc"
        {
            echo ""
            echo "# Added by shairport-sync-manager"
            echo 'export PATH="${HOME}/.local/bin:${PATH}"'
        } >> "${HOME}/.bashrc"
        export PATH="${BIN_DIR}:${PATH}"
        log_ok "PATH updated. Re-open your terminal after install for the change to stick."
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# PIPEWIRE SAFETY CHECKS
# These checks run before start to give you clear, actionable diagnostics.
# They are informational only — they never modify PipeWire.
# ──────────────────────────────────────────────────────────────────────────────
check_pipewire_running() {
    # PipeWire must be active in your user session for the pipewire backend to
    # connect. On Pi OS Trixie with a full desktop this is always true once
    # you are logged in — this check is a safety net for edge cases.
    # Ref: https://github.com/mikebrady/shairport-sync/blob/master/ADVANCED%20TOPICS/PulseAudioAndPipeWire.md
    if systemctl --user is-active --quiet pipewire 2>/dev/null; then
        log_ok "PipeWire is running in your user session."
        return 0
    else
        log_warn "PipeWire does not appear to be running in your user session."
        log_warn "This is unexpected on Pi OS Trixie with the desktop loaded."
        log_warn "Check with:  systemctl --user status pipewire"
        log_warn "Audio may not work until PipeWire is running."
        return 1
    fi
}

check_linger_safety() {
    # Linger must be OFF. If it is ON from a previous install of this script
    # or any other tool, starting shairport-sync would go into a boot-time
    # lingering session that cannot reach your desktop PipeWire — causing
    # the "no sound" symptom AND potentially breaking HDMI/aux enumeration.
    # This check catches any leftover linger state and refuses to proceed
    # until it is disabled.
    # Ref: https://github.com/mikebrady/shairport-sync/issues/1970
    if loginctl show-user "$USER" 2>/dev/null | grep -q "Linger=yes"; then
        echo ""
        echo -e "${RED}${BOLD}  ╔══════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}${BOLD}  ║   ⛔ LINGER IS ENABLED — REFUSING TO START       ║${NC}"
        echo -e "${RED}${BOLD}  ╚══════════════════════════════════════════════════╝${NC}"
        echo ""
        log_error "loginctl linger is ON for user: $USER"
        echo ""
        echo "  Linger causes user services to start at boot before your"
        echo "  desktop session exists. This WILL cause shairport-sync to"
        echo "  start in a session that cannot reach PipeWire — resulting in:"
        echo "    • No audio output from AirPlay"
        echo "    • Possible HDMI / aux audio breakage on next boot"
        echo ""
        echo "  To fix this, run:"
        echo -e "    ${BOLD}sudo loginctl disable-linger $USER${NC}"
        echo ""
        echo "  Then verify it is off:"
        echo -e "    ${BOLD}loginctl show-user $USER | grep Linger${NC}"
        echo "  Expected:  Linger=no"
        echo ""
        echo "  After disabling linger, return here and try again."
        echo ""
        press_enter
        return 1
    fi
    log_ok "Linger is OFF — safe to proceed."
    return 0
}

check_service_not_enabled() {
    # The service must never be enabled. Enabled means it would auto-start
    # at login, which recreates the same race condition as linger.
    # This catches any state where the service was enabled externally.
    if systemctl --user is-enabled --quiet shairport-sync 2>/dev/null; then
        echo ""
        log_warn "shairport-sync user service is currently ENABLED (auto-start at login)."
        log_warn "This is not safe with your PipeWire setup."
        log_warn "Disabling it now…"
        systemctl --user disable shairport-sync 2>/dev/null || true
        log_ok "Service disabled — will no longer auto-start at login."
        echo ""
    fi
    return 0
}

check_port_5000() {
    if ss -tlnp 2>/dev/null | grep -q ':5000 '; then
        log_warn "Port 5000 is already in use on this device."
        log_warn "Another AirPlay receiver may be running."
        log_warn "Check with:  ss -tlnp | grep 5000"
        return 1
    fi
    return 0
}

# ──────────────────────────────────────────────────────────────────────────────
# VERSION & STATUS HELPERS
# Ref: https://github.com/mikebrady/shairport-sync/releases
# ──────────────────────────────────────────────────────────────────────────────
get_installed_version() {
    if [[ -x "${BIN_DIR}/shairport-sync" ]]; then
        "${BIN_DIR}/shairport-sync" --version 2>&1 \
            | grep -oP '\d+\.\d+[\.\d]*' | head -1 || echo "unknown"
    elif command -v shairport-sync &>/dev/null; then
        shairport-sync --version 2>&1 \
            | grep -oP '\d+\.\d+[\.\d]*' | head -1 || echo "unknown"
    else
        echo "not installed"
    fi
}

get_latest_version() {
    curl -fsSL --connect-timeout 8 \
        "https://api.github.com/repos/mikebrady/shairport-sync/releases/latest" \
        2>/dev/null \
        | grep -oP '"tag_name":\s*"\K[^"]+' | head -1 || echo "unknown"
}

get_service_status() {
    if systemctl --user is-active --quiet shairport-sync 2>/dev/null; then
        echo "running"
    elif [[ -f "${SERVICE_FILE}" ]]; then
        # Show "stopped" — never show "enabled" because we never enable it
        echo "stopped"
    else
        echo "not configured"
    fi
}

get_autostart_status() {
    # Reflects the toggle in AirPlay Solace — purely the presence of the
    # desktop file, not any systemd state. See AUTOSTART_DESKTOP above.
    [[ -f "${AUTOSTART_DESKTOP}" ]] && echo "on" || echo "off"
}

save_installed_major_version() {
    local ver="$1"
    local major
    major=$(echo "$ver" | grep -oP '^\d+' || echo "0")
    mkdir -p "${CONFIG_DIR}"
    echo "$major" > "${VERSION_FILE}"
}

get_saved_major_version() {
    [[ -f "${VERSION_FILE}" ]] && cat "${VERSION_FILE}" || echo "0"
}

major_of() {
    echo "$1" | grep -oP '^\d+' || echo "0"
}

check_major_version_bump() {
    local new_ver="$1"
    local saved_major new_major
    saved_major=$(get_saved_major_version)
    new_major=$(major_of "$new_ver")

    if [[ "$saved_major" != "0" && "$new_major" =~ ^[0-9]+$ && "$saved_major" =~ ^[0-9]+$ && "$new_major" -gt "$saved_major" ]]; then
        echo ""
        echo -e "${YELLOW}${BOLD}  ╔══════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}${BOLD}  ║   ⚡ Major version change detected               ║${NC}"
        echo -e "${YELLOW}${BOLD}  ╚══════════════════════════════════════════════════╝${NC}"
        echo ""
        log_warn "Installed major version : ${saved_major}.x"
        log_warn "Incoming major version  : ${new_major}.x"
        echo ""
        echo "  Major releases often include breaking changes to config"
        echo "  file keys, section names, and command-line flags."
        echo "  The v5.0 release, for example, renamed:"
        echo '    output_backend = "pw"  →  "pipewire"'
        echo "    pw { }                →  pipewire { }"
        echo "    --config              →  --configfile"
        echo ""
        echo "  Before continuing, review the upstream changelog:"
        echo "  https://github.com/mikebrady/shairport-sync/releases"
        echo "  https://github.com/mikebrady/shairport-sync/blob/master/CONFIGURATIONFILECHANGES5.md"
        echo ""
        confirm "  Understood — proceed with the major version upgrade?" \
            || { log_info "Upgrade cancelled. Nothing changed."; press_enter; return 1; }
        echo ""
        log_info "Proceeding — the script will auto-migrate any known config"
        log_info "changes it recognises. Review your config after install"
        log_info "using menu option 5 (Edit config) to catch anything unexpected."
        echo ""
    fi
    return 0
}

# ──────────────────────────────────────────────────────────────────────────────
# BUILD DEPENDENCIES
#
# Classic AirPlay 1 dependency list from upstream BUILD.md:
#   https://github.com/mikebrady/shairport-sync/blob/master/BUILD.md
#
# Trixie note: systemd-dev is required on Debian 13 / Pi OS Trixie for
#   sd-daemon.h. Upstream BUILD.md explicitly calls this out.
#   WARNING from upstream: do NOT install systemd-dev on a backported system
#   as it can damage the system. This script is written for native Trixie only.
#   Ref: https://github.com/mikebrady/shairport-sync/blob/master/BUILD.md
#
# libpipewire-0.3-dev: confirmed available in Debian Trixie.
#   Ref: https://packages.debian.org/trixie/libpipewire-0.3-dev
#
# libglib2.0-dev: needed for GLib/GIO used by shairport-sync internals.
#
# Dependencies are NOT removed on uninstall — many other Pi OS packages
# share them and removing them risks breaking the system.
# ──────────────────────────────────────────────────────────────────────────────
install_build_deps() {
    log_section "Installing Build Dependencies (Classic AirPlay 1)"
    log_info "Ref: https://github.com/mikebrady/shairport-sync/blob/master/BUILD.md"

    local packages=(
        build-essential git autoconf automake libtool
        libpopt-dev libconfig-dev libasound2-dev
        avahi-daemon libavahi-client-dev libssl-dev libsoxr-dev
        libavutil-dev libavcodec-dev libavformat-dev
        libglib2.0-dev
        libpipewire-0.3-dev
        wget curl
    )

    log_info "Updating package lists…"
    sudo apt-get update -qq

    log_info "Installing packages…"
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -y --no-install-recommends \
        "${packages[@]}"

    # systemd-dev deliberately NOT installed.
    #   It was previously thought to be required on Trixie for sd-daemon.h.
    #   Source audit of configure.ac and Makefile.am confirms: systemd-dev is
    #   only needed when --with-systemd-startup is used, so pkg-config can find
    #   systemdsystemunitdir for the make install target. We drop --with-systemd-startup
    #   and skip make install entirely, so systemd-dev is not needed and not installed.
    #   Ref: https://github.com/mikebrady/shairport-sync/issues/2133

    log_ok "Build dependencies installed."
    log_info "Note: dependencies are kept on the system after uninstall."
    log_info "They are shared with other Pi OS packages — removing them risks system breakage."
}

# ──────────────────────────────────────────────────────────────────────────────
# BUILD & INSTALL
#
# Configure flags explained:
#   --with-pipewire        Native PipeWire backend — routes to default sink
#   --with-alsa            ALSA also compiled in (PipeWire exposes ALSA device)
#   --with-soxr            High-quality resampling (Pi 4 has the power for it)
#   --with-avahi           mDNS/Bonjour — Pi appears by hostname on the network
#   --with-ssl=openssl     Required for AirPlay encryption
#   --with-ffmpeg          Audio transcoding (44.1k↔48k, format conversion)
#   --with-systemd-startup Trixie/Debian 13 requires this flag name
#                          (renamed from --with-systemd in v5)
#
# Deliberately NOT included:
#   --with-airplay-2       Requires NQPTP system daemon — incompatible with
#                          PipeWire Bluetooth, boot-time service required
#   --with-dbus-interface  Would write dbus policy to /usr/share/dbus-1/system.d/
#   --with-mpris-interface Would write dbus policy to /usr/share/dbus-1/system.d/
#   Both of the above write outside the user home directory — omitted entirely.
#
# Trixie make install bug (issue #2133, confirmed January 2026 on Pi OS Trixie
# with kernel 6.12):
#   `make install` fails at install-systemd-local because the Makefile tries to
#   create a system user and write service files to /etc/systemd/system/.
#   This requires root and fails on Trixie's permission model.
#   Fix: copy the binary directly to ~/.local/bin — safe, correct, complete.
#   Ref: https://github.com/mikebrady/shairport-sync/issues/2133
# ──────────────────────────────────────────────────────────────────────────────
build_shairport_sync() {
    log_section "Building Shairport Sync (AirPlay 1 Classic — userland)"
    log_info "Source  : ${REPO_URL}"
    log_info "Binary  : ${BIN_DIR}/shairport-sync"

    rm -rf "${BUILD_DIR}"
    git clone "${REPO_URL}" "${BUILD_DIR}"
    pushd "${BUILD_DIR}" > /dev/null

    log_info "Running autoreconf…  (1–2 min on Pi 4 @ 2200 MHz)"
    autoreconf -fi

    echo ""
    echo -e "  ${CYAN}Configure flags:${NC}"
    echo "    --sysconfdir=/etc      Upstream default — binary finds config correctly"
    echo "    --without-configfiles  Prevents make install writing /etc/shairport-sync.conf"
    echo "    --with-pipewire        Native PipeWire backend"
    echo "    --with-alsa            ALSA (PipeWire exposes ALSA pseudo-device)"
    echo "    --with-soxr            High-quality resampling"
    echo "    --with-avahi           mDNS/Bonjour — visible on your LAN"
    echo "    --with-ssl=openssl     AirPlay encryption"
    echo "    --with-ffmpeg          Audio transcoding"
    echo ""
    echo -e "  ${YELLOW}Omitted flags (PipeWire / system safety):${NC}"
    echo "    --with-systemd-startup Only controls make install system service write"
    echo "                           — pointless since we skip make install, and"
    echo "                             causes the Trixie make install failure (#2133)"
    echo "    --with-airplay-2       Requires NQPTP system daemon — omitted"
    echo "    --with-dbus-interface  Writes to system dbus dirs — omitted"
    echo "    --with-mpris-interface Writes to system dbus dirs — omitted"
    echo ""

    log_info "Configuring…"
    # --sysconfdir=/etc
    #   Baked into the binary at compile time as the fallback config search path.
    #   Upstream BUILD.md uses /etc. We always pass --configfile= explicitly in
    #   ExecStart so the runtime path is unambiguous, but sysconfdir must still
    #   be /etc or the binary internal defaults will be wrong.
    #   Using ~/.config/... caused silent fallback to ALSA with no audio output.
    #   Ref: https://github.com/mikebrady/shairport-sync/blob/master/BUILD.md
    #
    # --without-configfiles
    #   configure.ac defaults with_configfiles=yes which causes make install to
    #   write /etc/shairport-sync.conf. We write our own config to ~/.config/ and
    #   skip make install entirely. This flag makes that intent explicit and safe.
    #   Ref: Makefile.am INSTALL_CONFIG_FILES / CONFIG_FILE_INSTALL_TARGET
    #
    # --with-systemd-startup deliberately OMITTED.
    #   This flag ONLY sets INSTALL_SYSTEMD_STARTUP in Makefile.am which tells
    #   make install to write /etc/systemd/system/shairport-sync.service and create
    #   a shairport-sync system user. We skip make install so this flag is pointless.
    #   It is also the flag that triggers the Trixie make install failure (#2133).
    #   Dropping it also means systemd-dev is not needed as a build dependency.
    #   Confirmed: flag never appears in SOURCES or AM_CFLAGS in Makefile.am.
    #   The compiled binary is identical with or without this flag.
    #   Ref: https://github.com/mikebrady/shairport-sync/issues/2133
    ./configure \
        --sysconfdir=/etc \
        --without-configfiles \
        --with-pipewire \
        --with-alsa \
        --with-soxr \
        --with-avahi \
        --with-ssl=openssl \
        --with-ffmpeg

    log_info "Compiling…  (7–10 min on Pi 4 @ stock, faster when overclocked)"
    make -j"$(nproc)"

    # TRIXIE FIX: skip `make install` — it fails on Pi OS Trixie.
    # The Makefile tries to create a system user and write to /etc/systemd/system/.
    # We do NOT want system service files anyway — this is on-demand only.
    # Binary is copied directly to ~/.local/bin — safe and complete.
    # Ref: https://github.com/mikebrady/shairport-sync/issues/2133
    log_info "Installing binary to ${BIN_DIR}  (Trixie-safe — skipping make install)…"
    mkdir -p "${BIN_DIR}"
    cp -f shairport-sync "${BIN_DIR}/shairport-sync"
    chmod 755 "${BIN_DIR}/shairport-sync"

    # Man page — install to user share if present
    if [[ -f "man/shairport-sync.7" ]]; then
        mkdir -p "${INSTALL_PREFIX}/share/man/man7"
        cp -f man/shairport-sync.7 "${INSTALL_PREFIX}/share/man/man7/"
        log_ok "Man page installed: ${INSTALL_PREFIX}/share/man/man7/shairport-sync.7"
    fi

    popd > /dev/null
    rm -rf "${BUILD_DIR}"
    log_ok "Binary installed: ${BIN_DIR}/shairport-sync"

    # Save major version for future update bump detection
    local installed_ver
    installed_ver=$(get_installed_version)
    save_installed_major_version "$installed_ver"
    log_info "Installed major version saved: $(get_saved_major_version).x"

    # Verify PipeWire appears in the version string.
    # If missing, the build silently fell back to ALSA-only — PipeWire routing
    # (and thus HDMI/aux/Bluetooth auto-routing) will not work.
    local ver_string
    ver_string=$("${BIN_DIR}/shairport-sync" --version 2>&1 || true)
    if echo "$ver_string" | grep -qi "pipewire"; then
        log_ok "PipeWire support confirmed in version string."
        log_info "Version: $ver_string"
    else
        log_warn "PipeWire NOT found in version string!"
        log_warn "Version: $ver_string"
        log_warn "Build may have fallen back to ALSA-only."
        log_warn "Ensure libpipewire-0.3-dev was installed cleanly, then re-run option 1."
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# USER CONFIG
#
# v5 change: output_backend = "pipewire"  (was "pw" in v4 and earlier)
# The build flag --with-pipewire is unchanged — only the runtime string changed.
# Ref: https://github.com/mikebrady/shairport-sync/blob/master/CONFIGURATIONFILECHANGES5.md
#
# Output routing:
#   output_backend = "pipewire" sends audio to PipeWire's default sink.
#   Change your system default audio output in the taskbar volume menu to
#   switch between HDMI, aux (3.5mm), and Bluetooth — shairport-sync follows.
#   No config file changes needed to switch outputs.
# ──────────────────────────────────────────────────────────────────────────────
write_user_config() {
    log_section "User Configuration"
    mkdir -p "${CONFIG_DIR}"

    if [[ -f "${CONFIG_FILE}" ]]; then
        log_info "Config already exists: ${CONFIG_FILE}"
        # MIGRATION: v5 renamed output_backend from "pw" to "pipewire".
        if grep -q 'output_backend = "pw"' "${CONFIG_FILE}"; then
            log_warn "Migrating config: output_backend \"pw\" → \"pipewire\" (v5 rename)"
            sed -i 's/output_backend = "pw"/output_backend = "pipewire"/' "${CONFIG_FILE}"
            log_ok "Config migrated."
        else
            log_info "Config is up to date — leaving it in place."
        fi
        return
    fi

    log_info "Writing default config → ${CONFIG_FILE}"
    cat > "${CONFIG_FILE}" << 'EOF'
// Shairport Sync — AirPlay 1 (Classic) config  (v5 compatible)
// Full reference: https://github.com/mikebrady/shairport-sync/blob/master/shairport-sync.conf.sample
//
// OUTPUT ROUTING:
//   output_backend = "pipewire" sends audio to your PipeWire default sink.
//   To switch between HDMI, aux (3.5mm jack), or Bluetooth — just change your
//   system default audio output in the taskbar volume/sound menu BEFORE
//   starting AirPlay. No changes to this file are needed.
//
//   To hardcode a specific output (e.g. always use HDMI even if BT is default):
//   1. Use menu option 4 (Show audio sinks) to find the exact sink name
//   2. Uncomment the sink line in the pipewire {} section below
//
// PORT NOTE:
//   shairport-sync uses port 5000. Only one AirPlay receiver can use it at a
//   time. If something else is using port 5000, start will fail — stop the
//   other process first.
//
// ON-DEMAND ONLY:
//   This install is manually started/stopped from the manager script.
//   It does NOT start automatically at boot or login. This is intentional
//   to protect Pi OS PipeWire/HDMI audio device enumeration.

general = {
    name = "%H";                      // Receiver name shown on devices (%H = hostname)
    output_backend = "pipewire";      // PipeWire native — v5 value (was "pw" in v4)
};

// PipeWire-specific settings
// Ref: https://github.com/mikebrady/shairport-sync/blob/master/shairport-sync.conf.sample
pipewire = {
    // To hardcode a specific output sink (optional):
    //   1. Run menu option 4 to list available sink names
    //   2. Find your device (e.g. "alsa_output.platform-fef05700.hdmi.hdmi-stereo"
    //      for HDMI, or "bluez_output.XX_XX_XX_XX_XX_XX.1" for Bluetooth)
    //   3. Uncomment and paste the name below:
    // sink = "alsa_output.platform-fef05700.hdmi.hdmi-stereo";
    //
    // Default (commented out): follows your system default audio output.
    // This is the easiest option — just set your preferred output in the
    // taskbar before hitting Start.
};

sessioncontrol = {
    allow_session_interruption = "yes";  // Let another AirPlay sender take over
    session_timeout = 120;
};
EOF
    log_ok "Config written: ${CONFIG_FILE}"
}

# ──────────────────────────────────────────────────────────────────────────────
# USER SYSTEMD SERVICE UNIT
#
# This writes a service unit to ~/.config/systemd/user/shairport-sync.service.
# It is used ONLY for  systemctl --user start/stop  — on-demand control.
#
# CRITICAL: this script NEVER runs:
#   systemctl --user enable shairport-sync   ← would auto-start at login
#   loginctl enable-linger                   ← would auto-start at boot
# Either of those would cause shairport-sync to start before PipeWire has
# fully enumerated audio devices, breaking HDMI and aux output.
#
# The [Install] / WantedBy section is intentionally omitted from the unit file
# so that `systemctl --user enable` is not even possible without editing the
# file manually — an extra safety layer.
#
# Ref: https://github.com/mikebrady/shairport-sync/blob/master/ADVANCED%20TOPICS/PulseAudioAndPipeWire.md
# ──────────────────────────────────────────────────────────────────────────────
install_user_service() {
    log_section "Installing User Service Unit (on-demand only — never auto-start)"

    mkdir -p "${SYSTEMD_USER_DIR}"

    # MIGRATION: if an old service file exists using --config (v4 and earlier),
    # fix it to --configfile (v5 rename) before rewriting.
    if [[ -f "${SERVICE_FILE}" ]]; then
        if grep -q -- "--config=" "${SERVICE_FILE}" && \
           ! grep -q -- "--configfile=" "${SERVICE_FILE}"; then
            log_warn "Migrating service unit: --config → --configfile (v5 rename)"
            sed -i 's|--config=|--configfile=|g' "${SERVICE_FILE}"
            log_ok "Service unit migrated."
        fi
    fi

    # Write the service unit.
    # NO [Install] / WantedBy section — prevents accidental enable.
    #
    # After=sound.target matches the official upstream user service file exactly:
    #   https://raw.githubusercontent.com/mikebrady/shairport-sync/master/scripts/shairport-sync.user.service
    # Using After=pipewire.service pipewire-pulse.service wireplumber.service
    # caused silent failures — those units may not appear in the user session
    # graph by those exact names, causing systemctl --user start to stall or
    # start shairport-sync before PipeWire was ready to accept connections.
    # sound.target is the correct, reliable, upstream-tested dependency.
    cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=Shairport Sync - AirPlay Audio Receiver (on-demand)
Documentation=https://github.com/mikebrady/shairport-sync
After=sound.target

[Service]
ExecStart=${BIN_DIR}/shairport-sync --configfile=${CONFIG_FILE} --log-to-syslog
Restart=on-failure
RestartSec=5

# [Install] section intentionally omitted.
# This service is on-demand only — started manually via this manager script.
# DO NOT add WantedBy=default.target — that would cause auto-start at login
# and break PipeWire HDMI/aux audio enumeration on Pi OS Trixie.
# loginctl enable-linger must also remain OFF for the same reason.
EOF

    systemctl --user daemon-reload
    log_ok "Service unit installed: ${SERVICE_FILE}"
    log_ok "Service is NOT enabled — starts only when you choose Start from this menu."
}

# ──────────────────────────────────────────────────────────────────────────────
# AVAHI
# Avahi provides mDNS/Bonjour so your Pi appears by hostname on the network.
# It is a system daemon managed by the OS — this script only checks/starts it,
# never modifies its config.
# Ref: https://github.com/mikebrady/shairport-sync/blob/master/BUILD.md
# ──────────────────────────────────────────────────────────────────────────────
ensure_avahi() {
    log_section "Checking Avahi (mDNS/Bonjour)"
    if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
        log_ok "Avahi daemon is running — Pi will be visible on the network."
    else
        log_warn "Avahi not running — starting it now (requires sudo)…"
        sudo systemctl enable avahi-daemon 2>/dev/null || true
        sudo systemctl start  avahi-daemon 2>/dev/null || true
        if systemctl is-active --quiet avahi-daemon 2>/dev/null; then
            log_ok "Avahi started."
        else
            log_warn "Avahi could not be started. AirPlay discovery may not work."
            log_warn "Check with:  systemctl status avahi-daemon"
        fi
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# WIFI POWER SAVE
# Disables WiFi power management for the current session to prevent audio
# dropouts. This is a temporary session setting — it resets on reboot.
# Ref: https://github.com/mikebrady/shairport-sync/blob/master/BUILD.md
# ──────────────────────────────────────────────────────────────────────────────
disable_wifi_power_save() {
    log_section "WiFi Power Management"

    local iface
    iface=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | head -1 || true)

    if [[ -z "$iface" ]]; then
        log_info "No WiFi interface detected — skipping (wired connection assumed)."
        return
    fi

    if sudo iw dev "$iface" set power_save off 2>/dev/null; then
        log_ok "WiFi power save disabled on ${iface} (current session only)."
        log_info "This resets on reboot — that is intentional and safe."
        log_info "To persist across reboots, add to /etc/rc.local:"
        log_info "  iw dev ${iface} set power_save off"
    else
        log_warn "Could not disable WiFi power save on ${iface}."
        log_warn "You may experience audio dropouts over WiFi."
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# INSTALL HEALTH CHECK
# Checks all critical pieces of the install for signs of a partial or broken
# state — e.g. power failure mid-compile, failed binary copy, stale config.
# Returns: "ok" | "partial" | "none"
# ──────────────────────────────────────────────────────────────────────────────
get_install_health() {
    if [[ ! -f "${BIN_DIR}/shairport-sync" ]]; then
        echo "none"; return
    fi

    local issues=0

    # Binary must be executable
    [[ ! -x "${BIN_DIR}/shairport-sync" ]] && (( issues++ ))

    # Binary must report a valid version string
    local ver_string
    ver_string=$("${BIN_DIR}/shairport-sync" --version 2>&1 || true)
    [[ -z "$ver_string" ]] && (( issues++ ))

    # PipeWire or pw must appear in version string
    # shairport-sync --version lists backends differently across versions:
    #   v4.x: "pw"   v5.x: "pipewire"  — accept either
    echo "$ver_string" | grep -qiE "pipewire|[[:space:]]pw[[:space:],]|[[:space:]]pw$" || (( issues++ ))

    # Config file must exist
    [[ ! -f "${CONFIG_FILE}" ]] && (( issues++ ))

    # Config must use v5 backend name
    if [[ -f "${CONFIG_FILE}" ]]; then
        grep -q 'output_backend = "pw"' "${CONFIG_FILE}" && (( issues++ ))
    fi

    # Service unit must exist
    [[ ! -f "${SERVICE_FILE}" ]] && (( issues++ ))

    # Service unit must use --configfile (v5) not --config (v4)
    if [[ -f "${SERVICE_FILE}" ]]; then
        grep -q -- "--config=" "${SERVICE_FILE}" && \
        ! grep -q -- "--configfile=" "${SERVICE_FILE}" && (( issues++ ))
    fi

    # Note: enabled/disabled state is NOT a health check item.
    # We handle unexpected enable at start time in check_service_not_enabled().
    # Including it here caused false "partial" after the auto-disable ran.

    [[ $issues -eq 0 ]] && echo "ok" || echo "partial"
}

# ──────────────────────────────────────────────────────────────────────────────
# MENU ACTIONS
# ──────────────────────────────────────────────────────────────────────────────

do_start_service() {
    log_section "Starting Shairport Sync (AirPlay receiver)"

    # Safety checks before starting — never start if linger is on
    check_linger_safety    || { press_enter; return; }
    check_service_not_enabled
    check_pipewire_running || log_warn "Attempting start anyway — check PipeWire if no sound."
    check_port_5000        || log_warn "Attempting start anyway — port 5000 may already be in use."

    echo ""
    systemctl --user start shairport-sync
    sleep 2

    if systemctl --user is-active --quiet shairport-sync; then
        log_ok "shairport-sync is running."
        echo ""
        echo -e "  ${GREEN}${BOLD}AirPlay receiver is active.${NC}"
        echo ""
        echo -e "  Your Pi will appear as: ${BOLD}$(hostname)${NC}"
        echo ""
        echo "  To use AirPlay:"
        echo "    • iPhone/iPad: open Control Centre → tap AirPlay icon"
        echo "    • Mac: click sound icon in menu bar → AirPlay"
        echo "    • Android: use an AirPlay sender app (e.g. AirPlay & DLNA)"
        echo "    • Select: $(hostname)"
        echo ""
        echo "  To switch audio output (HDMI / aux / Bluetooth):"
        echo "    Stop AirPlay, change your default audio output in the"
        echo "    taskbar, then Start again."
        echo ""
        echo "  If no sound: use menu option 3 (logs) to diagnose."
    else
        echo ""
        log_warn "shairport-sync did not start cleanly."
        log_warn "Use menu option 3 (Show logs) to diagnose."
        log_warn "Common causes:"
        log_warn "  • Port 5000 in use — another AirPlay receiver running"
        log_warn "  • PipeWire not ready — try again in a few seconds"
    fi

    press_enter
}

do_stop_service() {
    log_section "Stopping Shairport Sync"

    systemctl --user stop shairport-sync 2>/dev/null \
        && log_ok "shairport-sync stopped — AirPlay receiver is offline." \
        || log_warn "shairport-sync was not running."

    press_enter
}

do_show_logs() {
    log_section "Shairport Sync Logs (last 50 lines)"
    echo ""
    journalctl --user -u shairport-sync -n 50 --no-pager 2>/dev/null \
        || log_warn "No logs found — service may not have run yet."
    echo ""
    log_info "For live logs:  journalctl --user -u shairport-sync -f"
    press_enter
}

do_show_audio_sinks() {
    log_section "PipeWire Audio Sinks"

    echo ""
    echo "  Use these sink names to hardcode a specific audio output in the"
    echo "  config file (menu option 5). Normally you do not need to do this —"
    echo "  just set your preferred output in the taskbar and shairport-sync"
    echo "  will follow it automatically."
    echo ""

    if command -v pactl &>/dev/null; then
        echo -e "  ${CYAN}PipeWire sinks (pactl):${NC}"
        echo "  ────────────────────────────────────────────────────────"
        pactl list sinks short 2>/dev/null | while IFS= read -r line; do
            echo "    $line"
        done || log_warn "pactl returned no output."
        echo "  ────────────────────────────────────────────────────────"
    else
        log_warn "pactl not found. Install with:  sudo apt-get install pulseaudio-utils"
    fi

    echo ""

    if command -v pw-cli &>/dev/null; then
        echo -e "  ${CYAN}PipeWire audio sink nodes (pw-cli):${NC}"
        echo "  ────────────────────────────────────────────────────────"
        pw-cli list-objects Node 2>/dev/null \
            | grep -A2 "node.name\|media.class" \
            | grep -E "node\.name|Audio/Sink" | head -40 || true
        echo "  ────────────────────────────────────────────────────────"
    fi

    echo ""
    echo "  Common sink names on Pi OS Trixie:"
    echo "    HDMI      : alsa_output.platform-fef05700.hdmi.hdmi-stereo"
    echo "    Aux 3.5mm : alsa_output.platform-bcm2835_audio.stereo-fallback"
    echo "    Bluetooth : bluez_output.XX_XX_XX_XX_XX_XX.1  (MAC address varies)"
    echo ""
    echo "  To hardcode a sink: use menu option 5 (Edit config) and set"
    echo '    sink = "your-sink-name-here";'
    echo "  in the pipewire { } block."
    echo ""

    press_enter
}

do_edit_config() {
    log_section "Edit Config"

    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_warn "Config file not found: ${CONFIG_FILE}"
        log_warn "Install shairport-sync first (menu option 1)."
        press_enter
        return
    fi

    log_info "Opening config in nano"
    log_info "Save: Ctrl+O   Exit: Ctrl+X"
    echo ""
    sleep 1
    nano "${CONFIG_FILE}"

    echo ""
    if systemctl --user is-active --quiet shairport-sync 2>/dev/null; then
        if confirm "  shairport-sync is running — restart to apply changes?"; then
            systemctl --user restart shairport-sync
            sleep 2
            if systemctl --user is-active --quiet shairport-sync; then
                log_ok "Restarted successfully."
            else
                log_warn "Did not restart cleanly — check logs (menu option 3)."
            fi
        fi
    else
        log_info "Changes saved. Start shairport-sync (menu option 8) when ready."
    fi

    press_enter
}

# ──────────────────────────────────────────────────────────────────────────────
# INSTALL
# ──────────────────────────────────────────────────────────────────────────────
# ──────────────────────────────────────────────────────────────────────────────
# AIRPLAY SOLACE — GTK3 TOUCH GUI
# Matches Cava Solace style: dark theme, hover glows, Cairo animation,
# GLib timers, same color palette. Written as a heredoc, installed to
# ~/.local/bin/airplay-solace by do_install.
# ──────────────────────────────────────────────────────────────────────────────
write_gui_script() {
    mkdir -p "$(dirname "$GUI_SCRIPT")"

    # NOTE: heredoc uses PYEOF delimiter — single-quoted so bash does NOT
    # expand variables inside. All Python f-strings and $ signs are literal.
    cat > "$GUI_SCRIPT" << 'PYEOF'
#!/usr/bin/env python3
# =============================================================================
# airplay-solace — AirPlay Solace GTK3 GUI
# Generated by shairport-sync-manager.sh — re-run Install / Repair to update.
#
# Style matches Cava Solace: dark #111118 theme, hover glows, Cairo visualiser,
# GLib timer animations, therapeutic calm sage/sky/lavender palette.
#
# Does NOT modify PipeWire, /etc/, or any system config.
# Starts/stops shairport-sync via: systemctl --user start/stop shairport-sync
# =============================================================================
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Pango", "1.0")
from gi.repository import Gtk, Gdk, GLib, Pango
import cairo
import math
import os
import socket
import subprocess

# ── Autostart-at-login paths (v4.3) — must mirror the bash constants
# AUTOSTART_DESKTOP / AUTOSTART_LAUNCHER in shairport-sync-manager.sh.
# If those ever change there, update these two lines too.
AUTOSTART_DESKTOP  = os.path.expanduser(
    "~/.config/autostart/airplay-solace-autostart.desktop")
AUTOSTART_LAUNCHER = os.path.expanduser(
    "~/.local/bin/airplay-solace-autostart")

# ── Locate the terminal manager script ───────────────────────────────────────
def _find_manager():
    candidates = [
        os.path.expanduser("~/shairport-sync-manager.sh"),
        os.path.expanduser("~/.local/bin/shairport-sync-manager.sh"),
        "/usr/local/bin/shairport-sync-manager.sh",
    ]
    for c in candidates:
        if os.path.isfile(c):
            return c
    return None

# ── Color palette — matches Cava Solace dark theme ───────────────────────────
BG_DARK      = (0.067, 0.067, 0.094)
BG_CARD      = (0.098, 0.098, 0.133)
ACCENT_CYAN  = (0.118, 0.745, 0.820)
ACCENT_GREEN = (0.118, 0.843, 0.376)
ACCENT_AMBER = (0.980, 0.741, 0.184)
ACCENT_RED   = (0.800, 0.267, 0.267)
FG_PRIMARY   = (0.878, 0.878, 0.941)
FG_DIM       = (0.314, 0.314, 0.439)

# ── CSS — identical structure and feel to Cava Solace ────────────────────────
CSS = b"""
window {
    background-color: #111118;
}
.card {
    background-color: #191922;
    border-radius: 12px;
    padding: 8px;
}
.card2 {
    background-color: #20202a;
    border-radius: 10px;
    padding: 7px;
}
.btn-primary {
    background: #1ebdd1;
    color: #111118;
    border-radius: 10px;
    border: none;
    padding: 7px 14px;
    font-weight: bold;
    font-size: 13px;
    transition: all 120ms ease;
}
.btn-primary:hover {
    background: #38d8ef;
    box-shadow: 0 0 14px rgba(30,189,209,0.55);
}
.btn-primary:active {
    background: #0fa8bc;
}
.btn-stop {
    background: #1a1a2a;
    color: #fabf2f;
    border-radius: 10px;
    border: 1px solid #fabf2f;
    padding: 7px 14px;
    font-weight: bold;
    font-size: 13px;
    transition: all 120ms ease;
}
.btn-stop:hover {
    background: #2a2a1a;
    box-shadow: 0 0 14px rgba(250,191,47,0.45);
}
.btn-muted {
    background: #191922;
    color: #505070;
    border-radius: 10px;
    border: 1px solid #28283a;
    padding: 7px 14px;
    font-size: 12px;
    transition: all 120ms ease;
}
.btn-muted:hover {
    background: #20202e;
    color: #7070a0;
    box-shadow: 0 0 10px rgba(80,80,112,0.3);
}
.btn-close {
    background: #1a1a28;
    color: #cc4444;
    border-radius: 10px;
    border: 1px solid #441a1a;
    padding: 7px 14px;
    font-size: 12px;
    transition: all 120ms ease;
}
.btn-close:hover {
    background: #2a1a1a;
    box-shadow: 0 0 12px rgba(204,68,68,0.4);
}
.label-title {
    color: #e0e0f0;
    font-size: 15px;
    font-weight: bold;
}
.label-sub {
    color: #505070;
    font-size: 12px;
}
.label-hint {
    color: #404060;
    font-size: 11px;
}
.label-device {
    color: #1ebdd1;
    font-size: 13px;
    font-weight: bold;
}
separator {
    background-color: #28283a;
    min-height: 1px;
    margin: 6px 0;
}
"""

def _apply_css():
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(),
        provider,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )

def _sty(widget, *classes):
    ctx = widget.get_style_context()
    for c in classes:
        ctx.add_class(c)

# ── Service helpers ───────────────────────────────────────────────────────────
def _is_installed():
    p = os.path.expanduser("~/.local/bin/shairport-sync")
    return os.path.isfile(p) and os.access(p, os.X_OK)

def _is_running():
    try:
        r = subprocess.run(
            ["systemctl", "--user", "is-active", "--quiet", "shairport-sync"],
            capture_output=True
        )
        return r.returncode == 0
    except Exception:
        return False

def _start():
    subprocess.run(["systemctl", "--user", "start", "shairport-sync"],
                   capture_output=True)

def _stop():
    subprocess.run(["systemctl", "--user", "stop", "shairport-sync"],
                   capture_output=True)

# ── Autostart-at-login helpers (v4.3) ─────────────────────────────────────────
# The toggle is just the presence of AUTOSTART_DESKTOP — writing it turns
# autostart on, deleting it turns it off. The wrapper it points to
# (AUTOSTART_LAUNCHER, written by write_autostart_launcher in the bash
# script) is self-healing: if shairport-sync ever goes missing it deletes
# this same desktop file on its own. That's why _refresh() re-reads this
# from disk every poll instead of trusting the checkbox's last-set state.
def _is_autostart_enabled():
    return os.path.isfile(AUTOSTART_DESKTOP)

def _set_autostart(enabled):
    if enabled:
        os.makedirs(os.path.dirname(AUTOSTART_DESKTOP), exist_ok=True)
        with open(AUTOSTART_DESKTOP, "w") as f:
            f.write(
                "[Desktop Entry]\n"
                "Type=Application\n"
                "Name=AirPlay Auto-Start\n"
                "Comment=Starts the on-demand shairport-sync AirPlay receiver "
                "at login (PipeWire-safe -- untick in AirPlay Solace to disable)\n"
                f"Exec={AUTOSTART_LAUNCHER}\n"
                "Terminal=false\n"
                "Hidden=false\n"
                "X-GNOME-Autostart-enabled=true\n"
            )
        os.chmod(AUTOSTART_DESKTOP, 0o644)
    else:
        try:
            os.remove(AUTOSTART_DESKTOP)
        except FileNotFoundError:
            pass

def _open_manager():
    m = _find_manager()
    if not m:
        return False
    for cmd in [
        ["foot", "--", "bash", m],
        ["xfce4-terminal", f"--command=bash {m}"],
        ["lxterminal", "-e", f"bash {m}"],
        ["x-terminal-emulator", "-e", f"bash {m}"],
    ]:
        try:
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
        except FileNotFoundError:
            continue
    return False

def _is_cava_installed():
    """Detect Cava Solace by its desktop shortcut — same check as the start menu."""
    return os.path.isfile(os.path.expanduser(
        "~/.local/share/applications/cava-solace.desktop"))

def _launch_cava():
    """Launch Cava Solace using the same script path cava-manager installs to."""
    script = os.path.expanduser("~/.local/bin/cava-solace")
    try:
        subprocess.Popen(
            ["python3", script],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        return True
    except Exception:
        return False

# ── Pulse dot ─────────────────────────────────────────────────────────────────
class PulseDot(Gtk.DrawingArea):
    def __init__(self):
        super().__init__()
        self.set_size_request(18, 18)
        self._state = "inactive"
        self._alpha = 1.0
        self._dir   = -1
        self._tid   = None
        self.connect("draw", self._draw)

    def set_state(self, s):
        self._state = s
        if s == "running" and self._tid is None:
            self._tid = GLib.timeout_add(50, self._pulse)
        elif s != "running" and self._tid:
            GLib.source_remove(self._tid)
            self._tid   = None
            self._alpha = 1.0
        self.queue_draw()

    def _pulse(self):
        self._alpha += self._dir * 0.04
        if self._alpha <= 0.35:
            self._dir = 1
        elif self._alpha >= 1.0:
            self._dir = -1
        self.queue_draw()
        return True

    def _draw(self, w, cr):
        a = self.get_allocation()
        cx, cy, r = a.width/2, a.height/2, 7
        col = (ACCENT_GREEN if self._state == "running"
               else ACCENT_AMBER if self._state == "stopped"
               else FG_DIM)
        if self._state == "running":
            pat = cairo.RadialGradient(cx, cy, 0, cx, cy, r*2.2)
            pat.add_color_stop_rgba(0.0, *col, self._alpha*0.6)
            pat.add_color_stop_rgba(1.0, *col, 0.0)
            cr.set_source(pat)
            cr.arc(cx, cy, r*2.2, 0, 2*math.pi)
            cr.fill()
        a_val = self._alpha if self._state == "running" else 1.0
        cr.set_source_rgba(*col, a_val)
        cr.arc(cx, cy, r, 0, 2*math.pi)
        cr.fill()

# ── Main window ───────────────────────────────────────────────────────────────
class AirplaySolace(Gtk.Window):
    def __init__(self):
        super().__init__(title="AirPlay Solace")
        self.set_default_size(480, 260)
        self.set_size_request(340, 250)
        self.set_resizable(True)
        self.set_border_width(0)
        self.connect("delete-event", self._on_x)
        _apply_css()

        main_vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        main_vbox.set_margin_start(10); main_vbox.set_margin_end(10)
        main_vbox.set_margin_top(10);   main_vbox.set_margin_bottom(10)
        self.add(main_vbox)

        # ═══════════════════════════════════════════════════════════════
        # TOP ROW — column 1 (header/status/hints), column 2 (transport)
        # ═══════════════════════════════════════════════════════════════
        top_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        top_row.set_halign(Gtk.Align.FILL)
        main_vbox.pack_start(top_row, False, False, 0)

        # ── Column 1 — header, status, connection hints ──────────────────
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        top_row.pack_start(left, True, True, 0)

        # Header
        hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        _sty(hdr, "card")
        self._dot = PulseDot()
        hdr.pack_start(self._dot, False, False, 4)
        col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        t = Gtk.Label(label="AirPlay Solace")
        _sty(t, "label-title"); t.set_halign(Gtk.Align.START)
        t.set_ellipsize(Pango.EllipsizeMode.END)
        s = Gtk.Label(label="Pi 4  ·  Trixie  ·  AirPlay 1 Receiver")
        _sty(s, "label-sub"); s.set_halign(Gtk.Align.START)
        s.set_ellipsize(Pango.EllipsizeMode.END)
        col.pack_start(t, False, False, 0)
        col.pack_start(s, False, False, 0)
        hdr.pack_start(col, True, True, 0)
        left.pack_start(hdr, False, False, 0)

        # Status
        sc = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        _sty(sc, "card")
        self._slbl = Gtk.Label(); self._slbl.set_halign(Gtk.Align.START)
        self._slbl.set_ellipsize(Pango.EllipsizeMode.END)
        self._dlbl = Gtk.Label(); self._dlbl.set_halign(Gtk.Align.START)
        self._dlbl.set_ellipsize(Pango.EllipsizeMode.END)
        _sty(self._dlbl, "label-device")
        sc.pack_start(self._slbl, False, False, 0)
        sc.pack_start(self._dlbl, False, False, 0)
        left.pack_start(sc, False, False, 0)

        # Connection hints
        hn = socket.gethostname()
        hc = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        _sty(hc, "card2")
        for line in [
            f"Connect to:  {hn}",
            "iPhone/iPad  →  Control Centre  →  AirPlay icon",
            "Android      →  AirPlay sender app (e.g. AirMusic)",
            "Mac          →  \U0001f50a menu bar  →  AirPlay",
        ]:
            lb = Gtk.Label(label=line)
            _sty(lb, "label-hint"); lb.set_halign(Gtk.Align.START)
            lb.set_ellipsize(Pango.EllipsizeMode.END)
            hc.pack_start(lb, False, False, 0)
        self._hc = hc
        left.pack_start(hc, False, False, 0)

        # Autostart-at-login toggle (v4.3) — off by default. Toggling writes
        # or removes AUTOSTART_DESKTOP immediately; no separate Apply step.
        ac = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        _sty(ac, "card2")
        self._cb_autostart = Gtk.CheckButton(
            label="Start AirPlay automatically at login")
        cb_lbl = self._cb_autostart.get_child()
        if cb_lbl is not None:
            _sty(cb_lbl, "label-sub")
            cb_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        self._cb_autostart.set_tooltip_text(
            "Uses a login-time shortcut in ~/.config/autostart -- not a "
            "systemd boot service, so it can't race PipeWire at startup. "
            "Off by default; removed automatically on uninstall.")
        self._cb_autostart.connect("toggled", self._on_autostart_toggle)
        ac.pack_start(self._cb_autostart, True, True, 0)
        left.pack_start(ac, False, False, 0)

        # ── Column 2 — transport controls ─────────────────────────────────
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        right.set_size_request(150, -1)
        right.set_valign(Gtk.Align.START)
        top_row.pack_start(right, False, False, 0)

        self._bstart = Gtk.Button(label="\u25b6  Start AirPlay")
        _sty(self._bstart, "btn-primary")
        self._bstart.get_child().set_ellipsize(Pango.EllipsizeMode.END)
        self._bstart.connect("clicked", self._on_start)
        right.pack_start(self._bstart, False, False, 0)

        self._bstop = Gtk.Button(label="\u25a0  Stop AirPlay")
        _sty(self._bstop, "btn-stop")
        self._bstop.get_child().set_ellipsize(Pango.EllipsizeMode.END)
        self._bstop.connect("clicked", self._on_stop)
        right.pack_start(self._bstop, False, False, 0)

        # Cava Solace launch — only visible when cava-solace is detected
        self._btn_cava = Gtk.Button(label="\u266b  Launch Cava Solace")
        _sty(self._btn_cava, "btn-primary")
        self._btn_cava.get_child().set_ellipsize(Pango.EllipsizeMode.END)
        self._btn_cava.connect("clicked", self._on_cava)
        self._btn_cava.set_tooltip_text(
            "Open Cava Solace alongside AirPlay — both run independently")
        right.pack_start(self._btn_cava, False, False, 0)
        self._cava_row = self._btn_cava

        # ═══════════════════════════════════════════════════════════════
        # BOTTOM ROW — Manager / Background / Stop & Close, full width
        # ═══════════════════════════════════════════════════════════════
        bottom_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        bottom_row.set_halign(Gtk.Align.FILL)
        main_vbox.pack_start(bottom_row, False, False, 0)

        bm = Gtk.Button(label="\u2699  Manager")
        _sty(bm, "btn-muted")
        bm.get_child().set_ellipsize(Pango.EllipsizeMode.END)
        bm.connect("clicked", self._on_manager)
        bm.set_tooltip_text("Open terminal manager for install, uninstall, config, updates")
        bottom_row.pack_start(bm, True, True, 0)

        bb = Gtk.Button(label="\u229e  Background")
        _sty(bb, "btn-muted")
        bb.get_child().set_ellipsize(Pango.EllipsizeMode.END)
        bb.connect("clicked", self._on_bg)
        bb.set_tooltip_text("Hide window — AirPlay keeps running")
        bottom_row.pack_start(bb, True, True, 0)

        bc = Gtk.Button(label="\u2715  Stop & Close")
        _sty(bc, "btn-close")
        bc.get_child().set_ellipsize(Pango.EllipsizeMode.END)
        bc.connect("clicked", self._on_stop_close)
        bc.set_tooltip_text("Stop AirPlay and close this window")
        bottom_row.pack_start(bc, True, True, 0)

        self._mlbl = Gtk.Label(label="")
        _sty(self._mlbl, "label-hint"); self._mlbl.set_halign(Gtk.Align.CENTER)
        self._mlbl.set_ellipsize(Pango.EllipsizeMode.END)
        main_vbox.pack_start(self._mlbl, False, False, 0)

        self._ptid = GLib.timeout_add_seconds(2, self._poll)
        self._refresh()

    def _refresh(self):
        inst    = _is_installed()
        running = _is_running() if inst else False
        hn      = socket.gethostname()

        if not inst:
            self._slbl.set_markup(
                '<span color="#cc4444" font_weight="bold">Not installed</span>'
                '  <span color="#404060">— open Manager to install</span>')
            self._dlbl.set_text("")
            self._dot.set_state("inactive")
            self._bstart.set_sensitive(False)
            self._bstop.set_sensitive(False)
            self._hc.set_visible(False)
        elif running:
            self._slbl.set_markup(
                '<span color="#1ed760" font_weight="bold">\u25cf  AirPlay receiver is active</span>')
            self._dlbl.set_markup(
                f'<span color="#1ebdd1">Connect to: <b>{hn}</b></span>')
            self._dot.set_state("running")
            self._bstart.set_sensitive(False)
            self._bstop.set_sensitive(True)
            self._hc.set_visible(True)
        else:
            self._slbl.set_markup(
                '<span color="#fabf2f" font_weight="bold">\u25cb  AirPlay receiver is stopped</span>')
            self._dlbl.set_markup(
                '<span color="#505070">Press Start to begin receiving AirPlay audio</span>')
            self._dot.set_state("stopped")
            self._bstart.set_sensitive(True)
            self._bstop.set_sensitive(False)
            self._hc.set_visible(False)
        # Show Cava launch row only when cava-solace desktop shortcut is found
        cava_detected = _is_cava_installed()
        self._cava_row.set_visible(cava_detected)

        # Autostart checkbox: re-read from disk every refresh (not just on
        # click) so it stays accurate if the wrapper self-heals it away
        # (e.g. binary was deleted by hand) or it was toggled elsewhere.
        self._cb_autostart.set_sensitive(inst)
        self._cb_autostart.handler_block_by_func(self._on_autostart_toggle)
        self._cb_autostart.set_active(_is_autostart_enabled())
        self._cb_autostart.handler_unblock_by_func(self._on_autostart_toggle)

        return False

    def _poll(self):
        self._refresh()
        return True

    def _msg(self, txt):
        self._mlbl.set_text(txt)

    def _on_autostart_toggle(self, btn):
        enabled = btn.get_active()
        _set_autostart(enabled)
        self._msg("Auto-start at login enabled." if enabled
                   else "Auto-start at login disabled.")
        GLib.timeout_add_seconds(3, lambda: (self._msg(""), False))

    def _on_start(self, *_):
        self._msg("Starting AirPlay receiver…")
        _start()
        GLib.timeout_add(1500, self._refresh)
        GLib.timeout_add(3500, lambda: (self._msg(""), False))

    def _on_stop(self, *_):
        self._msg("Stopping AirPlay receiver…")
        _stop()
        GLib.timeout_add(1500, self._refresh)
        GLib.timeout_add(3500, lambda: (self._msg(""), False))

    def _on_bg(self, *_):
        self.hide()

    def _on_cava(self, *_):
        if not _launch_cava():
            self._msg("Cava Solace not found — check ~/.local/bin/cava-solace")
            GLib.timeout_add_seconds(4, lambda: (self._msg(""), False))

    def _on_manager(self, *_):
        if not _open_manager():
            self._msg("Manager not found — check ~/shairport-sync-manager.sh")
            GLib.timeout_add_seconds(4, lambda: (self._msg(""), False))

    def _on_stop_close(self, *_):
        _stop()
        self._quit()

    def _on_x(self, *_):
        _stop()
        self._quit()
        return True

    def _quit(self):
        if self._ptid:
            GLib.source_remove(self._ptid)
        Gtk.main_quit()


if __name__ == "__main__":
    win = AirplaySolace()
    win.show_all()
    Gtk.main()
PYEOF
    chmod +x "$GUI_SCRIPT"
    log_ok "AirPlay Solace GUI written: ${GUI_SCRIPT}"
}

write_gui_icon() {
    mkdir -p "${GUI_ICON_DIR}"
    cat > "${GUI_ICON}" << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <rect width="100" height="100" rx="14" fill="#111118"/>
  <circle cx="50" cy="42" r="22" fill="none" stroke="#1ebdd1" stroke-width="4"/>
  <circle cx="50" cy="42" r="12" fill="none" stroke="#1ebdd1" stroke-width="3" opacity="0.6"/>
  <circle cx="50" cy="42" r="4"  fill="#1ebdd1"/>
  <path d="M28 68 Q50 58 72 68" stroke="#1ed760" stroke-width="3" fill="none" stroke-linecap="round"/>
  <path d="M20 78 Q50 64 80 78" stroke="#1ed760" stroke-width="2.5" fill="none" stroke-linecap="round" opacity="0.5"/>
</svg>
SVGEOF
    touch "${GUI_ICON_DIR}"
    gtk-update-icon-cache -f -t "${HOME}/.local/share/icons/hicolor" 2>/dev/null || true
    log_ok "GUI icon written: ${GUI_ICON}"
}

write_gui_desktop() {
    mkdir -p "${GUI_DESKTOP_DIR}"
    cat > "${GUI_DESKTOP}" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=AirPlay Solace
GenericName=AirPlay Receiver
Comment=AirPlay 1 receiver for Raspberry Pi -- PipeWire safe on-demand
Exec=python3 ${GUI_SCRIPT}
Icon=airplay-solace
Terminal=false
Categories=Audio;AudioVideo;Music;
Keywords=airplay;music;audio;receiver;shairport;
StartupNotify=false
EOF
    chmod 644 "${GUI_DESKTOP}"
    update-desktop-database "${GUI_DESKTOP_DIR}" 2>/dev/null || true
    log_ok "Desktop shortcut written: ${GUI_DESKTOP}"
}

# ──────────────────────────────────────────────────────────────────────────────
# AUTOSTART LAUNCHER (v4.3)
#
# Writes the wrapper script that ~/.config/autostart/airplay-solace-
# autostart.desktop points its Exec= line at. This is intentionally NOT the
# main manager script — a dedicated, stable path under ~/.local/bin means
# the autostart trigger never breaks if this .sh file is moved or renamed.
#
# This function only writes/refreshes the wrapper itself. It does NOT create
# the ~/.config/autostart/*.desktop toggle file — that's written/removed by
# the checkbox in AirPlay Solace (immediate, no Apply step) so autostart
# stays opt-in and off by default after a fresh install, per the "no
# auto-start unless it's a desktop shortcut you put there yourself" rule.
#
# Safety behaviour baked into the wrapper itself (not just at write-time):
#   1. Self-heals: if the shairport-sync binary is missing — e.g. you
#      deleted it by hand instead of using option 2 (Uninstall) — the
#      wrapper deletes its own autostart desktop file and exits quietly.
#      No dangling shortcut survives a manual deletion.
#   2. Refuses to start if loginctl linger is somehow ON (mirrors
#      check_linger_safety in the main manager).
#   3. Polls `systemctl --user is-active pipewire` for up to 15s before
#      starting — autostart can fire slightly before audio is fully up.
#   4. Logs every run with a timestamp for troubleshooting.
# ──────────────────────────────────────────────────────────────────────────────
write_autostart_launcher() {
    mkdir -p "$(dirname "${AUTOSTART_LAUNCHER}")"
    cat > "${AUTOSTART_LAUNCHER}" << EOF
#!/usr/bin/env bash
# airplay-solace-autostart — generated by shairport-sync-manager.sh v${SCRIPT_VERSION}
# Login-time launcher for the on-demand shairport-sync receiver.
# Triggered ONLY by ~/.config/autostart/airplay-solace-autostart.desktop
# (XDG autostart spec) — this is NEVER wired to systemctl --user enable.
set -uo pipefail

BIN="${BIN_DIR}/shairport-sync"
DESKTOP_FILE="${AUTOSTART_DESKTOP}"
LOG_DIR="${AUTOSTART_LOG_DIR}"
LOG_FILE="${AUTOSTART_LOG}"
mkdir -p "\$LOG_DIR"

_log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*" >> "\$LOG_FILE"; }

# Self-heal: binary gone means the app was removed without going through
# option 2 (Uninstall). Clean up our own autostart entry and stop.
if [[ ! -x "\$BIN" ]]; then
    _log "shairport-sync binary not found at \$BIN — removing autostart entry (self-cleanup)."
    rm -f "\$DESKTOP_FILE"
    exit 0
fi

# Refuse on linger — mirrors check_linger_safety() in the main manager.
if loginctl show-user "\$USER" 2>/dev/null | grep -q "Linger=yes"; then
    _log "Linger is ON for \$USER — refusing to autostart. Run: sudo loginctl disable-linger \$USER"
    exit 0
fi

# Wait briefly for PipeWire — autostart can fire before audio is ready.
for i in \$(seq 1 15); do
    systemctl --user is-active --quiet pipewire 2>/dev/null && break
    sleep 1
done

systemctl --user start shairport-sync 2>>"\$LOG_FILE"
if systemctl --user is-active --quiet shairport-sync 2>/dev/null; then
    _log "AirPlay receiver started successfully at login."
else
    _log "AirPlay receiver failed to start at login — check: systemctl --user status shairport-sync"
fi
EOF
    chmod +x "${AUTOSTART_LAUNCHER}"
    log_ok "Autostart launcher written: ${AUTOSTART_LAUNCHER}"
}

install_gui_deps() {
    log_info "Checking GTK3 Python dependencies…"
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -y --no-install-recommends \
        python3-gi \
        python3-gi-cairo \
        gir1.2-gtk-3.0
    log_ok "GTK3 Python dependencies ready."
}

uninstall_gui() {
    local removed=0
    for f in "${GUI_SCRIPT}" "${GUI_ICON}" "${GUI_DESKTOP}" \
             "${AUTOSTART_LAUNCHER}" "${AUTOSTART_DESKTOP}"; do
        if [[ -f "$f" ]]; then
            rm -f "$f"
            log_ok "Removed: $f"
            (( removed++ )) || true
        fi
    done
    # Diagnostics log dir — not user-editable config, safe to remove always.
    if [[ -d "${AUTOSTART_LOG_DIR}" ]]; then
        rm -rf "${AUTOSTART_LOG_DIR}"
        log_ok "Removed: ${AUTOSTART_LOG_DIR}"
    fi
    [[ $removed -eq 0 ]] && log_info "GUI files not found — already removed."
    update-desktop-database "${GUI_DESKTOP_DIR}" 2>/dev/null || true
    gtk-update-icon-cache -f -t "${HOME}/.local/share/icons/hicolor" 2>/dev/null || true
}


launch_gui() {
    if [[ ! -f "${GUI_SCRIPT}" ]]; then
        log_warn "AirPlay Solace not installed — run option 1 (Install / Repair) first."
        press_enter
        return
    fi
    log_info "Launching AirPlay Solace…"
    python3 "${GUI_SCRIPT}" &
    disown
    sleep 1
    log_ok "AirPlay Solace launched."
    press_enter
}


do_install() {
    log_section "Shairport Sync – Full Install"
    log_info "AirPlay 1 Classic · PipeWire backend · On-demand only"
    log_info "Build guide: https://github.com/mikebrady/shairport-sync/blob/master/BUILD.md"
    echo ""
    echo -e "  ${YELLOW}${BOLD}PipeWire safety:${NC}"
    echo "  This install will NOT modify /etc/pipewire/, /etc/wireplumber/,"
    echo "  /etc/dbus-1/, or any system audio config. All files go to ~/.local"
    echo "  and ~/.config only. The service will NOT auto-start at boot or login."
    echo ""
    confirm "  Proceed with install?" || { log_info "Cancelled."; press_enter; return; }

    ensure_local_bin_on_path
    install_build_deps
    build_shairport_sync
    write_user_config
    ensure_avahi
    disable_wifi_power_save
    install_user_service
    install_gui_deps
    write_gui_script
    write_gui_icon
    write_gui_desktop
    write_autostart_launcher

    local installed_ver
    installed_ver=$(get_installed_version)

    echo ""
    echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  ✔  Shairport Sync ${installed_ver} installed!${NC}"
    echo ""
    echo -e "  Binary  : ${BIN_DIR}/shairport-sync"
    echo -e "  Config  : ${CONFIG_FILE}"
    echo -e "  Service : ${SERVICE_FILE}  (NOT enabled — on-demand only)"
    echo ""
    echo -e "  ${BOLD}To use AirPlay:${NC}"
    echo "    1. Choose your audio output in the taskbar (HDMI / aux / BT)"
    echo "    2. Open this manager and press 8 (Start)"
    echo "    3. Open Spotify / Apple Music on your phone"
    echo "    4. Tap the AirPlay icon and select: $(hostname)"
    echo "    5. Press 9 (Stop) when done"
    echo ""
    echo -e "  ${BOLD}Start at login (optional, off by default):${NC}"
    echo "    Open AirPlay Solace (option 7) and tick the checkbox under the"
    echo "    connection hints. Uses ~/.config/autostart — not a systemd boot"
    echo "    service — so it never races PipeWire at startup."
    echo ""
    echo -e "  ${BOLD}PipeWire audio is untouched.${NC}"
    echo "  HDMI, aux, and Bluetooth audio will continue to work normally."
    echo ""
    echo -e "  ${BOLD}Full uninstall:${NC} menu option 2 removes everything."
    echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════${NC}"

    press_enter
}

# ──────────────────────────────────────────────────────────────────────────────
# CHECK FOR UPDATES
# Only recompiles when a newer version is available on GitHub.
# Config is never touched. If already on latest, just says so and exits.
# ──────────────────────────────────────────────────────────────────────────────
do_update() {
    log_section "Shairport Sync – Check for Updates"

    local installed_ver
    installed_ver=$(get_installed_version)

    if [[ "$installed_ver" == "not installed" ]]; then
        log_warn "Not installed — use option 1 (Install / Repair) first."
        press_enter; return
    fi

    log_info "Currently installed : $installed_ver"
    log_info "Fetching latest version from GitHub…"
    local latest
    latest=$(get_latest_version)

    if [[ "$latest" == "unknown" ]]; then
        log_warn "Could not reach GitHub — check your internet connection."
        log_info "Currently installed: $installed_ver"
        confirm "  Update anyway using latest available source?"             || { press_enter; return; }
    elif [[ "$installed_ver" == "$latest" ]]; then
        echo ""
        echo -e "${GREEN}${BOLD}  ✔  You are already on the latest version: ${installed_ver}${NC}"
        echo ""
        echo "  Nothing to do — shairport-sync is up to date."
        echo ""
        confirm "  Recompile anyway (e.g. to apply a config change or repair)?"             || { press_enter; return; }
    else
        echo ""
        echo -e "  ${YELLOW}${BOLD}Update available!${NC}"
        echo -e "  Installed : ${installed_ver}"
        echo -e "  Latest    : ${latest}"
        echo ""
        check_major_version_bump "$latest" || return
        confirm "  Download and install ${latest} now?"             || { log_info "Cancelled."; press_enter; return; }
    fi

    # Stop if running before rebuilding
    if systemctl --user is-active --quiet shairport-sync 2>/dev/null; then
        log_info "Stopping AirPlay before update…"
        systemctl --user stop shairport-sync 2>/dev/null || true
    fi

    ensure_local_bin_on_path
    install_build_deps
    build_shairport_sync
    ensure_avahi
    install_user_service
    install_gui_deps
    write_gui_script
    write_gui_icon
    write_gui_desktop
    write_autostart_launcher

    local new_ver
    new_ver=$(get_installed_version)

    echo ""
    echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  ✔  Update complete!  ${installed_ver} → ${new_ver}${NC}"
    echo -e "  Config  : ${CONFIG_FILE}  (untouched)"
    echo -e "  Service : still NOT enabled — on-demand only"
    echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════${NC}"

    press_enter
}

# ──────────────────────────────────────────────────────────────────────────────
# UNINSTALL
#
# Removes everything this script ever created.
# Files removed:
#   ~/.local/bin/shairport-sync
#   ~/.local/share/man/man7/shairport-sync.7
#   ~/.config/systemd/user/shairport-sync.service
#   ~/.config/shairport-sync/  (optional — you may want to keep config)
#
# Files NOT touched:
#   /etc/pipewire/        — never modified, never removed
#   /etc/wireplumber/     — never modified, never removed
#   /etc/dbus-1/          — never modified, never removed
#   /etc/systemd/system/  — never modified, never removed
#   apt packages          — build deps kept (shared with other system packages)
# ──────────────────────────────────────────────────────────────────────────────
do_uninstall() {
    log_section "Shairport Sync – Full Uninstall"

    echo ""
    echo -e "  ${YELLOW}${BOLD}This will permanently remove:${NC}"
    echo "   • ${BIN_DIR}/shairport-sync"
    echo "   • ${INSTALL_PREFIX}/share/man/man7/shairport-sync.7"
    echo "   • ${SERVICE_FILE}"
    echo "   • ${GUI_SCRIPT}"
    echo "   • ${GUI_ICON}"
    echo "   • ${GUI_DESKTOP}"
    echo "   • ${AUTOSTART_LAUNCHER}"
    echo "   • ${AUTOSTART_DESKTOP}  (removed even if auto-start is currently off)"
    echo "   • ${AUTOSTART_LOG_DIR}/"
    echo "   • PATH line from ~/.bashrc  (if added by this script)"
    echo "   • ${CONFIG_DIR}/  (optional — you will be asked)"
    echo ""
    echo -e "  ${GREEN}This will NOT touch:${NC}"
    echo "   • /etc/pipewire/        (Pi OS audio config — never modified)"
    echo "   • /etc/wireplumber/     (Pi OS audio config — never modified)"
    echo "   • /etc/dbus-1/          (system dbus policy — never modified)"
    echo "   • /etc/systemd/system/  (system services  — never modified)"
    echo "   • apt build dependencies (shared with other packages — kept)"
    echo ""

    confirm "  Proceed with uninstall?" || { log_info "Cancelled."; press_enter; return; }

    # Stop and remove service unit
    log_section "Stopping and Removing Service Unit"
    systemctl --user stop    shairport-sync 2>/dev/null || true
    systemctl --user disable shairport-sync 2>/dev/null || true
    systemctl --user reset-failed shairport-sync 2>/dev/null || true

    if [[ -f "${SERVICE_FILE}" ]]; then
        rm -f "${SERVICE_FILE}"
        log_ok "Removed: ${SERVICE_FILE}"
    fi
    systemctl --user daemon-reload 2>/dev/null || true

    # Remove GUI
    log_section "Removing AirPlay Solace GUI"
    uninstall_gui

    # Remove binary
    log_section "Removing Binary"
    if [[ -f "${BIN_DIR}/shairport-sync" ]]; then
        rm -f "${BIN_DIR}/shairport-sync"
        log_ok "Removed: ${BIN_DIR}/shairport-sync"
    else
        log_info "Binary not found — already removed."
    fi

    # Remove man page
    find "${INSTALL_PREFIX}/share/man" -name "shairport-sync*" \
        -exec rm -f {} + 2>/dev/null || true

    # Remove build temp
    rm -rf "${BUILD_DIR}"

    # Remove PATH line from ~/.bashrc if this script added it
    if grep -q "# Added by shairport-sync-manager" "${HOME}/.bashrc" 2>/dev/null; then
        sed -i '/# Added by shairport-sync-manager/,+1d' "${HOME}/.bashrc"
        log_ok "Removed PATH entry from ~/.bashrc"
    fi

    # Config — ask separately (user may want to keep for reinstall)
    if [[ -d "${CONFIG_DIR}" ]]; then
        echo ""
        echo -e "  ${CYAN}Config directory: ${CONFIG_DIR}${NC}"
        echo "  Keep it to preserve your settings for reinstall."
        echo "  Remove it for a completely clean slate."
        echo ""
        if confirm "  Remove config directory too?"; then
            rm -rf "${CONFIG_DIR}"
            log_ok "Removed: ${CONFIG_DIR}"
        else
            log_info "Config kept: ${CONFIG_DIR}"
        fi
    fi

    # Residual scan — catches anything unexpected including GUI files
    log_section "Scanning for Residual Files"
    local residuals
    residuals=$(find "${HOME}/.local" "${HOME}/.config" \
        \( -name "*shairport*" -o -name "*airplay-solace*" \) \
        2>/dev/null | sort || true)

    if [[ -z "$residuals" ]]; then
        log_ok "No residual files found — clean uninstall confirmed."
    else
        log_warn "Residual files found:"
        echo "$residuals" | while IFS= read -r line; do echo "    $line"; done
        echo ""
        if confirm "  Remove all residual files?"; then
            echo "$residuals" | while IFS= read -r line; do
                rm -rf "$line" \
                    && log_ok "Removed: $line" \
                    || log_warn "Could not remove: $line"
            done
        fi
    fi

    echo ""
    echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  ✔  Shairport Sync fully uninstalled.${NC}"
    echo ""
    echo "  Pi OS PipeWire audio stack is completely untouched."
    echo "  HDMI, aux, and Bluetooth audio are unaffected."
    echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════${NC}"

    press_enter
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN MENU
# ──────────────────────────────────────────────────────────────────────────────
draw_menu() {
    clear

    local installed_ver service_status latest_ver update_notice=""
    installed_ver=$(get_installed_version)
    service_status=$(get_service_status)
    latest_ver=$(get_latest_version)
    local install_health
    install_health=$(get_install_health)

    if [[ "$installed_ver" != "not installed" && \
          "$latest_ver"    != "unknown"        && \
          "$installed_ver" != "$latest_ver" ]]; then
        update_notice="${YELLOW}${BOLD}  ⚡ Update available: ${latest_ver}${NC}"
    fi

    local status_colour="${RED}"
    [[ "$service_status" == "running" ]] && status_colour="${GREEN}"
    [[ "$service_status" == "stopped" ]] && status_colour="${YELLOW}"

    local autostart_status autostart_label autostart_colour
    autostart_status=$(get_autostart_status)
    if [[ "$autostart_status" == "on" ]]; then
        autostart_label="on (login)"
        autostart_colour="${GREEN}"
    else
        autostart_label="off"
        autostart_colour="${NC}"
    fi

    local health_str health_colour
    case "$install_health" in
        ok)      health_str="✔ ok";             health_colour="${GREEN}"  ;;
        partial) health_str="⚠ partial/broken"; health_colour="${RED}"    ;;
        none)    health_str="—";                health_colour="${NC}"     ;;
    esac

    # Linger warning — shown prominently if linger is unexpectedly on
    local linger_warn=""
    if loginctl show-user "$USER" 2>/dev/null | grep -q "Linger=yes"; then
        linger_warn="${RED}${BOLD}  ⛔ LINGER IS ON — disable before starting AirPlay${NC}"
    fi


    echo ""
    # ── Box 1: header + status ──────────────────────────────────────────────
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}  ║   Shairport Sync Manager  v${SCRIPT_VERSION}                  ║${NC}"
    echo -e "${CYAN}${BOLD}  ║   Pi 4 · Trixie · AirPlay 1 · On-Demand Only     ║${NC}"
    echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════════════╣${NC}"
    printf  "${CYAN}${BOLD}  ║${NC}  Installed : %-22s ${health_colour}%-11s${NC}${CYAN}${BOLD}║${NC}\n" \
            "$installed_ver" "$health_str"
    printf  "${CYAN}${BOLD}  ║${NC}  Latest    : %-35s${CYAN}${BOLD}║${NC}\n" "$latest_ver"
    printf  "${CYAN}${BOLD}  ║${NC}  AirPlay   : ${status_colour}%-26s${NC}            ${CYAN}${BOLD}║${NC}\n" \
            "$service_status"
    printf  "${CYAN}${BOLD}  ║${NC}  Autostart : ${autostart_colour}%-26s${NC}            ${CYAN}${BOLD}║${NC}\n" \
            "$autostart_label"

    echo -e "${CYAN}${BOLD}  ║${NC}                                                  ${CYAN}${BOLD}║${NC}"

    # ── Box 1: tools menu ───────────────────────────────────────────────────
    echo -e "${CYAN}${BOLD}  ╠══════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}${BOLD}  ║${NC}                                                  ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}  ║${NC}    ${BOLD}1)${NC}  Install / Repair Shairport Sync           ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}  ║${NC}    ${BOLD}2)${NC}  Uninstall Shairport Sync                  ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}  ║${NC}    ${BOLD}3)${NC}  Show logs (troubleshoot)                  ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}  ║${NC}    ${BOLD}4)${NC}  Show audio sinks (HDMI / aux / BT names)  ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}  ║${NC}    ${BOLD}5)${NC}  Edit config                               ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}  ║${NC}    ${BOLD}6)${NC}  Check for Updates                         ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}  ║${NC}                                                  ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════════════╝${NC}"

    echo ""

    # ── Box 2: AirPlay controls + directions ────────────────────────────────
    if [[ "$service_status" == "running" ]]; then
        echo -e "${GREEN}${BOLD}  ╔══════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}${BOLD}  ║  ♫  AirPlay Receiver is ACTIVE                  ║${NC}"
        echo -e "${GREEN}${BOLD}  ╠══════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}${BOLD}  ║${NC}                                                  ${GREEN}${BOLD}║${NC}"
        printf  "${GREEN}${BOLD}  ║${NC}  Connect from your device to: ${BOLD}%-19s${NC}${GREEN}${BOLD}║${NC}\n" "$(hostname)"
        echo -e "${GREEN}${BOLD}  ║${NC}                                                  ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}  ║${NC}  ${BOLD}iPhone/iPad${NC}  Open Control Centre              ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}  ║${NC}               tap 🔊 → tap AirPlay icon         ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}  ║${NC}  ${BOLD}Android${NC}      Use an AirPlay sender app        ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}  ║${NC}               (e.g. AirMusic or AirPlay & DLNA) ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}  ║${NC}  ${BOLD}Mac${NC}          Click 🔊 in menu bar → AirPlay   ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}  ║${NC}                                                  ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}  ╠══════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}${BOLD}  ║${NC}    ${BOLD}7)${NC}  Open AirPlay Solace (touch UI)           ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}  ║${NC}    ${BOLD}8)${NC}  Start AirPlay  (already running)         ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}  ║${NC}    ${BOLD}9)${NC}  Stop AirPlay receiver                    ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}  ║${NC}   ${BOLD}10)${NC}  Exit  (AirPlay keeps running)            ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}  ║${NC}   ${BOLD}11)${NC}  Stop AirPlay + Exit + Close window       ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}  ║${NC}                                                  ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}  ╚══════════════════════════════════════════════════╝${NC}"
    else
        echo -e "${YELLOW}${BOLD}  ╔══════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}${BOLD}  ║  AirPlay Controls                                ║${NC}"
        echo -e "${YELLOW}${BOLD}  ╠══════════════════════════════════════════════════╣${NC}"
        echo -e "${YELLOW}${BOLD}  ║${NC}                                                  ${YELLOW}${BOLD}║${NC}"
        echo -e "${YELLOW}${BOLD}  ║${NC}    ${BOLD}7)${NC}  Open AirPlay Solace (touch UI)           ${YELLOW}${BOLD}║${NC}"
        echo -e "${YELLOW}${BOLD}  ║${NC}    ${BOLD}8)${NC}  Start AirPlay receiver                    ${YELLOW}${BOLD}║${NC}"
        echo -e "${YELLOW}${BOLD}  ║${NC}         Before starting:                         ${YELLOW}${BOLD}║${NC}"
        echo -e "${YELLOW}${BOLD}  ║${NC}         • Set audio output in taskbar            ${YELLOW}${BOLD}║${NC}"
        echo -e "${YELLOW}${BOLD}  ║${NC}           (HDMI / 3.5mm aux / Bluetooth)         ${YELLOW}${BOLD}║${NC}"
        echo -e "${YELLOW}${BOLD}  ║${NC}         • Pi appears as: ${BOLD}$(hostname)${NC}            ${YELLOW}${BOLD}║${NC}"
        echo -e "${YELLOW}${BOLD}  ║${NC}                                                  ${YELLOW}${BOLD}║${NC}"
        echo -e "${YELLOW}${BOLD}  ║${NC}    ${BOLD}9)${NC}  Stop AirPlay receiver  (not running)     ${YELLOW}${BOLD}║${NC}"
        echo -e "${YELLOW}${BOLD}  ║${NC}   ${BOLD}10)${NC}  Exit  (AirPlay stays off)                ${YELLOW}${BOLD}║${NC}"
        echo -e "${YELLOW}${BOLD}  ║${NC}   ${BOLD}11)${NC}  Stop AirPlay + Exit + Close window       ${YELLOW}${BOLD}║${NC}"
        echo -e "${YELLOW}${BOLD}  ║${NC}                                                  ${YELLOW}${BOLD}║${NC}"
        echo -e "${YELLOW}${BOLD}  ╚══════════════════════════════════════════════════╝${NC}"
    fi

    [[ -n "$update_notice" ]] && echo -e "$update_notice"
    [[ -n "$linger_warn"   ]] && echo -e "$linger_warn"
    [[ "$install_health" == "partial" ]] && \
        echo -e "${RED}${BOLD}  ⚠ Partial install detected — run option 1 to repair${NC}"
    echo ""
}

main() {
    refuse_root

    while true; do
        draw_menu
        local choice=""
        read -rp "  Enter choice [1-11]: " choice
        case "$choice" in
            1) do_install          ;;
            2) do_uninstall        ;;
            3) do_show_logs        ;;
            4) do_show_audio_sinks ;;
            5) do_edit_config      ;;
            6) do_update           ;;
            7) launch_gui          ;;
            8) do_start_service    ;;
            9) do_stop_service     ;;
            10)
                echo ""
                log_info "Goodbye! (AirPlay continues running in the background)"
                echo ""
                exit 0
                ;;
            11)
                echo ""
                log_info "Stopping AirPlay and closing…"
                systemctl --user stop shairport-sync 2>/dev/null || true
                sleep 1
                log_ok "AirPlay stopped."
                echo ""
                exit 0
                ;;
            *)
                log_warn "Invalid choice — please enter 1–11."
                sleep 1
                ;;
        esac
    done
}

main
