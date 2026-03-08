#!/bin/bash

################################################################################
# ClowMe VPS Auto-Installer
# Автоматичне встановлення та налаштування ClowMe на VPS
################################################################################

set -e  # Зупинитися при помилці

# Кольори для виводу
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Глобальні змінні
INSTALL_LOG="/tmp/clowme_install.log"
ERROR_LOG="/tmp/clowme_errors.log"
SECURITY_LOG="/tmp/clowme_security.log"
INSTALL_DIR="/home/clowme/clowme"
CLOWME_USER="clowme"

# Функції виводу
print_header() {
    echo -e "\n${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║${NC} $1"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"
}

print_step() {
    echo -e "${CYAN}▶${NC} ${BOLD}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    echo "[$(date)] ERROR: $1" >> "$ERROR_LOG"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}


# Функція для запиту підтвердження
ask_confirmation() {
    local prompt="$1"
    local default="${2:-n}"
    
    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    read -p "$(echo -e ${CYAN}$prompt${NC})" response
    response=${response:-$default}
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Функція для запиту вводу з валідацією
ask_input() {
    local prompt="$1"
    local default="$2"
    local validation="$3"
    local value=""
    
    while true; do
        if [ -n "$default" ]; then
            read -p "$(echo -e ${CYAN}$prompt [default: $default]: ${NC})" value
            value=${value:-$default}
        else
            read -p "$(echo -e ${CYAN}$prompt: ${NC})" value
        fi
        
        # Валідація
        if [ -z "$validation" ] || eval "$validation"; then
            echo "$value"
            return 0
        else
            print_error "Невірне значення. Спробуй ще раз."
        fi
    done
}

# Функція для вибору з меню
ask_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    local recommended=""
    
    echo -e "${CYAN}$prompt${NC}"
    for i in "${!options[@]}"; do
        if [[ "${options[$i]}" == *"(рекомендовано)"* ]]; then
            echo -e "  ${GREEN}$((i+1))) ${options[$i]}${NC}"
            recommended=$((i+1))
        else
            echo "  $((i+1))) ${options[$i]}"
        fi
    done
    
    while true; do
        if [ -n "$recommended" ]; then
            read -p "$(echo -e ${CYAN}Вибери опцію [default: $recommended]: ${NC})" choice
            choice=${choice:-$recommended}
        else
            read -p "$(echo -e ${CYAN}Вибери опцію: ${NC})" choice
        fi
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            echo "$choice"
            return 0
        else
            print_error "Невірний вибір. Введи число від 1 до ${#options[@]}."
        fi
    done
}


# Перевірка системних вимог
check_system_requirements() {
    print_header "Перевірка системних вимог"
    
    local issues=0
    
    # Перевірка ОС
    print_step "Перевірка операційної системи..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        print_info "OS: $NAME $VERSION"
        
        if [[ "$ID" == "ubuntu" ]]; then
            VERSION_NUM=$(echo $VERSION_ID | cut -d. -f1)
            if [ "$VERSION_NUM" -ge 20 ]; then
                print_success "Ubuntu версія підходить ($VERSION_ID)"
            else
                print_warning "Ubuntu версія стара ($VERSION_ID), можуть бути проблеми"
                ((issues++))
            fi
        elif [[ "$ID" == "debian" ]]; then
            print_success "Debian виявлено ($VERSION_ID)"
        else
            print_warning "Не Ubuntu/Debian, можуть бути проблеми"
            ((issues++))
        fi
    else
        print_error "Не вдалося визначити ОС"
        ((issues++))
    fi
    
    # Перевірка RAM
    print_step "Перевірка оперативної пам'яті..."
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    print_info "RAM: ${TOTAL_RAM}MB"
    
    if [ "$TOTAL_RAM" -ge 1024 ]; then
        print_success "RAM достатньо"
    elif [ "$TOTAL_RAM" -ge 512 ]; then
        print_warning "RAM мінімальна (${TOTAL_RAM}MB), рекомендовано 1GB+"
    else
        print_error "RAM замало (${TOTAL_RAM}MB)"
        ((issues++))
    fi
    
    # Перевірка диску
    print_step "Перевірка дискового простору..."
    AVAILABLE_DISK=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    print_info "Вільно: ${AVAILABLE_DISK}GB"
    
    if [ "$AVAILABLE_DISK" -ge 10 ]; then
        print_success "Диск достатньо"
    elif [ "$AVAILABLE_DISK" -ge 5 ]; then
        print_warning "Диск мінімальний (${AVAILABLE_DISK}GB)"
    else
        print_error "Диск замало (${AVAILABLE_DISK}GB)"
        ((issues++))
    fi
    
    # Перевірка інтернету
    print_step "Перевірка інтернет з'єднання..."
    if ping -c 1 -W 2 google.com &> /dev/null; then
        print_success "Інтернет працює"
    else
        print_error "Немає інтернет з'єднання"
        ((issues++))
    fi
    
    if [ $issues -gt 0 ]; then
        print_warning "Знайдено $issues проблем"
        if ! ask_confirmation "Продовжити встановлення?" "n"; then
            print_error "Встановлення скасовано"
            exit 1
        fi
    else
        print_success "Всі перевірки пройдено успішно"
    fi
    
    echo "[$(date)] System check completed with $issues issues" >> "$INSTALL_LOG"
}


# Встановлення системних пакетів
install_system_packages() {
    print_header "Встановлення системних пакетів"
    
    print_step "Оновлення списку пакетів..."
    apt update >> "$INSTALL_LOG" 2>&1
    print_success "Список пакетів оновлено"
    
    print_step "Оновлення системи..."
    DEBIAN_FRONTEND=noninteractive apt upgrade -y >> "$INSTALL_LOG" 2>&1
    print_success "Система оновлена"
    
    # Визначити версію Python
    print_step "Визначення версії Python..."
    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
        PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)
        print_info "Поточна версія Python: $PYTHON_VERSION"
        
        if [ "$PYTHON_MINOR" -ge 9 ]; then
            PYTHON_CMD="python3"
            print_success "Python версія підходить"
        else
            print_warning "Python версія стара, встановлюємо Python 3.9"
            apt install -y software-properties-common >> "$INSTALL_LOG" 2>&1
            add-apt-repository -y ppa:deadsnakes/ppa >> "$INSTALL_LOG" 2>&1
            apt update >> "$INSTALL_LOG" 2>&1
            apt install -y python3.9 python3.9-venv python3.9-dev >> "$INSTALL_LOG" 2>&1
            PYTHON_CMD="python3.9"
            print_success "Python 3.9 встановлено"
        fi
    else
        print_step "Встановлення Python..."
        apt install -y python3 python3-venv python3-dev >> "$INSTALL_LOG" 2>&1
        PYTHON_CMD="python3"
        print_success "Python встановлено"
    fi
    
    # Встановити основні пакети
    print_step "Встановлення основних пакетів..."
    apt install -y \
        python3-pip \
        git \
        nginx \
        ufw \
        sqlite3 \
        curl \
        wget \
        htop \
        fail2ban \
        unattended-upgrades \
        >> "$INSTALL_LOG" 2>&1
    print_success "Основні пакети встановлено"
    
    # Встановити certbot
    print_step "Встановлення Certbot..."
    if command -v snap &> /dev/null; then
        snap install --classic certbot >> "$INSTALL_LOG" 2>&1
        ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true
        print_success "Certbot встановлено через snap"
    else
        apt install -y certbot python3-certbot-nginx >> "$INSTALL_LOG" 2>&1
        print_success "Certbot встановлено через apt"
    fi
    
    echo "[$(date)] System packages installed" >> "$INSTALL_LOG"
}


