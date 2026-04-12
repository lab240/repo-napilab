# NapiLab APT Repository — Setup Guide

Инструкция по развёртыванию apt-репозитория с нуля на голом VPS (Ubuntu).

---

## Требования

- VPS с Ubuntu
- Домен направленный на IP VPS (в нашем случае `repo.napilab.ru`)
- Доступ по SSH с правами root

---

## 1. Установка пакетов

```bash
apt update && apt upgrade -y
apt install -y nginx certbot python3-certbot-nginx reprepro gnupg2 \
               build-essential cmake gcc-aarch64-linux-gnu git \
               autoconf automake libtool autoconf-archive
```

---

## 2. GPG ключ для подписи репозитория

```bash
gpg --full-generate-key
# RSA, 4096, без срока истечения
# Имя: NapiLab
# Email: info@napilab.ru
```

Убрать passphrase (для автоматической подписи):

```bash
gpg --homedir /root/.gnupg --edit-key info@napilab.ru
# passwd → Enter → Enter → save
```

Проверяем ключ:

```bash
gpg --homedir /root/.gnupg --list-keys
```

Экспортируем публичный ключ:

```bash
mkdir -p /var/www/apt
gpg --armor --export info@napilab.ru > /var/www/apt/napilab.gpg
```

---

## 3. Настройка reprepro

```bash
mkdir -p /var/www/apt/conf
```

`/var/www/apt/conf/distributions`:

```
Origin: NapiLab
Label: NapiLab
Codename: stable
Architectures: amd64 arm64
Components: main
Description: NapiLab APT repository
SignWith: <fingerprint из gpg --list-keys>
```

`/var/www/apt/conf/options`:

```
verbose
basedir /var/www/apt
```

Инициализируем:

```bash
reprepro -b /var/www/apt export stable
```

---

## 4. Настройка nginx

```bash
tee /etc/nginx/sites-available/repo.napilab.ru << 'EOF'
server {
    listen 80;
    server_name repo.napilab.ru;
    root /var/www/apt;
    autoindex on;

    location ~ /(.*)/conf {
        deny all;
    }
    location ~ /(.*)/db {
        deny all;
    }
}
EOF

ln -s /etc/nginx/sites-available/repo.napilab.ru /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
```

---

## 5. SSL через Let's Encrypt

```bash
certbot --nginx -d repo.napilab.ru
```

Проверяем:

```bash
curl https://repo.napilab.ru/napilab.gpg
```

---

## 6. Скрипты сборки пакетов

Скрипты сборки размещены как отдельные файлы в `scripts/`.

Установка на VPS:

```bash
mkdir -p /usr/local/lib/napilab-repo
cp scripts/build-*.sh /usr/local/lib/napilab-repo/
chmod +x /usr/local/lib/napilab-repo/build-*.sh

cp scripts/build-napilab-repo.sh /usr/local/bin/build-napilab-repo.sh
chmod +x /usr/local/bin/build-napilab-repo.sh
```

### Пакеты

| Пакет | Описание | Upstream | Сборка |
|-------|----------|----------|--------|
| `mbusd` | Modbus TCP → RTU gateway | [3cky/mbusd](https://github.com/3cky/mbusd) | CMake + cross-toolchain |
| `mbscan` | Modbus RTU bus scanner | [lab240/mbscan](https://github.com/lab240/mbscan) | gcc, static |
| `modbus-slave` | Modbus RTU slave emulator | [lab240/modbus-slave](https://github.com/lab240/modbus-slave) | gcc, static |
| `gpiod` | libgpiod v2 — утилиты и библиотека | [brgl/libgpiod](https://github.com/brgl/libgpiod) (ветка `v2.2.x`) | autotools + cross-compile |

---

## 7. Использование

### Пересобрать все пакеты

```bash
sudo build-napilab-repo.sh
```

### Пересобрать один пакет

```bash
sudo build-napilab-repo.sh mbusd
sudo build-napilab-repo.sh mbscan
sudo build-napilab-repo.sh modbus-slave
sudo build-napilab-repo.sh gpiod
```

### Добавить новый пакет

1. Создать скрипт `scripts/build-<name>.sh`
2. Скопировать в `/usr/local/lib/napilab-repo/` на VPS
3. Добавить `<name>` в массив `PACKAGES` в `build-napilab-repo.sh`

---

## 8. Подключение репозитория на клиенте

### x86_64

```bash
curl -fsSL https://repo.napilab.ru/napilab.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/napilab.gpg > /dev/null
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/napilab.gpg] https://repo.napilab.ru stable main" | sudo tee /etc/apt/sources.list.d/napilab.list
sudo apt update
```

### ARM64 (Armbian)

```bash
curl -fsSL https://repo.napilab.ru/napilab.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/napilab.gpg > /dev/null
echo "deb [arch=arm64 signed-by=/usr/share/keyrings/napilab.gpg] https://repo.napilab.ru stable main" | sudo tee /etc/apt/sources.list.d/napilab.list
sudo apt update
```

### Установка пакетов

```bash
sudo apt install mbusd mbscan modbus-slave gpiod
```

### Удаление репозитория

```bash
sudo rm /etc/apt/sources.list.d/napilab.list /usr/share/keyrings/napilab.gpg
sudo apt update
```

---

## 9. Проверка репозитория

```bash
# Содержимое репо
reprepro -b /var/www/apt list stable

# Доступность через HTTPS
curl https://repo.napilab.ru/dists/stable/Release | head -5
```

---

## Структура файлов

### Репозиторий (этот проект)

```
scripts/
    build-mbusd.sh
    build-mbscan.sh
    build-modbus-slave.sh
    build-gpiod.sh
    build-napilab-repo.sh            # главный скрипт-оркестратор
```

### VPS

```
/var/www/apt/                        # корень apt-репозитория (nginx)
    napilab.gpg                      # публичный GPG ключ
    conf/
        distributions
        options
    dists/                           # индексы (генерирует reprepro)
    pool/                            # .deb файлы

/usr/local/bin/
    build-napilab-repo.sh            # главный скрипт

/usr/local/lib/napilab-repo/
    build-mbusd.sh
    build-mbscan.sh
    build-modbus-slave.sh
    build-gpiod.sh

/root/napilab-build/                 # рабочая директория сборки
    mbusd/
    mbscan/
    modbus-slave/
    gpiod/
```