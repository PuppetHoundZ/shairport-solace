# AirPlay Solace — Shairport-Sync & GTK3 Control Suite

This manager script compiles `shairport-sync` from source and installs **AirPlay Solace**, an on-demand AirPlay 1 Classic receiver paired with an embedded GTK3 Python GUI. 

Unlike standard installations, this receiver **never runs as a boot daemon**. This architecture is critical for maintaining PipeWire stability across HDMI and AUX outputs on Raspberry Pi hardware.

## Features
* **Source Compilation:** Builds the latest compatible version of `shairport-sync` directly on your device.
* **PipeWire-Native Alignment:** Configured specifically for userland execution, preventing audio device conflicts.
* **On-Demand Control:** Launch and stop the AirPlay receiver instantly via the integrated GTK3 Python interface.
* **No Root Daemon:** Operates entirely within user space to protect system audio routing stability.

## Prerequisites & Requirements
* **OS:** Raspberry Pi OS Trixie (Debian 13) arm64 recommended.
* **Audio Server:** PipeWire (running and configured for your current user session).
* **Dependencies:** Development tools for compilation (handled automatically by the manager script's installation option).

## Usage

Do **NOT** run this script as root or via `sudo`. It must be executed in user space to integrate properly with your running PipeWire session.

```bash
chmod +x shairport-sync-manager.sh
./shairport-sync-manager.sh

```

## References

* [Source](https://github.com/mikebrady/shairport-sync)
* [Build](https://github.com/mikebrady/shairport-sync/blob/master/BUILD.md)
* [PipeWire](https://github.com/mikebrady/shairport-sync/blob/master/ADVANCED%20TOPICS/PulseAudioAndPipeWire.md)
* [Trixie bug](https://github.com/mikebrady/shairport-sync/issues/2133)
* [Linger](https://github.com/mikebrady/shairport-sync/issues/1970)
* [Pi forums](https://forums.raspberrypi.com/)

## Disclaimer

Provided as-is, free of charge, for Raspberry Pi users. This software is not affiliated with the shairport-sync project, Raspberry Pi Ltd, or Apple Inc. Use at your own risk. It is highly recommended to maintain a full system backup before modifying audio configurations.

```

```
