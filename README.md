# 🤖 3x-UI Telegram Bot

Полностью автоматизированная система управления VPN серверами на базе 3x-UI через Telegram бота с интерактивным меню управления.

## ✨ Возможности

- 🚀 **Автоматическая установка** одной командой с интерактивной настройкой
- 🎯 **Интеллектуальное управление** - меню управления после установки
- 🔄 **Автообновление** - автоматическая проверка и обновление скрипта установки
- 👥 **Управление пользователями** через Telegram бота
- 🌍 **Мультисервер** - неограниченное количество серверов 3x-UI
- 📊 **Статистика** использования в реальном времени
- 📱 **QR-коды** для быстрого подключения клиентов
- 🛠️ **Встроенная панель управления** после установки
- 💚 **Система поддержки разработчика** с QR-кодами донатов
- 🔐 **Безопасность** - двойное подтверждение при удалении

## 🚀 Быстрая установка

Выполните одну команду на чистом Ubuntu/Debian VPS:

```bash
curl -sSL https://raw.githubusercontent.com/stalkerj/vpn-telegram-bot/codex-y2oa12/install-vpn-bot.sh | sudo bash
```

### Что вам понадобится:

1. **Telegram Bot Token** - получите от [@BotFather](https://t.me/BotFather)
2. **Telegram Admin ID** - узнайте у [@userinfobot](https://t.me/userinfobot)
3. **Данные серверов 3x-UI**:
   - URL панели (https://your-server.com:port)
   - Путь к панели (обычно /panel)
   - Username и Password
   - IP-адрес сервера
   - Название страны/региона

## 📋 Системные требования

| Компонент | Минимум | Рекомендуется |
|-----------|---------|---------------|
| ОС | Ubuntu 20.04+ / Debian 11+ | Ubuntu 22.04 LTS |
| RAM | 512 MB | 1 GB |
| Диск | 1 GB | 2 GB |
| Python | 3.8+ | 3.10+ |

## 🎯 Процесс установки

Скрипт автоматически выполняет:

1. ✅ Проверку системных требований (RAM, диск, root-доступ)
2. 🔍 Определение операционной системы
3. 📦 Обновление системы с прогрессом
4. 🐍 Установку Python, pip, venv и всех зависимостей (включая qrencode)
5. 🔐 Интерактивный сбор конфигурации
6. 📁 Установку бота в `/root/vpn-bot`
7. ⚙️ Настройку systemd службы с автозапуском
8. 🛠️ Создание команды `vpn-bot` для быстрого доступа
9. 🚀 Запуск бота с проверкой статуса
10. 💚 Показ QR-кода для поддержки разработчика

**Время установки:** ~5-10 минут (зависит от скорости интернета)

## 🛠️ Управление ботом

### Команда vpn-bot

Быстрый доступ к меню управления из любого места:

```bash
vpn-bot
```

### Основные команды:

```bash
# Быстрый доступ к меню
vpn-bot

# Статус бота
systemctl status vpn-bot

# Перезапуск
systemctl restart vpn-bot

# Остановка
systemctl stop vpn-bot

# Запуск
systemctl start vpn-bot

# Логи в реальном времени
journalctl -u vpn-bot -f

# Последние 50 строк логов
journalctl -u vpn-bot -n 50

# Редактирование конфигурации
nano /root/vpn-bot/.env

# После редактирования .env:
systemctl restart vpn-bot
```

## 💾 Резервное копирование

### Важные файлы для backup:

```bash
# Конфигурация (самое важное!)
/root/vpn-bot/.env

# Полный backup
tar -czf /root/vpn-bot-backup-$(date +%Y%m%d).tar.gz -C /root vpn-bot
```

### Восстановление:

```bash
# Восстановить .env
cp /backup/.env /root/vpn-bot/.env
chmod 600 /root/vpn-bot/.env
systemctl restart vpn-bot

# Восстановить из архива
tar -xzf /root/vpn-bot-backup-20251203.tar.gz -C /root
systemctl restart vpn-bot
```

## 🗑️ Удаление

### Через меню (рекомендуется):

```bash
vpn-bot
# Выбрать: 6 (Полное удаление)
# Подтвердить: YES
# Подтвердить: УДАЛИТЬ
# Увидеть прощание и QR-код
```

Показывается:
- 💚 Благодарность за использование
- 🔗 QR-код для доната (если установлен qrencode)
- ⏳ Пауза 3 секунды
- 🗑️ Удаление всех компонентов
- 👋 Финальное прощание

### Ручное удаление:

```bash
# Остановить и удалить службу
systemctl stop vpn-bot
systemctl disable vpn-bot
rm /etc/systemd/system/vpn-bot.service
systemctl daemon-reload

# Удалить файлы
rm -rf /root/vpn-bot
rm /usr/local/bin/vpn-bot
```

## 🔒 Безопасность

- ✅ Файл `.env` защищен правами `600` (только root)
- ✅ Пароли не отображаются при вводе
- ✅ Двойное подтверждение при удалении (YES + УДАЛИТЬ)
- ✅ Бот работает только от root (изолированно)
- ✅ Проверка подлинности токенов
- ✅ Защита от случайного удаления

## 📝 Конфигурация .env

Формат файла `/root/vpn-bot/.env`:

```bash
# Telegram Bot Configuration
TELEGRAM_BOT_TOKEN=1234567890:ABCdefGHIjklMNOpqrsTUVwxyz
ADMIN_USER_ID=123456789

# Server 1 - Германия
XUI_HOST_1=https://89.32.13.16:17268
XUI_PATH_1=/kDYLDAOQijhYTi
XUI_USERNAME_1=ROg8giytu87
XUI_PASSWORD_1=your_password
XUI_TOKEN_1=
SERVER_IP_1=89.32.13.16
COUNTRY_NAME_1=Германия

# Server 2 - Франция
XUI_HOST_2=https://92.15.123.45:2053
XUI_PATH_2=/panel
XUI_USERNAME_2=admin
XUI_PASSWORD_2=password
XUI_TOKEN_2=
SERVER_IP_2=92.15.123.45
COUNTRY_NAME_2=Франция

# Server 3 - добавьте еще серверы по аналогии
# XUI_HOST_3=...
```

## 🐛 Устранение проблем

### Бот не запускается:

```bash
# Проверить статус
vpn-bot
# Выбрать: 1

# Или через systemctl
systemctl status vpn-bot

# Посмотреть логи
vpn-bot
# Выбрать: 4

# Или напрямую
journalctl -u vpn-bot -n 50
```

### Команда vpn-bot не найдена:

```bash
# Проверить существование
ls -la /usr/local/bin/vpn-bot

# Пересоздать команду (если нужно)
cat > /usr/local/bin/vpn-bot << 'EOF'
#!/bin/bash
if [ -f "/root/vpn-bot/menu.sh" ]; then
    source /root/vpn-bot/menu.sh
    menu_loop
else
    echo "❌ Файл меню не найден"
    exit 1
fi
EOF
chmod +x /usr/local/bin/vpn-bot
```

### Ошибка curl: (23) при выходе:

Эта проблема решена в версии 3.4! Если вы видите эту ошибку:

```bash
# Обновите скрипт
curl -sSL https://raw.githubusercontent.com/stalkerj/vpn-telegram-bot/main/install-vpn-bot.sh | sudo bash
# Выбрать: 3 (Обновить только код)
```

### Бот не отвечает в Telegram:

```bash
# Проверить статус
systemctl status vpn-bot

# Проверить подключение к Telegram API
curl -s https://api.telegram.org/bot<YOUR_TOKEN>/getMe

# Проверить токен в .env
cat /root/vpn-bot/.env | grep TELEGRAM_BOT_TOKEN

# Перезапустить
systemctl restart vpn-bot
```

### Ошибки подключения к 3x-UI:

```bash
# Проверить доступность панели
curl -k https://YOUR_SERVER_IP:PORT/panel

# Проверить настройки
vpn-bot
# Выбрать: 2 (Список серверов)

# Проверить .env
cat /root/vpn-bot/.env

# Проверить логи
vpn-bot
# Выбрать: 4
```

## 📊 Мониторинг

### Просмотр статистики:

```bash
# Через меню
vpn-bot
# Выбрать: 1 (Статус)

# Статус службы
systemctl status vpn-bot

# Использование ресурсов
top -p $(pgrep -f vpn_bot.py)

# Размер логов
journalctl -u vpn-bot --disk-usage

# Очистка старых логов (старше 7 дней)
journalctl --vacuum-time=7d
```

## 🆕 Обновление

### Обновление через скрипт (рекомендуется):

```bash
# Запустить скрипт
curl -sSL https://raw.githubusercontent.com/stalkerj/vpn-telegram-bot/main/install-vpn-bot.sh | sudo bash

# Выбрать:
# 3 - Обновить только код (сохранит .env)
# или
# 2 - Полная переустановка (потребуется ввести данные заново)
```

### Ручное обновление кода бота:

```bash
# Создать backup
cp /root/vpn-bot/.env /root/vpn-bot-env-backup

# Скачать новую версию
TEMP_SCRIPT="/tmp/update_script.sh"
curl -sSL https://raw.githubusercontent.com/stalkerj/vpn-telegram-bot/main/install-vpn-bot.sh > "$TEMP_SCRIPT"

# Извлечь код бота
MARKER_LINE=$(grep -n "^__BOT_CODE_BELOW__" "$TEMP_SCRIPT" | cut -d: -f1)
tail -n +$((MARKER_LINE + 1)) "$TEMP_SCRIPT" > /root/vpn-bot/vpn_bot.py

# Восстановить .env и перезапустить
cp /root/vpn-bot-env-backup /root/vpn-bot/.env
chmod +x /root/vpn-bot/vpn_bot.py
systemctl restart vpn-bot
rm -f "$TEMP_SCRIPT"
```

## 💚 Поддержка разработчика

Если проект оказался полезным, вы можете поддержать разработку:

**🔗 CloudTips:** https://pay.cloudtips.ru/p/52d42415

QR-код для доната показывается:
- После установки бота
- При выходе из меню
- При удалении бота

Каждый донат мотивирует на развитие проекта! ❤️

## 🎓 FAQ (Часто задаваемые вопросы)

**Q: Можно ли установить на VPS с уже установленным 3x-UI?**  
A: Да, бот работает с любым количеством удаленных панелей 3x-UI.

**Q: Сколько серверов можно подключить?**  
A: Неограниченное количество. Просто добавьте новые блоки в `.env`.

**Q: Как добавить новый сервер после установки?**  
A: Запустите `vpn-bot` → пункт 5 → добавьте новый блок → пункт 3 (перезапуск).

**Q: Бот работает только на русском?**  
A: Да, интерфейс на русском языке.

**Q: Нужен ли root доступ?**  
A: Да, скрипт должен запускаться от root или через sudo.

**Q: Можно ли установить на Debian/Ubuntu Desktop?**  
A: Да, но рекомендуется использовать VPS/VDS сервер.

**Q: Как восстановить бота после перезагрузки сервера?**  
A: Служба запускается автоматически. Проверьте: `systemctl status vpn-bot`

**Q: Что делать если забыл токен бота?**  
A: Посмотрите в файле: `cat /root/vpn-bot/.env | grep TOKEN`

**Q: Можно ли использовать с другими панелями кроме 3x-UI?**  
A: Нет, бот разработан специально для работы с API 3x-UI.

**Q: Как обновить версию скрипта?**  
A: Скрипт автоматически проверяет обновления при повторном запуске.

## 📞 Поддержка

- 🐛 **Issues**: [GitHub Issues](https://github.com/stalkerj/vpn-telegram-bot/issues)
- 💬 **Telegram**: [@stalkerj](https://t.me/stalkerj)
- 💚 **Донат**: [CloudTips](https://pay.cloudtips.ru/p/52d42415)

## 📜 Лицензия

MIT License - используйте свободно!

## 🙏 Благодарности

- [3x-UI](https://github.com/MHSanaei/3x-ui) - панель управления Xray
- [pyTelegramBotAPI](https://github.com/eternnoir/pyTelegramBotAPI) - Telegram Bot API
- [qrencode](https://fukuchi.org/works/qrencode/) - генерация QR-кодов

---

**⭐ Если проект помог вам - поставьте звезду на GitHub!**

**💚 Поддержите разработчика:** https://pay.cloudtips.ru/p/52d42415
