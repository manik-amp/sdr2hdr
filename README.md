# SDR2HDR

Convert SDR videos to HDR10 using FFmpeg on Android through Termux.

## Features

- SDR to HDR10 conversion
- FFmpeg processing
- Android and Termux support
- ARM64 optimized
- Automatic Android storage paths
- HDR10 / BT.2020 / PQ support
- Configurable encoding quality
- Common video format support

## Requirements

- Android 8.0+
- ARM64 processor recommended
- Termux
- 2-4 GB free storage minimum

Install Termux from F-Droid or GitHub.
Do not use the outdated Google Play version.

## Quick Install

Open Termux and paste:

    termux-setup-storage && pkg update -y && pkg upgrade -y && pkg install git python ffmpeg -y && git clone https://github.com/tanmin-asp/sdr2hdr.git && cd sdr2hdr && pip install -r requirements.txt --break-system-packages && chmod +x sdr2hdr.sh

Allow storage permission when Android asks.

## Run

After installation:

    cd ~/sdr2hdr && ./sdr2hdr.sh

Or:

    bash ~/sdr2hdr/sdr2hdr.sh

## Storage Paths

After running termux-setup-storage:

    Downloads: ~/storage/shared/Download/
    Camera:   ~/storage/shared/DCIM/Camera/
    Movies:   ~/storage/shared/Movies/
    Pictures: ~/storage/shared/Pictures/

## HDR Profiles

Supported HDR-related settings include:

    BT.2020
    PQ / ST 2084
    BT.2020 Primaries
    BT.2020 Matrix

## Encoding

Default example:

    Preset: faster
    CRF: 21

Lower CRF = higher quality and larger files.

Higher CRF = more compression and smaller files.

The faster preset is intended for practical Android processing speeds.

## Performance

Processing speed depends on:

- CPU performance
- Video resolution
- Input codec
- Output codec
- Video duration
- FFmpeg settings
- Storage speed
- Device temperature

4K videos require significantly more processing than 1080p.

## Keep Termux Awake

For long conversions:

    termux-wake-lock
    cd ~/sdr2hdr
    ./sdr2hdr.sh

After processing:

    termux-wake-unlock

## Troubleshooting

### Permission denied

Run:

    chmod +x ~/sdr2hdr/sdr2hdr.sh

Then:

    cd ~/sdr2hdr
    ./sdr2hdr.sh

### File not found

Check the project files:

    ls ~/sdr2hdr

Then:

    cd ~/sdr2hdr

### Python externally managed environment

Run:

    pip install -r requirements.txt --break-system-packages

### dpkg error

Run:

    dpkg --configure -a
    apt install -f

Then:

    pkg update
    pkg upgrade

### Process killed

Before processing:

    termux-wake-lock

Then:

    cd ~/sdr2hdr
    ./sdr2hdr.sh

## Check Installation

FFmpeg:

    ffmpeg -version

Python:

    python --version

Git:

    git --version

Check HDR-related FFmpeg filters:

    ffmpeg -filters | grep -E "zscale|tonemap|colorspace"

## Important

SDR to HDR conversion does not restore HDR information originally captured by an HDR camera.

The process maps SDR content into an HDR10-oriented signal.

Final results depend on the source video, conversion settings, encoder, display, and video player.

## Project Structure

    sdr2hdr/
    ├── sdr2hdr.sh
    ├── requirements.txt
    ├── README.md
    ├── LICENSE
    └── ...

## License

GPL-3.0

See LICENSE for the full license text.

## Credits

Built with FFmpeg for SDR video processing on Android through Termux.
