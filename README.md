# SDR to HDR10 Converter (Termux)

Fast, high-precision CLI utility to convert SDR footage to true HDR10 (BT.2020 / SMPTE 2084) directly on Android via Termux. Features 32-bit float grading, HDR10 metadata injection, real-time encode stats, and social media presets.

---

## Features

* **32-Bit Float Color Pipeline:** High-precision floating point grading (`gbrpf32le`), exposure leveling, and SMPTE 2084 (PQ) transfer curve conversion.
* **Metadata Injection:** Embeds static mastering display metadata (`master-display`) and light level bounds (`MaxCLL` / `MaxFALL`) for true HDR10 compliance.
* **Automatic Colorspace Fallback:** Automatically probes input color matrices (`BT.709`, `BT.601`) and gracefully handles untagged clips.
* **Interactive Terminal UI:** Interactive file browser, real-time progress bar, FPS counter, and dynamic ETA estimation.
* **In-Flight Controls:** Hotkeys to pause (`P`) or abort cleanly (`Q`) during the encoding process.
* **Platform Presets:** Tailored presets for TikTok (60fps CFR) and Instagram (30fps CFR), plus raw frame passthrough.

---

## Prerequisites

Make sure `ffmpeg` is installed in Termux:

```bash
pkg update && pkg install ffmpeg -y
```

---

## Installation

Install or update the script to your system path with a single command:

```bash
curl -sL [https://raw.githubusercontent.com/manik-amp/sdr2hdr/main/sdr2hdr.sh](https://raw.githubusercontent.com/manik-amp/sdr2hdr/main/sdr2hdr.sh) -o $PREFIX/bin/sdr2hdr && chmod +x $PREFIX/bin/sdr2hdr
```

---

## Usage

### 1. Interactive Menu Mode
Launch the interactive terminal browser:

```bash
sdr2hdr
```

### 2. Direct File Conversion
Pass a video path directly as an argument:

```bash
sdr2hdr /sdcard/DCIM/Camera/VID_sample.mp4
```

---

## Controls During Encode

* **`P`** : Pause / Resume encoding
* **`Q`** : Cancel encoding and purge temporary cache files

---

## Output Location

Converted HDR10 clips are saved directly to your device storage:

```text
/sdcard/DCIM/HDR10_Converted/
```

---

## License

This project is open source and available under the [MIT License](LICENSE).
