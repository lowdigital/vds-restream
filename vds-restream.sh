#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to display messages
log() {
    echo -e "\e[32m$1\e[0m"
}

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run the script as root."
    exit 1
fi

# Step 1: Remove existing Nginx installations (if any)
log "Removing existing Nginx installations..."
apt purge -y nginx nginx-common nginx-full libnginx-mod-rtmp || true
apt autoremove -y || true
rm -rf /etc/nginx

# Step 2: Update package lists
log "Updating package lists..."
apt update

# Step 3: Install Nginx
log "Installing Nginx..."
apt install -y nginx

# Step 4: Check Nginx status
log "Checking Nginx status..."
systemctl start nginx
systemctl enable nginx

# Step 5: Install RTMP module
log "Installing RTMP module..."
apt install -y libnginx-mod-rtmp

# Step 6: Configure RTMP
log "Configuring RTMP..."
cat > /etc/nginx/rtmp.conf <<EOF
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
EOF

# Step 7: Include rtmp.conf in nginx.conf after events {} block and before http {}
NGINX_CONF="/etc/nginx/nginx.conf"

# Ensure events { } block exists
if ! grep -q "events {" "$NGINX_CONF"; then
    sed -i '/^pid/a events {\n    worker_connections 1024;\n}' "$NGINX_CONF"
    log "Added events { } block to nginx.conf"
fi

# Add worker_connections if not present
if ! grep -q "worker_connections" "$NGINX_CONF"; then
    sed -i '/events {/a \    worker_connections 1024;' "$NGINX_CONF"
fi

# Include rtmp.conf after events { } block
if ! grep -q "include /etc/nginx/rtmp.conf;" "$NGINX_CONF"; then
    sed -i '/events {/,/}/!b;/}/a include /etc/nginx/rtmp.conf;' "$NGINX_CONF"
    log "Included /etc/nginx/rtmp.conf after events { } block"
fi

# Ensure http { } block exists and includes conf.d/*.conf
if ! grep -q "^http {" "$NGINX_CONF"; then
    echo -e "\nhttp {\n    include /etc/nginx/mime.types;\n    default_type application/octet-stream;\n    include /etc/nginx/conf.d/*.conf;\n}" >> "$NGINX_CONF"
    log "Added http { } block to nginx.conf"
else
    # Ensure conf.d/*.conf is included inside http { } block
    if ! grep -q "include /etc/nginx/conf.d/\*\.conf;" "$NGINX_CONF"; then
        sed -i '/^http {/a \    include /etc/nginx/conf.d/*.conf;' "$NGINX_CONF"
        log "Included /etc/nginx/conf.d/*.conf in http { } block"
    fi
fi

# Step 8: Configure RTMP statistics
log "Configuring RTMP statistics..."
cat > /etc/nginx/conf.d/stat.conf <<EOF
server {
    listen 8080;

    location /stat {
        rtmp_stat all;
        rtmp_stat_stylesheet stat.xsl;
    }

    location /stat.xsl {
        root /usr/share/nginx/html;
    }
}
EOF

# Step 9: Test Nginx configuration
log "Testing Nginx configuration..."
nginx -t

# Step 10: Restart Nginx
log "Restarting Nginx..."
systemctl restart nginx

# Step 11: Create restream user
log "Creating restream user..."
useradd -r -s /usr/sbin/nologin restream || true

# Step 12: Install FFmpeg
log "Installing FFmpeg..."
apt install -y ffmpeg

# Step 13: Prompt for stream keys
log "Requesting stream keys..."
read -p "Enter YouTube stream key (leave blank if not needed): " YOUTUBE_KEY
read -p "Enter Twitch stream key (leave blank if not needed): " TWITCH_KEY
read -p "Enter VK stream key (leave blank if not needed): " VK_KEY

# Step 14: Create configuration file with keys
log "Creating configuration file with stream keys..."
mkdir -p /home/restream
chown restream:restream /home/restream

cat > /home/restream/stream_keys.conf <<EOF
YOUTUBE_KEY="$YOUTUBE_KEY"
TWITCH_KEY="$TWITCH_KEY"
VK_KEY="$VK_KEY"
EOF

# Set permissions for the configuration file
chmod 600 /home/restream/stream_keys.conf
chown restream:restream /home/restream/stream_keys.conf

# Step 15: Create restream script
log "Creating restream script..."
cat > /home/restream/restream.sh <<'EOF'
#!/bin/bash

# Load stream keys from configuration file
source /home/restream/stream_keys.conf

# Input stream from OBS or another source
INPUT_STREAM="rtmp://localhost/live/stream"

# Build the list of output URLs
OUTPUT_URLS=()
[ -n "$YOUTUBE_KEY" ] && OUTPUT_URLS+=("[f=flv]rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_KEY")
[ -n "$TWITCH_KEY" ] && OUTPUT_URLS+=("[f=flv]rtmp://live.twitch.tv/app/$TWITCH_KEY")
[ -n "$VK_KEY" ] && OUTPUT_URLS+=("[f=flv]rtmp://vsuc.okcdn.ru/input/$VK_KEY")

# Check if at least one output stream is configured
if [ ${#OUTPUT_URLS[@]} -eq 0 ]; then
    echo "$(date) - No output streams configured. Please check /home/restream/stream_keys.conf"
    sleep 10
    exit 1
fi

# Build the output string for ffmpeg using the tee muxer
OUTPUT_STRING=$(IFS="|"; echo "${OUTPUT_URLS[*]}")

# Function to relay the stream to configured platforms
relay_stream() {
    echo "$(date) - Starting stream relay..."
    ffmpeg -re -i "$INPUT_STREAM" -c copy -f tee "$OUTPUT_STRING"
}

# Main loop
while true
do
    relay_stream
    echo "$(date) - Restarting stream in 5 seconds..."
    sleep 5
done
EOF

chmod +x /home/restream/restream.sh
chown restream:restream /home/restream/restream.sh

# Step 16: Create systemd service for restreaming
log "Creating systemd service for restreaming..."
cat > /etc/systemd/system/restream.service <<EOF
[Unit]
Description=Restreaming service for YouTube, Twitch, and VK
After=network.target

[Service]
WorkingDirectory=/home/restream
ExecStart=/home/restream/restream.sh
Restart=always
RestartSec=5
User=restream
Group=restream
StandardOutput=journal
StandardError=journal
SyslogIdentifier=restream

[Install]
WantedBy=multi-user.target
EOF

# Step 17: Reload systemd and start the service
log "Starting restreaming service..."
systemctl daemon-reload
systemctl enable restream.service
systemctl start restream.service

log "Installation complete! The restreaming service is installed, enabled on startup, and running."
