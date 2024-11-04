#!/bin/bash

# Prompt for stream keys for each platform
read -p "Enter YouTube stream key (leave empty if not needed): " YOUTUBE_KEY
read -p "Enter Twitch stream key (leave empty if not needed): " TWITCH_KEY
read -p "Enter VK stream key (leave empty if not needed): " VK_KEY

# Create the directory and script file
mkdir -p /home/restream
cat <<EOF > /home/restream/restream.sh
#!/bin/bash

# Input stream from OBS or other source
INPUT_STREAM="rtmp://localhost/live/stream"  # URL of the input stream

# URLs for streaming
YOUTUBE_URL="${YOUTUBE_KEY:+rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_KEY}"
TWITCH_URL="${TWITCH_KEY:+rtmp://live.twitch.tv/app/$TWITCH_KEY}"
VK_PLAY_URL="${VK_KEY:+rtmp://vsuc.okcdn.ru/input/$VK_KEY}"

# Function to relay the stream to specified platforms
relay_stream() {
    echo "\$(date) - Starting relay to platforms..."
    ffmpeg -re -i "\$INPUT_STREAM" \\
    ${YOUTUBE_KEY:+-c copy -f flv "\$YOUTUBE_URL"} \\
    ${TWITCH_KEY:+-c copy -f flv "\$TWITCH_URL"} \\
    ${VK_KEY:+-c copy -f flv "\$VK_PLAY_URL"}
}

# Main loop
while true
do
    relay_stream
    echo "\$(date) - Restarting stream in 5 seconds..."
    sleep 5
done
EOF

# Set the necessary permissions
chmod +x /home/restream/restream.sh

# Create the systemd service
cat <<EOF > /etc/systemd/system/restream.service
[Unit]
Description=Restream Service for Broadcasting to YouTube, Twitch, and VK Play
After=network.target

[Service]
ExecStart=/home/restream/restream.sh
Restart=always
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start the service
systemctl daemon-reload
systemctl enable restream.service
systemctl start restream.service

echo "Restream service installed, enabled on startup, and started."