# Створення користувача
create_user() {
    print_header "Створення користувача"
    
    if id "$CLOWME_USER" &>/dev/null; then
        print_warning "Користувач $CLOWME_USER вже існує"
    else
        print_step "Створення користувача $CLOWME_USER..."
        useradd -m -s /bin/bash "$CLOWME_USER"
        print_success "Користувач створено"
    fi
    
    # Додати до sudo групи (опціонально)
    if ask_confirmation "Додати користувача до sudo групи?" "n"; then
        usermod -aG sudo "$CLOWME_USER"
        print_success "Користувач доданий до sudo групи"
    fi
    
    echo "[$(date)] User $CLOWME_USER created" >> "$INSTALL_LOG"
}

# Налаштування firewall
configure_firewall() {
    print_header "Налаштування Firewall"
    
    print_step "Налаштування UFW..."
    
    # Дозволити SSH
    ufw allow OpenSSH >> "$INSTALL_LOG" 2>&1
    print_success "SSH дозволено"
    
    # Дозволити HTTP/HTTPS
    ufw allow 80/tcp >> "$INSTALL_LOG" 2>&1
    ufw allow 443/tcp >> "$INSTALL_LOG" 2>&1
    print_success "HTTP/HTTPS дозволено"
    
    # Увімкнути UFW
    print_step "Увімкнення UFW..."
    echo "y" | ufw enable >> "$INSTALL_LOG" 2>&1
    print_success "UFW увімкнено"
    
    # Показати статус
    print_info "Статус UFW:"
    ufw status numbered
    
    echo "[$(date)] Firewall configured" >> "$INSTALL_LOG"
    echo "[$(date)] UFW rules: $(ufw status numbered)" >> "$SECURITY_LOG"
}


