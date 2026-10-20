#!/bin/bash
set -e

SCRIPTS_DIR=/usr/local/lib/napilab-repo

PACKAGES=(mbusd mbscan modbus-slave modlink mbus-gw-t2r gpiod i2cscan napi-mac napi-switch)

if [ -n "$1" ]; then
    PACKAGES=($1)
fi

for PKG in "${PACKAGES[@]}"; do
    SCRIPT=$SCRIPTS_DIR/build-${PKG}.sh
    if [ ! -f "$SCRIPT" ]; then
        echo "ERROR: $SCRIPT not found"
        exit 1
    fi
    echo "=============================="
    echo "Building $PKG"
    echo "=============================="
    bash $SCRIPT
done

echo ""
echo "=== Repo contents ==="
reprepro -b /var/www/apt list stable
