#!/bin/bash

# VPN Manager Bot - Installation Script
# Скрипт установки и управления VPN Manager Bot

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

INSTALL_DIR="/opt/vpn-manager-bot"
SERVICE_NAME="vpn-manager-bot"
VENV_DIR="$INSTALL_DIR/venv"

# Функция вывода цветного текста
print_color() {
    color=$1
    message=$2
    echo -e "${color}${message}${NC}"
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_color "$RED" "Ошибка: Этот скрипт требует прав root"
        print_color "$YELLOW" "Запустите: sudo bash install-vpn-bot.sh"
        exit 1
    fi
}

# Проверка операционной системы
check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        print_color "$RED" "Не удалось определить операционную систему"
        exit 1
    fi

    print_color "$BLUE" "Обнаружена ОС: $OS $VERSION"
}

# Установка зависимостей
install_dependencies() {
    print_color "$BLUE" "Установка зависимостей..."

    if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
        apt-get update
        apt-get install -y python3 python3-pip python3-venv git curl wget
    elif [[ "$OS" == "centos" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "fedora" ]]; then
        yum install -y python3 python3-pip git curl wget
    else
        print_color "$RED" "Неподдерживаемая ОС: $OS"
        exit 1
    fi

    print_color "$GREEN" "✓ Зависимости установлены"
}

# Создание структуры каталогов
create_directories() {
    print_color "$BLUE" "Создание структуры каталогов..."

    mkdir -p "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/logs"
    mkdir -p "$INSTALL_DIR/data"
    mkdir -p "$INSTALL_DIR/backups"

    print_color "$GREEN" "✓ Каталоги созданы"
}

