#!/bin/bash

# VPN Telegram Bot - Auto Installer Script
# Автоматический установщик VPN Telegram бота для 3x-ui панели
# Версия: 2.1 (исправлена проверка версии Python)
# Дата: 19.01.2026

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Переменные
BOT_DIR="/root/vpn-bot"
SERVICE_NAME="vpn-bot"
PYTHON_MIN_VERSION="3.8"
LOG_FILE="/var/log/vpn-bot-install.log"

# Функция логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Функция вывода с цветом
print_color() {
    echo -e "${2}${1}${NC}"
}

# Функция проверки ошибок
check_error() {
    if [ $? -ne 0 ]; then
        print_color "❌ Ошибка: $1" "$RED"
        log "ERROR: $1"
        exit 1
    fi
}

# Функция сравнения версий
version_compare() {
    if [[ $1 == $2 ]]; then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2
        fi
    done
    return 0
}

# Приветствие
clear
print_color "╔════════════════════════════════════════════════╗" "$BLUE"
print_color "║   VPN TELEGRAM BOT - АВТОМАТИЧЕСКАЯ УСТАНОВКА  ║" "$BLUE"
print_color "║              для панели 3x-ui                  ║" "$BLUE"
print_color "╚════════════════════════════════════════════════╝" "$BLUE"
echo ""
log "Начало установки VPN Telegram Bot"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
    print_color "❌ Запустите скрипт с правами root (sudo)" "$RED"
    exit 1
fi

# Проверка версии Python
print_color "🔍 Проверка версии Python..." "$YELLOW"
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    log "Обнаружена версия Python: $PYTHON_VERSION"

    version_compare "$PYTHON_VERSION" "$PYTHON_MIN_VERSION"
    result=$?

    if [ $result -eq 2 ]; then
        print_color "❌ Требуется Python >= $PYTHON_MIN_VERSION, обнаружена версия $PYTHON_VERSION" "$RED"
        print_color "Установка более новой версии Python..." "$YELLOW"
        apt update && apt install -y python3 python3-pip python3-venv
        check_error "Не удалось обновить Python3"
        PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
        log "Обновлена версия Python: $PYTHON_VERSION"
    fi

    print_color "✅ Python $PYTHON_VERSION установлен" "$GREEN"
else
    print_color "⚠️  Python3 не найден, устанавливаем..." "$YELLOW"
    apt update && apt install -y python3 python3-pip python3-venv
    check_error "Не удалось установить Python3"
    PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    print_color "✅ Python $PYTHON_VERSION установлен" "$GREEN"
fi

# Проверка существующей установки
if systemctl is-active --quiet $SERVICE_NAME; then
    print_color "⚠️  Обнаружена работающая установка бота" "$YELLOW"
    read -p "Остановить и переустановить? (y/n): " reinstall
    if [ "$reinstall" = "y" ]; then
        systemctl stop $SERVICE_NAME
        log "Остановлен существующий сервис бота"
    else
        print_color "Установка отменена" "$YELLOW"
        exit 0
    fi
fi

# Резервное копирование существующей конфигурации
if [ -d "$BOT_DIR" ] && [ -f "$BOT_DIR/.env" ]; then
    BACKUP_DIR="/root/vpn-bot-backup-$(date +%Y%m%d-%H%M%S)"
    print_color "💾 Создание резервной копии в $BACKUP_DIR..." "$YELLOW"
    cp -r "$BOT_DIR" "$BACKUP_DIR"
    log "Создана резервная копия: $BACKUP_DIR"
fi

# Обновление системы
print_color "📦 Обновление списка пакетов..." "$YELLOW"
apt update >> "$LOG_FILE" 2>&1
check_error "Не удалось обновить список пакетов"

# Установка зависимостей
print_color "📦 Установка системных зависимостей..." "$YELLOW"
apt install -y git python3-pip python3-venv curl wget nano jq >> "$LOG_FILE" 2>&1
check_error "Не удалось установить зависимости"

# Клонирование репозитория
print_color "📥 Загрузка бота из репозитория..." "$YELLOW"
if [ -d "$BOT_DIR" ]; then
    cd "$BOT_DIR"
    git pull >> "$LOG_FILE" 2>&1 || {
        print_color "⚠️  Не удалось обновить репозиторий, клонируем заново..." "$YELLOW"
        cd /root
        rm -rf "$BOT_DIR"
        git clone https://github.com/stalkerj/vpn-telegram-bot.git "$BOT_DIR" >> "$LOG_FILE" 2>&1
    }
else
    git clone https://github.com/stalkerj/vpn-telegram-bot.git "$BOT_DIR" >> "$LOG_FILE" 2>&1
