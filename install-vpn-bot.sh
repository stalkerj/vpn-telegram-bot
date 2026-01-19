#!/bin/bash

# ============================================
# VPN Telegram Bot - Auto Installer
# Версия: 3.9 (добавлена валидация ввода данных и добавление серверов)
# ============================================


# ============================================
# ФУНКЦИИ ВАЛИДАЦИИ ВВОДА
# ============================================

# Валидация Telegram Bot Token (формат: 1234567890:ABCdefGHIjklMNOpqrsTUVwxyz)
validate_bot_token() {
    local token="$1"
    # Формат: 9-10 цифр, двоеточие, 35 символов (буквы, цифры, дефис, подчеркивание)
    if [[ "$token" =~ ^[0-9]{9,10}:[A-Za-z0-9_-]{35}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Валидация Telegram Admin ID (только цифры)
validate_admin_id() {
    local id="$1"
    # Только цифры, минимум 5 символов
    if [[ "$id" =~ ^[0-9]{5,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Валидация URL панели (https://IP:PORT)
validate_panel_url() {
    local url="$1"
    # Формат: https://IP:PORT (без слеша в конце)
    if [[ "$url" =~ ^https://[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]{1,5}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Валидация пути к панели (должен начинаться с /)
validate_panel_path() {
    local path="$1"
    # Должен начинаться с / и содержать хотя бы один символ после
    if [[ "$path" =~ ^/[A-Za-z0-9_-]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Валидация IP адреса
validate_ip() {
    local ip="$1"
    # Формат: X.X.X.X где X от 0 до 255
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        # Проверяем что каждый октет <= 255
        IFS='.' read -ra OCTETS <<< "$ip"
        for octet in "${OCTETS[@]}"; do
            if [ "$octet" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}



set -e  # Остановить на ошибке

# --- Цветовые переменные ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Функции красивого вывода ---
print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║        VPN TELEGRAM BOT INSTALLER v${SCRIPT_VERSION}  ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_header() {
    echo ""
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${PURPLE}  $1${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Спиннер для длительных операций
show_spinner() {
    local pid=$1
    local message=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    echo -n "   "
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %10 ))
        printf "\r   ${CYAN}${spin:$i:1}${NC} $message"
        sleep 0.1
    done
    printf "\r   ${GREEN}✓${NC} $message\n"
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
       print_error "Этот скрипт должен быть запущен от root"
       print_info "Запустите: sudo bash $0"
       exit 1
    fi
}

# Определение ОС
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        print_error "Не удалось определить ОС"
        exit 1
    fi

    print_info "Обнаружена ОС: $OS $VER"
}

# Проверка системных требований
check_requirements() {
    print_header "🔍 Проверка системных требований"

    # Проверка RAM
    total_ram=$(free -m | awk '/^Mem:/{print $2}')
    if [ $total_ram -lt 400 ]; then
        print_warning "Обнаружено ${total_ram}MB RAM. Рекомендуется минимум 512MB"
    else
        print_success "RAM: ${total_ram}MB"
    fi

    # Проверка свободного места
    free_space=$(df -m / | awk 'NR==2 {print $4}')
    if [ $free_space -lt 500 ]; then
        print_warning "Свободно ${free_space}MB. Рекомендуется минимум 1GB"
    else
        print_success "Свободное место: ${free_space}MB"
    fi
}

# Обновление системы с прогрессом
update_system() {
    print_header "📦 Обновление системы"

    if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
        # Обновление списков пакетов
        print_info "Обновляем списки пакетов..."
        {
            apt update -y > /tmp/apt_update.log 2>&1
        } &
        show_spinner $! "Загрузка информации о пакетах"
        print_success "Списки пакетов обновлены"

        # Подсчет пакетов для обновления
        upgradable_count=$(apt list --upgradable 2>/dev/null | grep -c "upgradable from" || echo "0")

        # Проверяем, что это число
        if ! [[ "$upgradable_count" =~ ^[0-9]+$ ]]; then
            upgradable_count=0
        fi

        if [ "$upgradable_count" -gt 0 ]; then
            print_info "Найдено пакетов для обновления: $upgradable_count"
            print_info "Обновляем установленные пакеты (это может занять 5-10 минут)..."
            echo ""

            # Показываем прогресс обновления в реальном времени
            {
                DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" 2>&1 | while IFS= read -r line; do
                    # Показываем только важные строки
                    if [[ "$line" =~ "Setting up" ]] || [[ "$line" =~ "Unpacking" ]] || [[ "$line" =~ "Processing" ]]; then
                        echo "   ${CYAN}→${NC} ${line:0:70}"
                    fi
                done
            }

            echo ""
            print_success "Система обновлена"
        else
            print_success "Все пакеты уже актуальны"
        fi
    else
        print_warning "Автоматическое обновление не поддерживается для $OS"
    fi
}

# Установка зависимостей с прогрессом
install_dependencies() {
    print_header "📦 Установка зависимостей"

    local packages="python3 python3-pip python3-venv git curl wget nano ufw qrencode"

    print_info "Проверяем необходимые пакеты..."

    if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
        # Проверяем, какие пакеты уже установлены
        local to_install=""
        local already_installed=""

        for pkg in $packages; do
            if dpkg -l | grep -q "^ii  $pkg "; then
                already_installed="$already_installed $pkg"
            else
                to_install="$to_install $pkg"
            fi
        done

        if [ -n "$already_installed" ]; then
            print_success "Уже установлены:${already_installed}"
        fi

        if [ -n "$to_install" ]; then
            print_info "Устанавливаем:${to_install}"
            echo ""

            {
                DEBIAN_FRONTEND=noninteractive apt install -y $to_install 2>&1 | while IFS= read -r line; do
                    if [[ "$line" =~ "Setting up" ]] || [[ "$line" =~ "Unpacking" ]]; then
                        echo "   ${CYAN}→${NC} ${line:0:70}"
                    fi
                done
            }

            echo ""
        fi

        print_success "Все пакеты установлены"
    else
        print_error "Неподдерживаемая ОС: $OS"
        exit 1
    fi

    # Проверка Python версии
    python_version=$(python3 --version | awk '{print $2}')
    print_success "Python версия: $python_version"
}

# Сбор данных конфигурации
collect_config() {
    print_header "🔐 Настройка конфигурации"

    echo -e "${CYAN}Необходимо ввести данные для подключения к Telegram и серверам 3x-ui${NC}"
    echo ""

    # ВАЖНО: Перенаправляем stdin с /dev/tty для работы с pipe (curl | bash)
    exec < /dev/tty

    # Telegram Bot Token
    while true; do
        echo -ne "${GREEN}📱 Telegram Bot Token${NC} (от @BotFather): "
        read BOT_TOKEN

        # Убираем пробелы и невидимые символы
        BOT_TOKEN=$(echo "$BOT_TOKEN" | tr -d '[:space:]')

        if [[ -z "$BOT_TOKEN" ]]; then
            print_warning "Токен не может быть пустым!"
        elif [[ ! "$BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
            print_warning "Неверный формат токена! Пример: 1234567890:ABCdefGHIjklMNOpqrsTUVwxyz"
        else
            break
        fi
    done

    # Admin ID
    while true; do
        echo -ne "${GREEN}👤 Telegram Admin ID${NC} (ваш ID от @userinfobot): "
        read ADMIN_ID

        # Убираем пробелы
        ADMIN_ID=$(echo "$ADMIN_ID" | tr -d '[:space:]')

        if [[ -z "$ADMIN_ID" ]]; then
            print_warning "Admin ID не может быть пустым!"
        elif ! [[ "$ADMIN_ID" =~ ^[0-9]+$ ]]; then
            print_warning "Admin ID должен содержать только цифры!"
        else
            break
        fi
    done

    print_success "Основные данные получены"
    echo ""

    # Серверы 3x-ui
    print_info "━━━ Настройка серверов 3x-ui ━━━"
    print_warning "Можно добавить несколько серверов"
    print_info "Для завершения ввода серверов - оставьте название пустым"
    echo ""

    declare -g -a SERVERS
    server_num=1

    while true; do
        echo -e "${YELLOW}╔═══ Сервер #${server_num} ═══╗${NC}"

        echo -ne "${CYAN}🌍 Название страны/сервера${NC} (например: Германия): "
        read COUNTRY_NAME

        # Если пустое - завершаем ввод серверов
        if [[ -z "$COUNTRY_NAME" ]]; then
            if [[ $server_num -eq 1 ]]; then
                print_warning "Нужно добавить хотя бы один сервер!"
                continue
            else
                print_success "Добавлено серверов: $((server_num - 1))"
                break
            fi
        fi

        # URL панели
        while true; do
            echo -ne "${CYAN}🔗 URL панели${NC} (https://server.com:2053): "
            read XUI_HOST
            XUI_HOST=$(echo "$XUI_HOST" | tr -d '[:space:]')
            
            if [[ -z "$XUI_HOST" ]]; then
                print_warning "URL не может быть пустым!"
            elif ! validate_panel_url "$XUI_HOST"; then
                print_warning "⚠️  Неверный формат! Пример: https://1.1.1.1:12345"
            else
                break
            fi
        done

        # Путь к панели
        while true; do
            echo -ne "${CYAN}📂 Путь к панели${NC} [по умолчанию: /panel]: "
            read XUI_PATH
            XUI_PATH=${XUI_PATH:-/panel}
            
            if ! validate_panel_path "$XUI_PATH"; then
                print_warning "⚠️  Путь должен начинаться с / (например: /kDYLDAOQis3aMfA)"
            else
                break
            fi
        done

        # Username
        echo -ne "${CYAN}👤 Username панели${NC} [по умолчанию: admin]: "
        read XUI_USERNAME
        XUI_USERNAME=${XUI_USERNAME:-admin}

        # Password
        while true; do
            echo -ne "${CYAN}🔒 Password панели${NC}: "
            read -s XUI_PASSWORD
            echo ""

            if [[ -z "$XUI_PASSWORD" ]]; then
                print_warning "Пароль не может быть пустым!"
            else
                break
            fi
        done

        # IP адрес сервера
        while true; do
            echo -ne "${CYAN}🌐 IP адрес сервера${NC}: "
            read SERVER_IP
            SERVER_IP=$(echo "$SERVER_IP" | tr -d '[:space:]')
            
            if [[ -z "$SERVER_IP" ]]; then
                print_warning "IP не может быть пустым!"
            elif ! validate_ip "$SERVER_IP"; then
                print_warning "⚠️  Неверный формат IP! Пример: 84.211.13.16"
            else
                break
            fi
        done

        # Сохраняем данные сервера
        SERVERS+=("$server_num|$COUNTRY_NAME|$XUI_HOST|$XUI_PATH|$XUI_USERNAME|$XUI_PASSWORD|$SERVER_IP")

        echo -e "${YELLOW}╚═══════════════════╝${NC}"
        print_success "Сервер #${server_num} (${COUNTRY_NAME}) добавлен"
        echo ""

        server_num=$((server_num + 1))
    done
}

# Создание директории и установка
install_bot() {
    print_header "📁 Установка бота"

    BOT_DIR="/root/vpn-bot"

    # Создаем директорию
    print_info "Создаем директорию: $BOT_DIR"
    mkdir -p "$BOT_DIR"
    cd "$BOT_DIR"
    print_success "Директория создана"

    # Создаем виртуальное окружение
    print_info "Создаем Python виртуальное окружение..."
    {
        python3 -m venv vpn-bot-env > /tmp/venv_create.log 2>&1
    } &
    show_spinner $! "Настройка изолированного Python окружения"
    print_success "Виртуальное окружение создано"

# Активируем и устанавливаем зависимости
print_info "Устанавливаем Python библиотеки..."
source vpn-bot-env/bin/activate
echo ""
print_info "→ Обновляем pip..."
pip install --upgrade pip > /tmp/pip_upgrade.log 2>&1

print_info "→ Устанавливаем библиотеки:"
echo "  • pyTelegramBotAPI (Telegram Bot API)"
echo "  • requests (HTTP клиент)"
echo "  • qrcode (генерация QR-кодов)"
echo "  • Pillow (работа с изображениями для QR-кодов)"
echo "  • python-dotenv (переменные окружения)"
echo "  • APScheduler (планировщик задач)"
echo "  • urllib3 (HTTP библиотека)"
echo ""

{
pip install pyTelegramBotAPI requests qrcode Pillow python-dotenv APScheduler urllib3 > /tmp/pip_install.log 2>&1
} &
show_spinner $! "Загрузка и установка Python пакетов"

print_success "Python библиотеки установлены"

    # Создаем .env файл
    print_info "Создаем файл конфигурации .env..."
    cat > "$BOT_DIR/.env" << EOF
# Telegram Bot Configuration
TELEGRAM_BOT_TOKEN=$BOT_TOKEN
ADMIN_USER_ID=$ADMIN_ID

EOF

    # Добавляем серверы в .env
    for server_data in "${SERVERS[@]}"; do
        IFS='|' read -r num country host path username password ip <<< "$server_data"

        cat >> "$BOT_DIR/.env" << EOF
# Server $num - $country
XUI_HOST_$num=$host
XUI_PATH_$num=$path
XUI_USERNAME_$num=$username
XUI_PASSWORD_$num=$password
XUI_TOKEN_$num=
SERVER_IP_$num=$ip
COUNTRY_NAME_$num=$country

EOF
    done

    chmod 600 "$BOT_DIR/.env"
    print_success "Файл .env создан и защищен"

# Создаем файл с функциями меню
print_info "Создаем скрипт управления меню..."
cat > "$BOT_DIR/menu.sh" << 'MENU_EOF'
#!/bin/bash

# Цветовые переменные
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

menu_loop() {
    while true; do
        clear
        echo -e "${CYAN}╔════ VPN TELEGRAM BOT: МЕНЮ ═══════════════╗${NC}"
        echo "1) Статус бота"
        echo "2) Список серверов"
        echo "3) Добавить новый сервер"
        echo "4) Перезапустить бота"
        echo "5) Показать логи"
        echo "6) Редактировать конфигурацию"
        echo "7) Полное удаление бота"
        echo "0) Выход"

        echo ""
        
        # Показываем донат QR-код под меню
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║    💚 Спасибо, что пользуетесь нашим ботом! 💚       ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        # QR-код для доната
        if command -v qrencode &> /dev/null && [ -t 1 ]; then
            echo -e "${CYAN}Поддержите проект:${NC}"

            echo ""
            qrencode -t ANSIUTF8 "https://pay.cloudtips.ru/p/52d42415" 2>/dev/null
            echo ""
        fi
        
        echo -e "${GREEN}🔗 https://pay.cloudtips.ru/p/52d42415${NC}"

        echo ""
        
        read -p "➤ Выберите действие: " choice
        
        case $choice in
            1) menu_status ;;
            2) menu_list_servers ;;
            3) menu_add_server ;;
            4) menu_restart_bot ;;
            5) menu_show_logs ;;
            6) menu_edit_config ;;
            7) menu_remove_bot ;;
            0)

                clear
                echo ""
                echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
                echo -e "${GREEN}║                                                       ║${NC}"
                echo -e "${GREEN}║    💚 Спасибо, что пользуетесь нашим ботом! 💚       ║${NC}"
                echo -e "${GREEN}║                                                       ║${NC}"
                echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
                echo ""
                echo -e "${CYAN}☕ Поддержать разработчика:${NC}"
                echo ""
                
                # Генерируем QR-код для доната
                if command -v qrencode &> /dev/null && [ -t 1 ]; then
                    qrencode -t ANSIUTF8 "https://pay.cloudtips.ru/p/52d42415" 2>/dev/null
                    echo ""
                else
                    echo -e "${YELLOW}📱 Отсканируйте QR-код или перейдите по ссылке:${NC}"
                fi
                
                echo -e "${GREEN}🔗 https://pay.cloudtips.ru/p/52d42415${NC}"
                echo ""
                echo -e "${CYAN}Ваша поддержка помогает улучшать проект! ❤️${NC}"
                echo ""
                sleep 3
                break
                ;;
            *) echo -e "${RED}Неверный выбор!${NC}"; sleep 1 ;;
        esac
    done
}

menu_status() {
    echo ""
    echo -e "${CYAN}--- Статус VPN бота ---${NC}"
    systemctl status vpn-bot.service --no-pager -n 10
    echo ""
    echo -e "${GREEN}Время работы:${NC}"
    systemctl show vpn-bot.service --property=ActiveEnterTimestamp --no-pager
    echo ""
    read -p "Нажмите Enter для возврата..." tmp
}

menu_add_server() {
    clear
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Добавление нового сервера 3x-ui        ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Читаем текущее количество серверов из .env
    local env_file="/root/vpn-bot/.env"
    
    if [ ! -f "$env_file" ]; then
        print_error "Файл конфигурации не найден: $env_file"
        read -p "Нажмите Enter для возврата..." tmp
        return
    fi
    
    # Определяем номер следующего сервера
    local server_count=0
    local next_server_num=1
    
    # Ищем максимальный номер сервера
    while grep -q "^XUI_${next_server_num}_HOST=" "$env_file" 2>/dev/null; do
        server_count=$next_server_num
        ((next_server_num++))
    done
    
    echo -e "${GREEN}Текущее количество серверов: ${server_count}${NC}"
    echo -e "${CYAN}Добавляем сервер #${next_server_num}${NC}"
    echo ""
    
    # Перенаправляем stdin для корректного чтения
    exec < /dev/tty
    
    # Собираем данные нового сервера
    local new_servers=()
    
    while true; do
        echo -e "${YELLOW}╔═══ Сервер #${next_server_num} ═══╗${NC}"
        
        # Название сервера
        echo -ne "${CYAN}🌍 Название страны/сервера${NC} (например: Германия): "
        read SERVER_NAME
        
        if [ -z "$SERVER_NAME" ]; then
            echo ""
            print_info "Название пустое - завершаем добавление серверов"
            break
        fi
        
        # URL панели с валидацией
        while true; do
            echo -ne "${CYAN}🔗 URL панели${NC} (https://server.com:2053): "
            read XUI_HOST
            XUI_HOST=$(echo "$XUI_HOST" | tr -d '[:space:]')
            
            if [[ -z "$XUI_HOST" ]]; then
                print_warning "URL не может быть пустым!"
            elif ! validate_panel_url "$XUI_HOST"; then
                print_warning "⚠️  Неверный формат! Пример: https://1.1.1.1:12345"
            else
                break
            fi
        done
        
        # Путь к панели с валидацией
        while true; do
            echo -ne "${CYAN}📂 Путь к панели${NC} [по умолчанию: /panel]: "
            read XUI_PATH
            XUI_PATH=${XUI_PATH:-/panel}
            
            if ! validate_panel_path "$XUI_PATH"; then
                print_warning "⚠️  Путь должен начинаться с / (например: /kDYLDAOQis3aMfA)"
            else
                break
            fi
        done
        
        # Username
        echo -ne "${CYAN}👤 Username панели${NC} [по умолчанию: admin]: "
        read XUI_USERNAME
        XUI_USERNAME=${XUI_USERNAME:-admin}
        
        # Password
        while true; do
            echo -ne "${CYAN}🔒 Password панели${NC}: "
            read -s XUI_PASSWORD
            echo ""
            
            if [[ -z "$XUI_PASSWORD" ]]; then
                print_warning "Пароль не может быть пустым!"
            else
                break
            fi
        done
        
        # IP адрес с валидацией
        while true; do
            echo -ne "${CYAN}🌐 IP адрес сервера${NC}: "
            read SERVER_IP
            SERVER_IP=$(echo "$SERVER_IP" | tr -d '[:space:]')
            
            if [[ -z "$SERVER_IP" ]]; then
                print_warning "IP не может быть пустым!"
            elif ! validate_ip "$SERVER_IP"; then
                print_warning "⚠️  Неверный формат IP! Пример: 84.21.173.216"
            else
                break
            fi
        done
        
        # Сохраняем данные сервера
        new_servers+=("${next_server_num}|${SERVER_NAME}|${XUI_HOST}|${XUI_PATH}|${XUI_USERNAME}|${XUI_PASSWORD}|${SERVER_IP}")
        
        echo ""
        print_success "Сервер #${next_server_num} '${SERVER_NAME}' добавлен"
        echo ""
        
        ((next_server_num++))
        
        echo -e "${CYAN}Добавить еще один сервер? (y/n)${NC}"
        read -p "➤ " add_more
        
        if [[ ! "$add_more" =~ ^[yYдД]$ ]]; then
            break
        fi
        
        echo ""
    done
    
    # Если серверы добавлены - записываем в .env
    if [ ${#new_servers[@]} -gt 0 ]; then
        echo ""
        print_info "Добавляем ${#new_servers[@]} новых серверов в конфигурацию..."
        
        # Добавляем серверы в .env
        for server_data in "${new_servers[@]}"; do
            IFS='|' read -r num country host path username password ip <<< "$server_data"
            
            # Добавляем в конец файла
            cat >> "$env_file" << EOF

# Server $num - $country
XUI_${num}_HOST=$host
XUI_${num}_PATH=$path
XUI_${num}_USERNAME=$username
XUI_${num}_PASSWORD=$password
SERVER_IP_${num}=$ip
EOF
            print_success "Сервер #${num} '$country' записан в конфигурацию"
        done
        
        echo ""
        print_success "Конфигурация обновлена! Перезапустите бота (пункт 4)"
        echo ""
    else
        print_info "Новые серверы не добавлены"
    fi
    
    read -p "Нажмите Enter для возврата..." tmp
}

menu_list_servers() {
    local envfile="/root/vpn-bot/.env"
    echo ""
    echo -e "${CYAN}--- Список серверов ---${NC}"
    if [ -f "$envfile" ]; then
        echo ""
        grep "^# Server" "$envfile" 2>/dev/null || echo "Серверы не найдены"
        echo ""
        grep "^COUNTRY_NAME_" "$envfile" 2>/dev/null | while read line; do
            server_name=$(echo "$line" | cut -d'=' -f2)
            server_num=$(echo "$line" | grep -oP 'COUNTRY_NAME_\K[0-9]+')
            echo "Сервер $server_num: $server_name"
            grep "^XUI_HOST_$server_num=" "$envfile" 2>/dev/null
            grep "^SERVER_IP_$server_num=" "$envfile" 2>/dev/null
            echo ""
        done
    else
        echo "Файл конфигурации не найден"
    fi
    echo ""
    read -p "Нажмите Enter для возврата..." tmp
}

menu_restart_bot() {
    echo ""
    echo -e "${YELLOW}Перезапуск службы vpn-bot...${NC}"
    systemctl restart vpn-bot.service
    sleep 2
    systemctl status vpn-bot.service --no-pager -n 10
    echo ""
    read -p "Нажмите Enter для возврата..." tmp
}

menu_show_logs() {
    echo ""
    echo -e "${CYAN}--- Последние 50 строк логов ---${NC}"
    journalctl -u vpn-bot -n 50 --no-pager
    echo ""
    echo -e "${GREEN}Для просмотра в реальном времени: journalctl -u vpn-bot -f${NC}"
    echo ""
    read -p "Нажмите Enter для возврата..." tmp
}

menu_edit_config() {
    echo ""
    echo -e "${CYAN}--- Редактирование конфигурации ---${NC}"
    echo "Открываю редактор nano..."
    sleep 1
    nano /root/vpn-bot/.env
    echo ""
    echo -e "${YELLOW}После изменения конфигурации перезапустите бота (пункт 3)${NC}"
    read -p "Нажмите Enter для возврата..." tmp
}

menu_remove_bot() {
    echo ""
    echo -e "${RED}!!! ВНИМАНИЕ !!!${NC}"
    echo "Это действие полностью удалит VPN Telegram Bot:"
    echo "- Службу systemd"
    echo "- Виртуальное окружение"
    echo "- Все файлы в /root/vpn-bot"
    echo "- Команду vpn-bot"
    echo ""
    read -p "Введите YES для подтверждения: " confirm1
    [ "$confirm1" != "YES" ] && echo "Отменено" && sleep 1 && return
    
    read -p "Точно? Введите УДАЛИТЬ: " confirm2
    [ "$confirm2" != "УДАЛИТЬ" ] && echo "Отменено" && sleep 1 && return
    
    systemctl stop vpn-bot.service 2>/dev/null || true
    systemctl disable vpn-bot.service 2>/dev/null || true
    rm -f /etc/systemd/system/vpn-bot.service
    rm -f /usr/local/bin/vpn-bot
    rm -rf /root/vpn-bot
    systemctl daemon-reload
    
    echo -e "${GREEN}VPN Bot полностью удалён!${NC}"
    sleep 2
    exit 0
}
MENU_EOF

chmod +x "$BOT_DIR/menu.sh"
print_success "Скрипт меню создан"

    # Извлекаем код бота (ИСПРАВЛЕНО для работы с pipe)
    print_info "Записываем код бота..."

    # Сохраняем сам скрипт во временный файл если запущен через pipe
    if [ ! -f "${BASH_SOURCE[0]}" ] || [ "${BASH_SOURCE[0]}" == "bash" ]; then
        # Скрипт запущен через pipe, сохраняем его содержимое
        TEMP_SCRIPT="/tmp/install_script_$$.sh"

        # Читаем текущий скрипт из /proc/self/fd/0 (stdin)
        # Но stdin уже перенаправлен на /dev/tty, поэтому используем другой метод

        # Скачиваем скрипт заново
        print_info "Загружаем код бота с GitHub..."
        curl -sSL https://raw.githubusercontent.com/stalkerj/vpn-telegram-bot/main/install-vpn-bot.sh > "$TEMP_SCRIPT" 2>/dev/null || {
            print_error "Не удалось загрузить скрипт"
            exit 1
        }
        SCRIPT_PATH="$TEMP_SCRIPT"
    else
        SCRIPT_PATH="${BASH_SOURCE[0]}"
    fi

    # Находим строку маркера и извлекаем все после нее
    MARKER_LINE=$(grep -n "^__BOT_CODE_BELOW__" "$SCRIPT_PATH" 2>/dev/null | cut -d: -f1)

    if [ -z "$MARKER_LINE" ]; then
        print_error "Не найден маркер кода бота в скрипте!"
        exit 1
    fi

    # Извлекаем код бота (все после маркера)
    tail -n +$((MARKER_LINE + 1)) "$SCRIPT_PATH" > "$BOT_DIR/vpn_bot.py"

    # Удаляем временный файл если создавали
    [ -n "$TEMP_SCRIPT" ] && rm -f "$TEMP_SCRIPT"

    chmod +x "$BOT_DIR/vpn_bot.py"
    bot_size=$(du -h "$BOT_DIR/vpn_bot.py" | cut -f1)
    print_success "Файл бота создан (размер: $bot_size)"
}

# Настройка systemd службы
setup_service() {
    print_header "🔧 Настройка автозапуска"

    print_info "Создаем systemd службу..."

    cat > /etc/systemd/system/vpn-bot.service << EOF
[Unit]
Description=VPN Telegram Bot Manager
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/vpn-bot
ExecStart=/root/vpn-bot/vpn-bot-env/bin/python /root/vpn-bot/vpn_bot.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vpn-bot

[Install]
WantedBy=multi-user.target
EOF

    print_success "Служба создана"

    # Перезагружаем systemd
    print_info "Применяем изменения systemd..."
    systemctl daemon-reload

    # Включаем автозапуск
    print_info "Включаем автозапуск..."
    systemctl enable vpn-bot.service > /dev/null 2>&1

    print_success "Автозапуск настроен"
}

# Запуск бота
start_bot() {
    print_header "🚀 Запуск бота"

    print_info "Запускаем службу vpn-bot..."
    systemctl start vpn-bot.service

    # Даем время на запуск
    echo ""
    for i in {3..1}; do
        echo -ne "   ${CYAN}⏳${NC} Ожидание запуска: $i сек...\r"
        sleep 1
    done
    echo -ne "   ${GREEN}✓${NC} Бот запущен                 \n"
    echo ""

    # Проверяем статус
    if systemctl is-active --quiet vpn-bot.service; then
        print_success "Бот успешно запущен и работает!"
        save_current_version
    else
        print_error "Ошибка запуска бота!"
        print_info "Показываем последние логи:"
        echo ""
        journalctl -u vpn-bot.service -n 20 --no-pager
        exit 1
    fi
}

# Финальный экран
# Финальный экран
show_completion() {
    clear
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║                                                       ║"
    echo "║            🎉  УСТАНОВКА ЗАВЕРШЕНА!  🎉             ║"
    echo "║                                                       ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""

    print_success "VPN Telegram Bot успешно установлен и запущен!"
    save_current_version
    echo ""

    echo -e "${CYAN}🎯 Быстрый доступ к меню:${NC}"
    echo "   Введите команду: vpn-bot"
    echo ""

    echo -e "${CYAN}📍 Информация об установке:${NC}"
    echo "   • Директория:    /root/vpn-bot"
    echo "   • Конфигурация:  /root/vpn-bot/.env"
    echo "   • Код бота:      /root/vpn-bot/vpn_bot.py"
    echo "   • Служба:        vpn-bot.service"
    echo ""

        # Показываем донат QR-код
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║    💚 Спасибо, что пользуетесь нашим ботом! 💚       ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # QR-код для доната (только если терминал интерактивный)
    if command -v qrencode &> /dev/null && [ -t 1 ]; then
        echo -e "${CYAN}Поддержите проект:${NC}"
        echo ""
        qrencode -t ANSIUTF8 "https://www.tbank.ru/cf/A1Cj74Nvan6" 2>/dev/null
        echo ""
    fi
    
    echo -e "${GREEN}🔗 https://www.tbank.ru/cf/A1Cj74Nvan6${NC}"
    echo ""


    echo -e "${CYAN}🔧 Управление ботом:${NC}"
    echo "   • Статус:        systemctl status vpn-bot"
    echo "   • Остановка:     systemctl stop vpn-bot"
    echo "   • Запуск:        systemctl start vpn-bot"
    echo "   • Перезапуск:    systemctl restart vpn-bot"
    echo "   • Логи:          journalctl -u vpn-bot -f"
    echo ""

    echo -e "${CYAN}📊 Полезные команды:${NC}"
    echo "   • Логи (live):   journalctl -u vpn-bot -f"
    echo "   • Последние 50:  journalctl -u vpn-bot -n 50"
    echo "   • Редактировать: nano /root/vpn-bot/.env"
    echo ""

    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_success "Откройте бота в Telegram и отправьте /start"
    print_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Показываем последние 15 строк логов
    print_header "📋 Последние логи бота"
    journalctl -u vpn-bot.service -n 15 --no-pager
    echo ""
    
    print_success "Установка завершена! Спасибо за использование! 🚀"
    echo ""

    # Создаем глобальную команду vpn-bot
    create_vpn_bot_command
}

# Функция создания команды vpn-bot (отдельная для переиспользования)
create_vpn_bot_command() {
    if [ ! -f "/usr/local/bin/vpn-bot" ]; then
        print_info "Создаем команду vpn-bot..."
        cat > /usr/local/bin/vpn-bot << 'EOF'
#!/bin/bash
# VPN Bot Menu Launcher
if [ -f "/root/vpn-bot/menu.sh" ]; then
    source /root/vpn-bot/menu.sh
    menu_loop
else
    echo "❌ Ошибка: Файл /root/vpn-bot/menu.sh не найден"
    echo "Переустановите бота: curl -sSL https://raw.githubusercontent.com/stalkerj/vpn-telegram-bot/main/install-vpn-bot.sh | sudo bash"
    exit 1
fi
EOF
        chmod +x /usr/local/bin/vpn-bot
        print_success "Команда vpn-bot создана!"
    else
        : # Команда vpn-bot уже существует (не показываем)
    fi
}

check_if_installed() {
    if [ -d "/root/vpn-bot" ] && [ -f "/etc/systemd/system/vpn-bot.service" ] && [ -f "/root/vpn-bot/.env" ]; then
        return 0  # Установлен
    else
        return 1  # Не установлен
    fi
}

# Функция проверки обновлений скрипта

# Сохранение текущей версии скрипта
save_current_version() {
    local version_file="/root/vpn-bot/VERSION"
    local current_version=$(head -20 "${BASH_SOURCE[0]}" 2>/dev/null | grep -oP '(?:Версия: )\K[0-9.]+' | head -1)

    if [ -z "$current_version" ]; then
        current_version="3.9"  # Fallback на текущую версию
    fi

    # Создаем директорию если нет
    mkdir -p "$(dirname "$version_file")"

    # Сохраняем версию
    echo "$current_version" > "$version_file"
    chmod 644 "$version_file"
}

check_for_updates() {
    # Читаем установленную версию из файла VERSION
    local local_version=""
    local version_file="/root/vpn-bot/VERSION"
    
    # Способ 1: Читаем из файла VERSION (основной способ)
    if [ -f "$version_file" ]; then
        local_version=$(cat "$version_file" 2>/dev/null | tr -d '[:space:]')
    fi
    
    # Способ 2: Если файла нет - ищем в текущем скрипте
    if [ -z "$local_version" ]; then
        if [ -f "${BASH_SOURCE[0]}" ] && [ "${BASH_SOURCE[0]}" != "bash" ] && [ "${BASH_SOURCE[0]}" != "-bash" ]; then
            local_version=$(head -20 "${BASH_SOURCE[0]}" 2>/dev/null | grep -oP '(?:Версия: )\\K[0-9.]+' | head -1)
        fi
    fi
    
    # Способ 3: Если все еще пусто - считаем первой установкой
    if [ -z "$local_version" ]; then
        local_version="0.0"
    fi
    
    local github_url="https://raw.githubusercontent.com/stalkerj/vpn-telegram-bot/main/install-vpn-bot.sh"
    
    # Тихо проверяем обновления
    
    # Скачиваем первые 50 строк для проверки версии
    remote_version=$(curl -sSL "$github_url" 2>/dev/null | head -50 | grep -oP '(?:v|Версия: )\K[0-9.]+' | head -1)
    
    if [ -z "$remote_version" ]; then
        print_warning "Не удалось проверить обновления на GitHub"
        return 1
    fi
    
    # Функция сравнения версий (3.4 > 3.2)
    version_greater() {
        test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
    }
    
    # Сравниваем версии
    if version_greater "$remote_version" "$local_version"; then
        echo ""
        print_warning "Доступна новая версия скрипта: $remote_version (текущая: $local_version)"
        echo ""
        echo -e "${CYAN}Хотите обновить скрипт установки? (y/n)${NC}"
        echo -e "${YELLOW}Примечание: Это обновит только установщик, настройки сохранятся${NC}"
        echo ""
        
        # ВАЖНО: Перенаправляем stdin для чтения
        exec < /dev/tty
        read -p "➤ " update_choice
        
        if [[ "$update_choice" == "y" ]] || [[ "$update_choice" == "Y" ]]; then
            print_info "Скачиваю обновленную версию установщика..."
            
            local temp_installer="/tmp/install-vpn-bot-v${remote_version}.sh"
            
            if curl -sSL "$github_url" > "$temp_installer" 2>/dev/null; then
                chmod +x "$temp_installer"
                print_success "Установщик обновлен до версии $remote_version"
                
                # Сохраняем новую версию
                echo "$remote_version" > "/root/vpn-bot/VERSION"

                
                print_info "Перезапускаю обновленный установщик..."
                sleep 2
                exec bash "$temp_installer"
                exit 0
            else
                print_error "Не удалось скачать обновление"
                return 1
            fi
        fi
    fi
}

# ============================================
# ГЛАВНАЯ ФУНКЦИЯ
# ============================================
main() {
    # Извлекаем версию для баннера
    # Способ 1: Читаем из установленного VERSION файла
    if [ -f "/root/vpn-bot/VERSION" ]; then
        SCRIPT_VERSION=$(cat /root/vpn-bot/VERSION 2>/dev/null | tr -d '[:space:]')
    fi

    # Способ 2: Если нет VERSION - берем из заголовка скрипта
    if [ -z "$SCRIPT_VERSION" ]; then
        # При запуске через curl это не сработает, поэтому используем встроенную версию
        SCRIPT_VERSION=$(head -20 "${BASH_SOURCE[0]}" 2>/dev/null | grep -oP '(?:Версия: )\K[0-9.]+' | head -1)
    fi

    # Способ 3: Fallback на встроенную версию (из строки 5 этого файла)
    if [ -z "$SCRIPT_VERSION" ]; then
        SCRIPT_VERSION="3.9"  # Синхронизируйте с версией в строке 5!
    fi

    print_banner
    check_root
    
    # Проверяем, установлен ли бот
    if check_if_installed; then
        clear
        echo -e "${GREEN}"
        echo "╔═══════════════════════════════════════════════════════╗"
        echo "║                                                       ║"
        echo "║     ✅ VPN TELEGRAM BOT УЖЕ УСТАНОВЛЕН!              ║"
        echo "║                                                       ║"
        echo "╚═══════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        echo ""
        print_success "Бот успешно установлен и работает!"
        echo ""
        
        # Проверяем статус
        if systemctl is-active --quiet vpn-bot.service; then
            print_success "Статус: 🟢 Работает"
        else
            print_warning "Статус: 🔴 Остановлен"
        fi
        
        # Проверяем и создаём команду vpn-bot если её нет
        create_vpn_bot_command
        
        # Проверяем обновления скрипта
        echo ""
    # Проверяем обновления только если скрипт доступен как файл
    check_for_updates
        
        echo ""
        echo -e "${CYAN}Что вы хотите сделать?${NC}"
        echo "1) Открыть меню управления"
        echo "2) Переустановить бота (удалит текущую конфигурацию)"
        echo "3) Обновить только код бота (сохранит настройки)"
        echo "4) Выход"
        echo ""

                # Показываем донат QR-код под меню
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║    💚 Спасибо, что пользуетесь нашим ботом! 💚       ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        # QR-код для доната (только если терминал интерактивный)
        if command -v qrencode &> /dev/null && [ -t 1 ]; then
            echo -e "${CYAN}Поддержите проект:${NC}"
            echo ""
            qrencode -t ANSIUTF8 "https://www.tbank.ru/cf/A1Cj74Nvan6" 2>/dev/null
            echo ""
        fi
        
        echo -e "${GREEN}🔗 https://www.tbank.ru/cf/A1Cj74Nvan6${NC}"
        echo ""
        
        # ВАЖНО: Перенаправляем stdin для корректного чтения
        exec < /dev/tty

        
        # ВАЖНО: Перенаправляем stdin для корректного чтения
        exec < /dev/tty
        read -p "➤ Выберите действие: " action
        
        case $action in
            1)
                # Открываем меню
                if [ -f "/root/vpn-bot/menu.sh" ]; then
                    source /root/vpn-bot/menu.sh
                    menu_loop
                else
                    print_error "Файл меню не найден. Переустановите бота."
                fi
                exit 0
                ;;
            2)
                # Переустановка
                echo ""
                echo -e "${RED}⚠️ ВНИМАНИЕ!${NC}"
                echo "Переустановка удалит все текущие настройки и конфигурацию!"
                read -p "Продолжить? (YES для подтверждения): " confirm
                if [ "$confirm" == "YES" ]; then
                    print_info "Удаляем текущую установку..."
                    systemctl stop vpn-bot.service 2>/dev/null || true
                    systemctl disable vpn-bot.service 2>/dev/null || true
                    rm -f /etc/systemd/system/vpn-bot.service
                    rm -f /usr/local/bin/vpn-bot
                    rm -rf /root/vpn-bot
                    systemctl daemon-reload
                    print_success "Старая установка удалена"
                    sleep 2
                    # Продолжаем установку ниже
                else
                    echo "Отменено"
                    exit 0
                fi
                ;;
            3)
                # Обновление только кода бота (сохраняем .env)
                echo ""
                print_info "Обновляю код бота (настройки сохранятся)..."
                
                # Создаем резервную копию .env
                if [ -f "/root/vpn-bot/.env" ]; then
                    cp /root/vpn-bot/.env /tmp/vpn-bot-env-backup
                    print_success "Настройки сохранены"
                fi
                
                # Останавливаем бота
                systemctl stop vpn-bot.service 2>/dev/null || true
                
                # Скачиваем новый скрипт
                TEMP_SCRIPT="/tmp/update_script_$$.sh"
                curl -sSL https://raw.githubusercontent.com/stalkerj/vpn-telegram-bot/main/install-vpn-bot.sh > "$TEMP_SCRIPT" 2>/dev/null || {
                    print_error "Не удалось загрузить скрипт"
                    exit 1
                }
                
                # Извлекаем код бота
                MARKER_LINE=$(grep -n "^__BOT_CODE_BELOW__" "$TEMP_SCRIPT" 2>/dev/null | cut -d: -f1)
                if [ -n "$MARKER_LINE" ]; then
                    tail -n +$((MARKER_LINE + 1)) "$TEMP_SCRIPT" > /root/vpn-bot/vpn_bot.py
                    chmod +x /root/vpn-bot/vpn_bot.py
                    print_success "Код бота обновлен"
                fi
                
                # Восстанавливаем .env
                if [ -f "/tmp/vpn-bot-env-backup" ]; then
                    mv /tmp/vpn-bot-env-backup /root/vpn-bot/.env
                    chmod 600 /root/vpn-bot/.env
                fi
                
                rm -f "$TEMP_SCRIPT"
                
                # Перезапускаем бота
                systemctl start vpn-bot.service
                sleep 2
                
                if systemctl is-active --quiet vpn-bot.service; then
                    print_success "Бот успешно обновлен и запущен!"
                    save_current_version
                else
                    print_error "Ошибка запуска бота после обновления"
                    journalctl -u vpn-bot.service -n 20 --no-pager
                fi
                exit 0
                ;;
            4|*)
                echo "Выход"
                exit 0
                ;;
        esac
    fi
    
    # Если бот не установлен или выбрана переустановка - продолжаем обычную установку
    detect_os
    check_requirements
    sleep 2
    update_system
    install_dependencies
    collect_config
    install_bot
    setup_service
    start_bot
    show_completion
    
    # После установки спрашиваем, открыть ли меню
    echo ""
    echo -e "${CYAN}Хотите открыть меню управления сейчас? (y/n)${NC}"
    
    # Проверяем что терминал интерактивный
    if [ -t 0 ]; then
        read -p "➤ " open_menu
        
        if [[ "$open_menu" =~ ^[yYдД]$ ]]; then
            if [ -f "/root/vpn-bot/menu.sh" ]; then
                bash /root/vpn-bot/menu.sh
            else
                echo "Ошибка: menu.sh не найден"
            fi
        fi
    else
        echo "➤ Меню недоступно при установке через curl | bash"
        echo "   Используйте команду: vpn-bot"
    fi

}

# ============================================
# ТЕРМИНАЛЬНОЕ МЕНЮ УПРАВЛЕНИЯ (BASH)
# Размещаем ПОСЛЕ функции main, но ДО запуска
# ============================================

menu_loop() {
    while true; do
        clear
        echo -e "${CYAN}╔════ VPN TELEGRAM BOT: МЕНЮ ═══════════════╗${NC}"
        echo "1) Добавить сервер 3x-ui"
        echo "2) Редактировать сервер"
        echo "3) Список серверов"
        echo "4) Перезапустить бота"
        echo "5) Показать логи"
        echo "6) Полное удаление бота"
        echo "0) Выход"
        echo ""

        case $choice in
            1) menu_add_server ;;
            2) menu_edit_server ;;
            3) menu_list_servers ;;
            4) menu_restart_bot ;;
            5) menu_show_logs ;;
            6) menu_remove_bot ;;
            0) 
                clear
                echo ""
                echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
                echo -e "${GREEN}║                                                       ║${NC}"
                echo -e "${GREEN}║    💚 Спасибо, что пользуетесь нашим ботом! 💚       ║${NC}"
                echo -e "${GREEN}║                                                       ║${NC}"
                echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
                echo ""
                echo -e "${CYAN}☕ Поддержать разработчика:${NC}"
                echo ""

        read -p "➤ Выберите действие: " choice
                
                # Генерируем QR-код для доната
                if command -v qrencode &> /dev/null && [ -t 1 ]; then
                    qrencode -t ANSIUTF8 "https://www.tbank.ru/cf/A1Cj74Nvan6" 2>/dev/null
                    echo ""
                else
                    echo -e "${YELLOW}📱 Отсканируйте QR-код или перейдите по ссылке:${NC}"
                fi
                
                echo -e "${GREEN}🔗 https://www.tbank.ru/cf/A1Cj74Nvan6${NC}"
                echo ""
                echo -e "${CYAN}Ваша поддержка помогает улучшать проект! ❤️${NC}"
                echo ""
                sleep 3
                break
                ;;
            *) echo -e "${RED}Неверный выбор!${NC}"; sleep 1 ;;
        esac
    done
}

