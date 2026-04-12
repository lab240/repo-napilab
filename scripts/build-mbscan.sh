#!/bin/bash
set -e

REPO=/var/www/apt
WORKDIR=/root/napilab-build/mbscan

mkdir -p $WORKDIR
cd $WORKDIR

[ -d .git ] && git pull || git clone https://github.com/lab240/mbscan.git .

VER=$(grep "PKG_VERSION" Makefile | head -1 | grep -oP '[\d.]+')~git.$(git rev-parse --short HEAD)
echo "Building mbscan $VER"

gcc -O2 -Wall -static -o bin-amd64 src/mbscan.c
aarch64-linux-gnu-gcc -O2 -Wall -static -o bin-arm64 src/mbscan.c

for ARCH in amd64 arm64; do
    rm -rf deb-${ARCH}
    mkdir -p deb-${ARCH}/DEBIAN deb-${ARCH}/usr/bin
    cat > deb-${ARCH}/DEBIAN/control << CTRL
Package: mbscan
Version: ${VER}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: NapiLab <info@napilab.ru>
Description: Fast Modbus RTU bus scanner
 Pure C, zero dependencies.
CTRL
done

cp bin-amd64 deb-amd64/usr/bin/mbscan
cp bin-arm64 deb-arm64/usr/bin/mbscan

dpkg-deb --build deb-amd64 mbscan_${VER}_amd64.deb
dpkg-deb --build deb-arm64 mbscan_${VER}_arm64.deb

reprepro -b $REPO remove stable mbscan || true
reprepro -b $REPO includedeb stable mbscan_${VER}_amd64.deb
reprepro -b $REPO includedeb stable mbscan_${VER}_arm64.deb

echo "mbscan $VER done"