fi
check_error "Не удалось загрузить репозиторий"
log "Репозиторий успешно загружен"

cd "$BOT_DIR"

# Создание виртуального окружения
print_color "🐍 Создание виртуального окружения Python..." "$YELLOW"
python3 -m venv venv >> "$LOG_FILE" 2>&1
check_error "Не удалось создать виртуальное окружение"

# Активация виртуального окружения и установка зависимостей
print_color "📚 Установка Python библиотек..." "$YELLOW"
source venv/bin/activate
pip install --upgrade pip >> "$LOG_FILE" 2>&1
pip install -r requirements.txt >> "$LOG_FILE" 2>&1
check_error "Не удалось установить Python зависимости"
log "Python зависимости установлены"

# Интерактивный сбор конфигурации
print_color "\n🔐 НАСТРОЙКА БОТА" "$BLUE"
print_color "═══════════════════════════════════════════════" "$BLUE"

# Функция валидации IP
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Функция валидации порта
validate_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ ]] && [ $port -ge 1 ] && [ $port -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# Функция валидации URL
validate_url() {
    local url=$1
    if [[ $url =~ ^https?:// ]]; then
        return 0
    else
        return 1
    fi
}

# Telegram Bot Token
while true; do
    read -p "Введите Telegram Bot Token (@BotFather): " BOT_TOKEN
    if [ -n "$BOT_TOKEN" ] && [[ $BOT_TOKEN =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
        # Проверка токена через API
        print_color "🔍 Проверка токена через Telegram API..." "$YELLOW"
        response=$(curl -s "https://api.telegram.org/bot$BOT_TOKEN/getMe")
        if echo "$response" | grep -q '"ok":true'; then
            print_color "✅ Токен валиден" "$GREEN"
            break
        else
            print_color "❌ Токен недействителен, проверьте правильность" "$RED"
        fi
    else
        print_color "❌ Неверный формат токена" "$RED"
    fi
done

# Admin Telegram ID
while true; do
    read -p "Введите ваш Telegram ID (получить: @userinfobot): " ADMIN_ID
    if [[ $ADMIN_ID =~ ^[0-9]+$ ]]; then
        break
    else
        print_color "❌ ID должен содержать только цифры" "$RED"
    fi
done

# 3x-ui Panel URL
while true; do
    read -p "Введите URL панели 3x-ui (https://ip:port): " PANEL_URL
    if validate_url "$PANEL_URL"; then
        # Проверка доступности панели
        print_color "🔍 Проверка доступности панели..." "$YELLOW"
        if curl -k -s -o /dev/null -w "%{http_code}" "$PANEL_URL" | grep -q "200\|302\|401"; then
            print_color "✅ Панель доступна" "$GREEN"
            break
        else
            print_color "⚠️  Панель недоступна, но продолжаем..." "$YELLOW"
            read -p "Продолжить? (y/n): " continue_anyway
            if [ "$continue_anyway" = "y" ]; then
                break
            fi
        fi
    else
        print_color "❌ Неверный формат URL (должен начинаться с http:// или https://)" "$RED"
    fi
done

# Извлечение IP и порта из URL для проверки
PANEL_HOST=$(echo "$PANEL_URL" | sed -E 's|https?://([^:/]+).*|\1|')
log "IP панели: $PANEL_HOST"

# 3x-ui Admin Username
read -p "Логин администратора 3x-ui: " PANEL_USERNAME

# 3x-ui Admin Password
read -sp "Пароль администратора 3x-ui: " PANEL_PASSWORD
echo ""

# Database name
read -p "Имя базы данных (по умолчанию: vpn_bot): " DB_NAME
DB_NAME=${DB_NAME:-vpn_bot}

# Генерация секретного ключа
SECRET_KEY=$(openssl rand -hex 32)
log "Сгенерирован секретный ключ"

# Показ итоговой конфигурации
print_color "\n📋 ИТОГОВАЯ КОНФИГУРАЦИЯ:" "$BLUE"
print_color "═══════════════════════════════════════════════" "$BLUE"
echo "Telegram Bot Token: ${BOT_TOKEN:0:10}...${BOT_TOKEN: -5}"
echo "Admin Telegram ID: $ADMIN_ID"
echo "3x-ui Panel URL: $PANEL_URL"
echo "3x-ui Username: $PANEL_USERNAME"
echo "Database: $DB_NAME"
print_color "═══════════════════════════════════════════════" "$BLUE"
read -p "\nПродолжить установку с этими параметрами? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    print_color "Установка отменена" "$YELLOW"
    exit 0
fi

# Создание .env файла
print_color "\n📝 Создание файла конфигурации..." "$YELLOW"
cat > "$BOT_DIR/.env" << EOF
# Telegram Bot Configuration
BOT_TOKEN=$BOT_TOKEN
ADMIN_ID=$ADMIN_ID

# 3x-ui Panel Configuration
PANEL_URL=$PANEL_URL
PANEL_USERNAME=$PANEL_USERNAME
PANEL_PASSWORD=$PANEL_PASSWORD

# Database Configuration
DB_NAME=$DB_NAME
DB_PATH=./data/$DB_NAME.db

# Security
SECRET_KEY=$SECRET_KEY

# Logging
LOG_LEVEL=INFO
LOG_FILE=./logs/bot.log

# Generated: $(date)
EOF

# Установка безопасных прав доступа
chmod 600 "$BOT_DIR/.env"
log "Файл .env создан с правами 600"

# Создание необходимых директорий
mkdir -p "$BOT_DIR/data"
mkdir -p "$BOT_DIR/logs"
log "Созданы директории data и logs"

# Создание systemd service
print_color "⚙️  Создание systemd службы..." "$YELLOW"
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=VPN Telegram Bot for 3x-ui
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$BOT_DIR
Environment="PATH=$BOT_DIR/venv/bin"
ExecStart=$BOT_DIR/venv/bin/python $BOT_DIR/bot.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vpn-bot

[Install]
WantedBy=multi-user.target
EOF

log "Systemd service создан"

# Перезагрузка systemd
systemctl daemon-reload
check_error "Не удалось перезагрузить systemd"

# Включение автозапуска
systemctl enable $SERVICE_NAME >> "$LOG_FILE" 2>&1
check_error "Не удалось включить автозапуск"
log "Автозапуск включен"

# Создание скрипта управления серверами
print_color "🔧 Создание вспомогательных скриптов..." "$YELLOW"
cat > "$BOT_DIR/manage_servers.py" << 'EOFPYTHON'
#!/usr/bin/env python3
import sys
import sqlite3
import os
from dotenv import load_dotenv

load_dotenv()

DB_PATH = os.getenv('DB_PATH', './data/vpn_bot.db')

def list_servers():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT id, panel_url, username FROM servers")
    servers = cursor.fetchall()
    conn.close()

    if servers:
        print("\nНастроенные серверы:")
        for srv in servers:
            print(f"  ID: {srv[0]} | URL: {srv[1]} | User: {srv[2]}")
    else:
        print("Серверы не настроены")

def add_server(panel_url, username, password):
    from urllib.parse import urlparse

    parsed = urlparse(panel_url)
    server_ip = parsed.hostname

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO servers (panel_url, server_ip, username, password) VALUES (?, ?, ?, ?)",
        (panel_url, server_ip, username, password)
    )
    conn.commit()
    conn.close()
    print(f"✅ Сервер {panel_url} добавлен")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: manage_servers.py [list|add]")
        sys.exit(1)

    command = sys.argv[1]

    if command == "list":
        list_servers()
    elif command == "add" and len(sys.argv) == 5:
        add_server(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        print("Invalid command")
EOFPYTHON

chmod +x "$BOT_DIR/manage_servers.py"

# Создание команды vpn-bot для быстрого доступа
print_color "🔧 Создание команды vpn-bot..." "$YELLOW"
cat > /usr/local/bin/vpn-bot << 'EOFCMD'
#!/bin/bash

BOT_DIR="/root/vpn-bot"
SERVICE_NAME="vpn-bot"

show_menu() {
    clear
    echo "╔════ VPN TELEGRAM BOT: МЕНЮ ═══════════════╗"
    echo "║ 1) Статус бота                            ║"
    echo "║ 2) Список серверов                        ║"
    echo "║ 3) Добавить новый сервер                  ║"
    echo "║ 4) Перезапустить бота                     ║"
    echo "║ 5) Показать логи                          ║"
    echo "║ 6) Редактировать конфигурацию             ║"
    echo "║ 7) Обновить бота                          ║"
    echo "║ 8) Полное удаление бота                   ║"
    echo "║ 0) Выход                                  ║"
    echo "╚═══════════════════════════════════════════╝"
}

while true; do
    show_menu
    read -p "Выберите действие: " choice

    case $choice in
        1)
            echo ""
            systemctl status $SERVICE_NAME --no-pager
            echo ""
            read -p "Нажмите Enter для продолжения..."
            ;;
        2)
            echo ""
            if [ -f "$BOT_DIR/.env" ]; then
                echo "Настроенные серверы:"
                grep "PANEL_URL" "$BOT_DIR/.env" | cut -d'=' -f2
                echo ""
                if [ -f "$BOT_DIR/manage_servers.py" ]; then
                    cd "$BOT_DIR"
                    source venv/bin/activate
                    python3 manage_servers.py list
                fi
            else
                echo "❌ Файл конфигурации не найден"
            fi
            echo ""
            read -p "Нажмите Enter для продолжения..."
            ;;
        3)
            echo ""
            echo "Добавление нового сервера 3x-ui"
            echo "════════════════════════════════"
            read -p "URL панели (https://ip:port): " panel_url
            read -p "Логин администратора: " admin_user
            read -sp "Пароль администратора: " admin_pass
            echo ""

            if [ -f "$BOT_DIR/manage_servers.py" ]; then
                cd "$BOT_DIR"
                source venv/bin/activate
                python3 manage_servers.py add "$panel_url" "$admin_user" "$admin_pass"
            else
                echo "❌ Скрипт управления серверами не найден"
            fi
            echo ""
            read -p "Нажмите Enter для продолжения..."
            ;;
        4)
            echo ""
            echo "Перезапуск бота..."
            systemctl restart $SERVICE_NAME
            sleep 2
            systemctl status $SERVICE_NAME --no-pager
            echo ""
            read -p "Нажмите Enter для продолжения..."
            ;;
        5)
            echo ""
            echo "Последние 100 строк логов (Ctrl+C для выхода):"
            echo "════════════════════════════════════════════════"
            journalctl -u $SERVICE_NAME -n 100 -f
            ;;
        6)
            nano "$BOT_DIR/.env"
            echo ""
            read -p "Перезапустить бота для применения изменений? (y/n): " restart
            if [ "$restart" = "y" ]; then
                systemctl restart $SERVICE_NAME
                echo "✅ Бот перезапущен"
                sleep 2
            fi
            ;;
        7)
            echo ""
            echo "Обновление бота..."
            cd "$BOT_DIR"
            git pull
            source venv/bin/activate
            pip install -r requirements.txt --upgrade
            systemctl restart $SERVICE_NAME
            echo "✅ Бот обновлен и перезапущен"
            echo ""
            read -p "Нажмите Enter для продолжения..."
            ;;
        8)
            echo ""
            read -p "⚠️  Вы уверены? Это удалит ВСЕ данные бота! (yes/no): " confirm
            if [ "$confirm" = "yes" ]; then
                echo "Остановка службы..."
                systemctl stop $SERVICE_NAME 2>/dev/null
                systemctl disable $SERVICE_NAME 2>/dev/null

                echo "Удаление файлов..."
                rm -f /etc/systemd/system/$SERVICE_NAME.service
                rm -rf $BOT_DIR
                rm -f /usr/local/bin/vpn-bot

                systemctl daemon-reload
                echo "✅ Бот полностью удален"
                sleep 2
                exit 0
            else
                echo "Удаление отменено"
                sleep 2
            fi
            ;;
        0)
            exit 0
            ;;
        *)
            echo ""
            echo "❌ Неверный выбор"
            sleep 2
            ;;
    esac