# Остальные функции menu_add_server, menu_edit_server и т.д. остаются без изменений



menu_add_server() {
    echo ""
    echo -e "${CYAN}--- Добавление нового сервера ---${NC}"
    echo "Функция в разработке. Отредактируйте /root/vpn-bot/.env вручную:"
    echo "nano /root/vpn-bot/.env"
    echo ""
    read -p "Нажмите Enter для возврата..." tmp
}

menu_edit_server() {
    menu_list_servers
    echo ""
    echo "Для редактирования откройте файл конфигурации:"
    echo "nano /root/vpn-bot/.env"
    echo ""
    read -p "Нажмите Enter для возврата..." tmp
}

menu_list_servers() {
    local envfile="/root/vpn-bot/.env"
    echo ""
    echo -e "${CYAN}--- Список серверов ---${NC}"
    if [ -f "$envfile" ]; then
        grep "^# Server" "$envfile" || echo "Серверы не найдены"
        echo ""
        grep "^COUNTRY_NAME_" "$envfile" || echo ""
        grep "^XUI_HOST_" "$envfile" || echo ""
    else
        echo "Файл конфигурации не найден"
    fi
    echo ""
    read -p "Нажмите Enter для возврата..." tmp
}

menu_restart_bot() {
    echo ""
    echo -e "${YELLOW}Перезапуск службы vpn-bot...${NC}"
    systemctl restart vpn-bot.service
    sleep 2
    systemctl status vpn-bot.service --no-pager -n 10
    echo ""
    read -p "Нажмите Enter для возврата..." tmp
}

