# NapiLab APT Repository — Setup Guide

Instructions for deploying an APT repository from scratch on a bare VPS (Ubuntu).

---

## Requirements

- VPS running Ubuntu
- Domain pointing to VPS IP (in our case `repo.napilab.ru`)
- SSH access with root privileges

---

## 1. Install packages

```bash
apt update && apt upgrade -y
apt install -y nginx certbot python3-certbot-nginx reprepro gnupg2 \
               build-essential cmake gcc-aarch64-linux-gnu git \
               autoconf automake libtool autoconf-archive
```

---

## 2. GPG key for repository signing

```bash
gpg --full-generate-key
# RSA, 4096, no expiration
# Name: NapiLab
# Email: info@napilab.ru
```

Remove passphrase (for unattended signing):

```bash
gpg --homedir /root/.gnupg --edit-key info@napilab.ru
# passwd → Enter → Enter → save
```

Verify the key:

```bash
gpg --homedir /root/.gnupg --list-keys
```

Export the public key:

```bash
mkdir -p /var/www/apt
gpg --armor --export info@napilab.ru > /var/www/apt/napilab.gpg
```

---

## 3. Configure reprepro

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
SignWith: <fingerprint from gpg --list-keys>
```

`/var/www/apt/conf/options`:

```
verbose
basedir /var/www/apt
```

Initialize:

```bash
reprepro -b /var/www/apt export stable
```

---

## 4. Configure nginx

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

## 5. SSL via Let's Encrypt

```bash
certbot --nginx -d repo.napilab.ru
```

Verify:

```bash
curl https://repo.napilab.ru/napilab.gpg
```

---

## 6. Build scripts

Build scripts are stored as separate files in `scripts/`.

Deploy to VPS:

```bash
mkdir -p /usr/local/lib/napilab-repo
cp scripts/build-*.sh /usr/local/lib/napilab-repo/
chmod +x /usr/local/lib/napilab-repo/build-*.sh

cp scripts/build-napilab-repo.sh /usr/local/bin/build-napilab-repo.sh
chmod +x /usr/local/bin/build-napilab-repo.sh
```

### Packages

| Package | Description | Upstream | Build |
|---------|-------------|----------|-------|
| `mbusd` | Modbus TCP → RTU gateway | [3cky/mbusd](https://github.com/3cky/mbusd) | CMake + cross-toolchain |
| `mbscan` | Modbus RTU bus scanner | [lab240/mbscan](https://github.com/lab240/mbscan) | gcc, static |
| `modbus-slave` | Modbus RTU slave emulator | [lab240/modbus-slave](https://github.com/lab240/modbus-slave) | gcc, static |
| `gpiod` | libgpiod v2 — tools and library | [brgl/libgpiod](https://github.com/brgl/libgpiod) (branch `v2.2.x`) | autotools + cross-compile |
| `napi-mac` | NAPI board MACs from EEPROM, `lanusb1..4` names | [lab240/napi-macs-from-eeprom](https://github.com/lab240/napi-macs-from-eeprom) (branch `c-port`) | `make test` + `make deb`, static, arm64 only |

---

## 7. Usage

### Rebuild all packages

```bash
sudo build-napilab-repo.sh
```

### Rebuild a single package

```bash
sudo build-napilab-repo.sh mbusd
sudo build-napilab-repo.sh mbscan
sudo build-napilab-repo.sh modbus-slave
sudo build-napilab-repo.sh gpiod
sudo build-napilab-repo.sh napi-mac
```

### Add a new package

1. Create `scripts/build-<name>.sh`
2. Copy to `/usr/local/lib/napilab-repo/` on VPS
3. Add `<name>` to the `PACKAGES` array in `build-napilab-repo.sh`

---

## 8. Connect the repository on a client

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

### Install packages

```bash
sudo apt install mbusd mbscan modbus-slave gpiod
sudo apt install napi-mac        # NAPI board only (arm64)
```

### Remove the repository

```bash
sudo rm /etc/apt/sources.list.d/napilab.list /usr/share/keyrings/napilab.gpg
sudo apt update
```

---

## 9. Verify the repository

```bash
# Repository contents
reprepro -b /var/www/apt list stable

# HTTPS availability
curl https://repo.napilab.ru/dists/stable/Release | head -5
```

---

## File structure

### This repository

```
scripts/
    build-mbusd.sh
    build-mbscan.sh
    build-modbus-slave.sh
    build-gpiod.sh
    build-napi-mac.sh
    build-napilab-repo.sh            # orchestrator script
```

### VPS

```
/var/www/apt/                        # APT repository root (nginx)
    napilab.gpg                      # public GPG key
    conf/
        distributions
        options
    dists/                           # indices (generated by reprepro)
    pool/                            # .deb files

/usr/local/bin/
    build-napilab-repo.sh            # orchestrator script

/usr/local/lib/napilab-repo/
    build-mbusd.sh
    build-mbscan.sh
    build-modbus-slave.sh
    build-gpiod.sh
    build-napi-mac.sh

/root/napilab-build/                 # build working directory
    mbusd/
    mbscan/
    modbus-slave/
    gpiod/
    napi-mac/
```