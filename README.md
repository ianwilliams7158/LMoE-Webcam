sudo chmod +x installer.sh
sudo ./installer.sh

It will pause and ask for a youtube link

If you're using the same waveshare 1.69 screens as me, you will need to adjust the centering of the image:

sudo nano /usr/local/bin/playlist_cycler.py

Change the COL_OFFSET from 0 to 20

then restart the background daemon

sudo systemctl restart playlist.service


https://www.waveshare.com/1.69inch-lcd-module.htm