# Скачивание файлов бота
download_bot_files() {
    print_color "$BLUE" "Скачивание файлов бота..."

    cd "$INSTALL_DIR"

    # Если указан GitHub репозиторий, клонируем его
    if [[ -n "$GITHUB_REPO" ]]; then
        print_color "$BLUE" "Клонирование из GitHub: $GITHUB_REPO"
        git clone "$GITHUB_REPO" temp_repo
        mv temp_repo/* .
        mv temp_repo/.* . 2>/dev/null || true
        rm -rf temp_repo
    else
        print_color "$YELLOW" "Файлы бота должны быть размещены в $INSTALL_DIR"
        print_color "$YELLOW" "Убедитесь, что файл vpn_bot.py находится в этой директории"
    fi

    print_color "$GREEN" "✓ Файлы бота готовы"
}

# Создание виртуального окружения
create_virtualenv() {
    print_color "$BLUE" "Создание виртуального окружения Python..."

    cd "$INSTALL_DIR"
    python3 -m venv "$VENV_DIR"

    print_color "$GREEN" "✓ Виртуальное окружение создано"
}

# Установка Python зависимостей
install_python_deps() {
    print_color "$BLUE" "Установка Python зависимостей..."

    source "$VENV_DIR/bin/activate"

    if [[ -f "$INSTALL_DIR/requirements.txt" ]]; then
        pip install --upgrade pip
        pip install -r "$INSTALL_DIR/requirements.txt"
    else
        print_color "$YELLOW" "requirements.txt не найден, устанавливаю базовые зависимости..."
        pip install --upgrade pip
        pip install python-telegram-bot requests schedule
    fi

    deactivate

    print_color "$GREEN" "✓ Python зависимости установлены"
}

# Настройка конфигурации
setup_config() {
    print_color "$BLUE" "Настройка конфигурации..."

    if [[ ! -f "$INSTALL_DIR/.env" ]]; then
        cat > "$INSTALL_DIR/.env" << EOF
# Telegram Bot Configuration
TELEGRAM_BOT_TOKEN=your_bot_token_here
ADMIN_USER_IDS=123456789,987654321

# 3X-UI Panel Configuration
PANEL_URLS=https://panel1.example.com,https://panel2.example.com
PANEL_USERNAMES=admin,admin
PANEL_PASSWORDS=password1,password2

# Database Configuration
DATABASE_PATH=$INSTALL_DIR/data/vpn_bot.db

# Logging Configuration
LOG_FILE=$INSTALL_DIR/logs/bot.log
LOG_LEVEL=INFO

# Monitoring Configuration
ENABLE_MONITORING=true
CHECK_INTERVAL=300
ALERT_ADMIN=true

# Report Configuration
DAILY_REPORT_TIME=09:00
WEEKLY_REPORT_DAY=monday
WEEKLY_REPORT_TIME=09:00
EOF

        print_color "$YELLOW" "⚠ Конфигурационный файл создан: $INSTALL_DIR/.env"
        print_color "$YELLOW" "⚠ ВАЖНО: Отредактируйте файл .env перед запуском бота!"
        print_color "$YELLOW" "   nano $INSTALL_DIR/.env"
    else
        print_color "$GREEN" "✓ Конфигурационный файл уже существует"
    fi
}

# Создание systemd service
create_systemd_service() {
    print_color "$BLUE" "Создание systemd service..."

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=VPN Manager Telegram Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$VENV_DIR/bin"
ExecStart=$VENV_DIR/bin/python $INSTALL_DIR/vpn_bot.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"

    print_color "$GREEN" "✓ Systemd service создан и активирован"
}

# Создание скрипта управления
create_management_script() {
    print_color "$BLUE" "Создание скрипта управления..."

    cat > "/usr/local/bin/vpn-bot" << 'EOF'
#!/bin/bash

SERVICE_NAME="vpn-manager-bot"
INSTALL_DIR="/opt/vpn-manager-bot"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_color() {
    color=$1
    message=$2
    echo -e "${color}${message}${NC}"
}

show_menu() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║   VPN Manager Bot - Управление         ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "1) Показать статус бота"
    echo "2) Запустить бота"
    echo "3) Остановить бота"
    echo "4) Перезапустить бота"
    echo "5) Показать логи (последние 50 строк)"
    echo "6) Показать логи в реальном времени"
    echo "7) Редактировать конфигурацию"
    echo "8) Обновить бота из GitHub"
    echo "9) Создать резервную копию"
    echo "10) Восстановить из резервной копии"
    echo "11) Полностью удалить бота"
    echo "0) Выход"
    echo ""
    echo -n "Выберите действие: "
}

check_status() {
    systemctl status "$SERVICE_NAME" --no-pager
}

start_bot() {
    print_color "$BLUE" "Запуск бота..."
    systemctl start "$SERVICE_NAME"
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_color "$GREEN" "✓ Бот успешно запущен"
    else
        print_color "$RED" "✗ Ошибка при запуске бота"
    fi
}

stop_bot() {
    print_color "$BLUE" "Остановка бота..."
    systemctl stop "$SERVICE_NAME"
    sleep 2
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        print_color "$GREEN" "✓ Бот успешно остановлен"
    else
        print_color "$RED" "✗ Ошибка при остановке бота"
    fi
}

restart_bot() {
    print_color "$BLUE" "Перезапуск бота..."
    systemctl restart "$SERVICE_NAME"
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_color "$GREEN" "✓ Бот успешно перезапущен"
    else
        print_color "$RED" "✗ Ошибка при перезапуске бота"
    fi
}

show_logs() {
    journalctl -u "$SERVICE_NAME" -n 50 --no-pager
}

follow_logs() {
    print_color "$BLUE" "Логи в реальном времени (Ctrl+C для выхода)..."
    journalctl -u "$SERVICE_NAME" -f
}

edit_config() {
    if command -v nano &> /dev/null; then
        nano "$INSTALL_DIR/.env"
    elif command -v vi &> /dev/null; then
        vi "$INSTALL_DIR/.env"
    else
        print_color "$RED" "Редактор не найден. Установите nano или vi"
    fi
}

update_bot() {
    print_color "$BLUE" "Обновление бота из GitHub..."
    cd "$INSTALL_DIR"

    if [[ -d .git ]]; then
        systemctl stop "$SERVICE_NAME"
        git pull
        source venv/bin/activate
        pip install -r requirements.txt 2>/dev/null || true
        deactivate
        systemctl start "$SERVICE_NAME"
        print_color "$GREEN" "✓ Бот обновлен"
    else
        print_color "$RED" "✗ Это не Git репозиторий"
    fi
}

create_backup() {
    print_color "$BLUE" "Создание резервной копии..."
    BACKUP_NAME="backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    BACKUP_PATH="$INSTALL_DIR/backups/$BACKUP_NAME"

    mkdir -p "$INSTALL_DIR/backups"
    tar -czf "$BACKUP_PATH" -C "$INSTALL_DIR" data .env 2>/dev/null || true

    print_color "$GREEN" "✓ Резервная копия создана: $BACKUP_PATH"
}

restore_backup() {
    print_color "$YELLOW" "Доступные резервные копии:"
    ls -lh "$INSTALL_DIR/backups/" 2>/dev/null || print_color "$RED" "Резервные копии не найдены"
    echo ""
    echo -n "Введите имя файла резервной копии: "
    read backup_file

    if [[ -f "$INSTALL_DIR/backups/$backup_file" ]]; then
        print_color "$BLUE" "Восстановление из резервной копии..."
        systemctl stop "$SERVICE_NAME"
        tar -xzf "$INSTALL_DIR/backups/$backup_file" -C "$INSTALL_DIR"
        systemctl start "$SERVICE_NAME"
        print_color "$GREEN" "✓ Восстановление завершено"
    else
        print_color "$RED" "✗ Файл не найден"
    fi
}

uninstall_bot() {
    print_color "$RED" "╔════════════════════════════════════════╗"
    print_color "$RED" "║      ВНИМАНИЕ: УДАЛЕНИЕ БОТА           ║"
    print_color "$RED" "╚════════════════════════════════════════╝"
    print_color "$YELLOW" "Это действие удалит:"
    echo "  - Все файлы бота ($INSTALL_DIR)"
    echo "  - Базу данных и логи"
    echo "  - Systemd service"
    echo "  - Этот скрипт управления"
    echo ""
    print_color "$RED" "Это действие НЕОБРАТИМО!"
    echo ""
    echo -n "Введите 'DELETE' для подтверждения: "
    read confirmation1

    if [[ "$confirmation1" != "DELETE" ]]; then
        print_color "$YELLOW" "Удаление отменено"
        return
    fi

    echo ""
    print_color "$RED" "Вы уверены? Это последнее предупреждение!"
    echo -n "Введите 'YES' для окончательного подтверждения: "
    read confirmation2

    if [[ "$confirmation2" != "YES" ]]; then
        print_color "$YELLOW" "Удаление отменено"
        return
    fi

    print_color "$BLUE" "Удаление бота..."

    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload

    rm -rf "$INSTALL_DIR"
    rm -f "/usr/local/bin/vpn-bot"

    print_color "$GREEN" "✓ Бот полностью удален"
    print_color "$BLUE" "Скрипт завершает работу..."
    exit 0
}

# Главный цикл
while true; do
    show_menu
    read choice

    case $choice in
        1) check_status ;;
        2) start_bot ;;
        3) stop_bot ;;
        4) restart_bot ;;
        5) show_logs ;;
        6) follow_logs ;;
        7) edit_config ;;
        8) update_bot ;;
        9) create_backup ;;
        10) restore_backup ;;
        11) uninstall_bot ;;
        0) print_color "$BLUE" "До свидания!"; exit 0 ;;
        *) print_color "$RED" "Неверный выбор" ;;
    esac

    echo ""
    echo -n "Нажмите Enter для продолжения..."
    read
done
EOF

    chmod +x "/usr/local/bin/vpn-bot"

    print_color "$GREEN" "✓ Скрипт управления создан: vpn-bot"
}

# Финальная настройка прав
set_permissions() {
    print_color "$BLUE" "Настройка прав доступа..."

    chown -R root:root "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"
    chmod 600 "$INSTALL_DIR/.env"

    print_color "$GREEN" "✓ Права доступа настроены"
}

# Главная функция установки
main_install() {
    print_color "$GREEN" "╔════════════════════════════════════════╗"
    print_color "$GREEN" "║  VPN Manager Bot - Установка           ║"
    print_color "$GREEN" "╚════════════════════════════════════════╝"
    echo ""

    check_root
    check_os
    install_dependencies
    create_directories
    download_bot_files
    create_virtualenv
    install_python_deps
    setup_config
    create_systemd_service
    create_management_script
    set_permissions

    echo ""
    print_color "$GREEN" "╔════════════════════════════════════════╗"
    print_color "$GREEN" "║     Установка завершена успешно!       ║"
    print_color "$GREEN" "╚════════════════════════════════════════╝"
    echo ""
    print_color "$YELLOW" "Следующие шаги:"
    echo "1. Отредактируйте конфигурацию: nano $INSTALL_DIR/.env"
    echo "2. Запустите меню управления: vpn-bot"
    echo ""
    print_color "$BLUE" "Для управленияботом используйте команду: vpn-bot"
    echo ""

    echo -n "Открыть меню управления сейчас? (y/n): "
    read open_menu

    if [[ "$open_menu" == "y" ]] || [[ "$open_menu" == "Y" ]]; then
        /usr/local/bin/vpn-bot
    fi
}

# Запуск установки
main_install
