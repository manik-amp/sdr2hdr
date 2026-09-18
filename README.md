# SDR to HDR10 Converter (Termux)

An interactive CLI utility to convert SDR footage into true HDR10 (BT.2020 / SMPTE 2084) using 32-bit float grading directly inside Termux on ARM64 Android devices.

### Prerequisites

```bash
pkg update && pkg install ffmpeg -y
curl -sL [https://raw.githubusercontent.com/manik-amp/sdr2hdr/main/sdr2hdr](https://raw.githubusercontent.com/manik-amp/sdr2hdr/main/sdr2hdr) -o $PREFIX/bin/sdr2hdr && chmod +x$PREFIX/bin/sdr2hdr