# Збір конфігурації від користувача
collect_configuration() {
    print_header "Збір конфігурації"
    
    # Telegram Bot Token
    print_step "Налаштування Telegram Bot"
    print_info "Отримай токен від @BotFather в Telegram"
    TELEGRAM_BOT_TOKEN=$(ask_input "Telegram Bot Token" "" '[[ "$value" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]')
    
    # Webhook Secret
    print_step "Генерація webhook secret..."
    WEBHOOK_SECRET=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
    print_success "Webhook secret згенеровано"
    
    # Domain
    DOMAIN=$(ask_input "Доменне ім'я (наприклад: bot.example.com)" "")
    
    # Admin ID
    print_step "Отримання Admin ID"
    print_info "Відправ повідомлення своєму боту в Telegram, потім натисни Enter"
    read -p "Натисни Enter коли готово..."
    
    print_step "Отримання ID з Telegram..."
    ADMIN_ID=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates" | \
        python3 -c "import sys, json; data=json.load(sys.stdin); print(data['result'][-1]['message']['from']['id'] if data['result'] else '')" 2>/dev/null)
    
    if [ -n "$ADMIN_ID" ]; then
        print_success "Admin ID отримано: $ADMIN_ID"
    else
        print_warning "Не вдалося автоматично отримати ID"
        ADMIN_ID=$(ask_input "Введи свій Telegram ID вручну" "")
    fi
    
    # Gemini API Key (опціонально)
    if ask_confirmation "Використовувати Gemini API як fallback?" "y"; then
        GEMINI_API_KEY=$(ask_input "Gemini API Key" "")
    else
        GEMINI_API_KEY=""
    fi
    
    # Local LLM
    if ask_confirmation "Встановити локальну LLM (Ollama)?" "n"; then
        INSTALL_OLLAMA=true
        LOCAL_MODEL_ENDPOINT="http://localhost:11434"
    else
        INSTALL_OLLAMA=false
        LOCAL_MODEL_ENDPOINT="http://localhost:11434"
    fi
    
    # Workers
    ENABLE_WORKERS=$(ask_confirmation "Увімкнути background workers?" "y" && echo "true" || echo "false")
    
    # Backup retention
    BACKUP_RETENTION=$(ask_input "Скільки днів зберігати backups" "7")
    
    # Зберегти конфігурацію
    cat > /tmp/clowme_config.env << EOF
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
WEBHOOK_SECRET=$WEBHOOK_SECRET
DOMAIN=$DOMAIN
ADMIN_ID=$ADMIN_ID
GEMINI_API_KEY=$GEMINI_API_KEY
LOCAL_MODEL_ENDPOINT=$LOCAL_MODEL_ENDPOINT
ENABLE_WORKERS=$ENABLE_WORKERS
BACKUP_RETENTION=$BACKUP_RETENTION
INSTALL_OLLAMA=$INSTALL_OLLAMA
EOF
    
    print_success "Конфігурація зібрана"
    echo "[$(date)] Configuration collected" >> "$INSTALL_LOG"
}


# Завантаження проекту
download_project() {
    print_header "Завантаження проекту ClowMe"
    
    # Вибір методу завантаження
    choice=$(ask_choice "Як завантажити проект?" \
        "З локального комп'ютера (через SCP) (рекомендовано)" \
        "З GitHub" \
        "Проект вже завантажено")
    
    case $choice in
        1)
            print_step "Очікування завантаження через SCP..."
            print_info "На локальному комп'ютері виконай:"
            echo -e "${YELLOW}  cd /path/to/ClowMe${NC}"
            echo -e "${YELLOW}  tar -czf clowme-deploy.tar.gz --exclude='.git' --exclude='venv' --exclude='*.pyc' .${NC}"
            echo -e "${YELLOW}  scp clowme-deploy.tar.gz root@$(hostname -I | awk '{print $1}'):/tmp/${NC}"
            echo ""
            read -p "Натисни Enter коли файл завантажено..."
            
            if [ -f /tmp/clowme-deploy.tar.gz ]; then
                print_step "Розпакування архіву..."
                su - "$CLOWME_USER" -c "mkdir -p $INSTALL_DIR"
                su - "$CLOWME_USER" -c "tar -xzf /tmp/clowme-deploy.tar.gz -C $INSTALL_DIR"
                rm /tmp/clowme-deploy.tar.gz
                print_success "Проект розпаковано"
            else
                print_error "Файл не знайдено"
                exit 1
            fi
            ;;
        2)
            REPO_URL=$(ask_input "GitHub repository URL" "https://github.com/your-org/clowme.git")
            print_step "Клонування з GitHub..."
            su - "$CLOWME_USER" -c "git clone $REPO_URL $INSTALL_DIR" >> "$INSTALL_LOG" 2>&1
            print_success "Проект клоновано"
            ;;
        3)
            if [ ! -d "$INSTALL_DIR" ]; then
                print_error "Директорія $INSTALL_DIR не існує"
                exit 1
            fi
            print_success "Використовуємо існуючий проект"
            ;;
    esac
    
    # Встановити права
    chown -R "$CLOWME_USER:$CLOWME_USER" "$INSTALL_DIR"
    
    echo "[$(date)] Project downloaded to $INSTALL_DIR" >> "$INSTALL_LOG"
}