menu_show_logs() {
    echo ""
    echo -e "${CYAN}--- Последние 50 строк логов ---${NC}"
    journalctl -u vpn-bot -n 50 --no-pager
    echo ""
    echo "Для просмотра в реальном времени: journalctl -u vpn-bot -f"
    echo ""
    read -p "Нажмите Enter для возврата..." tmp
}

menu_remove_bot() {
    echo ""
    echo -e "${RED}!!! ВНИМАНИЕ !!!${NC}"
    echo "Это действие полностью удалит VPN Telegram Bot:"
    echo "- Службу systemd"
    echo "- Виртуальное окружение"
    echo "- Все файлы в /root/vpn-bot"
    echo ""
    read -p "Введите YES для подтверждения: " confirm1
    [ "$confirm1" != "YES" ] && echo "Отменено" && sleep 1 && return
    
    read -p "Точно? Введите УДАЛИТЬ: " confirm2
    [ "$confirm2" != "УДАЛИТЬ" ] && echo "Отменено" && sleep 1 && return
    
    systemctl stop vpn-bot.service 2>/dev/null || true
    systemctl disable vpn-bot.service 2>/dev/null || true
    rm -f /etc/systemd/system/vpn-bot.service
    rm -rf /root/vpn-bot
    systemctl daemon-reload
    
    echo -e "${GREEN}VPN Bot полностью удалён!${NC}"
    sleep 2
    exit 0
}

post_install_menu() {
    print_header "Терминальное меню управления"
    echo -e "${CYAN}Открыть меню управления ботом? (y/n)${NC}"
    read -p "➤ " answer
    if [[ "$answer" == "y" ]] || [[ "$answer" == "Y" ]]; then
        menu_loop
    fi
}

# Запуск установки


main

# Выход
exit 0

# ============================================
# НИЖЕ ЭТОЙ ЛИНИИ НАХОДИТСЯ КОД БОТА
# НЕ РЕДАКТИРУЙТЕ ВРУЧНУЮ!
# ============================================
__BOT_CODE_BELOW__
import os
import io
import uuid
import json
import qrcode
import base64
import requests
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
import urllib.parse
import sys
import time
import socket
from datetime import datetime, timedelta
from typing import List, Dict, Optional
from dotenv import load_dotenv
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger
import traceback

import telebot
from telebot import types

# Загрузка переменных окружения
load_dotenv()

# Конфигурация бота из .env
BOT_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN')
ADMIN_USER_ID = int(os.getenv('ADMIN_USER_ID'))

# Проверяем, что основные переменные загружены
if not BOT_TOKEN:
    raise ValueError("TELEGRAM_BOT_TOKEN not found in .env file")
if not ADMIN_USER_ID:
    raise ValueError("ADMIN_USER_ID not found in .env file")

print(f"✅ Конфигурация загружена:")
print(f"   Admin ID: {ADMIN_USER_ID}")

bot = telebot.TeleBot(BOT_TOKEN)

# Время запуска бота для статистики
bot_start_time = datetime.now()

# Хранилище текущего сервера и контекста
user_current_servers: Dict[int, str] = {}
USER_CTX: Dict[int, Dict[str, str]] = {}

# Глобальный планировщик задач
scheduler = BackgroundScheduler()

# Хранилище последних статусов серверов для отслеживания изменений
server_last_status: Dict[str, bool] = {}

# Настройки мониторинга и отчетов
HEALTH_CHECK_INTERVAL_MINUTES = 5  # Проверка каждые 5 минут
DAILY_REPORT_HOUR = 9  # Ежедневный отчет в 9:00
DAILY_REPORT_MINUTE = 0
WEEKLY_REPORT_DAY = 'mon'  # Еженедельный отчет по понедельникам
WEEKLY_REPORT_HOUR = 10
WEEKLY_REPORT_MINUTE = 0


def escape_markdown_v1(text: str) -> str:
    """Экранируем специальные символы для Markdown v1"""
    # Основные символы, которые нужно экранировать для Markdown
    escape_chars = ['_', '*', '[', ']', '(', ')', '`']
    for ch in escape_chars:
        text = text.replace(ch, '\\' + ch)
    return text

def safe_markdown_text(text: str, use_v2: bool = False) -> str:
    """Безопасное экранирование текста для Markdown"""
    if not text:
        return ""
    
    if use_v2:
        # Для MarkdownV2
        escape_chars = ['_', '*', '[', ']', '(', ')', '~', '`', '>', '#', '+', '-', '=', '|', '{', '}', '.', '!']
    else:
        # Для обычного Markdown - только основные символы
        escape_chars = ['_', '*', '[', ']', '(', ')', '`']
    
    result = str(text)
    for ch in escape_chars:
        result = result.replace(ch, '\\' + ch)
    return result

def set_user_context(user_id: int, key: str, value):
    USER_CTX.setdefault(user_id, {})[key] = value

def get_user_context(user_id: int, key: str, default=None):
    return USER_CTX.get(user_id, {}).get(key, default)

def clear_user_context(user_id: int, *keys):
    if user_id in USER_CTX:
        for k in keys:
            USER_CTX[user_id].pop(k, None)

def send_long_message(bot, chat_id, text, reply_markup=None, parse_mode=None):
    """Отправка длинных сообщений с автоматической разбивкой"""
    MAX_LEN = 4096
    if len(text) <= MAX_LEN:
        bot.send_message(chat_id, text, reply_markup=reply_markup, parse_mode=parse_mode, disable_web_page_preview=True)
        return
    parts = []
    while len(text) > MAX_LEN:
        cut_idx = text.rfind('\n', 0, MAX_LEN)
        if cut_idx == -1:
            cut_idx = MAX_LEN
        parts.append(text[:cut_idx])
        text = text[cut_idx:].lstrip('\n')
    if text:
        parts.append(text)
    for part in parts[:-1]:
        bot.send_message(chat_id, part, parse_mode=parse_mode, disable_web_page_preview=True)
    bot.send_message(chat_id, parts[-1], reply_markup=reply_markup, parse_mode=parse_mode, disable_web_page_preview=True)

def load_servers_config() -> Dict:
    """Динамическая загрузка конфигурации серверов из переменных окружения"""
    servers = {}
    i = 1
    while True:
        host = os.getenv(f'XUI_HOST_{i}')
        if not host:
            break
        path = os.getenv(f'XUI_PATH_{i}', '/panel')
        username = os.getenv(f'XUI_USERNAME_{i}', 'admin')
        password = os.getenv(f'XUI_PASSWORD_{i}', 'password')
        token = os.getenv(f'XUI_TOKEN_{i}', '')
        server_ip = os.getenv(f'SERVER_IP_{i}', 'localhost')
        country_name = os.getenv(f'COUNTRY_NAME_{i}', f'Server {i}')
        servers[f"server{i}"] = {
            "name": country_name,
            "host": host,
            "path": path,
            "username": username,
            "password": password,
            "token": token,
            "server_ip": server_ip
        }
        print(f"   📡 Сервер {i}: {country_name}")
        i += 1
    if not servers:
        raise ValueError("Не найдено ни одной конфигурации сервера! Проверьте переменные XUI_HOST_1, XUI_HOST_2, и т.д.")
    print(f"✅ Загружено серверов: {len(servers)}")
    return servers

SERVERS_CONFIG = load_servers_config()

def get_current_server_id(user_id: int) -> str:
    """Получить ID текущего сервера для пользователя"""
    default_server = list(SERVERS_CONFIG.keys())[0]
    return user_current_servers.get(user_id, default_server)

def set_current_server(user_id: int, server_id: str):
    """Установить текущий сервер для пользователя"""
    user_current_servers[user_id] = server_id

def get_current_server_config(user_id: int) -> Dict:
    """Получить конфигурацию текущего сервера"""
    server_id = get_current_server_id(user_id)
    default_server = list(SERVERS_CONFIG.keys())[0]
    return SERVERS_CONFIG.get(server_id, SERVERS_CONFIG[default_server])

def safe_decode_username(encoded: str) -> str:
    """Декодирование имени пользователя из callback_data (hex)"""
    try:
        if encoded == "error":
            return "unknown_user"
        return bytes.fromhex(encoded).decode('utf-8')
    except Exception as e:
        print(f"❌ Ошибка декодирования username {encoded}: {e}")
        return "unknown_user"

def safe_encode_username(username: str) -> str:
    """Кодирование имени пользователя для callback_data (hex)"""
    try:
        # Удаляем потенциально проблемные символы перед кодированием
        cleaned_username = username.strip()
        return cleaned_username.encode('utf-8').hex()
    except Exception as e:
        print(f"❌ Ошибка кодирования username {username}: {e}")
        return "error"