done
EOFCMD

chmod +x /usr/local/bin/vpn-bot
log "Команда vpn-bot создана"

# Запуск бота
print_color "\n🚀 Запуск бота..." "$YELLOW"
systemctl start $SERVICE_NAME
sleep 3

# Проверка статуса
if systemctl is-active --quiet $SERVICE_NAME; then
    print_color "✅ Бот успешно запущен!" "$GREEN"
    log "Бот успешно запущен"
else
    print_color "❌ Ошибка запуска бота. Проверьте логи: journalctl -u $SERVICE_NAME -n 50" "$RED"
    log "ERROR: Бот не запустился"
    exit 1
fi

# Показ статуса
print_color "\n📊 Статус службы:" "$BLUE"
systemctl status $SERVICE_NAME --no-pager

# Завершение
print_color "\n╔════════════════════════════════════════════════╗" "$GREEN"
print_color "║          УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!          ║" "$GREEN"
print_color "╚════════════════════════════════════════════════╝" "$GREEN"
print_color "\n📌 Полезные команды:" "$BLUE"
print_color "   vpn-bot              - Меню управления ботом" "$YELLOW"
print_color "   systemctl status vpn-bot - Статус службы" "$YELLOW"
print_color "   journalctl -u vpn-bot -f - Просмотр логов" "$YELLOW"
print_color "\n💚 Поддержите разработчика:" "$GREEN"
print_color "   GitHub: https://github.com/stalkerj/vpn-telegram-bot" "$BLUE"

log "Установка завершена успешно"
echo ""