# Налаштування Python середовища
setup_python_environment() {
    print_header "Налаштування Python середовища"
    
    print_step "Створення віртуального середовища..."
    su - "$CLOWME_USER" -c "cd $INSTALL_DIR && $PYTHON_CMD -m venv venv" >> "$INSTALL_LOG" 2>&1
    print_success "Віртуальне середовище створено"
    
    print_step "Оновлення pip..."
    su - "$CLOWME_USER" -c "cd $INSTALL_DIR && source venv/bin/activate && pip install --upgrade pip" >> "$INSTALL_LOG" 2>&1
    print_success "pip оновлено"
    
    print_step "Встановлення залежностей..."
    su - "$CLOWME_USER" -c "cd $INSTALL_DIR && source venv/bin/activate && pip install -r requirements.txt" >> "$INSTALL_LOG" 2>&1
    print_success "Залежності встановлено"
    
    # Створити необхідні директорії
    print_step "Створення директорій..."
    su - "$CLOWME_USER" -c "mkdir -p $INSTALL_DIR/{data,backups,logs}"
    chmod 700 "$INSTALL_DIR"/{data,backups,logs}
    print_success "Директорії створено"
    
    echo "[$(date)] Python environment configured" >> "$INSTALL_LOG"
}


# Створення .env файлу
create_env_file() {
    print_header "Створення конфігураційного файлу"
    
    # Завантажити конфігурацію
    source /tmp/clowme_config.env
    
    print_step "Створення .env файлу..."
    
    cat > "$INSTALL_DIR/.env" << EOF
# Telegram Configuration
CLOWME_TELEGRAM__WEBHOOK_SECRET=$WEBHOOK_SECRET
CLOWME_TELEGRAM__BOT_TOKEN=$TELEGRAM_BOT_TOKEN
CLOWME_TELEGRAM__DOMAIN=$DOMAIN

# Model Providers
CLOWME_MODELS__LOCAL_MODEL_ENDPOINT=$LOCAL_MODEL_ENDPOINT
CLOWME_MODELS__GEMINI_API_KEY=$GEMINI_API_KEY

# Database
CLOWME_DATABASE__SQLITE_PATH=$INSTALL_DIR/data/clowme.sqlite3

# Security
CLOWME_SECURITY__ADMIN_ACTOR_IDS=["$ADMIN_ID"]

# Workers
CLOWME_WORKERS__ENABLE_BACKGROUND_WORKERS=$ENABLE_WORKERS
CLOWME_WORKERS__TASK_LEASE_TIMEOUT_SECONDS=300

# Installer
CLOWME_INSTALLER__BACKUP_RETENTION_DAYS=$BACKUP_RETENTION
CLOWME_INSTALLER__BACKUP_DIRECTORY=$INSTALL_DIR/backups

# Logging
CLOWME_LOGGING__LOG_LEVEL=INFO
CLOWME_LOGGING__JSON_LOGS=true
EOF
    
    chmod 600 "$INSTALL_DIR/.env"
    chown "$CLOWME_USER:$CLOWME_USER" "$INSTALL_DIR/.env"
    
    print_success ".env файл створено"
    echo "[$(date)] .env file created" >> "$INSTALL_LOG"
}

# Ініціалізація бази даних
initialize_database() {
    print_header "Ініціалізація бази даних"
    
    print_step "Запуск installer..."
    su - "$CLOWME_USER" -c "cd $INSTALL_DIR && source venv/bin/activate && python3 -m agent_platform.installer install" >> "$INSTALL_LOG" 2>&1
    print_success "База даних ініціалізована"
    
    print_step "Перевірка hash chain..."
    su - "$CLOWME_USER" -c "cd $INSTALL_DIR && source venv/bin/activate && python3 -m agent_platform.event_store.verify_chain data/clowme.sqlite3" >> "$INSTALL_LOG" 2>&1
    print_success "Hash chain перевірено"
    
    echo "[$(date)] Database initialized" >> "$INSTALL_LOG"
}


# Налаштування Nginx
configure_nginx() {
    print_header "Налаштування Nginx"
    
    source /tmp/clowme_config.env
    
    print_step "Створення конфігурації Nginx..."
    
    cat > /etc/nginx/sites-available/clowme << EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        client_max_body_size 10M;
        proxy_read_timeout 60s;
    }

    location /health {
        proxy_pass http://127.0.0.1:8000/health;
        access_log off;
    }
}
EOF
    
    # Активувати конфігурацію
    ln -sf /etc/nginx/sites-available/clowme /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Перевірити конфігурацію
    print_step "Перевірка конфігурації Nginx..."
    if nginx -t >> "$INSTALL_LOG" 2>&1; then
        print_success "Конфігурація Nginx валідна"
    else
        print_error "Помилка в конфігурації Nginx"
        nginx -t
        exit 1
    fi
    
    # Перезапустити Nginx
    systemctl restart nginx
    print_success "Nginx перезапущено"
    
    echo "[$(date)] Nginx configured for $DOMAIN" >> "$INSTALL_LOG"
}

