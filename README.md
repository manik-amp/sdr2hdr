# 🎬 SDR2HDR — Mobile HDR10 Video Converter

A fast, high-precision CLI utility designed to convert standard dynamic range (SDR) video footage into true **HDR10 (BT.2020 / SMPTE ST 2084 PQ)** directly on Android devices via **Termux (ARM64)**.

---

## 🌟 Key Features

- **True HDR10 Mastering:** Accurately converts standard Rec.709/sRGB color profiles to wide-gamut BT.2020 with the PQ (Perceptual Quantizer) transfer function.
- **High-Precision Color Processing:** Uses 32-bit float color matrix grading to minimize color banding and preserve shadow/highlight details.
- **HDR Metadata Injection:** Automatically writes essential HDR10 metadata (`Mastering Display Color Volume`, `MaxCLL`, `MaxFALL`) for native HDR display recognition on Samsung, iPhone, and OLED screens.
- **Social Media Presets:** Tuned bitrates and color profiles optimized for Instagram Reels, TikTok HDR, and YouTube Shorts.
- **Hardware-Aware Encoding:** Uses optimized multi-threaded ARM64 FFmpeg pipelines for maximum encoding speed without root access.

---

## 📋 Prerequisites

1. **Termux:** Must be downloaded from [F-Droid](https://f-droid.org/packages/com.termux/) or GitHub (do **not** use the outdated Google Play Store build).
2. **Android OS:** Android 8.0+ (ARM64 processor recommended).
3. **Storage Space:** At least 2–4 GB free internal storage for temporary encoding passes.

---

## 🚀 Quick Install (One-Line Setup)

Open Termux and paste the following command:

```bash
termux-setup-storage && pkg update -y && pkg install git python ffmpeg -y && git clone [https://github.com/manik-amp/sdr2hdr.git](https://github.com/manik-amp/sdr2hdr.git) && cd sdr2hdr && pip install -r requirements.txt --break-system-packages && chmod +x sdr2hdr.sh && ./sdr2hdr.sh