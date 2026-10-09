#!/bin/bash
set -e

REPO=/var/www/apt
WORKDIR=/root/napilab-build/napi-mac
# Override for testing an unpublished branch: NAPI_MAC_GIT=/path/to/repo.git
GIT_URL=${NAPI_MAC_GIT:-https://github.com/lab240/napi-macs-from-eeprom.git}
BRANCH=${NAPI_MAC_BRANCH:-c-port}

mkdir -p $WORKDIR
cd $WORKDIR

if [ -d .git ]; then
    git remote set-url origin "$GIT_URL"
    git fetch origin
    git checkout -q $BRANCH
    git reset -q --hard origin/$BRANCH
else
    git clone -b $BRANCH "$GIT_URL" .
fi

VER=$(grep -E '^VERSION' Makefile | head -1 | grep -oP '[\d.]+')~git.$(git rev-parse --short HEAD)
echo "Building napi-mac $VER"

# Unit tests on the build host before packaging
make clean
make test

# Board-specific (NAPI RK3308): arm64 only
make deb CC=aarch64-linux-gnu-gcc STRIP=aarch64-linux-gnu-strip DEB_ARCH=arm64 DEB_VERSION=${VER}

reprepro -b $REPO remove stable napi-mac || true
reprepro -b $REPO includedeb stable build/napi-mac_${VER}_arm64.deb

echo "napi-mac $VER done"