# Налаштування SSL
configure_ssl() {
    print_header "Налаштування SSL сертифіката"
    
    source /tmp/clowme_config.env
    
    if ask_confirmation "Налаштувати SSL сертифікат (Let's Encrypt)?" "y"; then
        print_step "Отримання SSL сертифіката..."
        print_info "Переконайся що домен $DOMAIN вказує на цей сервер"
        
        if ask_confirmation "Домен налаштовано?" "y"; then
            certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" --redirect >> "$INSTALL_LOG" 2>&1
            
            if [ $? -eq 0 ]; then
                print_success "SSL сертифікат встановлено"
                
                # Налаштувати auto-renewal
                print_step "Налаштування автоматичного оновлення..."
                (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -
                print_success "Автоматичне оновлення налаштовано"
            else
                print_warning "Не вдалося отримати SSL сертифікат"
                print_info "Можна налаштувати пізніше: certbot --nginx -d $DOMAIN"
            fi
        else
            print_info "SSL можна налаштувати пізніше: certbot --nginx -d $DOMAIN"
        fi
    else
        print_info "SSL не налаштовано. Webhook працюватиме тільки через HTTP"
        echo "[$(date)] WARNING: SSL not configured" >> "$SECURITY_LOG"
    fi
    
    echo "[$(date)] SSL configuration completed" >> "$INSTALL_LOG"
}


# Створення systemd service
create_systemd_service() {
    print_header "Створення systemd service"
    
    print_step "Створення service файлу..."
    
    cat > /etc/systemd/system/clowme.service << EOF
[Unit]
Description=ClowMe Agent Platform
After=network.target

[Service]
Type=simple
User=$CLOWME_USER
Group=$CLOWME_USER
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/python3 -m agent_platform
Restart=always
RestartSec=10
StandardOutput=append:$INSTALL_DIR/logs/clowme.log
StandardError=append:$INSTALL_DIR/logs/clowme-error.log

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$INSTALL_DIR/data $INSTALL_DIR/backups $INSTALL_DIR/logs

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Service файл створено"
    
    # Перезавантажити systemd
    systemctl daemon-reload
    
    # Увімкнути автозапуск
    systemctl enable clowme >> "$INSTALL_LOG" 2>&1
    print_success "Автозапуск увімкнено"
    
    # Запустити service
    print_step "Запуск ClowMe service..."
    systemctl start clowme
    
    sleep 3
    
    if systemctl is-active --quiet clowme; then
        print_success "ClowMe service запущено"
    else
        print_error "Не вдалося запустити service"
        print_info "Перевір логи: journalctl -u clowme -n 50"
        echo "[$(date)] ERROR: Service failed to start" >> "$ERROR_LOG"
    fi
    
    echo "[$(date)] Systemd service created and started" >> "$INSTALL_LOG"
}

# Налаштування Telegram webhook
setup_telegram_webhook() {
    print_header "Налаштування Telegram Webhook"
    
    source /tmp/clowme_config.env
    
    # Визначити протокол
    if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
        WEBHOOK_URL="https://$DOMAIN/webhook"
    else
        WEBHOOK_URL="http://$DOMAIN/webhook"
        print_warning "Використовується HTTP (SSL не налаштовано)"
    fi
    
    print_step "Встановлення webhook: $WEBHOOK_URL"
    
    RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
        -H "Content-Type: application/json" \
        -d "{\"url\":\"$WEBHOOK_URL\",\"secret_token\":\"$WEBHOOK_SECRET\",\"max_connections\":40,\"allowed_updates\":[\"message\",\"edited_message\",\"callback_query\"]}")
    
    if echo "$RESPONSE" | grep -q '"ok":true'; then
        print_success "Webhook встановлено"
        
        # Перевірити webhook
        print_step "Перевірка webhook..."
        WEBHOOK_INFO=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo")
        echo "$WEBHOOK_INFO" | python3 -m json.tool >> "$INSTALL_LOG" 2>&1
        print_success "Webhook активний"
    else
        print_error "Не вдалося встановити webhook"
        echo "$RESPONSE" | python3 -m json.tool
        echo "[$(date)] ERROR: Webhook setup failed: $RESPONSE" >> "$ERROR_LOG"
    fi
    
    echo "[$(date)] Telegram webhook configured" >> "$INSTALL_LOG"
}


# Налаштування cron jobs
setup_cron_jobs() {
    print_header "Налаштування автоматичних задач"
    
    print_step "Створення cron jobs..."
    
    # Створити crontab для користувача clowme
    su - "$CLOWME_USER" -c "crontab -l 2>/dev/null" > /tmp/clowme_crontab || true
    
    # Додати задачі якщо їх ще немає
    if ! grep -q "clowme backup" /tmp/clowme_crontab 2>/dev/null; then
        cat >> /tmp/clowme_crontab << EOF

# ClowMe automated tasks
# Daily backup at 2:00 AM
0 2 * * * cd $INSTALL_DIR && $INSTALL_DIR/venv/bin/python3 -m agent_platform.installer backup >> $INSTALL_DIR/logs/backup.log 2>&1

# Weekly hash chain verification (Sunday at 3:00 AM)
0 3 * * 0 cd $INSTALL_DIR && $INSTALL_DIR/venv/bin/python3 -m agent_platform.event_store.verify_chain data/clowme.sqlite3 >> $INSTALL_DIR/logs/integrity.log 2>&1

# Daily cleanup of old backups
0 4 * * * cd $INSTALL_DIR && $INSTALL_DIR/venv/bin/python3 -m agent_platform.installer cleanup-backups --days $BACKUP_RETENTION >> $INSTALL_DIR/logs/cleanup.log 2>&1
EOF
        
        su - "$CLOWME_USER" -c "crontab /tmp/clowme_crontab"
        print_success "Cron jobs налаштовано"
    else
        print_info "Cron jobs вже налаштовані"
    fi
    
    rm -f /tmp/clowme_crontab
    
    echo "[$(date)] Cron jobs configured" >> "$INSTALL_LOG"
}

