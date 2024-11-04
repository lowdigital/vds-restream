# VDS Restream Setup Script

This repository contains a bash script for installing and configuring a video streaming relay service using Nginx with the RTMP module. The script automates the installation process, allowing you to deploy your own RTMP server and set up stream relay to platforms like YouTube, Twitch, and VK with a single command.

## Table of Contents
- Features
- Prerequisites
- Installation
- Usage
    - Starting a Stream
    - Updating Stream Keys
- Configuration
    - Nginx Configuration
    - Firewall Setup
- Security
- Monitoring and Debugging
- Uninstallation
- Authors
- License
- Contacts

## Features
- **Automatic Installation**: The script installs all necessary packages and configures them without user intervention.
- **Multi-Platform Support**: Relay streams to YouTube, Twitch, and VK simultaneously.
- **Flexibility**: Easily add or remove platforms as needed.
- **Ease of Use**: Installation and service startup take just one command.
- **Security**: Stream keys are stored in a secure file with restricted access.

## Prerequisites
- **Operating System**: Debian 11.
- **User Permissions**: Access to the root account (without using sudo).
- **Internet Connection**: Required for package installation and stream relay.

## Installation
To install the restreaming service, run the following command as root:

```bash
bash <(curl -s https://raw.githubusercontent.com/lowdigital/vds-restream/main/vds-restream.sh)
```

Or, if `curl` is not installed:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/lowdigital/vds-restream/main/vds-restream.sh)
```

**Note**: Before running, ensure you trust the source of the script.

## Usage

### Starting a Stream
After installation, you can start streaming to your server:

- **Streaming URL**: `rtmp://<YOUR_SERVER_IP>/live/stream`
- **Replace `<YOUR_SERVER_IP>`**: Use the actual IP address of your server.

Configure your streaming software (e.g., OBS Studio) to use the provided URL.

### Updating Stream Keys
If you need to update your stream keys after installation:

1. Edit the stream keys configuration file:
    ```bash
    nano /home/restream/stream_keys.conf
    ```
2. Update the key values:
    ```ini
    YOUTUBE_KEY="NEW_KEY"
    TWITCH_KEY="NEW_KEY"
    VK_KEY="NEW_KEY"
    ```
3. Save the changes and restart the service:
    ```bash
    systemctl restart restream.service
    ```

## Configuration

### Nginx Configuration
The Nginx configuration file is located at `/etc/nginx/nginx.conf`. The main changes made by the script include:

- Enabling the RTMP module.
- Adding the `rtmp {}` block in a separate file `/etc/nginx/rtmp.conf`.
- Setting up a statistics server on port 8080.

### Firewall Setup
It is recommended to restrict access to the following ports:

- **RTMP Port (1935)**: Limit access to trusted IP addresses or sources.
- **Statistics Port (8080)**: If you do not use the statistics or want to restrict access, close this port.

Example configuration using `ufw`:
```bash
ufw allow from <YOUR_IP> to any port 1935
ufw allow from <YOUR_IP> to any port 8080
ufw deny 1935
ufw deny 8080
```

## Security
- **Stream Keys Storage**: Keys are stored in `/home/restream/stream_keys.conf` with permissions set to `600`, accessible only by the `restream` user.
- **User Isolation**: The restreaming service runs under the system user `restream`, which has no login shell.
- **Access Restrictions**: Configure your firewall to prevent unauthorized access to the RTMP server and statistics.

## Monitoring and Debugging
- **Check Service Status**:
    ```bash
    systemctl status restream.service
    ```

- **View Service Logs**:
    ```bash
    journalctl -u restream.service -f
    ```

- **Test Nginx Configuration**:
    ```bash
    nginx -t
    ```

- **View Nginx Logs**:
    ```bash
    tail -f /var/log/nginx/error.log
    ```

## Uninstallation
To completely remove the restreaming service:

1. Stop and disable the service:
    ```bash
    systemctl stop restream.service
    systemctl disable restream.service
    ```

2. Remove files and directories:
    ```bash
    rm -rf /home/restream
    rm /etc/systemd/system/restream.service
    rm /etc/nginx/rtmp.conf
    rm /etc/nginx/conf.d/stat.conf
    ```

3. Remove the `restream` user:
    ```bash
    userdel restream
    ```

4. Remove packages (optional):
    ```bash
    apt purge -y nginx nginx-common nginx-full libnginx-mod-rtmp ffmpeg
    apt autoremove -y
    ```

## Authors

- Project Author: [low digital](https://t.me/low_digital)

## License

This project is licensed under the MIT License. See the LICENSE file for details.

## Contacts

Follow updates on the Telegram channel: [low digital](https://t.me/low_digital).
