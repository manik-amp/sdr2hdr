#!/usr/bin/env bash

echo "========================================"
echo "          HDR10 Studio Launcher         "
echo "========================================"

# Make sure Python and FFmpeg are installed
command -v python &> /dev/null || pkg install python -y
command -v ffmpeg &> /dev/null || pkg install ffmpeg -y

# Install Flask if missing
[ -f "requirements.txt" ] && pip install -r requirements.txt --quiet

# Find your phone's Wi-Fi IP address automatically
LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
[ -z "$LOCAL_IP" ] && LOCAL_IP="127.0.0.1"

echo ""
echo "[✓] Starting HDR10 Studio..."
echo "----------------------------------------"
echo "  Open on this device: http://127.0.0.1:5000"
echo "  Open on your PC:     http://${LOCAL_IP}:5000"
echo "----------------------------------------"
echo "Press Ctrl + C to stop."
echo ""

python app.py