# Налаштування logrotate
setup_logrotate() {
    print_header "Налаштування ротації логів"
    
    print_step "Створення конфігурації logrotate..."
    
    cat > /etc/logrotate.d/clowme << EOF
$INSTALL_DIR/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 $CLOWME_USER $CLOWME_USER
    sharedscripts
    postrotate
        systemctl reload clowme > /dev/null 2>&1 || true
    endscript
}
EOF
    
    print_success "Logrotate налаштовано"
    echo "[$(date)] Logrotate configured" >> "$INSTALL_LOG"
}

# Налаштування fail2ban
setup_fail2ban() {
    print_header "Налаштування Fail2ban"
    
    if ask_confirmation "Налаштувати Fail2ban для захисту від атак?" "y"; then
        print_step "Створення jail для Nginx..."
        
        cat > /etc/fail2ban/jail.local << EOF
[nginx-limit-req]
enabled = true
filter = nginx-limit-req
logpath = /var/log/nginx/error.log
maxretry = 5
findtime = 600
bantime = 3600

[nginx-noscript]
enabled = true
filter = nginx-noscript
logpath = /var/log/nginx/access.log
maxretry = 6
findtime = 600
bantime = 3600
EOF
        
        systemctl restart fail2ban
        print_success "Fail2ban налаштовано"
        echo "[$(date)] Fail2ban configured" >> "$SECURITY_LOG"
    else
        print_info "Fail2ban не налаштовано"
    fi
}


# Встановлення Ollama (опціонально)
install_ollama() {
    source /tmp/clowme_config.env
    
    if [ "$INSTALL_OLLAMA" = "true" ]; then
        print_header "Встановлення Ollama (Local LLM)"
        
        print_step "Завантаження та встановлення Ollama..."
        curl -fsSL https://ollama.com/install.sh | sh >> "$INSTALL_LOG" 2>&1
        
        if command -v ollama &> /dev/null; then
            print_success "Ollama встановлено"
            
            # Запустити service
            systemctl start ollama
            systemctl enable ollama
            print_success "Ollama service запущено"
            
            # Завантажити модель
            if ask_confirmation "Завантажити модель llama2 (~4GB)?" "y"; then
                print_step "Завантаження моделі llama2..."
                print_warning "Це може зайняти кілька хвилин..."
                ollama pull llama2 >> "$INSTALL_LOG" 2>&1
                print_success "Модель llama2 завантажено"
            fi
        else
            print_error "Не вдалося встановити Ollama"
        fi
        
        echo "[$(date)] Ollama installed" >> "$INSTALL_LOG"
    fi
}

# Аналіз безпеки
security_analysis() {
    print_header "Аналіз безпеки системи"
    
    local issues=0
    
    # Перевірка SSH
    print_step "Перевірка SSH конфігурації..."
    if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
        print_warning "Root login через SSH увімкнено"
        echo "[$(date)] SECURITY: Root SSH login enabled" >> "$SECURITY_LOG"
        ((issues++))
    else
        print_success "Root login через SSH вимкнено"
    fi
    
    # Перевірка firewall
    print_step "Перевірка firewall..."
    if ufw status | grep -q "Status: active"; then
        print_success "Firewall активний"
    else
        print_warning "Firewall не активний"
        echo "[$(date)] SECURITY: Firewall not active" >> "$SECURITY_LOG"
        ((issues++))
    fi
    
    # Перевірка SSL
    print_step "Перевірка SSL..."
    source /tmp/clowme_config.env
    if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
        print_success "SSL сертифікат встановлено"
    else
        print_warning "SSL сертифікат не встановлено"
        echo "[$(date)] SECURITY: No SSL certificate" >> "$SECURITY_LOG"
        ((issues++))
    fi
    
    # Перевірка прав на файли
    print_step "Перевірка прав на файли..."
    if [ "$(stat -c %a $INSTALL_DIR/.env)" = "600" ]; then
        print_success "Права на .env коректні"
    else
        print_warning "Права на .env некоректні"
        chmod 600 "$INSTALL_DIR/.env"
        echo "[$(date)] SECURITY: Fixed .env permissions" >> "$SECURITY_LOG"
    fi
    
    # Перевірка автоматичних оновлень
    print_step "Перевірка автоматичних оновлень..."
    if dpkg -l | grep -q unattended-upgrades; then
        print_success "Автоматичні оновлення встановлено"
    else
        print_warning "Автоматичні оновлення не встановлено"
        ((issues++))
    fi
    
    # Підсумок
    if [ $issues -eq 0 ]; then
        print_success "Аналіз безпеки: проблем не виявлено"
    else
        print_warning "Аналіз безпеки: виявлено $issues потенційних проблем"
        print_info "Детальніше дивись: $SECURITY_LOG"
    fi
    
    echo "[$(date)] Security analysis completed with $issues issues" >> "$SECURITY_LOG"
}


