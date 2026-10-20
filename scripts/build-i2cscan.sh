#!/bin/bash
set -e

REPO=/var/www/apt
WORKDIR=/root/napilab-build/i2cscan

mkdir -p $WORKDIR
cd $WORKDIR

[ -d .git ] && git pull || git clone https://github.com/lab240/i2cscan.git .

VER=1.0.0~git.$(git rev-parse --short HEAD)
echo "Building i2cscan $VER"

gcc -O2 -Wall -static -o bin-amd64 src/i2cscan.c
aarch64-linux-gnu-gcc -O2 -Wall -static -o bin-arm64 src/i2cscan.c

for ARCH in amd64 arm64; do
    rm -rf deb-${ARCH}
    mkdir -p deb-${ARCH}/DEBIAN deb-${ARCH}/usr/bin
    cat > deb-${ARCH}/DEBIAN/control << CTRL
Package: i2cscan
Version: ${VER}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: NapiLab <info@napilab.ru>
Description: Lightweight I2C bus scanner for embedded Linux
 Scans I2C buses and identifies known chips by reading ID registers.
 Single static binary, no dependencies on i2c-tools.
CTRL
done

cp bin-amd64 deb-amd64/usr/bin/i2cscan
cp bin-arm64 deb-arm64/usr/bin/i2cscan

dpkg-deb --build deb-amd64 i2cscan_${VER}_amd64.deb
dpkg-deb --build deb-arm64 i2cscan_${VER}_arm64.deb

reprepro -b $REPO remove stable i2cscan || true
reprepro -b $REPO includedeb stable i2cscan_${VER}_amd64.deb
reprepro -b $REPO includedeb stable i2cscan_${VER}_arm64.deb

echo "i2cscan $VER done"