class VPNManager:
    def __init__(self, server_config: Dict):
        self.server_config = server_config
        self.base_url = f"{server_config['host']}{server_config['path']}"
        self.session = requests.Session()
        self.session.verify = False
        self.is_authenticated = False
        print(f"🔗 Подключение к API: {self.base_url}")
    
    def authenticate(self):
        """Аутентификация в панели"""
        try:
            login_data = {"username": self.server_config['username'], "password": self.server_config['password']}
            headers = {}
            if self.server_config['token']:
                headers = {"Authorization": f"Bearer {self.server_config['token']}"}
            response = self.session.post(f"{self.base_url}/login", json=login_data, headers=headers, timeout=10)
            if response.status_code == 200:
                result = response.json()
                if result.get('success'):
                    self.is_authenticated = True
                    print("✅ Аутентификация успешна")
                    return True
                else:
                    print(f"❌ Ошибка аутентификации: {result.get('msg', 'Unknown error')}")
            else:
                print(f"❌ HTTP ошибка: {response.status_code}")
        except Exception as e:
            print(f"❌ Ошибка при аутентификации: {e}")
        return False
    
    def check_server_health(self):
        """Быстрая проверка ответа API"""
        try:
            response = self.session.post(f"{self.base_url}/xui/API/inbounds/list", timeout=10)
            if response.status_code == 200:
                print("✅ Сервер 3X-UI отвечает нормально")
                return True
            else:
                print(f"⚠️ Сервер отвечает с кодом {response.status_code}")
                return False
        except Exception as e:
            print(f"❌ Ошибка проверки сервера: {e}")
            return False
    
    def get_available_inbounds(self):
        """Список inbound'ов"""
        if not self.is_authenticated:
            if not self.authenticate():
                return []
        try:
            response = self.session.post(f"{self.base_url}/xui/API/inbounds/list", timeout=10)
            if response.status_code == 200:
                result = response.json()
                if result.get('success'):
                    inbounds = result.get('obj', [])
                    print("📊 Доступные inbound'ы:")
                    for inbound in inbounds:
                        print(f"   ID: {inbound.get('id')}, Protocol: {inbound.get('protocol')}, Port: {inbound.get('port')}")
                    return inbounds
        except Exception as e:
            print(f"❌ Ошибка получения inbound'ов: {e}")
        return []
    
    def get_users_list(self) -> List[Dict]:
        """Агрегированный список пользователей по всем inbound'ам"""
        if not self.is_authenticated:
            if not self.authenticate():
                return []
        try:
            response = self.session.post(f"{self.base_url}/xui/API/inbounds/list", timeout=10)
            if response.status_code != 200:
                print(f"❌ Ошибка получения inbound'ов: {response.status_code}")
                return []
            result = response.json()
            if not result.get('success'):
                print(f"❌ API ошибка: {result.get('msg', 'Unknown error')}")
                return []
            inbounds = result.get('obj', [])
            users_data = []
            for inbound in inbounds:
                if 'clientStats' in inbound and inbound['clientStats']:
                    for client in inbound['clientStats']:
                        total_gb = client.get('total', 0) / (1024**3) if client.get('total', 0) > 0 else 'Безлимит'
                        used_gb = client.get('down', 0) / (1024**3)  # Только входящий трафик (скачивание)
                        expiry_time = 'Безлимит'
                        if client.get('expiryTime', 0) > 0:
                            expiry_time = datetime.fromtimestamp(client.get('expiryTime') / 1000).strftime('%Y-%m-%d %H:%M:%S')
                        users_data.append({
                            'email': client.get('email', 'N/A'),
                            'enable': client.get('enable', False),
                            'total_gb': total_gb,
                            'used_gb': used_gb,
                            'expiry_time': expiry_time,
                            'inbound_id': inbound.get('id'),
                            'inbound_port': inbound.get('port'),
                            'protocol': inbound.get('protocol'),
                            'client_id': client.get('id'),
                            'settings': inbound.get('settings', '{}'),
                            'stream_settings': inbound.get('streamSettings', '{}')
                        })
            return users_data
        except Exception as e:
            print(f"❌ Ошибка получения пользователей: {e}")
            self.is_authenticated = False
            return []
    
    def get_detailed_inbound_settings(self, inbound_id: int) -> Optional[Dict]:
        """Детальные настройки по inbound"""
        if not self.is_authenticated:
            if not self.authenticate():
                return None
        try:
            response = self.session.post(f"{self.base_url}/xui/API/inbounds/get/{inbound_id}", timeout=10)
            if response.status_code == 200:
                result = response.json()
                if result.get('success') and 'obj' in result:
                    return result['obj']
            return None
        except Exception as e:
            print(f"❌ Ошибка получения детальных настроек: {e}")
            return None
    
    def create_user(self, username: str, inbound_id: int = 1, total_gb: int = 0, expiry_days: int = 0) -> bool:
        """Создание пользователя в указанном inbound"""
        print(f"🚀 Создание пользователя {username} в inbound {inbound_id}")
        print(f"   Параметры: total_gb={total_gb}, expiry_days={expiry_days}")
        
        if not self.is_authenticated:
            if not self.authenticate():
                print("❌ Ошибка: не удалось аутентифицироваться")
                return False
        
        # Проверяем дубликат по email
        existing_users = self.get_users_list()
        if any(user['email'].lower() == username.lower() for user in existing_users):
            print(f"❌ Пользователь {username} уже существует")
            return False
        
        # Проверяем inbound
        inbounds = self.get_available_inbounds()
        if not inbounds:
            print("❌ Нет доступных inbound'ов!")
            return False
        
        if not any(ib.get('id') == inbound_id for ib in inbounds):
            print(f"❌ Inbound с ID {inbound_id} не найден!")
            return False
        
        try:
            client_uuid = str(uuid.uuid4())
            expiry_timestamp = int((datetime.now() + timedelta(days=expiry_days)).timestamp() * 1000) if expiry_days > 0 else 0
            total_bytes = total_gb * (1024**3) if total_gb > 0 else 0
            
            print(f"   UUID: {client_uuid}")
            print(f"   Total bytes: {total_bytes}")
            print(f"   Expiry timestamp: {expiry_timestamp}")
            
            client_data = {
                "id": client_uuid,
                "email": username,
                "enable": True,
                "flow": "xtls-rprx-vision",
                "limitIp": 0,
                "totalGB": total_bytes,
                "expiryTime": expiry_timestamp,
                "tgId": "",
                "subId": self._generate_sub_id(),
                "reset": 0
            }
            
            request_payload = {
                "id": inbound_id,
                "settings": json.dumps({"clients": [client_data]}, separators=(',', ':'))
            }
            
            headers = {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'X-Requested-With': 'XMLHttpRequest'
            }
            
            # Список endpoint'ов для попытки создания
            endpoints = [
                f"{self.base_url}/panel/api/inbounds/addClient",
                f"{self.base_url}/xui/API/inbounds/addClient",
                f"{self.base_url}/xui/inbounds/addClient"
            ]
            
            for api_url in endpoints:
                try:
                    print(f"🔄 Пробую endpoint: {api_url}")
                    response = self.session.post(api_url, json=request_payload, headers=headers, timeout=15)
                    
                    print(f"   Статус код: {response.status_code}")
                    
                    if response.status_code == 200:
                        try:
                            result = response.json()
                            print(f"   API Response: {result}")
                            
                            # Проверяем success в ответе API
                            if result.get('success'):
                                print(f"✅ API вернул success для endpoint {api_url}")
                                
                                # Даем время серверу обновить список
                                time.sleep(2)
                                
                                # Проверяем, что пользователь действительно создан
                                users_after = self.get_users_list()
                                if any(u['email'].lower() == username.lower() for u in users_after):
                                    print(f"✅ Пользователь {username} успешно создан!")
                                    return True
                                else:
                                    print(f"⚠️ API вернул success, но пользователь не найден в списке. Пробую следующий endpoint...")
                                    continue
                            else:
                                error_msg = result.get('msg', 'Unknown error')
                                print(f"❌ API вернул ошибку: {error_msg}")
                                continue
                        except json.JSONDecodeError as e:
                            print(f"❌ Ошибка парсинга JSON: {e}")
                            continue
                    else:
                        print(f"❌ Неудачный статус код: {response.status_code}")
                        continue
                        
                except Exception as e:
                    print(f"❌ Ошибка при запросе к {api_url}: {e}")
                    continue
            
            # Если все endpoint'ы не сработали
            print(f"❌ Не удалось создать пользователя {username} ни одним из endpoint'ов")
            return False
            
        except Exception as e:
            print(f"❌ Критическая ошибка создания пользователя: {e}")
            import traceback
            print(f"Трассировка: {traceback.format_exc()}")
            return False
    
    def delete_user(self, username: str) -> bool:
        """Удаление первого найденного по email (для совместимости)"""
        print(f"🗑️ Удаление пользователя: {username}")
        if not self.is_authenticated:
            if not self.authenticate():
                return False
        try:
            users = self.get_users_list()
            target_user = next((u for u in users if u['email'].lower().strip() == username.lower().strip()), None)
            if not target_user:
                print(f"❌ Пользователь {username} не найден")
                return False
            return self.delete_user_in_inbound(username, target_user['inbound_id'])
        except Exception as e:
            print(f"❌ Ошибка удаления пользователя: {e}")
            return False

    def delete_user_in_inbound(self, username: str, inbound_id: int) -> bool:
        """Удаление пользователя строго в указанном inbound"""
        print(f"🗑️ Удаление пользователя: {username} в inbound {inbound_id}")
        if not self.is_authenticated:
            if not self.authenticate():
                return False
        try:
            detailed_settings = self.get_detailed_inbound_settings(inbound_id)
            if not detailed_settings:
                print(f"❌ Не удалось получить настройки inbound {inbound_id}")
                return False
            settings_str = detailed_settings.get('settings', '{}')
            settings = json.loads(settings_str) if isinstance(settings_str, str) else settings_str
            client_uuid = None
            for client in settings.get('clients', []):
                if str(client.get('email', '')).lower().strip() == username.lower().strip():
                    client_uuid = client.get('id')
                    break
            if not client_uuid:
                print(f"❌ UUID клиента {username} в inbound {inbound_id} не найден")
                return False
            headers = {'Accept': 'application/json', 'Content-Type': 'application/json', 'X-Requested-With': 'XMLHttpRequest'}
            api_url = f"{self.base_url}/panel/api/inbounds/{inbound_id}/delClient/{client_uuid}"
            response = self.session.post(api_url, headers=headers, timeout=15)
            if response.status_code == 200:
                try:
                    jr = response.json()
                    if jr.get('success'):
                        print(f"✅ API вернул success: {jr.get('msg', '')}")
                        time.sleep(3)
                        # Проверяем, что клиента больше нет в этом inbound
                        detailed_after = self.get_detailed_inbound_settings(inbound_id)
                        if detailed_after:
                            s_str = detailed_after.get('settings', '{}')
                            s_obj = json.loads(s_str) if isinstance(s_str, str) else s_str
                            still = any(str(c.get('email', '')).lower().strip() == username.lower().strip() for c in s_obj.get('clients', []))
                            if not still:
                                print(f"✅ Пользователь {username} успешно удален из inbound {inbound_id}!")
                                return True
                        print(f"❌ Пользователь {username} все еще существует в inbound {inbound_id}")
                        return False
                    else:
                        print(f"❌ API вернул ошибку: {jr.get('msg', 'Unknown error')}")
                        return False
                except:
                    print("⚠️ Не удалось парсить JSON ответ при удалении")
                    return False
            return False
        except Exception as e:
            print(f"❌ Ошибка удаления пользователя в inbound: {e}")
            return False
    
    def get_backup(self) -> Optional[bytes]:
        """Экспорт бекапа базы данных 3x-ui (исправленный с правильными API endpoints)"""
        if not self.is_authenticated:
            if not self.authenticate():
                return None
        
        # Правильные endpoints из официальной API документации 3x-ui
        endpoints = [
            f"{self.base_url}/panel/api/inbounds/createbackup",
            f"{self.base_url}/api/inbounds/createbackup", 
            f"{self.base_url}/panel/server/getDb",
            f"{self.base_url}/server/getDb",
            f"{self.base_url}/panel/api/server/getDb",
            f"{self.base_url}/download/backup.db",
            f"{self.base_url}/download/x-ui.db",
            f"{self.base_url}/panel/api/backup/export",
            f"{self.base_url}/api/backup/export"
        ]
        
        headers = {
            'Accept': 'application/json, application/octet-stream, */*',
            'Content-Type': 'application/json',
            'X-Requested-With': 'XMLHttpRequest'
        }
        
        for endpoint in endpoints:
            try:
                print(f"🔄 Пробую endpoint: {endpoint}")
                
                # Для createbackup нужен POST запрос
                if 'createbackup' in endpoint:
                    response = self.session.post(endpoint, headers=headers, timeout=30)
                else:
                    # Для остальных - GET запрос
                    response = self.session.get(endpoint, headers=headers, timeout=30, stream=True)
                
                if response.status_code == 200:
                    # Проверяем content-type и размер ответа
                    content_type = response.headers.get('content-type', '').lower()
                    content_length = len(response.content) if hasattr(response, 'content') else 0
                    
                    print(f"✅ Ответ получен. Content-Type: {content_type}, Размер: {content_length}")
                    
                    # Проверяем, что это бинарные данные или JSON с данными
                    if ('application/octet-stream' in content_type or 
                        'application/x-sqlite3' in content_type or
                        'application/x-sqlite' in content_type or
                        'application/vnd.sqlite3' in content_type or
                        content_length > 10000):  # База данных должна быть больше 10KB
                        
                        print(f"✅ Бекап получен через {endpoint}, размер: {content_length} байт")
                        return response.content
                    
                    # Возможно JSON ответ с данными в base64
                    elif 'application/json' in content_type:
                        try:
                            json_response = response.json()
                            if json_response.get('success') and json_response.get('obj'):
                                # Проверяем, есть ли данные в base64
                                if isinstance(json_response['obj'], str) and len(json_response['obj']) > 1000:
                                    backup_data = base64.b64decode(json_response['obj'])
                                    print(f"✅ Бекап получен (JSON/base64) через {endpoint}, размер: {len(backup_data)} байт")
                                    return backup_data
                        except (json.JSONDecodeError, base64.binascii.Error) as e:
                            print(f"⚠️ Ошибка парсинга JSON/base64: {e}")
                            continue
                            
                    # Возможно текстовый ответ, который содержит данные
                    elif content_length > 1000:
                        print(f"✅ Получены данные (text) через {endpoint}, размер: {content_length} байт")
                        return response.content
                        
                else:
                    print(f"❌ Ошибка {response.status_code} для {endpoint}")
                    
            except Exception as e:
                print(f"❌ Исключение для {endpoint}: {e}")
                continue
        
        print("❌ Не удалось получить бекап ни одним из способов")
        return None

    def get_system_status(self) -> Dict:
        """Получение статуса системы: CPU, RAM, диск"""
        if not self.is_authenticated:
            if not self.authenticate():
                return {}
        try:
            # Пробуем разные endpoints для системной информации
            endpoints = [
                f"{self.base_url}/server/status",
                f"{self.base_url}/panel/api/server/status",
                f"{self.base_url}/xui/API/server/status"
            ]
            
            for endpoint in endpoints:
                try:
                    response = self.session.post(endpoint, timeout=10)
                    if response.status_code == 200:
                        result = response.json()
                        if result.get('success') and result.get('obj'):
                            obj = result.get('obj', {})
                            
                            # Отладочный вывод для понимания структуры данных
                            print(f"🔍 Системная информация из API: {obj}")
                            
                            return obj
                except Exception as e:
                    print(f"❌ Ошибка endpoint {endpoint}: {e}")
                    continue
            
            return {}
        except Exception as e:
            print(f"❌ Ошибка получения статуса системы: {e}")
            return {}

    def get_monthly_traffic_stats(self) -> Dict:
        """Получить статистику трафика сервера за текущий месяц"""
        if not self.is_authenticated:
            if not self.authenticate():
                return {}
        try:
            # Пробуем разные endpoints для месячной статистики
            endpoints = [
                f"{self.base_url}/xui/API/server/status",
                f"{self.base_url}/server/status", 
                f"{self.base_url}/panel/api/server/status"
            ]
            
            for endpoint in endpoints:
                try:
                    response = self.session.post(endpoint, timeout=10)
                    if response.status_code == 200:
                        result = response.json()
                        if result.get('success') and result.get('obj'):
                            obj = result['obj']
                            # Получаем месячный трафик из netTraffic
                            net_traffic = obj.get('netTraffic', {})
                            total_sent = net_traffic.get('sent', 0) / (1024**3)  # Конвертируем в GB
                            total_recv = net_traffic.get('recv', 0) / (1024**3)
                            total_monthly_gb = total_recv  # Только входящий трафик (скачивание)
                            
                            return {
                                'total_monthly_gb': round(total_monthly_gb, 2),
                                'sent_gb': round(total_sent, 2),
                                'recv_gb': round(total_recv, 2)
                            }
                except:
                    continue
            
            # Если API не предоставляет данные, вычисляем из пользователей
            users = self.get_users_list()
            monthly_traffic = 0
            for user in users:
                if isinstance(user['used_gb'], (int, float)):
                    monthly_traffic += user['used_gb']
            
            return {
                'total_monthly_gb': round(monthly_traffic, 2),
                'sent_gb': 0,
                'recv_gb': 0
            }
        except Exception as e:
            print(f"❌ Ошибка получения месячной статистики трафика: {e}")
            return {}

    def get_top_users_by_traffic(self, limit: int = 10) -> List[Dict]:
        """Получить топ пользователей по трафику"""
        users = self.get_users_list()
        if not users:
            return []
        
        # Сортируем по использованному трафику
        sorted_users = sorted(users, key=lambda x: x['used_gb'] if isinstance(x['used_gb'], (int, float)) else 0, reverse=True)
        return sorted_users[:limit]
    
    def _generate_sub_id(self) -> str:
        """Генерация subId"""
        import random
        import string
        return ''.join(random.choices(string.ascii_lowercase + string.digits, k=16))
    
    def get_client_config(self, username: str) -> Optional[str]:
        """VLESS конфигурация по email"""
        if not self.is_authenticated:
            if not self.authenticate():
                return None
        try:
            users = self.get_users_list()
            target_user = next((u for u in users if u['email'].lower().strip() == username.lower().strip()), None)
            if not target_user:
                return None
            return self._generate_vless_config(target_user)
        except Exception as e:
            print(f"❌ Ошибка получения конфигурации: {e}")
            return None
    
    def _generate_vless_config(self, user: Dict) -> str:
        """Генерация VLESS URL"""
        try:
            server_host = self.server_config['server_ip']
            protocol = user['protocol']
            port = user['inbound_port']
            inbound_id = user.get('inbound_id')
            detailed_settings = self.get_detailed_inbound_settings(inbound_id)
            client_id = None
            if detailed_settings and 'settings' in detailed_settings:
                detailed_clients_str = detailed_settings['settings']
                detailed_clients = json.loads(detailed_clients_str) if isinstance(detailed_clients_str, str) else detailed_clients_str
                for client in detailed_clients.get('clients', []):
                    if client.get('email') == user['email']:
                        client_id = client.get('id')
                        break
            if not client_id:
                client_id = user.get('client_id', str(uuid.uuid4()))
            if protocol == 'vless':
                config = f"vless://{client_id}@{server_host}:{port}"
                params = []
                stream_settings = {}
                if detailed_settings and 'streamSettings' in detailed_settings:
                    stream_settings_str = detailed_settings['streamSettings']
                    stream_settings = json.loads(stream_settings_str) if isinstance(stream_settings_str, str) else stream_settings_str
                network = stream_settings.get('network', 'tcp')
                params.append(f"type={network}")
                params.append("encryption=none")
                security = stream_settings.get('security', 'none')
                params.append(f"security={security}")
                params.append("flow=xtls-rprx-vision")
                if security == 'reality':
                    reality_settings = stream_settings.get('realitySettings', {})
                    public_key = None
                    if 'settings' in reality_settings and 'publicKey' in reality_settings['settings']:
                        public_key = reality_settings['settings']['publicKey']
                    elif 'publicKey' in reality_settings:
                        public_key = reality_settings['publicKey']
                    if public_key:
                        params.append(f"pbk={public_key}")
                    fp = 'firefox'
                    if 'settings' in reality_settings and 'fingerprint' in reality_settings['settings']:
                        fp = reality_settings['settings']['fingerprint']
                    elif 'fingerprint' in reality_settings:
                        fp = reality_settings['fingerprint']
                    params.append(f"fp={fp}")
                    server_names = reality_settings.get('serverNames', [])
                    sni = server_names[0] if server_names else 'ign.com'
                    params.append(f"sni={sni}")
                    short_ids = reality_settings.get('shortIds', [])
                    if short_ids:
                        params.append(f"sid={short_ids[0]}")
                    spx = '/'
                    if 'settings' in reality_settings and 'spiderX' in reality_settings['settings']:
                        spx = reality_settings['settings']['spiderX']
                    elif 'spiderX' in reality_settings:
                        spx = reality_settings['spiderX']
                    params.append(f"spx={urllib.parse.quote(spx, safe='')}")
                if params:
                    config += "?" + "&".join(params)
                encoded_email = urllib.parse.quote(user['email'], safe='')
                config += f"#vless-{encoded_email}"
                return config
            else:
                return f"{protocol}://config_for_{user['email']}@{server_host}:{port}"
        except Exception as e:
            print(f"❌ Ошибка генерации конфигурации: {e}")
            return f"ERROR: Could not generate config for {user.get('email', 'unknown')}"
    
    def get_user_stats(self, username: str):
        """Статистика по конкретному пользователю"""
        users = self.get_users_list()
        for user in users:
            if user['email'].lower().strip() == username.lower().strip():
                return user
        return None

    def get_server_stats(self) -> Dict:
        """Статистика по серверу - только месячный трафик"""
        if not self.is_authenticated:
            if not self.authenticate():
                return {}
        try:
            users = self.get_users_list()
            total_users = len(users)
            active_users = len([u for u in users if u.get('enable')])
            
            # Получить месячную статистику трафика
            monthly_stats = self.get_monthly_traffic_stats()
            total_monthly_gb = monthly_stats.get('total_monthly_gb', 0.0)
            
            # Получить статус системы
            system_status = self.get_system_status()
            
            response = self.session.post(f"{self.base_url}/xui/API/inbounds/list", timeout=10)
            inbounds_count = 0
            if response.status_code == 200:
                result = response.json()
                if result.get('success'):
                    inbounds_count = len(result.get('obj', []))
            
            return {
                'total_users': total_users,
                'active_users': active_users,
                'total_monthly_traffic_gb': total_monthly_gb,  # Только месячный трафик
                'inbounds_count': inbounds_count,
                'system_status': system_status
            }
        except Exception as e:
            print(f"❌ Ошибка получения статистики: {e}")
            return {}


def get_vpn_manager(user_id: int) -> VPNManager:
    """Экземпляр VPNManager для текущего сервера"""
    server_config = get_current_server_config(user_id)
    return VPNManager(server_config)

def is_admin(user_id: int) -> bool:
    """Проверка прав"""
    return user_id == ADMIN_USER_ID

def generate_qr_code(text: str) -> io.BytesIO:
    """QR-code для строки конфигурации"""
    qr = qrcode.QRCode(version=1, box_size=10, border=5)
    qr.add_data(text)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    bio = io.BytesIO()
    img.save(bio, 'PNG')
    bio.seek(0)
    return bio

def create_servers_keyboard() -> types.InlineKeyboardMarkup:
    """Клавиатура выбора сервера"""
    markup = types.InlineKeyboardMarkup(row_width=1)
    for server_id, server_config in SERVERS_CONFIG.items():
        markup.add(
            types.InlineKeyboardButton(
                text=f"{server_config['name']}",
                callback_data=f"select_server_{server_id}"
            )
        )
    return markup

def create_users_keyboard(users: List[Dict], page: int = 0, per_page: int = 10) -> types.InlineKeyboardMarkup:
    """Клавиатура со списком пользователей (пагинация)"""
    start_idx = page * per_page
    end_idx = min(len(users), start_idx + per_page)
    users_page = users[start_idx:end_idx]
    markup = types.InlineKeyboardMarkup(row_width=2)
    buttons = []
    for user in users_page:
        status_icon = "✅" if user['enable'] else "🚫"
        buttons.append(
            types.InlineKeyboardButton(
                f"{status_icon} {user['email']}",
                callback_data=f"user_details|{safe_encode_username(user['email'])}"
            )
        )
    for i in range(0, len(buttons), 2):
        if i + 1 < len(buttons):
            markup.row(buttons[i], buttons[i + 1])
        else:
            markup.row(buttons[i])
    nav_buttons = []
    total_pages = (len(users) + per_page - 1) // per_page
    if page > 0:
        nav_buttons.append(types.InlineKeyboardButton("◀️ Назад", callback_data=f"users_page_{page-1}"))
    if total_pages > 1:
        nav_buttons.append(types.InlineKeyboardButton(f"📄 {page+1}/{total_pages}", callback_data="noop"))
    if page < total_pages - 1:
        nav_buttons.append(types.InlineKeyboardButton("Вперед ▶️", callback_data=f"users_page_{page+1}"))
    if nav_buttons:
        markup.row(*nav_buttons)
    return markup

