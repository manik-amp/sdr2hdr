# SDR to HDR10 Converter (Termux)

An interactive CLI tool to convert SDR video to true HDR10 (BT.2020 / SMPTE 2084) using 32-bit float grading directly inside Termux on ARM64 Android devices.

---

## Features

* **32-Bit Float Color Pipeline:** Real-time grading using `gbrpf32le` high-precision floating point, exposure adjustment, and PQ (SMPTE 2084) curve mapping.
* **HDR10 Metadata Injection:** Embeds static mastering display metadata (`master-display`) and content light levels (`MaxCLL` / `MaxFALL`).
* **Auto Colorspace Fallback:** Detects input video color matrices via `ffprobe` and handles untagged clips gracefully.
* **Interactive Terminal UI:** Auto-centered layout, video picker, live progress percentage, FPS counter, and ETA.
* **In-Flight Controls:** Pause (`P`) and Cancel (`Q`) hotkeys during conversion.
* **Platform Presets:** Optimized presets for TikTok (60fps CFR) and Instagram (30fps CFR) or raw passthrough.

---

## Prerequisites

Make sure FFmpeg is installed in Termux:

```bash
pkg update && pkg install ffmpeg -y
```

---

## Installation

Install or update the tool with a single command:

```bash
curl -sL https://raw.githubusercontent.com/manik-amp/sdr2hdr/main/sdr2hdr -o $PREFIX/bin/sdr2hdr && chmod +x $PREFIX/bin/sdr2hdr

```

---

## Usage

### 1. Interactive Menu Mode
Launch the interactive picker to select directories and files:

```bash
sdr2hdr
```

### 2. Direct Video Conversion
Pass a video path directly to bypass the folder scanner:

```bash
sdr2hdr /sdcard/DCIM/Camera/VID_sample.mp4
```

---

## Controls During Encode

* **`P`** : Pause / Resume encoding
* **`Q`** : Stop and clean up temporary files

---

## Output Location

Converted files are automatically organized and saved to:
```text
/sdcard/DCIM/HDR10_Converted/
```
