# AirPlay Solace — Shairport-Sync Manager & GTK3 Control Suite

A self-contained manager script that compiles [`shairport-sync`](https://github.com/mikebrady/shairport-sync) from source and installs **AirPlay Solace**, an on-demand AirPlay 1 Classic receiver paired with an embedded GTK3 Python GUI — designed for Raspberry Pi OS.

Unlike standard shairport-sync installations, this receiver **never runs as a boot daemon**. This is critical — running shairport-sync as a system service at boot races PipeWire's audio device enumeration and breaks HDMI and AUX output on Raspberry Pi hardware.

---

## 🛠️ Features

* **Source Compilation:** Builds the latest compatible shairport-sync directly on your device with Pi OS Trixie-specific build flags.
* **PipeWire-Safe Architecture:** Four non-negotiable safety rules baked in — no linger, no boot daemon, correct `--sysconfdir`, no `--with-systemd-startup`. Proven on real hardware.
* **On-Demand Control:** Start and stop the AirPlay receiver instantly from the GTK3 GUI or terminal menu. Nothing runs unless you ask it to.
* **AirPlay Solace GUI:** Embedded GTK3 touch interface showing live receiver status, connection hints, Start/Stop controls, and an optional auto-start at login toggle.
* **Cava Solace Integration:** Detects [Cava Solace](https://github.com/PuppetHoundZ/Cava-Solace) and shows a launch button — both GUIs fit side-by-side on an 800×480 touchscreen simultaneously.
* **Optional Auto-Start at Login:** Opt-in only via a checkbox in the GUI. Uses XDG autostart (not `systemctl --user enable`). The wrapper polls for PipeWire readiness before starting and self-heals if the binary is missing.
* **Fault-Tolerant Installer:** Rollback/crash recovery via marker files — auto-restores previous state on power loss or interrupted install.
* **Safe Uninstall:** Removes all installed files cleanly; build dependencies are retained to avoid breaking other Pi OS packages.

---

## 📂 Key Path Architecture

| Asset Type | File Path |
| :--- | :--- |
| **shairport-sync binary** | `~/.local/bin/shairport-sync` |
| **AirPlay Solace GUI** | `~/.local/bin/airplay-solace` |
| **Auto-start wrapper** | `~/.local/bin/airplay-solace-autostart` |
| **shairport-sync config** | `~/.config/shairport-sync/shairport-sync.conf` |
| **systemd user unit** | `~/.config/systemd/user/shairport-sync.service` (never enabled) |
| **Auto-start toggle** | `~/.config/autostart/airplay-solace-autostart.desktop` |
| **Desktop Launcher** | `~/.local/share/applications/airplay-solace.desktop` |
| **Scalable Vector Icon** | `~/.local/share/icons/hicolor/scalable/apps/airplay-solace.svg` |
| **Rollback State Dir** | `~/.local/share/shairport-sync-manager/` |

---

## 📋 Requirements

* **OS:** Raspberry Pi OS Trixie (Debian 13) arm64
* **Audio:** PipeWire (default on Trixie — never replaced or disabled by this script)
* **Network:** Internet connection required for initial source build + Avahi/mDNS for AirPlay discovery
* **Storage:** ~100 MB free disk space during build (reclaimed after install)

The manager automatically checks and installs missing build dependencies. All are retained on uninstall.

---

## 🚀 Installation & Usage

1. Download or copy the manager script to your system.
2. Make it executable:
   ```bash
   chmod +x shairport-sync-manager.sh
   ```
3. Run it as your **normal user** (do **NOT** use `sudo` or run as root):
   ```bash
   ./shairport-sync-manager.sh
   ```

### Terminal Menu Options

| Option | Action |
| :--- | :--- |
| **1** | Install / Repair shairport-sync |
| **2** | Uninstall shairport-sync |
| **3** | Show logs |
| **4** | Show audio sinks (HDMI / AUX / Bluetooth names) |
| **5** | Edit config |
| **6** | Check for updates |
| **7** | Open AirPlay Solace (touch GUI) |
| **8** | Start AirPlay receiver |
| **9** | Stop AirPlay receiver |
| **10** | Exit (AirPlay keeps running) |
| **11** | Stop AirPlay + Exit + Close window |

### Connecting from Your Device

Once the receiver is running, your Pi appears on the network by its hostname:

| Device | How to connect |
| :--- | :--- |
| **iPhone / iPad** | Open Control Centre → tap 🔊 → tap AirPlay icon → select your Pi |
| **Android** | Use an AirPlay sender app (e.g. AirMusic or AirPlay & DLNA) |
| **Mac** | Click 🔊 in the menu bar → AirPlay → select your Pi |

---

## 🔗 Cross-App Integration

AirPlay Solace integrates with **Cava Solace** ([Cava-Solace](https://github.com/PuppetHoundZ/Cava-Solace)):

* Detects Cava Solace via `~/.local/share/applications/cava-solace.desktop`
* Shows a **Launch Cava Solace** button in the GUI when detected
* Both GUIs fit side-by-side on an 800×480 touchscreen — confirmed on real hardware

---

## References

* [shairport-sync source](https://github.com/mikebrady/shairport-sync)
* [Build instructions](https://github.com/mikebrady/shairport-sync/blob/master/BUILD.md)
* [PipeWire integration](https://github.com/mikebrady/shairport-sync/blob/master/ADVANCED%20TOPICS/PulseAudioAndPipeWire.md)
* [Trixie make install bug #2133](https://github.com/mikebrady/shairport-sync/issues/2133)
* [Linger / boot daemon issue #1970](https://github.com/mikebrady/shairport-sync/issues/1970)
* [Raspberry Pi forums](https://forums.raspberrypi.com/)

## Disclaimer

Provided as-is, free of charge, for Raspberry Pi users. Not affiliated with the shairport-sync project, Raspberry Pi Ltd, or Apple Inc. Use at your own risk.