def get_bot_uptime() -> str:
    """Аптайм бота в человекочитаемом формате"""
    uptime = datetime.now() - bot_start_time
    days = uptime.days
    hours, remainder = divmod(uptime.seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    if days > 0:
        return f"{days}д {hours}ч {minutes}м {seconds}с"
    elif hours > 0:
        return f"{hours}ч {minutes}м {seconds}с"
    elif minutes > 0:
        return f"{minutes}м {seconds}с"
    else:
        return f"{seconds}с"

def send_startup_message():
    """Сообщение администратору о запуске"""
    try:
        startup_message = f"🚀 **Бот успешно запущен!**\n\n"
        startup_message += f"⏰ Время запуска: {bot_start_time.strftime('%Y-%m-%d %H:%M:%S')}\n"
        startup_message += f"👤 Администратор: `{ADMIN_USER_ID}`\n\n"
        startup_message += f"🌐 **Доступные серверы:**\n"
        for server_id, server_config in SERVERS_CONFIG.items():
            startup_message += f"   • {server_config['name']}: `{server_config['host']}{server_config['path']}`\n"
        startup_message += "\n✅ Бот готов к работе!"
        bot.send_message(ADMIN_USER_ID, startup_message, parse_mode='Markdown')
        print("✅ Сообщение о запуске отправлено администратору")
    except Exception as e:
        print(f"❌ Ошибка отправки сообщения о запуске: {e}")

        # ============================================
# МОНИТОРИНГ СЕРВЕРОВ
# ============================================

def check_server_health(server_id: str, server_config: Dict) -> Dict:
    """
    Проверка здоровья конкретного сервера
    Возвращает словарь с результатами проверки
    """
    result = {
        'server_id': server_id,
        'server_name': server_config['name'],
        'is_healthy': False,
        'response_time_ms': None,
        'error': None,
        'timestamp': datetime.now()
    }
    
    try:
        start_time = time.time()
        
        # Создаем временный VPNManager для проверки
        manager = VPNManager(server_config)
        
        # Пытаемся аутентифицироваться
        auth_success = manager.authenticate()
        
        if auth_success:
            # Проверяем, что API отвечает
            health_check = manager.check_server_health()
            
            end_time = time.time()
            response_time = (end_time - start_time) * 1000  # В миллисекундах
            
            result['is_healthy'] = health_check
            result['response_time_ms'] = round(response_time, 2)
            
            print(f"✅ Сервер {server_config['name']}: OK ({response_time:.2f}ms)")
        else:
            result['error'] = "Ошибка аутентификации"
            print(f"❌ Сервер {server_config['name']}: ошибка аутентификации")
            
    except requests.exceptions.ConnectionError as e:
        result['error'] = f"Ошибка подключения: {str(e)}"
        print(f"❌ Сервер {server_config['name']}: недоступен (ConnectionError)")
    except requests.exceptions.Timeout as e:
        result['error'] = f"Таймаут: {str(e)}"
        print(f"❌ Сервер {server_config['name']}: таймаут")
    except Exception as e:
        result['error'] = f"Неизвестная ошибка: {str(e)}"
        print(f"❌ Сервер {server_config['name']}: {e}")
    
    return result


def monitor_all_servers():
    """
    Фоновая задача: проверка всех серверов и отправка алертов при проблемах
    """
    print(f"🔍 [{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Запуск проверки серверов...")
    
    for server_id, server_config in SERVERS_CONFIG.items():
        try:
            health_result = check_server_health(server_id, server_config)
            
            # Получаем предыдущий статус сервера
            previous_status = server_last_status.get(server_id, True)
            current_status = health_result['is_healthy']
            
            # Обновляем текущий статус
            server_last_status[server_id] = current_status
            
            # Если статус изменился - отправляем уведомление
            if previous_status and not current_status:
                # Сервер упал
                send_server_down_alert(health_result)
            elif not previous_status and current_status:
                # Сервер восстановился
                send_server_up_alert(health_result)
                
        except Exception as e:
            print(f"❌ Ошибка при проверке сервера {server_id}: {e}")
            print(traceback.format_exc())


def send_server_down_alert(health_result: Dict):
    """
    Отправка алерта администратору о недоступности сервера
    """
    try:
        server_name = health_result['server_name']
        error_msg = health_result.get('error', 'Неизвестная ошибка')
        timestamp = health_result['timestamp'].strftime('%Y-%m-%d %H:%M:%S')
        
        alert_message = f"🚨 **АЛЕРТ: Сервер недоступен!**\n\n"
        alert_message += f"🌐 Сервер: `{safe_markdown_text(server_name)}`\n"
        alert_message += f"❌ Статус: Недоступен\n"
        alert_message += f"⚠️ Ошибка: `{safe_markdown_text(error_msg)}`\n"
        alert_message += f"🕐 Время: `{timestamp}`\n\n"
        alert_message += "Пожалуйста, проверьте состояние сервера как можно скорее."
        
        bot.send_message(
            ADMIN_USER_ID,
            alert_message,
            parse_mode='Markdown',
            disable_web_page_preview=True
        )
        
        print(f"📨 Отправлен алерт о падении сервера: {server_name}")
        
    except Exception as e:
        print(f"❌ Ошибка отправки алерта: {e}")


def send_server_up_alert(health_result: Dict):
    """
    Отправка уведомления о восстановлении сервера
    """
    try:
        server_name = health_result['server_name']
        response_time = health_result.get('response_time_ms', 'N/A')
        timestamp = health_result['timestamp'].strftime('%Y-%m-%d %H:%M:%S')
        
        alert_message = f"✅ **Сервер восстановлен!**\n\n"
        alert_message += f"🌐 Сервер: `{safe_markdown_text(server_name)}`\n"
        alert_message += f"✅ Статус: Работает\n"
        alert_message += f"⚡ Время ответа: `{response_time} ms`\n"
        alert_message += f"🕐 Время восстановления: `{timestamp}`"
        
        bot.send_message(
            ADMIN_USER_ID,
            alert_message,
            parse_mode='Markdown',
            disable_web_page_preview=True
        )
        
        print(f"📨 Отправлено уведомление о восстановлении сервера: {server_name}")
        
    except Exception as e:
        print(f"❌ Ошибка отправки уведомления: {e}")


# ============================================
# АВТОМАТИЧЕСКИЕ ОТЧЕТЫ
# ============================================

def generate_traffic_report(period: str = 'daily') -> str:
    """
    Генерация отчета по трафику и пользователям за период
    period: 'daily' или 'weekly'
    """
    try:
        # Разные заголовки для разных периодов
        if period == 'weekly':
            report = f"📈 **ЕЖЕНЕДЕЛЬНЫЙ ОТЧЕТ**\n"
            report += f"📅 Период: {(datetime.now() - timedelta(days=7)).strftime('%d.%m.%Y')} - {datetime.now().strftime('%d.%m.%Y')}\n"
            report += f"🕐 Сгенерирован: `{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}`\n\n"
        else:
            report = f"📊 **ЕЖЕДНЕВНЫЙ ОТЧЕТ**\n"
            report += f"📅 Дата: `{datetime.now().strftime('%d.%m.%Y (%A)')}`\n"
            report += f"🕐 Время: `{datetime.now().strftime('%H:%M:%S')}`\n\n"
        
        total_users_all = 0
        total_active_all = 0
        total_inactive_all = 0
        total_traffic_all = 0.0
        all_servers_status = []
        
        for server_id, server_config in SERVERS_CONFIG.items():
            try:
                server_name = server_config['name']
                report += f"━━━━━━━━━━━━━━━━━━━━\n"
                report += f"🌐 **{safe_markdown_text(server_name)}**\n\n"
                
                # Проверяем здоровье сервера
                health = check_server_health(server_id, server_config)
                
                if not health['is_healthy']:
                    report += f"❌ Статус: Недоступен\n"
                    report += f"⚠️ Ошибка: `{safe_markdown_text(health.get('error', 'N/A'))}`\n\n"
                    all_servers_status.append({'name': server_name, 'status': '❌ Недоступен'})
                    continue
                
                report += f"✅ Статус: Работает ({health.get('response_time_ms', 'N/A')} ms)\n\n"
                all_servers_status.append({'name': server_name, 'status': f"✅ Работает ({health.get('response_time_ms', 'N/A')} ms)"})
                
                # Получаем статистику сервера
                manager = VPNManager(server_config)
                if not manager.authenticate():
                    report += "⚠️ Не удалось получить статистику\n\n"
                    continue
                
                stats = manager.get_server_stats()
                users = manager.get_users_list()
                
                total_users = stats.get('total_users', 0)
                active_users = stats.get('active_users', 0)
                inactive_users = total_users - active_users
                monthly_traffic = stats.get('total_monthly_traffic_gb', 0.0)
                
                total_users_all += total_users
                total_active_all += active_users
                total_inactive_all += inactive_users
                total_traffic_all += monthly_traffic
                
                report += f"👥 Всего пользователей: `{total_users}`\n"
                report += f"✅ Активных: `{active_users}`"
                if active_users > 0:
                    report += f" ({(active_users/total_users*100):.1f}%)" if total_users > 0 else ""
                report += f"\n"
                report += f"❌ Неактивных: `{inactive_users}`\n"
                report += f"📈 Трафик за месяц: `{monthly_traffic:.2f} GB`\n\n"
                
                # Топ-5 пользователей по трафику
                top_users = manager.get_top_users_by_traffic(limit=5 if period == 'daily' else 10)
                if top_users:
                    limit_text = "5" if period == 'daily' else "10"
                    report += f"🔝 **Топ-{limit_text} по трафику:**\n"
                    for idx, user in enumerate(top_users, 1):
                        used_gb = user.get('used_gb', 0)
                        if isinstance(used_gb, (int, float)):
                            status_icon = "✅" if user.get('enable') else "🚫"
                            email = safe_markdown_text(user.get('email', 'N/A'))
                            report += f"{idx}\\. {status_icon} `{email}`: {used_gb:.2f} GB\n"
                    report += "\n"
                
            except Exception as e:
                report += f"❌ Ошибка получения данных: `{safe_markdown_text(str(e))}`\n\n"
        
        # Общая статистика
        report += f"━━━━━━━━━━━━━━━━━━━━\n"
        report += f"📊 **ИТОГО ПО ВСЕМ СЕРВЕРАМ:**\n\n"
        report += f"👥 Всего пользователей: `{total_users_all}`\n"
        report += f"✅ Активных: `{total_active_all}`"
        if total_users_all > 0:
            report += f" ({(total_active_all/total_users_all*100):.1f}%)"
        report += f"\n"
        report += f"❌ Неактивных: `{total_inactive_all}`\n"
        report += f"📈 Общий трафик: `{total_traffic_all:.2f} GB`\n"
        
        # Для недельного отчета добавляем дополнительную информацию
        if period == 'weekly':
            report += f"\n🔄 **Статус серверов:**\n"
            for srv in all_servers_status:
                report += f"• {safe_markdown_text(srv['name'])}: {srv['status']}\n"
            
            # Средний трафик на пользователя
            if total_active_all > 0:
                avg_traffic = total_traffic_all / total_active_all
                report += f"\n📊 Средний трафик на активного пользователя: `{avg_traffic:.2f} GB`\n"
        
        return report
        
    except Exception as e:
        print(f"❌ Ошибка генерации отчета: {e}")
        print(traceback.format_exc())
        return f"❌ Ошибка генерации отчета: {safe_markdown_text(str(e))}"

def send_daily_report():
    """
    Фоновая задача: отправка ежедневного отчета
    """
    print(f"📊 [{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Генерация ежедневного отчета...")
    
    try:
        report = generate_traffic_report(period='daily')
        send_long_message(bot, ADMIN_USER_ID, report, parse_mode='Markdown')
        print("✅ Ежедневный отчет отправлен")
    except Exception as e:
        print(f"❌ Ошибка отправки ежедневного отчета: {e}")
        print(traceback.format_exc())


def send_weekly_report():
    """
    Фоновая задача: отправка еженедельного отчета
    """
    print(f"📊 [{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Генерация еженедельного отчета...")
    
    try:
        report = generate_traffic_report(period='weekly')
        send_long_message(bot, ADMIN_USER_ID, report, parse_mode='Markdown')
        print("✅ Еженедельный отчет отправлен")
    except Exception as e:
        print(f"❌ Ошибка отправки еженедельного отчета: {e}")
        print(traceback.format_exc())


# ============================================
# ПЛАНИРОВЩИК ЗАДАЧ
# ============================================

def start_scheduler():
    """
    Запуск планировщика фоновых задач
    """
    try:
        # Проверка здоровья серверов каждые N минут
        scheduler.add_job(
            monitor_all_servers,
            trigger=IntervalTrigger(minutes=HEALTH_CHECK_INTERVAL_MINUTES),
            id='health_check',
            name='Проверка серверов',
            replace_existing=True
        )
        print(f"✅ Задача 'Проверка серверов' запланирована (каждые {HEALTH_CHECK_INTERVAL_MINUTES} минут)")
        
        # Ежедневный отчет
        scheduler.add_job(
            send_daily_report,
            trigger=CronTrigger(hour=DAILY_REPORT_HOUR, minute=DAILY_REPORT_MINUTE),
            id='daily_report',
            name='Ежедневный отчет',
            replace_existing=True
        )
        print(f"✅ Задача 'Ежедневный отчет' запланирована ({DAILY_REPORT_HOUR:02d}:{DAILY_REPORT_MINUTE:02d})")
        
        # Еженедельный отчет
        scheduler.add_job(
            send_weekly_report,
            trigger=CronTrigger(
                day_of_week=WEEKLY_REPORT_DAY,
                hour=WEEKLY_REPORT_HOUR,
                minute=WEEKLY_REPORT_MINUTE
            ),
            id='weekly_report',
            name='Еженедельный отчет',
            replace_existing=True
        )
        print(f"✅ Задача 'Еженедельный отчет' запланирована ({WEEKLY_REPORT_DAY} {WEEKLY_REPORT_HOUR:02d}:{WEEKLY_REPORT_MINUTE:02d})")
        
        # Запускаем планировщик
        scheduler.start()
        print("✅ Планировщик задач запущен")
        
    except Exception as e:
        print(f"❌ Ошибка запуска планировщика: {e}")
        print(traceback.format_exc())


def shutdown_scheduler():
    """
    Корректное завершение работы планировщика
    """
    try:
        if scheduler.running:
            scheduler.shutdown(wait=False)
            print("✅ Планировщик задач остановлен")
    except Exception as e:
        print(f"❌ Ошибка остановки планировщика: {e}")

def show_user_details(chat_id, username, user_id):
    """Детали пользователя + кнопки действий с месячным трафиком"""
    vpn_manager = get_vpn_manager(user_id)
    user_stats = vpn_manager.get_user_stats(username)
    if not user_stats:
        bot.send_message(chat_id, f"❌ Пользователь {username} не найден")
        return
    
    status = "✅ Активен" if user_stats['enable'] else "🚫 Заблокирован"
    if isinstance(user_stats['total_gb'], str):
        limit_text = user_stats['total_gb']
        usage_percent = "N/A"
    else:
        limit_text = f"{user_stats['total_gb']:.2f} GB"
        usage_percent = f"{(user_stats['used_gb'] / user_stats['total_gb']) * 100:.1f}%" if user_stats['total_gb'] > 0 else "N/A"
    
    used_text = f"{user_stats['used_gb']:.2f} GB"
    
    markup = types.InlineKeyboardMarkup()
    # Всегда используем safe_encode_username для callback_data
    username_encoded = safe_encode_username(username)
    markup.row(
        types.InlineKeyboardButton("📄 VLESS", callback_data=f"download_vless|{username_encoded}"),
        types.InlineKeyboardButton("🎯 QR-код", callback_data=f"download_qr|{username_encoded}")
    )
    markup.add(types.InlineKeyboardButton("🗑️ Удалить", callback_data=f"delete_user_confirm|{username_encoded}"))
    markup.add(types.InlineKeyboardButton("⬅️ К списку пользователей", callback_data="users_page_0"))
    
    current_server = get_current_server_config(user_id)
    
    # ИСПРАВЛЕНИЕ: Экранируем все динамические тексты
    safe_username = safe_markdown_text(username)
    safe_server_name = safe_markdown_text(current_server['name'])
    
    response = f"📊 **Пользователь {safe_username}**\n\n"
    response += f"🌐 Сервер: {safe_server_name}\n"
    response += f"📊 Статус: {status}\n"
    response += f"💾 Лимит трафика: {limit_text}\n"
    response += f"📈 Использовано всего: {used_text}\n"
    response += f"📅 **Трафик за текущий месяц: {used_text}**\n"
    if usage_percent != "N/A":
        response += f"📊 Процент использования: {usage_percent}\n"
    response += f"⏰ Действует до: {user_stats['expiry_time']}\n"
    response += f"🌐 Протокол: {user_stats['protocol']}\n"
    response += f"🔌 Порт: {user_stats['inbound_port']}\n"
    response += f"🆔 Inbound ID: {user_stats['inbound_id']}\n"
    
    bot.send_message(chat_id, response, reply_markup=markup, parse_mode='Markdown')

# ===== Inbound helpers =====

def get_inbounds_for_server(user_id: int) -> List[Dict]:
    vm = get_vpn_manager(user_id)
    inbounds = vm.get_available_inbounds()
    result = []
    for ib in inbounds:
        remark = ib.get('remark') or ''
        proto = ib.get('protocol', 'n/a')
        port = ib.get('port', 'n/a')
        label = remark if remark else f"{proto}:{port}"
        result.append({'id': ib.get('id'), 'protocol': proto, 'port': port, 'remark': label})
    return result

def build_inbounds_keyboard(inbounds: List[Dict], action: str, extra: str = "") -> types.InlineKeyboardMarkup:
    """
    action (пример):
      - inbound_for_search
      - inbound_for_create|{username}_{total_gb}_{expiry_days}
      - inbound_for_delete|{username_hex}
    """
    markup = types.InlineKeyboardMarkup(row_width=2)
    btns = []
    for ib in inbounds:
        text = f"{ib['remark']} ({ib['protocol']}:{ib['port']})" if ib.get('remark') else f"{ib['protocol']}:{ib['port']}"
        cb = f"select_inbound|{action}"
        if extra:
            cb += f"|{extra}"
        cb += f"|{ib['id']}"
        btns.append(types.InlineKeyboardButton(text, callback_data=cb))
    for i in range(0, len(btns), 2):
        if i + 1 < len(btns):
            markup.row(btns[i], btns[i+1])
        else:
            markup.row(btns[i])
    return markup

def build_inbounds_keyboard_safe(inbounds: List[Dict], action: str, user_id: int) -> types.InlineKeyboardMarkup:
    """Безопасная клавиатура inbound'ов без передачи username в callback_data"""
    markup = types.InlineKeyboardMarkup(row_width=2)
    btns = []
    for ib in inbounds:
        text = f"{ib['remark']} ({ib['protocol']}:{ib['port']})" if ib.get('remark') else f"{ib['protocol']}:{ib['port']}"
        # Передаем только action, user_id и inbound_id
        cb = f"select_inbound|{action}|{user_id}|{ib['id']}"
        btns.append(types.InlineKeyboardButton(text, callback_data=cb))
    
    for i in range(0, len(btns), 2):
        if i + 1 < len(btns):
            markup.row(btns[i], btns[i+1])
        else:
            markup.row(btns[i])
    return markup

# ===== СТРУКТУРА МЕНЮ =====

def create_main_menu_keyboard() -> types.ReplyKeyboardMarkup:
    """Создание главного меню с 3 основными кнопками"""
    markup = types.ReplyKeyboardMarkup(resize_keyboard=True, row_width=3)
    markup.add(
        types.KeyboardButton("🌐 Сервер"),
        types.KeyboardButton("👥 Пользователи"),
        types.KeyboardButton("ℹ️ Помощь")
    )
    return markup

def create_server_menu_keyboard() -> types.InlineKeyboardMarkup:
    """Создание меню сервера с системным мониторингом и аналитикой"""
    markup = types.InlineKeyboardMarkup(row_width=2)
    markup.add(
        types.InlineKeyboardButton("🔄 Выбрать сервер", callback_data="menu_select_server"),
        types.InlineKeyboardButton("📊 Статистика", callback_data="menu_server_stats")
    )
    markup.add(
        types.InlineKeyboardButton("🖥️ Системный мониторинг", callback_data="menu_system_monitor"),
        types.InlineKeyboardButton("📈 Аналитика трафика", callback_data="menu_traffic_analytics")
    )
    markup.add(
        types.InlineKeyboardButton("💾 Экспорт бекапа", callback_data="menu_export_backup"),
        types.InlineKeyboardButton("🔄 Перезапуск", callback_data="menu_restart")
    )
    return markup

def create_users_menu_keyboard() -> types.InlineKeyboardMarkup:
    """Создание меню пользователей"""
    markup = types.InlineKeyboardMarkup(row_width=2)
    markup.add(
        types.InlineKeyboardButton("👥 Список", callback_data="menu_users_list"),
        types.InlineKeyboardButton("🔍 Поиск", callback_data="menu_users_search")
    )
    markup.add(
        types.InlineKeyboardButton("➕ Создать", callback_data="menu_users_create"),
        types.InlineKeyboardButton("🗑️ Удалить", callback_data="menu_users_delete")
    )
    return markup


# ===== Команды и кнопки =====

@bot.message_handler(commands=['start'])
def start_command(message):
    if not is_admin(message.from_user.id):
        bot.reply_to(message, "❌ У вас нет прав доступа к этому боту.")
        return
    
    markup = create_main_menu_keyboard()
    current_server = get_current_server_config(message.from_user.id)
    
    bot.reply_to(message, 
                 f"🤖 Добро пожаловать в VPN Manager Bot!\n\n"
                 f"🌐 Текущий сервер: {current_server['name']}\n\n"
                 "Выберите раздел для управления VPN сервером:",
                 reply_markup=markup)

from telebot import types

@bot.message_handler(commands=['webapp'])
def webapp_menu(message):
    markup = types.ReplyKeyboardMarkup(resize_keyboard=True)
    btn_webapp = types.KeyboardButton(
    text="Открыть WebApp",
    web_app=types.WebAppInfo("https://77.221.139.72:8443/"))
    markup.add(btn_webapp)
    bot.send_message(message.chat.id, "WebApp запущен!", reply_markup=markup)

@bot.message_handler(func=lambda message: message.text == "🌐 Сервер")
def server_menu(message):
    if not is_admin(message.from_user.id):
        return
    current_server = get_current_server_config(message.from_user.id)
    markup = create_server_menu_keyboard()
    
    response = f"🌐 **Управление сервером**\n\n"
    response += f"📍 Текущий сервер: {current_server['name']}\n"
    response += f"🔗 URL: `{current_server['host']}{current_server['path']}`\n"
    response += f"🖥️ IP: `{current_server['server_ip']}`\n\n"
    response += "Выберите действие:"
    
    bot.reply_to(message, response, parse_mode='Markdown', reply_markup=markup)

@bot.message_handler(func=lambda message: message.text == "👥 Пользователи")
def users_menu(message):
    if not is_admin(message.from_user.id):
        return
    current_server = get_current_server_config(message.from_user.id)
    markup = create_users_menu_keyboard()
    
    response = f"👥 **Управление пользователями**\n\n"
    response += f"🌐 Текущий сервер: {current_server['name']}\n\n"
    response += "Выберите действие:"
    
    bot.reply_to(message, response, parse_mode='Markdown', reply_markup=markup)

@bot.message_handler(func=lambda message: message.text == "ℹ️ Помощь")
def help_button_command(message):
    help_text = f"""🤖 VPN Manager Bot - Полное руководство

Добро пожаловать в VPN Manager Bot! Этот бот предназначен для профессионального управления VPN серверами на базе 3X-UI с поддержкой нескольких серверов и выбором inbound при поиске, создании и удалении пользователей.

━━━━━━━━━━━━━━━━━━━━━━━━━━
🌟 ОСНОВНЫЕ ВОЗМОЖНОСТИ

🔸 Мультисерверное управление — подключение к нескольким VPN серверам
🔸 Полное управление пользователями — создание, удаление, мониторинг
🔸 Интеллектуальный поиск — быстрый поиск по имени с выбором inbound
🔸 Детальная аналитика — общая статистика сервера
🔸 Генерация VLESS конфигураций и QR-кодов
🔸 Экспорт бекапов базы данных
🔸 Системный мониторинг — CPU, RAM, диск
🔸 Аналитика трафика — топ пользователей по использованию
🔸 Безопасность — подтверждения и ограничения доступа

━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 ГЛАВНОЕ МЕНЮ

🌐 **Сервер**
   🔄 Выбрать сервер — переключение между VPN серверами
   📊 Статистика — метрики по текущему серверу
   🖥️ Системный мониторинг — отображение CPU, RAM, диска
   📈 Аналитика трафика — топ пользователей по использованию
   💾 Экспорт бекапа — скачать базу данных для восстановления
   🔄 Перезапуск — перезапуск бота
   🔧 Мониторинг- управление мониторингом и отчетами

👥 **Пользователи**
   👥 Список — просмотр всех пользователей с пагинацией
   🔍 Поиск — поиск по частичному имени с выбором inbound
   ➕ Создать — создание нового пользователя в выбранном inbound
   🗑️ Удалить — удаление пользователя из выбранного inbound

ℹ️ **Помощь** — это руководство

━━━━━━━━━━━━━━━━━━━━━━━━━━
👤 ПРОФИЛЬ ПОЛЬЗОВАТЕЛЯ

📋 Основные данные:
   • Имя, статус активности
   • Сервер, протокол, порт, Inbound ID

📊 Статистика трафика:
   • Лимит (или «Безлимит»)
   • Использовано всего (GB)
   • Трафик за текущий месяц (GB)
   • Процент использования

⏰ Временные параметры:
   • Дата окончания / бессрочно

🛠️ Действия:
   • 📄 VLESS — скачать конфигурационный файл
   • 🎯 QR-код — получить QR-код для быстрого подключения
   • 🗑️ Удалить — удаление с подтверждением

━━━━━━━━━━━━━━━━━━━━━━━━━━
⚙️ СИСТЕМНЫЕ КОМАНДЫ

/start — главное меню
/help — краткая справка
/status — статус бота и текущего сервера
/servers — список всех серверов со статусами
/restart — перезапуск бота (только администратор)
/id — ваш Telegram ID и статус доступа
/monitoring - управление мониторингом и отчетами

━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 ТЕХНИЧЕСКИЕ ОСОБЕННОСТИ

🌐 Протоколы:
   • VLESS (flow: xtls-rprx-vision)
   • VMess, Shadowsocks, Trojan (если настроены в панели)

🔒 Безопасность:
   • Проверка прав администратора для всех операций
   • Двойное подтверждение при удалении пользователей
   • Hex-кодирование имен в callback'ах для поддержки спецсимволов

⚡ Производительность:
   • Пагинация списков пользователей (по 10 на страницу)
   • Повторная аутентификация при необходимости
   • Поллинг с автоперезапуском при сбоях

💾 Бекапы:
   • Экспорт полной базы данных 3x-ui в формате .db
   • Автоматический поиск правильного API endpoint
   • Поддержка различных версий панели

📊 Мониторинг:
   • Системная информация: CPU, RAM, диск
   • Детальная аналитика трафика по пользователям
   • Месячная статистика использования

━━━━━━━━━━━━━━━━━━━━━━━━━━
🆘 ПОДДЕРЖКА

Администратор: {ADMIN_USER_ID}
Время работы: {get_bot_uptime()}

💡 Регулярно создавайте бекапы перед внесением изменений
💡 Используйте команду /status для диагностики проблем

© 2025 VPN Manager Bot — Профессиональное управление VPN инфраструктурой
"""
    send_long_message(bot, message.chat.id, help_text)

@bot.message_handler(commands=['help'])
def help_command(message):
    help_text = f"""🤖 VPN Manager Bot — краткая справка

Функции:
• Мультисерверное управление VPN
• Выбор inbound при поиске/создании/удалении
• Конфиги VLESS/QR, статистика, пагинация
• Экспорт бекапов базы данных
• Системный мониторинг и аналитика трафика

Команды:
• /status, /servers, /restart, /id

Аптайм: {get_bot_uptime()}
Подробная помощь: нажмите ℹ️ Помощь в меню"""
    bot.reply_to(message, help_text)

@bot.message_handler(commands=['servers'])
def servers_command(message):
    """Список всех серверов и статус"""
    if not is_admin(message.from_user.id):
        bot.reply_to(message, "❌ У вас нет прав доступа к этому боту.")
        return
    response = "🌐 **Список всех серверов:**\n\n"
    current_server_id = get_current_server_id(message.from_user.id)
    for server_id, server_config in SERVERS_CONFIG.items():
        try:
            vpn_manager = VPNManager(server_config)
            if vpn_manager.authenticate():
                status = "🟢 Доступен"
                stats = vpn_manager.get_server_stats()
                users_info = f" ({stats.get('active_users', 0)}/{stats.get('total_users', 0)} пользователей)"
            else:
                status = "🔴 Недоступен"
                users_info = ""
        except:
            status = "🔴 Ошибка"
            users_info = ""
        current_marker = " 📍" if server_id == current_server_id else ""
        response += f"{server_config['name']}{current_marker}\n"
        response += f"   📡 Статус: {status}{users_info}\n"
        response += f"   🔗 URL: `{server_config['host']}{server_config['path']}`\n"
        response += f"   🖥️ IP: `{server_config['server_ip']}`\n\n"
    bot.reply_to(message, response, parse_mode='Markdown')

@bot.message_handler(commands=['restart'])
def restart_bot_command(message):
    """Перезапуск бота"""
    if not is_admin(message.from_user.id):
        bot.reply_to(message, "❌ У вас нет прав для перезапуска бота.")
        return
    bot.reply_to(message, "🔄 Перезапускаю бота...")
    print("🔄 Получена команда перезапуска")
    bot.stop_polling()
    os.execv(sys.executable, [sys.executable] + sys.argv)

@bot.message_handler(commands=['status'])
def status_command(message):
    """Статус бота и сервера"""
    if not is_admin(message.from_user.id):
        bot.reply_to(message, "❌ У вас нет прав доступа к этому боту.")
        return
    status_text = "🔍 **Статус VPN Manager Bot**\n\n"
    status_text += f"🤖 **Статус бота:** ✅ Активен\n"
    status_text += f"⏰ **Время работы:** {get_bot_uptime()}\n"
    status_text += f"🕐 **Запущен:** {bot_start_time.strftime('%Y-%m-%d %H:%M:%S')}\n\n"
    current_server = get_current_server_config(message.from_user.id)
    status_text += f"🌐 **Текущий сервер:** {current_server['name']}\n"
    status_text += f"🔗 API: `{current_server['host']}{current_server['path']}`\n"
    status_text += f"🖥️ IP сервера: `{current_server['server_ip']}`\n\n"
    status_text += "📡 **Подключение к VPN серверу:**\n"
    try:
        vpn_manager = get_vpn_manager(message.from_user.id)
        test_connection = vpn_manager.authenticate()
        if test_connection:
            status_text += "✅ Подключение к 3X-UI: **Успешно**\n"
            server_health = vpn_manager.check_server_health()
            status_text += "✅ Состояние сервера: **Отличное**\n" if server_health else "⚠️ Состояние сервера: **Есть вопросы**\n"
            try:
                stats = vpn_manager.get_server_stats()
                if stats:
                    status_text += f"👥 Пользователей на сервере: **{stats['total_users']}**\n"
                    status_text += f"✅ Активных: **{stats['active_users']}**\n"
                    status_text += f"📡 Inbound'ов: **{stats['inbounds_count']}**\n"
                    status_text += f"📅 Трафик за месяц: **{stats['total_monthly_traffic_gb']} GB**\n"
                else:
                    status_text += "⚠️ Статистика: **Недоступна**\n"
            except Exception as e:
                status_text += f"❌ Ошибка получения статистики: **{str(e)}**\n"
        else:
            status_text += "❌ Подключение к 3X-UI: **Ошибка**\n"
            status_text += "🔧 Проверьте настройки сервера\n"
    except Exception as e:
        status_text += f"❌ Ошибка подключения: **{str(e)[:50]}...**\n"
    status_text += f"\n👤 **Ваш статус:** Администратор ✅\n"
    status_text += f"🆔 **Ваш ID:** `{message.from_user.id}`\n"
    bot.reply_to(message, status_text, parse_mode='Markdown')

@bot.message_handler(commands=['id'])
def id_command(message):
    """Ваш Telegram ID"""
    user = message.from_user
    id_text = f"🆔 **Ваша информация Telegram:**\n\n"
    id_text += f"👤 **User ID:** `{user.id}`\n"
    if user.username:
        id_text += f"📝 **Username:** @{user.username}\n"
    if user.first_name:
        id_text += f"👤 **Имя:** {user.first_name}\n"
    if user.last_name:
        id_text += f"👤 **Фамилия:** {user.last_name}\n"
    if user.language_code:
        id_text += f"🌐 **Язык:** {user.language_code}\n"
    if is_admin(user.id):
        id_text += f"\n🔑 **Статус:** Администратор ✅\n"
        id_text += f"🛠️ **Права доступа:** Полные права управления VPN\n"
    else:
        id_text += f"\n👤 **Статус:** Обычный пользователь\n"
        id_text += f"❌ **Права доступа:** Нет доступа к управлению VPN\n"
        id_text += f"\n💡 **Для получения доступа:** Обратитесь к администратору с вашим ID: `{user.id}`\n"
    bot.reply_to(message, id_text, parse_mode='Markdown')

# ===== CALLBACK ОБРАБОТЧИКИ МЕНЮ =====

@bot.callback_query_handler(func=lambda call: call.data == "menu_select_server")
def handle_menu_select_server(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    current_server_id = get_current_server_id(call.from_user.id)
    current_server = SERVERS_CONFIG[current_server_id]
    markup = create_servers_keyboard()
    response = f"🌐 **Выберите сервер для управления:**\n\n"
    response += f"📍 Текущий сервер: {current_server['name']}\n"
    response += f"🔗 URL: `{current_server['host']}{current_server['path']}`\n"
    response += f"🖥️ IP: `{current_server['server_ip']}`\n\n"
    response += "Нажмите на сервер для переключения:"
    try:
        bot.edit_message_text(text=response, chat_id=call.message.chat.id, message_id=call.message.message_id, parse_mode='Markdown', reply_markup=markup)
    except:
        bot.send_message(call.message.chat.id, response, parse_mode='Markdown', reply_markup=markup)
    bot.answer_callback_query(call.id)

@bot.callback_query_handler(func=lambda call: call.data == "menu_server_stats")
def handle_menu_server_stats(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    bot.answer_callback_query(call.id, "⏳ Получаю статистику...")
    try:
        current_server = get_current_server_config(call.from_user.id)
        vm = get_vpn_manager(call.from_user.id)
        stats = vm.get_server_stats()
        if not stats:
            response = f"❌ Не удалось получить статистику с сервера {current_server['name']}."
        else:
            response = "📊 **Статистика VPN сервера:**\n\n"
            response += f"🌐 Сервер: {current_server['name']}\n"
            response += f"🖥️ IP сервера: {current_server['server_ip']}\n"
            response += f"👥 Всего пользователей: {stats['total_users']}\n"
            response += f"✅ Активных пользователей: {stats['active_users']}\n"
            response += f"📡 Количество inbound'ов: {stats['inbounds_count']}\n"
            response += f"📅 **Трафик за текущий месяц: {stats['total_monthly_traffic_gb']} GB**"
        try:
            bot.edit_message_text(text=response, chat_id=call.message.chat.id, message_id=call.message.message_id, parse_mode='Markdown')
        except:
            bot.send_message(call.message.chat.id, response, parse_mode='Markdown')
    except Exception as e:
        try:
            bot.edit_message_text(text=f"❌ Ошибка при получении статистики: {e}", chat_id=call.message.chat.id, message_id=call.message.message_id)
        except:
            bot.send_message(call.message.chat.id, f"❌ Ошибка при получении статистики: {e}")

@bot.callback_query_handler(func=lambda call: call.data == "menu_system_monitor")
def handle_system_monitor(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    bot.answer_callback_query(call.id, "⏳ Получаю системную информацию...")
    
    try:
        current_server = get_current_server_config(call.from_user.id)
        vm = get_vpn_manager(call.from_user.id)
        stats = vm.get_server_stats()
        system_status = stats.get('system_status', {})
        
        # Проверяем, что system_status является словарем
        if not isinstance(system_status, dict):
            system_status = {}
        
        response = "🖥️ **Системный мониторинг**\n\n"
        response += f"🌐 Сервер: {current_server['name']}\n\n"
        
        # CPU информация  
        if 'cpu' in system_status:
            cpu_usage = system_status['cpu']
            if isinstance(cpu_usage, (int, float)):
                response += f"🔥 **CPU:**\n"
                response += f"   Использование: {cpu_usage:.1f}%\n"
                if 'cpuCores' in system_status:
                    response += f"   Ядра: {system_status['cpuCores']}\n"
                response += "\n"
        
        # Memory информация (только в гигабайтах)
        if 'mem' in system_status:
            mem_data = system_status['mem']
            if isinstance(mem_data, dict):
                current_bytes = mem_data.get('current', 0)  # Используемая память
                total_bytes = mem_data.get('total', 0)      # Общая память
                
                if total_bytes > 0:
                    # Конвертируем в гигабайты
                    current_gb = current_bytes / (1024 * 1024 * 1024)  # Для отображения в GB
                    total_gb = total_bytes / (1024 * 1024 * 1024)
                    
                    mem_percent = (current_bytes / total_bytes * 100) if total_bytes > 0 else 0
                    
                    response += f"🧠 **Память:**\n"
                    response += f"   Использовано: {current_gb:.2f} GB / {total_gb:.1f} GB\n"
                    response += f"   Процент: {mem_percent:.1f}%\n\n"
        
        # Disk информация  
        if 'disk' in system_status:
            disk_data = system_status['disk']
            if isinstance(disk_data, dict):
                current_bytes = disk_data.get('current', 0)  # Используемое место
                total_bytes = disk_data.get('total', 0)      # Общее место
                
                if total_bytes > 0:
                    # Конвертируем в гигабайты
                    current_gb = current_bytes / (1024 * 1024 * 1024)
                    total_gb = total_bytes / (1024 * 1024 * 1024)
                    disk_percent = (current_bytes / total_bytes * 100) if total_bytes > 0 else 0
                    
                    response += f"💿 **Диск:**\n"
                    response += f"   Использовано: {current_gb:.2f} GB / {total_gb:.1f} GB\n"
                    response += f"   Процент: {disk_percent:.1f}%\n\n"
        
        # Дополнительная системная информация
        if 'uptime' in system_status:
            uptime_seconds = system_status['uptime']
            uptime_hours = uptime_seconds / 3600
            uptime_days = uptime_hours / 24
            if uptime_days >= 1:
                response += f"⏰ **Время работы:** {uptime_days:.1f} дней\n"
            else:
                response += f"⏰ **Время работы:** {uptime_hours:.1f} часов\n"
        
        if 'tcpCount' in system_status and 'udpCount' in system_status:
            response += f"🔗 **Подключения:** TCP: {system_status['tcpCount']}, UDP: {system_status['udpCount']}\n"
        
        response += f"\n👥 Пользователей: {stats.get('active_users', 0)}/{stats.get('total_users', 0)}\n"
        response += f"📡 Inbound'ов: {stats.get('inbounds_count', 0)}\n"
        response += f"📅 **Трафик за месяц: {stats.get('total_monthly_traffic_gb', 0)} GB**"
        
        try:
            bot.edit_message_text(text=response, chat_id=call.message.chat.id, message_id=call.message.message_id, parse_mode='Markdown')
        except:
            bot.send_message(call.message.chat.id, response, parse_mode='Markdown')
            
    except Exception as e:
        error_message = f"❌ Ошибка при получении системной информации: {str(e)}"
        print(f"❌ Ошибка в handle_system_monitor: {e}")
        try:
            bot.edit_message_text(text=error_message, chat_id=call.message.chat.id, message_id=call.message.message_id)
        except:
            bot.send_message(call.message.chat.id, error_message)

@bot.callback_query_handler(func=lambda call: call.data == "menu_traffic_analytics")
def handle_traffic_analytics(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    bot.answer_callback_query(call.id, "⏳ Анализирую трафик...")
    
    try:
        # Получаем актуальную конфигурацию сервера
        current_server = get_current_server_config(call.from_user.id)
        vm = get_vpn_manager(call.from_user.id)
        
        # Принудительная переаутентификация для нового сервера
        if not vm.authenticate():
            error_msg = f"❌ Не удалось подключиться к серверу {current_server['name']}"
            try:
                bot.edit_message_text(text=error_msg, chat_id=call.message.chat.id, message_id=call.message.message_id)
            except:
                bot.send_message(call.message.chat.id, error_msg)
            return
        
        # Получаем топ пользователей по трафику
        top_users = vm.get_top_users_by_traffic(limit=10)
        stats = vm.get_server_stats()
        
        # ИСПРАВЛЕНИЕ: Экранируем имя сервера
        safe_server_name = safe_markdown_text(current_server['name'])
        
        response = f"📈 **Аналитика трафика**\n\n"
        response += f"🌐 Сервер: {safe_server_name}\n"
        response += f"📅 **Общий трафик за месяц: {stats.get('total_monthly_traffic_gb', 0)} GB**\n\n"
        
        if top_users:
            response += f"🏆 **Топ пользователей по трафику:**\n\n"
            for i, user in enumerate(top_users[:10], 1):
                status_icon = "✅" if user['enable'] else "🚫"
                used_gb = user['used_gb'] if isinstance(user['used_gb'], (int, float)) else 0
                # ИСПРАВЛЕНИЕ: Экранируем имена пользователей
                safe_email = safe_markdown_text(user['email'])
                response += f"{i}. {status_icon} **{safe_email}**\n"
                response += f"   📊 Трафик: {used_gb:.2f} GB\n"
                if i < len(top_users):
                    response += "\n"
        else:
            response += "👤 Пользователи не найдены или нет данных о трафике"
        
        try:
            bot.edit_message_text(text=response, chat_id=call.message.chat.id, message_id=call.message.message_id, parse_mode='Markdown')
        except:
            bot.send_message(call.message.chat.id, response, parse_mode='Markdown')
    except Exception as e:
        error_msg = f"❌ Ошибка при получении аналитики трафика: {str(e)}"
        print(f"❌ Ошибка в handle_traffic_analytics: {e}")
        try:
            bot.edit_message_text(text=error_msg, chat_id=call.message.chat.id, message_id=call.message.message_id)
        except:
            bot.send_message(call.message.chat.id, error_msg)

@bot.callback_query_handler(func=lambda call: call.data == "menu_export_backup")
def handle_menu_export_backup(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    bot.answer_callback_query(call.id, "⏳ Создаю бекап...")
    try:
        current_server = get_current_server_config(call.from_user.id)
        
        # Отправляем промежуточное сообщение о процессе
        try:
            bot.edit_message_text(
                text=f"⏳ Создание бекапа с сервера {current_server['name']}...\n\nПроверяю доступные API endpoints...",
                chat_id=call.message.chat.id,
                message_id=call.message.message_id
            )
        except:
            pass
        
        vm = get_vpn_manager(call.from_user.id)
        backup_data = vm.get_backup()
        
        if not backup_data:
            error_text = f"❌ Не удалось получить бекап с сервера {current_server['name']}\n\n"
            error_text += "💡 **Возможные решения:**\n"
            error_text += "• Создайте бекап вручную через веб-панель (Система → Бекап и восстановление → Экспорт)\n"
            error_text += "• Убедитесь, что у пользователя есть права на создание бекапов\n"  
            error_text += "• Проверьте версию панели 3x-ui (некоторые старые версии не поддерживают API экспорт)\n"
            error_text += "• Обновите панель до последней версии\n\n"
            error_text += f"🔗 Адрес панели: `{current_server['host']}{current_server['path']}`"
            
            try:
                bot.edit_message_text(
                    text=error_text,
                    chat_id=call.message.chat.id,
                    message_id=call.message.message_id,
                    parse_mode='Markdown'
                )
            except:
                bot.send_message(call.message.chat.id, error_text, parse_mode='Markdown')
            return
            
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f"3xui_backup_{current_server['name']}_{timestamp}.db"
        backup_io = io.BytesIO(backup_data)
        backup_io.name = filename
        
        caption = f"💾 **Бекап базы данных 3x-ui**\n"
        caption += f"🌐 Сервер: {current_server['name']}\n"
        caption += f"📅 Дата: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
        caption += f"📁 Размер: {len(backup_data):,} байт\n\n"
        caption += "💡 Для восстановления:\n"
        caption += "1. Зайдите в веб-панель\n"
        caption += "2. Система → Бекап и восстановление\n"
        caption += "3. Импорт базы данных → Выберите этот файл"
        
        bot.send_document(call.message.chat.id, document=backup_io, caption=caption, parse_mode='Markdown')
        
    except Exception as e:
        error_text = f"❌ Критическая ошибка при создании бекапа: {str(e)}\n\n"
        error_text += "🔧 Обратитесь к администратору или создайте бекап вручную через веб-панель."
        try:
            bot.edit_message_text(text=error_text, chat_id=call.message.chat.id, message_id=call.message.message_id)
        except:
            bot.send_message(call.message.chat.id, error_text)

@bot.callback_query_handler(func=lambda call: call.data == "menu_restart")
def handle_menu_restart(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    bot.answer_callback_query(call.id, "🔄 Перезапускаю...")
    try:
        bot.edit_message_text(text="🔄 Перезапускаю бота...", chat_id=call.message.chat.id, message_id=call.message.message_id)
    except:
        bot.send_message(call.message.chat.id, "🔄 Перезапускаю бота...")
    print("🔄 Получена команда перезапуска из меню")
    bot.stop_polling()
    os.execv(sys.executable, [sys.executable] + sys.argv)

@bot.callback_query_handler(func=lambda call: call.data == "menu_users_list")
def handle_menu_users_list(call):
    print(f"🔍 DEBUG: handle_menu_users_list вызван пользователем {call.from_user.id}")
    print(f"🔍 DEBUG: callback_data = {call.data}")
    
    if not is_admin(call.from_user.id):
        print(f"❌ DEBUG: Пользователь {call.from_user.id} не админ")
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    
    bot.answer_callback_query(call.id, "⏳ Загружаю список...")
    print("✅ DEBUG: answer_callback_query отправлен")
    
    try:
        current_server = get_current_server_config(call.from_user.id)
        print(f"🔍 DEBUG: Текущий сервер: {current_server['name']}")
        
        vpn_manager = get_vpn_manager(call.from_user.id)
        print("🔍 DEBUG: VPN Manager получен")
        
        users = vpn_manager.get_users_list()
        print(f"🔍 DEBUG: Получено пользователей: {len(users) if users else 0}")
        
        if not users:
            error_msg = f"❌ Не удалось получить список пользователей с сервера {current_server['name']} или список пуст."
            print(f"❌ DEBUG: {error_msg}")
            try:
                bot.edit_message_text(text=error_msg, chat_id=call.message.chat.id, message_id=call.message.message_id)
            except Exception as e:
                print(f"❌ DEBUG: Ошибка edit_message_text: {e}")
                bot.send_message(call.message.chat.id, error_msg)
            return
        
        users.sort(key=lambda x: x['email'].lower())
        print(f"🔍 DEBUG: Пользователи отсортированы")
        
        markup = create_users_keyboard(users, page=0, per_page=10)
        print("🔍 DEBUG: Клавиатура создана")
        
        message_text = f"👥 Список пользователей VPN:\n🌐 Сервер: {current_server['name']}\n\n💡 Нажмите на имя пользователя для просмотра деталей"
        
        try:
            bot.edit_message_text(
                text=message_text, 
                chat_id=call.message.chat.id, 
                message_id=call.message.message_id, 
                reply_markup=markup
            )
            print("✅ DEBUG: Сообщение обновлено через edit_message_text")
        except Exception as e:
            print(f"❌ DEBUG: Ошибка edit_message_text: {e}")
            bot.send_message(call.message.chat.id, message_text, reply_markup=markup)
            print("✅ DEBUG: Сообщение отправлено через send_message")
            
    except Exception as e:
        error_msg = f"❌ Критическая ошибка в handle_menu_users_list: {str(e)}"
        print(error_msg)
        import traceback
        print(f"🔍 DEBUG: Трассировка: {traceback.format_exc()}")
        try:
            bot.edit_message_text(text=error_msg, chat_id=call.message.chat.id, message_id=call.message.message_id)
        except:
            bot.send_message(call.message.chat.id, error_msg)

@bot.callback_query_handler(func=lambda call: call.data == "menu_users_search")
def handle_menu_users_search(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    bot.answer_callback_query(call.id, "🔍 Введите имя для поиска...")
    current_server = get_current_server_config(call.from_user.id)
    try:
        bot.edit_message_text(text=f"🔍 Поиск пользователя на сервере {current_server['name']}\n\nВведите имя пользователя для поиска:", chat_id=call.message.chat.id, message_id=call.message.message_id)
    except:
        bot.send_message(call.message.chat.id, f"🔍 Поиск пользователя на сервере {current_server['name']}\n\nВведите имя пользователя для поиска:")
    # Регистрируем следующий шаг
    bot.register_next_step_handler_by_chat_id(call.message.chat.id, find_user_step1)

@bot.callback_query_handler(func=lambda call: call.data == "menu_users_create")
def handle_menu_users_create(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    bot.answer_callback_query(call.id, "➕ Создание пользователя...")
    current_server = get_current_server_config(call.from_user.id)
    try:
        bot.edit_message_text(text=f"➕ Создание пользователя на сервере {current_server['name']}\n\nВведите имя нового пользователя:", chat_id=call.message.chat.id, message_id=call.message.message_id)
    except:
        bot.send_message(call.message.chat.id, f"➕ Создание пользователя на сервере {current_server['name']}\n\nВведите имя нового пользователя:")
    # Регистрируем следующий шаг
    bot.register_next_step_handler_by_chat_id(call.message.chat.id, create_user_step1)

@bot.callback_query_handler(func=lambda call: call.data == "menu_users_delete")
def handle_menu_users_delete(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    bot.answer_callback_query(call.id, "🗑️ Удаление пользователя...")
    current_server = get_current_server_config(call.from_user.id)
    try:
        bot.edit_message_text(text=f"🗑️ Удаление пользователя с сервера {current_server['name']}\n\nВведите имя пользователя для удаления:", chat_id=call.message.chat.id, message_id=call.message.message_id)
    except:
        bot.send_message(call.message.chat.id, f"🗑️ Удаление пользователя с сервера {current_server['name']}\n\nВведите имя пользователя для удаления:")
    # Регистрируем следующий шаг
    bot.register_next_step_handler_by_chat_id(call.message.chat.id, delete_user_step1)

# ===== ПОЛЬЗОВАТЕЛЬСКИЕ ФУНКЦИИ (step handlers) =====

def create_user_step1(message):
    if not is_admin(message.from_user.id):
        return
    username = message.text.strip()
    if not username:
        bot.reply_to(message, "❌ Имя пользователя не может быть пустым. Попробуйте снова.")
        return
    if len(username) < 3:
        bot.reply_to(message, "❌ Имя пользователя слишком короткое (минимум 3 символа). Попробуйте снова.")
        return
    if any(char in username for char in [' ', '\n', '\t', '\r']):
        bot.reply_to(message, "❌ Имя пользователя не может содержать пробелы или переносы строк. Попробуйте снова.")
        return
    msg = bot.reply_to(message, 
                      f"👤 Имя: {username}\n\n"
                      "💾 Введите лимит трафика в GB (0 = безлимит):")
    bot.register_next_step_handler(msg, create_user_step2, username)

def create_user_step2(message, username):
    if not is_admin(message.from_user.id):
        return
    try:
        total_gb = int(message.text.strip())
        if total_gb < 0:
            raise ValueError
    except ValueError:
        bot.reply_to(message, "❌ Некорректное значение. Введите число больше или равное 0.")
        return
    msg = bot.reply_to(message, 
                      f"👤 Имя: {username}\n"
                      f"💾 Лимит: {total_gb} GB\n\n"
                      "⏰ Введите срок действия в днях (0 = бессрочно):")
    bot.register_next_step_handler(msg, create_user_step3, username, total_gb)

def create_user_step3(message, username, total_gb):
    if not is_admin(message.from_user.id):
        return
    try:
        expiry_days = int(message.text.strip())
        if expiry_days < 0:
            raise ValueError
    except ValueError:
        bot.reply_to(message, "❌ Некорректное значение. Введите число больше или равное 0.")
        # Возвращаем функцию для повторного ввода
        msg = bot.reply_to(message, "⏰ Введите срок действия в днях (0 = бессрочно):")
        bot.register_next_step_handler(msg, create_user_step3, username, total_gb)
        return
    
    current_server = get_current_server_config(message.from_user.id)
    expiry_text = f"{expiry_days} дней" if expiry_days > 0 else "Бессрочно"
    limit_text = f"{total_gb} GB" if total_gb > 0 else "Безлимит"
    
    # ИСПРАВЛЕНИЕ: Экранируем имя пользователя для безопасного отображения
    safe_username = safe_markdown_text(username)
    safe_server_name = safe_markdown_text(current_server['name'])
    
    response = f"📝 **Создание нового пользователя:**\n\n"
    response += f"🌐 Сервер: {safe_server_name}\n"
    response += f"👤 Имя: {safe_username}\n"
    response += f"💾 Лимит трафика: {limit_text}\n"
    response += f"⏰ Срок действия: {expiry_text}\n"
    response += f"🔄 Flow: xtls-rprx-vision\n\n"
    response += "📥 Выберите inbound для создания пользователя:"
    
    # Сохраняем данные в контексте пользователя
    user_data = {
        'username': username,
        'total_gb': total_gb, 
        'expiry_days': expiry_days
    }
    set_user_context(message.from_user.id, 'create_user_data', json.dumps(user_data))
    
    inbounds = get_inbounds_for_server(message.from_user.id)
    if not inbounds:
        bot.reply_to(message, "❌ На сервере нет inbound'ов.")
        return
    
    # Используем новую безопасную функцию
    kb = build_inbounds_keyboard_safe(inbounds, action="inbound_for_create", user_id=message.from_user.id)
    bot.reply_to(message, response, parse_mode='Markdown', reply_markup=kb)

def delete_user_step1(message):
    if not is_admin(message.from_user.id):
        return
    username = message.text.strip()
    if not username or len(username) < 3:
        bot.reply_to(message, "❌ Некорректное имя пользователя. Попробуйте снова.")
        return
    vm = get_vpn_manager(message.from_user.id)
    users = vm.get_users_list()
    matches = [u for u in users if u['email'].lower().strip() == username.lower().strip()]
    if not matches:
        current_server = get_current_server_config(message.from_user.id)
        bot.reply_to(message, f"❌ Пользователь '{username}' не найден на сервере {current_server['name']}.")
        return
    if len(matches) == 1:
        user_stats = matches[0]
        markup = types.InlineKeyboardMarkup()
        username_encoded = safe_encode_username(username)
        markup.row(
            types.InlineKeyboardButton("✅ Да, удалить", callback_data=f"delete_user_yes|{username_encoded}|{user_stats['inbound_id']}"),
            types.InlineKeyboardButton("❌ Нет, отмена", callback_data="delete_cancel")
        )
        current_server = get_current_server_config(message.from_user.id)
        status = "✅ Активен" if user_stats['enable'] else "🚫 Заблокирован"
        used_text = f"{user_stats['used_gb']:.2f} GB"
        response = f"🗑️ **Подтверждение удаления пользователя:**\n\n"
        response += f"🌐 **Сервер:** {current_server['name']}\n"
        response += f"📥 **Inbound ID:** {user_stats['inbound_id']}\n"
        response += f"👤 **Имя:** {username}\n"
        response += f"📊 **Статус:** {status}\n"
        response += f"📈 **Использовано:** {used_text}\n\n"
        response += f"⚠️ Действие необратимо. Удалить?"
        bot.reply_to(message, response, parse_mode='Markdown', reply_markup=markup)
        return
    # несколько inbound — выбор
    inbounds = []
    seen = set()
    for u in matches:
        ib_id = u['inbound_id']
        if ib_id in seen:
            continue
        seen.add(ib_id)
        inbounds.append({'id': ib_id, 'protocol': u['protocol'], 'port': u['inbound_port'], 'remark': f"{u['protocol']}:{u['inbound_port']}"})
    kb = build_inbounds_keyboard(inbounds, action="inbound_for_delete", extra=safe_encode_username(username))
    bot.reply_to(message, f"🗑️ Найдено несколько inbound для '{username}'. Выберите inbound для удаления:", reply_markup=kb)

def find_user_step1(message):
    if not is_admin(message.from_user.id):
        return
    username = message.text.strip()
    if not username:
        bot.reply_to(message, "❌ Имя пользователя не может быть пустым. Попробуйте снова.")
        return
    if len(username) < 2:
        bot.reply_to(message, "❌ Имя пользователя слишком короткое (минимум 2 символа). Попробуйте снова.")
        return
    set_user_context(message.from_user.id, 'search_username', username)
    inbounds = get_inbounds_for_server(message.from_user.id)
    if not inbounds:
        bot.reply_to(message, "❌ На сервере нет inbound'ов.")
        return
    kb = build_inbounds_keyboard(inbounds, action="inbound_for_search")
    bot.reply_to(message, "📥 Выберите inbound для поиска пользователя:", reply_markup=kb)

# ===== Остальные callback обработчики =====

@bot.callback_query_handler(func=lambda call: call.data.startswith('select_server_'))
def handle_server_selection(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    server_id = call.data.replace('select_server_', '')
    if server_id not in SERVERS_CONFIG:
        bot.answer_callback_query(call.id, "❌ Сервер не найден")
        return
    
    # Устанавливаем новый сервер и очищаем контекст
    set_current_server(call.from_user.id, server_id)
    
    # Очищаем пользовательский контекст при смене сервера
    if call.from_user.id in USER_CTX:
        USER_CTX[call.from_user.id].clear()
    
    server_config = SERVERS_CONFIG[server_id]
    vpn_manager = get_vpn_manager(call.from_user.id)
    connection_status = "🔴 Недоступен"
    try:
        if vpn_manager.authenticate():
            connection_status = "🟢 Подключен"
    except:
        connection_status = "🔴 Ошибка подключения"
    
    bot.answer_callback_query(call.id, f"✅ Переключен на {server_config['name']}")
    response = f"✅ **Сервер успешно изменен!**\n\n"
    response += f"🌐 Выбранный сервер: {server_config['name']}\n"
    response += f"🔗 URL: `{server_config['host']}{server_config['path']}`\n"
    response += f"📡 Статус: {connection_status}\n"
    response += f"🖥️ IP сервера: `{server_config['server_ip']}`\n\n"
    response += "Теперь все операции будут выполняться на этом сервере."
    bot.edit_message_text(text=response, chat_id=call.message.chat.id, message_id=call.message.message_id, parse_mode='Markdown')

@bot.callback_query_handler(func=lambda call: call.data.startswith('users_page_'))
def handle_users_pagination(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    page = int(call.data.replace('users_page_', ''))
    vpn_manager = get_vpn_manager(call.from_user.id)
    users = vpn_manager.get_users_list()
    if not users:
        bot.answer_callback_query(call.id, "❌ Ошибка получения данных")
        return
    users.sort(key=lambda x: x['email'].lower())
    current_server = get_current_server_config(call.from_user.id)
    markup = create_users_keyboard(users, page=page, per_page=10)
    try:
        bot.edit_message_text(text=f"👥 Список пользователей VPN:\n🌐 Сервер: {current_server['name']}\n\n💡 Нажмите на имя пользователя для просмотра деталей",
                              chat_id=call.message.chat.id, message_id=call.message.message_id, reply_markup=markup)
        bot.answer_callback_query(call.id)
    except Exception:
        bot.delete_message(call.message.chat.id, call.message.message_id)
        bot.send_message(call.message.chat.id, f"👥 Список пользователей VPN:\n🌐 Сервер: {current_server['name']}\n\n💡 Нажмите на имя пользователя для просмотра деталей", reply_markup=markup)
        bot.answer_callback_query(call.id)

@bot.callback_query_handler(func=lambda call: call.data.startswith('user_details|'))
def handle_user_details(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    try:
        username_encoded = call.data.split('|', 1)[1]
        username = safe_decode_username(username_encoded)
        if not username:
            bot.answer_callback_query(call.id, "❌ Ошибка декодирования имени")
            return
    except Exception as e:
        print(f"❌ Ошибка парсинга callback: {e}")
        bot.answer_callback_query(call.id, "❌ Ошибка декодирования имени")
        return
    bot.answer_callback_query(call.id, f"📊 Загружаю данные {username.replace('_', ' ')}")
    show_user_details(call.message.chat.id, username, call.from_user.id)

@bot.callback_query_handler(func=lambda call: call.data.startswith('delete_user_confirm|'))
def handle_delete_user_confirm(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    try:
        username_encoded = call.data.split('|', 1)[1]
        username = safe_decode_username(username_encoded)
        if not username:
            bot.answer_callback_query(call.id, "❌ Ошибка декодирования имени")
            return
    except:
        bot.answer_callback_query(call.id, "❌ Ошибка декодирования имени")
        return
    bot.answer_callback_query(call.id, f"🗑️ Подтверждение удаления {username.replace('_', ' ')}")
    vm = get_vpn_manager(call.from_user.id)
    users = vm.get_users_list()
    matches = [u for u in users if u['email'].lower().strip() == username.lower().strip()]
    if not matches:
        bot.send_message(call.message.chat.id, f"❌ Пользователь {username} не найден")
        return
    if len(matches) == 1:
        user_stats = matches[0]
        markup = types.InlineKeyboardMarkup()
        username_encoded = safe_encode_username(username)
        markup.row(
            types.InlineKeyboardButton("✅ Да, удалить", callback_data=f"delete_user_yes|{username_encoded}|{user_stats['inbound_id']}"),
            types.InlineKeyboardButton("❌ Нет, отмена", callback_data="delete_cancel")
        )
        current_server = get_current_server_config(call.from_user.id)
        status = "✅ Активен" if user_stats['enable'] else "🚫 Заблокирован"
        used_text = f"{user_stats['used_gb']:.2f} GB"
        response = f"🗑️ **Подтверждение удаления пользователя:**\n\n"
        response += f"🌐 **Сервер:** {current_server['name']}\n"
        response += f"📥 **Inbound ID:** {user_stats['inbound_id']}\n"
        response += f"👤 **Имя:** {username}\n"
        response += f"📊 **Статус:** {status}\n"
        response += f"📈 **Использовано:** {used_text}\n\n"
        response += f"⚠️ Действие необратимо. Удалить?"
        try:
            bot.edit_message_text(text=response, chat_id=call.message.chat.id, message_id=call.message.message_id, parse_mode='Markdown', reply_markup=markup)
        except:
            bot.send_message(call.message.chat.id, response, parse_mode='Markdown', reply_markup=markup)
    else:
        inbounds = []
        seen = set()
        for u in matches:
            ib_id = u['inbound_id']
            if ib_id in seen:
                continue
            seen.add(ib_id)
            inbounds.append({'id': ib_id, 'protocol': u['protocol'], 'port': u['inbound_port'], 'remark': f"{u['protocol']}:{u['inbound_port']}"})
        kb = build_inbounds_keyboard(inbounds, action="inbound_for_delete", extra=safe_encode_username(username))
        try:
            bot.edit_message_text(text=f"🗑️ Найдено несколько inbound для '{username}'. Выберите inbound для удаления:",
                                  chat_id=call.message.chat.id, message_id=call.message.message_id, reply_markup=kb)
        except:
            bot.send_message(call.message.chat.id, f"🗑️ Найдено несколько inbound для '{username}'. Выберите inbound для удаления:", reply_markup=kb)

@bot.callback_query_handler(func=lambda call: call.data.startswith('delete_user_yes|'))
def handle_delete_user_final(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    try:
        parts = call.data.split('|')
        username = safe_decode_username(parts[1])
        inbound_id = int(parts[2]) if len(parts) > 2 else None
        if not username:
            bot.answer_callback_query(call.id, "❌ Ошибка декодирования имени")
            return
    except:
        bot.answer_callback_query(call.id, "❌ Ошибка данных")
        return
    bot.answer_callback_query(call.id, "⏳ Удаляю пользователя...")
    current_server = get_current_server_config(call.from_user.id)
    try:
        bot.edit_message_text(text=f"🔄 Удаление пользователя {username} с сервера {current_server['name']}...\n\n⏳ Пожалуйста, подождите...",
                              chat_id=call.message.chat.id, message_id=call.message.message_id)
    except:
        pass
    vm = get_vpn_manager(call.from_user.id)
    success = vm.delete_user(username) if inbound_id is None else vm.delete_user_in_inbound(username, inbound_id)
    if success:
        response = f"✅ Пользователь успешно удален!\n\n"
        response += f"🌐 Сервер: {current_server['name']}\n"
        if inbound_id is not None:
            response += f"📥 Inbound ID: {inbound_id}\n"
        response += f"🗑️ Пользователь '{username}' удален из системы.\n"
        response += f"💡 Действие необратимо."
        try:
            bot.edit_message_text(text=response, chat_id=call.message.chat.id, message_id=call.message.message_id)
        except:
            bot.send_message(call.message.chat.id, response)
    else:
        error_response = f"❌ Ошибка при удалении пользователя {username}\n\n"
        error_response += f"🌐 Сервер: {current_server['name']}\n"
        if inbound_id is not None:
            error_response += f"📥 Inbound ID: {inbound_id}\n"
        error_response += "💡 Проверьте подключение к серверу или выполните удаление через панель."
        try:
            bot.edit_message_text(
                text=error_response,
                chat_id=call.message.chat.id,
                message_id=call.message.message_id
            )
        except:
            bot.send_message(call.message.chat.id, error_response)

@bot.callback_query_handler(func=lambda call: call.data.startswith('select_inbound|inbound_for_create'))
def handle_inbound_for_create(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    
    try:
        parts = call.data.split('|')
        # Новый формат: select_inbound|inbound_for_create|user_id|inbound_id
        if len(parts) >= 4:
            user_id = int(parts[2])
            inbound_id = int(parts[3])
        else:
            # Старый формат для совместимости
            inbound_id = int(parts[-1])
            user_id = call.from_user.id
            
    except Exception as e:
        print(f"❌ Ошибка парсинга callback_data: {e}")
        bot.answer_callback_query(call.id, "❌ Ошибка данных inbound")
        return

    bot.answer_callback_query(call.id, f"⏳ Создаю в inbound {inbound_id}...")
    
    # Получаем данные из контекста
    user_data_json = get_user_context(user_id, 'create_user_data')
    if not user_data_json:
        bot.send_message(call.message.chat.id, "❌ Данные пользователя утеряны. Начните создание заново.")
        return
        
    try:
        user_data = json.loads(user_data_json)
        username = user_data['username']
        total_gb = user_data['total_gb']
        expiry_days = user_data['expiry_days']
    except Exception as e:
        print(f"❌ Ошибка парсинга данных пользователя: {e}")
        bot.send_message(call.message.chat.id, "❌ Ошибка данных пользователя. Начните создание заново.")
        return
    
    current_server = get_current_server_config(user_id)
    vm = get_vpn_manager(user_id)
    
    success = vm.create_user(username, inbound_id=inbound_id, total_gb=total_gb, expiry_days=expiry_days)
    
    if success:
        response = f"✅ Пользователь успешно создан!\n\n"
        response += f"🌐 Сервер: {current_server['name']}\n"
        response += f"📥 Inbound ID: {inbound_id}\n"
        response += f"👤 Имя: {username}\n"
        response += f"💾 Лимит: {total_gb} GB\n" if total_gb > 0 else "💾 Лимит: Безлимит\n"
        response += f"⏰ Срок: {expiry_days} дней\n" if expiry_days > 0 else "⏰ Срок: Бессрочно\n"
        response += f"🔄 Flow: xtls-rprx-vision"
        
        # Очищаем контекст
        clear_user_context(user_id, 'create_user_data')
        
        try:
            bot.edit_message_text(text=response, chat_id=call.message.chat.id, message_id=call.message.message_id)
        except:
            bot.send_message(call.message.chat.id, response)
    else:
        error_msg = f"❌ Ошибка создания пользователя {username} в inbound {inbound_id} на сервере {current_server['name']}"
        try:
            bot.edit_message_text(text=error_msg, chat_id=call.message.chat.id, message_id=call.message.message_id)
        except:
            bot.send_message(call.message.chat.id, error_msg)

@bot.callback_query_handler(func=lambda call: call.data.startswith('select_inbound|inbound_for_delete'))
def handle_inbound_for_delete(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    try:
        parts = call.data.split('|')
        username_hex = parts[-2]
        inbound_id = int(parts[-1])
        username = safe_decode_username(username_hex)
    except Exception:
        bot.answer_callback_query(call.id, "❌ Ошибка данных inbound")
        return

    vm = get_vpn_manager(call.from_user.id)
    users = vm.get_users_list()
    matches = [u for u in users if u['email'].lower().strip() == username.lower().strip() and u['inbound_id'] == inbound_id]
    if not matches:
        bot.answer_callback_query(call.id, "❌ Пользователь в этом inbound не найден")
        return

    user_stats = matches[0]
    markup = types.InlineKeyboardMarkup()
    username_encoded = safe_encode_username(username)
    markup.row(
        types.InlineKeyboardButton("✅ Да, удалить", callback_data=f"delete_user_yes|{username_encoded}|{inbound_id}"),
        types.InlineKeyboardButton("❌ Нет, отмена", callback_data="delete_cancel")
    )
    current_server = get_current_server_config(call.from_user.id)
    status = "✅ Активен" if user_stats['enable'] else "🚫 Заблокирован"
    used_text = f"{user_stats['used_gb']:.2f} GB"
    response = f"🗑️ Подтверждение удаления пользователя:\n\n"
    response += f"🌐 Сервер: {current_server['name']}\n"
    response += f"📥 Inbound ID: {inbound_id}\n"
    response += f"👤 Имя: {username}\n"
    response += f"📊 Статус: {status}\n"
    response += f"📈 Использовано: {used_text}\n\n"
    response += f"⚠️ Действие необратимо. Удалить?"
    try:
        bot.edit_message_text(
            text=response,
            chat_id=call.message.chat.id,
            message_id=call.message.message_id,
            reply_markup=markup
        )
    except:
        bot.send_message(call.message.chat.id, response, reply_markup=markup)
    bot.answer_callback_query(call.id)

@bot.callback_query_handler(func=lambda call: call.data.startswith('select_inbound|inbound_for_search'))
def handle_inbound_for_search(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    try:
        parts = call.data.split('|')
        inbound_id = int(parts[-1])
    except Exception:
        bot.answer_callback_query(call.id, "❌ Ошибка inbound")
        return

    username = get_user_context(call.from_user.id, 'search_username')
    if not username:
        bot.answer_callback_query(call.id, "❌ Истек контекст поиска")
        return

    vm = get_vpn_manager(call.from_user.id)
    users = vm.get_users_list()
    found = [u for u in users if u.get('inbound_id') == inbound_id and username.lower() in u['email'].lower()]

    current_server = get_current_server_config(call.from_user.id)
    if not found:
        try:
            bot.edit_message_text(
                text=f"❌ Пользователи, содержащие '{username}', не найдены в inbound {inbound_id} на сервере {current_server['name']}.",
                chat_id=call.message.chat.id,
                message_id=call.message.message_id
            )
        except:
            bot.send_message(call.message.chat.id, f"❌ Пользователи, содержащие '{username}', не найдены в inbound {inbound_id} на сервере {current_server['name']}.")
        bot.answer_callback_query(call.id)
        return

    if len(found) == 1:
        user = found[0]
        bot.answer_callback_query(call.id, f"📊 Найден: {user['email']}")
        show_user_details(call.message.chat.id, user['email'], call.from_user.id)
        return

    resp = f"🔍 Найдено пользователей: {len(found)} на сервере {current_server['name']} (inbound {inbound_id})\n\n"
    for i, u in enumerate(found[:10], 1):
        status = "✅" if u['enable'] else "🚫"
        used_text = f"{u['used_gb']:.2f} GB"
        resp += f"{i}. {status} {u['email']}\n   📈 {used_text} использовано\n\n"
    if len(found) > 10:
        resp += f"... и еще {len(found) - 10} пользователей\n\n"
    resp += "💡 Для подробной информации используйте точное имя пользователя или откройте из общего списка."
    try:
        bot.edit_message_text(
            text=resp,
            chat_id=call.message.chat.id,
            message_id=call.message.message_id
        )
    except:
        bot.send_message(call.message.chat.id, resp)
    bot.answer_callback_query(call.id)

@bot.callback_query_handler(func=lambda call: call.data.startswith('download_vless|'))
def handle_download_vless(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    
    try:
        username_encoded = call.data.split('|', 1)[1]
        username = safe_decode_username(username_encoded)
        if not username:
            bot.answer_callback_query(call.id, "❌ Ошибка декодирования имени")
            return
    except:
        bot.answer_callback_query(call.id, "❌ Ошибка декодирования имени")
        return
    
    bot.answer_callback_query(call.id, "⏳ Генерирую VLESS конфиг...")
    
    vpn_manager = get_vpn_manager(call.from_user.id)
    config = vpn_manager.get_client_config(username)
    
    if not config:
        bot.send_message(call.message.chat.id, f"❌ Не удалось получить конфигурацию для {username}")
        return
    
    config_bio = io.BytesIO(config.encode('utf-8'))
    config_bio.name = f"{username}_vless.txt"
    
    current_server = get_current_server_config(call.from_user.id)
    
    bot.send_document(
        call.message.chat.id,
        document=config_bio,
        caption=f"📄 VLESS конфигурация для {username}\n🌐 Сервер: {current_server['name']}\n🔄 Flow: xtls-rprx-vision"
    )

@bot.callback_query_handler(func=lambda call: call.data.startswith('download_qr|'))
def handle_download_qr(call):
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    
    try:
        username_encoded = call.data.split('|', 1)[1]
        username = safe_decode_username(username_encoded)
        if not username:
            bot.answer_callback_query(call.id, "❌ Ошибка декодирования имени")
            return
    except:
        bot.answer_callback_query(call.id, "❌ Ошибка декодирования имени")
        return
    
    bot.answer_callback_query(call.id, "⏳ Генерирую QR-код...")
    
    vpn_manager = get_vpn_manager(call.from_user.id)
    config = vpn_manager.get_client_config(username)
    
    if not config:
        bot.send_message(call.message.chat.id, f"❌ Не удалось получить конфигурацию для {username}")
        return
    
    qr_image = generate_qr_code(config)
    current_server = get_current_server_config(call.from_user.id)
    
    bot.send_photo(
        call.message.chat.id,
        photo=qr_image,
        caption=f"🎯 QR-код для подключения к VPN\n📧 Пользователь: {username}\n🌐 Сервер: {current_server['name']}\n🔄 Flow: xtls-rprx-vision"
    )

@bot.callback_query_handler(func=lambda call: call.data in ['create_cancel', 'delete_cancel'])
def cancel_action(call):
    if not is_admin(call.from_user.id):
        return
    action_map = {'create_cancel': 'создание', 'delete_cancel': 'удаление'}
    action = action_map.get(call.data, 'действие')
    bot.answer_callback_query(call.id, f"❌ {action.capitalize()} отменено")
    try:
        bot.edit_message_text(
            text=f"❌ {action.capitalize()} пользователя отменено.",
            chat_id=call.message.chat.id,
            message_id=call.message.message_id
        )
    except:
        bot.send_message(call.message.chat.id, f"❌ {action.capitalize()} пользователя отменено.")

@bot.callback_query_handler(func=lambda call: call.data == "noop")
def handle_noop(call):
    bot.answer_callback_query(call.id)

# ============================================
# КОМАНДЫ МОНИТОРИНГА
# ============================================

@bot.message_handler(commands=['monitoring'])
def cmd_monitoring(message):
    """
    Команда для управления мониторингом
    """
    if not is_admin(message.from_user.id):
        bot.reply_to(message, "❌ У вас нет доступа к этой команде.")
        return
    
    markup = types.InlineKeyboardMarkup(row_width=1)
    markup.add(
        types.InlineKeyboardButton("🔍 Проверить все серверы сейчас", callback_data="monitoring_check_now"),
        types.InlineKeyboardButton("📊 Отчет за сегодня", callback_data="monitoring_daily_report"),
        types.InlineKeyboardButton("📈 Еженедельный отчет", callback_data="monitoring_weekly_report"),
        types.InlineKeyboardButton("⚙️ Статус планировщика", callback_data="monitoring_scheduler_status"),
        types.InlineKeyboardButton("◀️ Главное меню", callback_data="main_menu")
    )
    
    bot.send_message(
        message.chat.id,
        "🔧 **Управление мониторингом**\n\nВыберите действие:",
        reply_markup=markup,
        parse_mode='Markdown'
    )


@bot.callback_query_handler(func=lambda call: call.data.startswith('monitoring_'))
def handle_monitoring_callbacks(call):
    """
    Обработка callback'ов мониторинга
    """
    if not is_admin(call.from_user.id):
        bot.answer_callback_query(call.id, "❌ Нет доступа")
        return
    
    try:
        action = call.data.replace('monitoring_', '')
        
        if action == 'check_now':
            bot.answer_callback_query(call.id, "🔍 Запуск проверки...")
            bot.edit_message_text(
                "🔍 Проверка серверов...\nПожалуйста, подождите...",
                call.message.chat.id,
                call.message.message_id
            )
            
            # Запускаем проверку в отдельном потоке
            import threading
            threading.Thread(target=monitor_all_servers).start()
            
            time.sleep(2)  # Даем время на проверку
            
            # Формируем отчет о текущем состоянии
            status_report = "📊 **Результаты проверки:**\n\n"
            for server_id, server_config in SERVERS_CONFIG.items():
                server_name = server_config['name']
                is_healthy = server_last_status.get(server_id, False)
                status_icon = "✅" if is_healthy else "❌"
                status_text = "Работает" if is_healthy else "Недоступен"
                status_report += f"{status_icon} `{safe_markdown_text(server_name)}`: {status_text}\n"
            
            bot.edit_message_text(
                status_report,
                call.message.chat.id,
                call.message.message_id,
                parse_mode='Markdown'
            )
            
        elif action == 'daily_report':
            bot.answer_callback_query(call.id, "📊 Генерация отчета...")
            bot.edit_message_text(
                "📊 Генерация ежедневного отчета...\nПожалуйста, подождите...",
                call.message.chat.id,
                call.message.message_id
            )
            
            report = generate_traffic_report(period='daily')
            bot.delete_message(call.message.chat.id, call.message.message_id)
            send_long_message(bot, call.message.chat.id, report, parse_mode='Markdown')
            
        elif action == 'weekly_report':
            bot.answer_callback_query(call.id, "📈 Генерация отчета...")
            bot.edit_message_text(
                "📈 Генерация еженедельного отчета...\nПожалуйста, подождите...",
                call.message.chat.id,
                call.message.message_id
            )
            
            report = generate_traffic_report(period='weekly')
            bot.delete_message(call.message.chat.id, call.message.message_id)
            send_long_message(bot, call.message.chat.id, report, parse_mode='Markdown')
            
        elif action == 'scheduler_status':
            bot.answer_callback_query(call.id)
            
            jobs = scheduler.get_jobs()
            status_msg = "⚙️ **Статус планировщика:**\n\n"
            status_msg += f"🔄 Планировщик: {'✅ Запущен' if scheduler.running else '❌ Остановлен'}\n"
            status_msg += f"📋 Активных задач: `{len(jobs)}`\n\n"
            
            if jobs:
                status_msg += "**Запланированные задачи:**\n"
                for job in jobs:
                    status_msg += f"• `{safe_markdown_text(job.name)}`\n"
                    status_msg += f"  Следующий запуск: `{job.next_run_time}`\n"
            
            bot.edit_message_text(
                status_msg,
                call.message.chat.id,
                call.message.message_id,
                parse_mode='Markdown'
            )
            
    except Exception as e:
        print(f"❌ Ошибка обработки callback мониторинга: {e}")
        bot.answer_callback_query(call.id, f"❌ Ошибка: {str(e)}")

# Универсальный обработчик для всех неизвестных сообщений
@bot.message_handler(func=lambda message: True)
def handle_unknown(message):
    if not is_admin(message.from_user.id):
        return
    bot.reply_to(message, "❓ Неизвестная команда. Используйте кнопки меню или /start")

if __name__ == '__main__':
    print("=" * 50)
    print("🚀 Запуск VPN Manager Telegram Bot")
    print("=" * 50)
    
    # Отправляем сообщение о запуске
    send_startup_message()
    
    # Запускаем планировщик фоновых задач
    start_scheduler()
    
    # Выполняем первую проверку серверов сразу при запуске
    print("🔍 Выполняется первоначальная проверка серверов...")
    monitor_all_servers()
    
    print("=" * 50)
    print("✅ Бот запущен и готов к работе!")
    print("📡 Мониторинг серверов активен")
    print("=" * 50)
    
    try:
        bot.infinity_polling(timeout=60, long_polling_timeout=60)
    except KeyboardInterrupt:
        print("\n⚠️ Получен сигнал остановки...")
        shutdown_scheduler()
        print("👋 Бот остановлен")
    except Exception as e:
        print(f"❌ Критическая ошибка: {e}")
        print(traceback.format_exc())
        shutdown_scheduler()
