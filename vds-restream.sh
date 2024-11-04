#!/bin/bash

# Install Nginx with RTMP module
echo "Installing Nginx with RTMP module..."
sudo apt update
sudo apt install -y libnginx-mod-rtmp nginx

# Check if Nginx is installed correctly
if ! command -v nginx &> /dev/null; then
    echo "Nginx installation failed. Please check your installation."
    exit 1
fi

# Configure Nginx for RTMP
echo "Configuring Nginx for RTMP..."
sudo tee /etc/nginx/nginx.conf > /dev/null <<EOF
worker_processes  auto;
events {
    worker_connections  1024;
}

rtmp {
    server {
        listen 1935;
        chunk_size 4096;

        application live {
            live on;
            record off;
        }
    }
}

http {
    server {
        listen 8080;
        
        location /stat {
            rtmp_stat all;
            rtmp_stat_stylesheet stat.xsl;
        }

        location /stat.xsl {
            root /usr/local/nginx/html;
        }
    }
}
EOF

# Restart Nginx to apply the new configuration
echo "Restarting Nginx..."
sudo systemctl restart nginx

# Prompt for stream keys for each platform
read -p "Enter YouTube stream key (leave empty if not needed): " YOUTUBE_KEY
read -p "Enter Twitch stream key (leave empty if not needed): " TWITCH_KEY
read -p "Enter VK stream key (leave empty if not needed): " VK_KEY

# Create the directory and script file for restreaming
echo "Creating restreaming script..."
mkdir -p /home/restream
sudo tee /home/restream/restream.sh > /dev/null <<EOF
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
echo "Setting permissions..."
chmod +x /home/restream/restream.sh

# Create the systemd service for restreaming
echo "Creating systemd service..."
sudo tee /etc/systemd/system/restream.service > /dev/null <<EOF
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
echo "Enabling and starting the restream service..."
sudo systemctl daemon-reload
sudo systemctl enable restream.service
sudo systemctl start restream.service

echo "Restream service installed, enabled on startup, and started."
