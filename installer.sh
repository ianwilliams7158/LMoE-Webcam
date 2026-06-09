#!/usr/bin/env bash
# =======================================================================
# Pi Zero W v1.1 Live Webcam SPI Streamer Auto-Installer (Interactive)
# =======================================================================
set -e

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run this script with sudo: sudo bash install.sh"
  exit 1
fi

# Interactive Stream Configuration
echo "=================================================="
echo "   Pi Zero W Webcam Streamer Setup Wizard"
echo "=================================================="
read -p "Paste your YouTube Webcam URL and press [ENTER]: " USER_URL

# Fallback check if the input was left blank
if [ -z "$USER_URL" ]; then
  echo "[!] No URL provided. Falling back to baseline stream link..."
  USER_URL="https://www.youtube.com/watch?v=K2gBg7jjhIc"
fi

echo ""
echo "[+] Starting fresh system package updates..."
apt update
apt install -y ffmpeg python3-spidev python3-gpiozero python3-venv

echo "[+] Activating hardware SPI interface..."
raspi-config nonint do_spi 0

echo "[+] Building isolated Python ecosystem with system hardware bridging..."
python3 -m venv --system-site-packages --clear /opt/video_env
/opt/video_env/bin/pip install --upgrade pip
/opt/video_env/bin/pip install yt-dlp

echo "[+] Injecting core streaming engine into /usr/local/bin/..."
cat << 'EOF' > /usr/local/bin/playlist_cycler.py
#!/usr/bin/env python3
import subprocess
import time
import sys
import spidev
from gpiozero import DigitalOutputDevice, PWMOutputDevice

# Configuration Baseline (Dynamically updated by installer)
TARGET_URL = "YOUTUBE_URL_PLACEHOLDER"
WIDTH = 280
HEIGHT = 240

# --- STATIC ALIGNMENT FIX ---
# If you see static on the right side, change COL_OFFSET to 20 or 40
COL_OFFSET = 0  
ROW_OFFSET = 0
# ----------------------------

class ST7789:
    def __init__(self, width=WIDTH, height=HEIGHT, dc=25, rst=27, bl=18):
        self.width = width
        self.height = height
        self.dc = DigitalOutputDevice(dc)
        self.rst = DigitalOutputDevice(rst)
        self.bl = PWMOutputDevice(bl) if bl else None
        
        self.spi = spidev.SpiDev()
        self.spi.open(0, 0)
        self.spi.max_speed_hz = 40000000
        self.spi.mode = 0b11
        
        self.reset()
        self.init_display()

    def command(self, cmd, *args):
        self.dc.off()
        self.spi.xfer2([cmd])
        if args:
            self.dc.on()
            self.spi.xfer2(list(args))

    def data(self, data_bytes):
        self.dc.on()
        chunk_size = 4096
        for i in range(0, len(data_bytes), chunk_size):
            self.spi.xfer2(list(data_bytes[i:i+chunk_size]))

    def reset(self):
        self.rst.on()
        time.sleep(0.05)
        self.rst.off()
        time.sleep(0.05)
        self.rst.on()
        time.sleep(0.05)

    def init_display(self):
        self.command(0x01) # Software Reset
        time.sleep(0.15)
        self.command(0x11) # Sleep Out
        time.sleep(0.1)
        
        # MADCTL: Set display orientation to landscape (anticlockwise)
        self.command(0x36, 0xA0) 
        
        self.command(0x3A, 0x05) # 16-bit RGB565 color format
        self.command(0x21) # Display Inversion ON
        self.command(0x29) # Display ON
        if self.bl:
            self.bl.value = 1.0

    def show_frame(self, frame_bytes):
        # Calculate memory coordinates including hardware screen offsets
        xs = COL_OFFSET
        xe = COL_OFFSET + self.width - 1
        ys = ROW_OFFSET
        ye = ROW_OFFSET + self.height - 1

        self.command(0x2A, (xs >> 8) & 0xFF, xs & 0xFF, (xe >> 8) & 0xFF, xe & 0xFF)
        self.command(0x2B, (ys >> 8) & 0xFF, ys & 0xFF, (ye >> 8) & 0xFF, ye & 0xFF)
        self.command(0x2C) # Write to Frame RAM
        self.data(frame_bytes)

def extract_direct_stream(video_url):
    try:
        cmd = ["/opt/video_env/bin/yt-dlp", "-g", "-f", "best[height<=360]/worst", video_url]
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return res.stdout.strip().split('\n')[0]
    except Exception as e:
        print(f"Extraction failed for {video_url}: {e}", file=sys.stderr)
        return None

def main():
    display = ST7789()
    frame_size = WIDTH * HEIGHT * 2 

    while True:
        stream_url = extract_direct_stream(TARGET_URL)
        if not stream_url:
            time.sleep(5)
            continue
            
        ffmpeg_cmd = [
            "ffmpeg",
            "-i", stream_url,
            "-f", "rawvideo",
            "-pix_fmt", "rgb565be",
            "-s", f"{WIDTH}x{HEIGHT}",
            "-v", "error",
            "-"
        ]
        
        try:
            proc = subprocess.Popen(ffmpeg_cmd, stdout=subprocess.PIPE, bufsize=frame_size)
            while True:
                frame = proc.stdout.read(frame_size)
                if not frame or len(frame) < frame_size:
                    break
                display.show_frame(frame)
            
            proc.terminate()
            proc.wait()
        except Exception as e:
            print(f"Decoder engine encounter: {e}", file=sys.stderr)
        
        time.sleep(5)

if __name__ == "__main__":
    main()
EOF

# Safely swap out the target template string inside the Python file using alternate delimiters
sed -i "s|YOUTUBE_URL_PLACEHOLDER|$USER_URL|g" /usr/local/bin/playlist_cycler.py
chmod +x /usr/local/bin/playlist_cycler.py

echo "[+] Constructing background Systemd service daemon..."
cat << 'EOF' > /etc/systemd/system/playlist.service
[Unit]
Description=Native SPI YouTube Webcam Streamer
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=PYTHONUNBUFFERED=1
ExecStart=/opt/video_env/bin/python3 /usr/local/bin/playlist_cycler.py
WorkingDirectory=/usr/local/bin
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

echo "[+] Registering and priming autostart triggers..."
systemctl daemon-reload
systemctl enable playlist.service
systemctl start playlist.service

echo "=================================================="
echo "[+] Installation complete! Streamer daemon initialized."
echo "[+] Targeted URL: $USER_URL"
echo "[+] Monitor feed state with: sudo journalctl -u playlist.service -f"
echo "=================================================="