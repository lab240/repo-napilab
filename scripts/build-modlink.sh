#!/bin/bash
set -e

REPO=/var/www/apt
WORKDIR=/root/napilab-build/modlink
GITHUB_REPO=git@github.com:napilab/modlink.git

mkdir -p $WORKDIR
cd $WORKDIR

[ -d .git ] && git pull || git clone $GITHUB_REPO .

VER=$(git describe --tags --always 2>/dev/null | sed 's/^v//' || echo "0.0.0")~git.$(git rev-parse --short HEAD)
COMMIT=$(git rev-parse --short HEAD)
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
MODULE=gitlab.nnz-ipc.net/pub/modlink

LDFLAGS="-X '${MODULE}/version.version=${VER}' \
         -X '${MODULE}/version.commit=${COMMIT}' \
         -X '${MODULE}/version.date=${DATE}'"

echo "Building modlink $VER"

GOOS=linux GOARCH=amd64 go build -ldflags "$LDFLAGS" -o bin-amd64 .
GOOS=linux GOARCH=arm64 go build -ldflags "$LDFLAGS" -o bin-arm64 .

for ARCH in amd64 arm64; do
    rm -rf deb-${ARCH}
    mkdir -p deb-${ARCH}/DEBIAN \
             deb-${ARCH}/usr/bin \
             deb-${ARCH}/lib/systemd/system
    cat > deb-${ARCH}/DEBIAN/control << CTRL
Package: modlink
Version: ${VER}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: NapiLab <info@napilab.ru>
Description: RTU Modbus Bridge
 Polls Modbus TCP devices and serves data over serial RTU interface.
CTRL
    cp deploy/modlink.service deb-${ARCH}/lib/systemd/system/
done

cp bin-amd64 deb-amd64/usr/bin/modlink
cp bin-arm64 deb-arm64/usr/bin/modlink

dpkg-deb --build deb-amd64 modlink_${VER}_amd64.deb
dpkg-deb --build deb-arm64 modlink_${VER}_arm64.deb

reprepro -b $REPO remove stable modlink || true
reprepro -b $REPO includedeb stable modlink_${VER}_amd64.deb
reprepro -b $REPO includedeb stable modlink_${VER}_arm64.deb

echo "modlink $VER done"
