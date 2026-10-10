```bash
#!/usr/bin/env bash

# Автоматизация управления пользователями, группами и службами Linux
# Целевая ОС: Ubuntu / Debian
# Запуск: sudo bash setup_users.sh

set -Eeuo pipefail

# Вывод информационных сообщений
log() {
    printf '[ИНФО] %s\n' "$*"
}

# Вывод ошибки и завершение скрипта
die() {
    printf '[ОШИБКА] %s\n' "$*" >&2
    exit 1
}

# Проверка наличия прав суперпользователя
if [[ "${EUID}" -ne 0 ]]; then
    die "Запустите скрипт с правами root: sudo bash $0"
fi

# Создание группы, если она ещё не существует
ensure_group() {
    local group="$1"

    if ! getent group "$group" >/dev/null; then
        groupadd "$group"
        log "Создана группа: $group"
    else
        log "Группа уже существует: $group"
    fi
}

# Создание пользователя, если он ещё не существует
ensure_user() {
    local username="$1"
    local group="$2"

    if ! id "$username" >/dev/null 2>&1; then
        # Создаём домашний каталог и назначаем основную группу
        useradd -m -s /bin/bash -g "$group" "$username"
        log "Создан пользователь: $username"
    else
        log "Пользователь уже существует: $username"
    fi

    # Создаём домашний каталог, если он отсутствует
    if [[ ! -d "/home/$username" ]]; then
        install -d "/home/$username"
        chown "$username:$group" "/home/$username"
    fi
}

# 1. Создаём группы для разных категорий пользователей
ensure_group default_users
ensure_group secret_users

# 2. Создаём пользователей
ensure_user user default_users
ensure_user secret_agent secret_users
ensure_user secret_spy secret_users
ensure_user secret_boss secret_users

# 3. Добавляем пользователей в соответствующие группы
# Ключ -aG сохраняет остальные дополнительные группы пользователя
usermod -aG default_users user

for username in secret_agent secret_spy secret_boss; do
    usermod -aG secret_users "$username"
done

# 4. Настраиваем доступ к домашним каталогам секретной группы
for username in secret_agent secret_spy secret_boss; do
    home="/home/$username"

    # Владелец — пользователь, группа — secret_users
    chown "$username:secret_users" "$home"

    # 7 — владелец: чтение, запись и выполнение
    # 5 — группа: чтение и выполнение
    # 0 — остальные пользователи: нет доступа
    chmod 750 "$home"

    log "Настроены права доступа: $home"
done

# 5. Настраиваем права на /var
# Права 755 разрешают всем чтение и проход по каталогу,
# но запрещают обычным пользователям запись в него
# В отличие от 777, эта настройка не открывает каталог
# для записи всем локальным пользователям
chmod 755 /var

log "Настроены права доступа для /var: 755"

# 6. Настраиваем беспарольный sudo для группы default_users
# ВНИМАНИЕ: это предоставляет участникам группы полный доступ root
# В реальной инфраструктуре следует выдавать только необходимые права

sudoers_file="/etc/sudoers.d/default_users"
tmp_file="$(mktemp /etc/sudoers.d/default_users.XXXXXX)"

# Удаляем временный файл при завершении скрипта
cleanup() {
    rm -f "$tmp_file"
}
trap cleanup EXIT

# Создаём правило sudoers во временном файле
printf '%%default_users ALL=(ALL:ALL) NOPASSWD: ALL\n' \
    > "$tmp_file"

# Назначаем владельца root и безопасные права файла
chown root:root "$tmp_file"
chmod 0440 "$tmp_file"

# Проверяем синтаксис до установки конфигурации
if visudo -cf "$tmp_file"; then
    install -o root -g root -m 0440 \
        "$tmp_file" "$sudoers_file"

    log "Настроен sudo для группы default_users"
else
    die "Ошибка в конфигурации sudoers"
fi

# 7. Обновляем список пакетов и устанавливаем Apache2
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y apache2

# Включаем автозапуск Apache и запускаем службу
systemctl enable --now apache2

# 8. Проверяем, что служба Apache действительно запущена
if systemctl is-active --quiet apache2; then
    log "Служба Apache работает"
else
    # Выводим диагностическую информацию при ошибке
    systemctl status apache2 --no-pager || true
    die "Не удалось запустить Apache"
fi

# 9. Проверяем синтаксис конфигурации sudoers
visudo -c

# Сообщаем об успешном завершении
log "Настройка системы завершена"
```