# Тестування системи
test_installation() {
    print_header "Тестування встановлення"
    
    source /tmp/clowme_config.env
    
    local tests_passed=0
    local tests_failed=0
    
    # Тест 1: Service працює
    print_step "Тест 1: Перевірка ClowMe service..."
    if systemctl is-active --quiet clowme; then
        print_success "Service працює"
        ((tests_passed++))
    else
        print_error "Service не працює"
        ((tests_failed++))
    fi
    
    # Тест 2: Health endpoint
    print_step "Тест 2: Перевірка health endpoint..."
    sleep 2
    if curl -s http://localhost:8000/health | grep -q "ok"; then
        print_success "Health endpoint працює"
        ((tests_passed++))
    else
        print_error "Health endpoint не відповідає"
        ((tests_failed++))
    fi
    
    # Тест 3: База даних
    print_step "Тест 3: Перевірка бази даних..."
    if [ -f "$INSTALL_DIR/data/clowme.sqlite3" ]; then
        EVENT_COUNT=$(sqlite3 "$INSTALL_DIR/data/clowme.sqlite3" "SELECT COUNT(*) FROM events;" 2>/dev/null || echo "0")
        print_success "База даних існує (події: $EVENT_COUNT)"
        ((tests_passed++))
    else
        print_error "База даних не знайдена"
        ((tests_failed++))
    fi
    
    # Тест 4: Nginx
    print_step "Тест 4: Перевірка Nginx..."
    if systemctl is-active --quiet nginx; then
        print_success "Nginx працює"
        ((tests_passed++))
    else
        print_error "Nginx не працює"
        ((tests_failed++))
    fi
    
    # Тест 5: Webhook
    print_step "Тест 5: Перевірка Telegram webhook..."
    WEBHOOK_INFO=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo")
    if echo "$WEBHOOK_INFO" | grep -q "\"url\":\"http"; then
        print_success "Webhook налаштовано"
        ((tests_passed++))
    else
        print_warning "Webhook не налаштовано або недоступний"
        ((tests_failed++))
    fi
    
    # Тест 6: Логи
    print_step "Тест 6: Перевірка логів..."
    if [ -f "$INSTALL_DIR/logs/clowme.log" ]; then
        LOG_SIZE=$(du -h "$INSTALL_DIR/logs/clowme.log" | cut -f1)
        print_success "Логи пишуться (розмір: $LOG_SIZE)"
        ((tests_passed++))
    else
        print_warning "Файл логів не знайдено"
    fi
    
    # Підсумок тестів
    echo ""
    print_info "Тестів пройдено: $tests_passed"
    print_info "Тестів провалено: $tests_failed"
    
    if [ $tests_failed -eq 0 ]; then
        print_success "Всі тести пройдено успішно!"
    else
        print_warning "Деякі тести провалено. Перевір логи."
    fi
    
    echo "[$(date)] Tests: $tests_passed passed, $tests_failed failed" >> "$INSTALL_LOG"
}

