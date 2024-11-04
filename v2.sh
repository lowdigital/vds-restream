#!/bin/bash

# Немедленный выход при ошибке
set -e

# Функция для вывода сообщений
log() {
    echo -e "\e[32m$1\e[0m"
}

# Проверка, выполняется ли скрипт от имени root
if [ "$EUID" -ne 0 ]; then
    echo "Пожалуйста, запустите скрипт от имени root."
    exit 1
fi

# Шаг 1: Удаление Nginx и связанных пакетов (если они установлены)
log "Удаление существующих установок Nginx..."
apt purge -y nginx nginx-common nginx-full libnginx-mod-rtmp || true
apt autoremove -y || true
rm -rf /etc/nginx

# Шаг 2: Обновление списка пакетов
log "Обновление списка пакетов..."
apt update

# Шаг 3: Установка Nginx
log "Установка Nginx..."
apt install -y nginx

# Шаг 4: Проверка работы Nginx
log "Проверка работы Nginx..."
systemctl start nginx
systemctl enable nginx

# Шаг 5: Установка модуля RTMP
log "Установка модуля RTMP..."
apt install -y libnginx-mod-rtmp

# Шаг 6: Настройка RTMP
log "Настройка RTMP..."
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

# Шаг 7: Включение rtmp.conf в nginx.conf после блока events {} и перед http {}
NGINX_CONF="/etc/nginx/nginx.conf"

# Убедимся, что блок events { } существует
if ! grep -q "events {" "$NGINX_CONF"; then
    sed -i '/^pid/a events {\n    worker_connections 1024;\n}' "$NGINX_CONF"
    log "Добавлен блок events { } в nginx.conf"
fi

# Если в блоке events { } нет worker_connections, добавим его
if ! grep -q "worker_connections" "$NGINX_CONF"; then
    sed -i '/events {/a \    worker_connections 1024;' "$NGINX_CONF"
fi

# Включаем rtmp.conf после блока events { }
if ! grep -q "include /etc/nginx/rtmp.conf;" "$NGINX_CONF"; then
    sed -i '/events {/,/}/!b;/}/a include /etc/nginx/rtmp.conf;' "$NGINX_CONF"
    log "Добавлен include /etc/nginx/rtmp.conf; после блока events { }"
fi

# Убедимся, что блок http { } существует и включает файлы из conf.d
if ! grep -q "^http {" "$NGINX_CONF"; then
    echo -e "\nhttp {\n    include /etc/nginx/mime.types;\n    default_type application/octet-stream;\n    include /etc/nginx/conf.d/*.conf;\n}" >> "$NGINX_CONF"
    log "Добавлен блок http { } в nginx.conf"
else
    # Убедимся, что include /etc/nginx/conf.d/*.conf; находится внутри блока http { }
    if ! grep -q "include /etc/nginx/conf.d/\*\.conf;" "$NGINX_CONF"; then
        sed -i '/^http {/a \    include /etc/nginx/conf.d/*.conf;' "$NGINX_CONF"
        log "Добавлен include /etc/nginx/conf.d/*.conf; в блок http { }"
    fi
fi

# Шаг 8: Настройка статистики RTMP
log "Настройка статистики RTMP..."
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

# Шаг 9: Проверка конфигурации Nginx
log "Проверка конфигурации Nginx..."
nginx -t

# Шаг 10: Перезапуск Nginx
log "Перезапуск Nginx..."
systemctl restart nginx

# Шаг 11: Создание пользователя для ретрансляции
log "Создание пользователя restream..."
useradd -r -s /usr/sbin/nologin restream || true

# Шаг 12: Установка FFmpeg
log "Установка FFmpeg..."
apt install -y ffmpeg

# Шаг 13: Запрос ключей потоков у пользователя
log "Запрос ключей потоков..."
read -p "Введите ключ потока YouTube (оставьте пустым, если не требуется): " YOUTUBE_KEY
read -p "Введите ключ потока Twitch (оставьте пустым, если не требуется): " TWITCH_KEY
read -p "Введите ключ потока VK (оставьте пустым, если не требуется): " VK_KEY

# Шаг 14: Создание файла конфигурации с ключами
log "Создание файла конфигурации с ключами..."
cat > /home/restream/stream_keys.conf <<EOF
YOUTUBE_KEY="$YOUTUBE_KEY"
TWITCH_KEY="$TWITCH_KEY"
VK_KEY="$VK_KEY"
EOF

# Установка прав доступа к файлу конфигурации
chmod 600 /home/restream/stream_keys.conf
chown restream:restream /home/restream/stream_keys.conf

# Шаг 15: Создание скрипта ретрансляции
log "Создание скрипта ретрансляции..."
mkdir -p /home/restream
chown restream:restream /home/restream

cat > /home/restream/restream.sh <<'EOF'
#!/bin/bash

# Загрузка ключей потоков из файла конфигурации
source /home/restream/stream_keys.conf

# Входящий поток от OBS или другого источника
INPUT_STREAM="rtmp://localhost/live/stream"

# URL-адреса для потоковой передачи
YOUTUBE_URL="${YOUTUBE_KEY:+rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_KEY}"
TWITCH_URL="${TWITCH_KEY:+rtmp://live.twitch.tv/app/$TWITCH_KEY}"
VK_PLAY_URL="${VK_KEY:+rtmp://vsuc.okcdn.ru/input/$VK_KEY}"

# Построение параметров вывода ffmpeg
OUTPUT_OPTIONS=()
[ -n "$YOUTUBE_URL" ] && OUTPUT_OPTIONS+=("-c:v copy -c:a copy -f flv \"$YOUTUBE_URL\"")
[ -n "$TWITCH_URL" ] && OUTPUT_OPTIONS+=("-c:v copy -c:a copy -f flv \"$TWITCH_URL\"")
[ -n "$VK_PLAY_URL" ] && OUTPUT_OPTIONS+=("-c:v copy -c:a copy -f flv \"$VK_PLAY_URL\"")

# Проверка, есть ли хотя бы один выходной поток
if [ ${#OUTPUT_OPTIONS[@]} -eq 0 ]; then
    echo "$(date) - Нет настроенных выходных потоков. Проверьте файл /home/restream/stream_keys.conf"
    sleep 10
    exit 1
fi

# Функция ретрансляции на указанные платформы
relay_stream() {
    echo "$(date) - Начало ретрансляции на платформы..."
    ffmpeg -re -i "$INPUT_STREAM" ${OUTPUT_OPTIONS[@]}
}

# Основной цикл
while true
do
    relay_stream
    echo "$(date) - Перезапуск потока через 5 секунд..."
    sleep 5
done
EOF

chmod +x /home/restream/restream.sh
chown restream:restream /home/restream/restream.sh

# Шаг 16: Создание сервиса systemd для ретрансляции
log "Создание сервиса systemd для ретрансляции..."
cat > /etc/systemd/system/restream.service <<EOF
[Unit]
Description=Сервис ретрансляции для YouTube, Twitch и VK
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

# Шаг 17: Перезагрузка systemd и запуск сервиса
log "Запуск сервиса ретрансляции..."
systemctl daemon-reload
systemctl enable restream.service
systemctl start restream.service

log "Установка завершена! Сервис ретрансляции установлен, включен при запуске и запущен."