# Генерація звіту
generate_report() {
    print_header "Генерація звіту про встановлення"
    
    source /tmp/clowme_config.env
    
    local REPORT_FILE="$INSTALL_DIR/INSTALLATION_REPORT.txt"
    
    cat > "$REPORT_FILE" << EOF
╔════════════════════════════════════════════════════════════╗
║          ClowMe Installation Report                        ║
╚════════════════════════════════════════════════════════════╝

Дата встановлення: $(date)
Сервер: $(hostname)
IP адреса: $(hostname -I | awk '{print $1}')

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
КОНФІГУРАЦІЯ
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Домен: $DOMAIN
Telegram Bot Token: ${TELEGRAM_BOT_TOKEN:0:10}...
Admin ID: $ADMIN_ID
Директорія: $INSTALL_DIR
Python: $($PYTHON_CMD --version)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ВСТАНОВЛЕНІ КОМПОНЕНТИ
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ ClowMe Agent Platform
✅ Python $(python3 --version | cut -d' ' -f2)
✅ Nginx $(nginx -v 2>&1 | cut -d'/' -f2)
✅ SQLite $(sqlite3 --version | cut -d' ' -f1)
✅ Certbot $(certbot --version 2>&1 | cut -d' ' -f2)
$([ "$INSTALL_OLLAMA" = "true" ] && echo "✅ Ollama (Local LLM)" || echo "❌ Ollama (не встановлено)")

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
СЕРВІСИ
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ClowMe: $(systemctl is-active clowme)
Nginx: $(systemctl is-active nginx)
UFW: $(ufw status | head -1)
$([ "$INSTALL_OLLAMA" = "true" ] && echo "Ollama: $(systemctl is-active ollama)" || echo "")

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ENDPOINTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Webhook: $([ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] && echo "https://$DOMAIN/webhook" || echo "http://$DOMAIN/webhook")
Health: http://localhost:8000/health
Admin: Telegram Bot @$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" | python3 -c "import sys, json; print(json.load(sys.stdin)['result']['username'])" 2>/dev/null)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
АВТОМАТИЧНІ ЗАДАЧІ
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Щоденний backup (2:00 AM)
✅ Щотижнева перевірка hash chain (неділя 3:00 AM)
✅ Щоденне очищення старих backups (4:00 AM)
✅ Ротація логів (щоденно)
$([ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] && echo "✅ Автоматичне оновлення SSL" || echo "")

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
КОРИСНІ КОМАНДИ
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Статус сервісу:
  systemctl status clowme

Логи:
  journalctl -u clowme -f
  tail -f $INSTALL_DIR/logs/clowme.log

Перезапуск:
  systemctl restart clowme

Backup:
  su - $CLOWME_USER -c "cd $INSTALL_DIR && source venv/bin/activate && python3 -m agent_platform.installer backup"

Перевірка hash chain:
  su - $CLOWME_USER -c "cd $INSTALL_DIR && source venv/bin/activate && python3 -m agent_platform.event_store.verify_chain data/clowme.sqlite3"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ЛОГИ ВСТАНОВЛЕННЯ
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Повний лог: $INSTALL_LOG
Помилки: $ERROR_LOG
Безпека: $SECURITY_LOG

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
НАСТУПНІ КРОКИ
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Відправ повідомлення своєму боту в Telegram
2. Перевір що бот відповідає
3. Налаштуй додаткові месенджери (опціонально):
   - docs/multi_messenger_quickstart.md
4. Налаштуй Topics для групових чатів:
   - docs/topics_guide.md
5. Створи плагіни для розширення функціоналу:
   - docs/plugins_guide.md

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Вітаємо! ClowMe успішно встановлено! 🎉

EOF
    
    chown "$CLOWME_USER:$CLOWME_USER" "$REPORT_FILE"
    
    print_success "Звіт збережено: $REPORT_FILE"
    
    # Показати звіт
    cat "$REPORT_FILE"
}


# Головна функція
main() {
    # Перевірка root прав
    if [ "$EUID" -ne 0 ]; then
        print_error "Цей скрипт потрібно запускати з правами root"
        echo "Використай: sudo bash $0"
        exit 1
    fi
    
    # Привітання
    clear
    echo -e "${BOLD}${MAGENTA}"
    cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║              ClowMe VPS Auto-Installer                     ║
║                                                            ║
║     Автоматичне встановлення та налаштування ClowMe       ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
    
    print_info "Версія: 1.0.0"
    print_info "Дата: $(date)"
    echo ""
    
    # Підтвердження
    if ! ask_confirmation "Розпочати встановлення ClowMe?" "y"; then
        print_info "Встановлення скасовано"
        exit 0
    fi
    
    # Ініціалізація логів
    echo "ClowMe Installation Started at $(date)" > "$INSTALL_LOG"
    echo "ClowMe Installation Errors" > "$ERROR_LOG"
    echo "ClowMe Security Analysis" > "$SECURITY_LOG"
    
    # Виконання кроків встановлення
    check_system_requirements
    install_system_packages
    create_user
    configure_firewall
    collect_configuration
    download_project
    setup_python_environment
    create_env_file
    initialize_database
    configure_nginx
    configure_ssl
    create_systemd_service
    setup_telegram_webhook
    setup_cron_jobs
    setup_logrotate
    setup_fail2ban
    install_ollama
    
    # Аналіз та тестування
    security_analysis
    test_installation
    
    # Генерація звіту
    generate_report
    
    # Фінальне повідомлення
    echo ""
    print_header "Встановлення завершено!"
    
    print_success "ClowMe успішно встановлено та запущено"
    echo ""
    print_info "Звіт про встановлення: $INSTALL_DIR/INSTALLATION_REPORT.txt"
    print_info "Логи встановлення: $INSTALL_LOG"
    
    if [ -s "$ERROR_LOG" ]; then
        print_warning "Виявлено помилки під час встановлення"
        print_info "Лог помилок: $ERROR_LOG"
    fi
    
    if [ -s "$SECURITY_LOG" ]; then
        print_info "Аналіз безпеки: $SECURITY_LOG"
    fi
    
    echo ""
    print_info "Наступні кроки:"
    echo "  1. Відправ повідомлення своєму боту в Telegram"
    echo "  2. Перевір статус: systemctl status clowme"
    echo "  3. Переглянь логи: tail -f $INSTALL_DIR/logs/clowme.log"
    echo ""
    
    # Очистити тимчасові файли
    rm -f /tmp/clowme_config.env
    
    print_success "Готово! 🎉"
}

# Обробка помилок
trap 'print_error "Встановлення перервано"; exit 1' INT TERM

# Запуск
main "$@"
