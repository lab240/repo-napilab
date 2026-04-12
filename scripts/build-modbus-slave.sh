#!/bin/bash
set -e

REPO=/var/www/apt
WORKDIR=/root/napilab-build/modbus-slave

mkdir -p $WORKDIR
cd $WORKDIR

[ -d .git ] && git pull || git clone https://github.com/lab240/modbus-slave.git .

VER=1.0.0~git.$(git rev-parse --short HEAD)
echo "Building modbus-slave $VER"

gcc -O2 -Wall -static -o bin-amd64 src/modbus_slave.c
aarch64-linux-gnu-gcc -O2 -Wall -static -o bin-arm64 src/modbus_slave.c

for ARCH in amd64 arm64; do
    rm -rf deb-${ARCH}
    mkdir -p deb-${ARCH}/DEBIAN deb-${ARCH}/usr/bin \
             deb-${ARCH}/lib/systemd/system \
             deb-${ARCH}/usr/share/modbus-slave/scripts
    cat > deb-${ARCH}/DEBIAN/control << CTRL
Package: modbus-slave
Version: ${VER}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: NapiLab <info@napilab.ru>
Description: Modbus RTU slave emulator
 Emulates up to 30 Modbus RTU slave devices. Zero dependencies.
CTRL
    cp service/modbus_slave.service deb-${ARCH}/lib/systemd/system/
    cp scripts/*.sh deb-${ARCH}/usr/share/modbus-slave/scripts/
done

cp bin-amd64 deb-amd64/usr/bin/modbus-slave
cp bin-arm64 deb-arm64/usr/bin/modbus-slave

dpkg-deb --build deb-amd64 modbus-slave_${VER}_amd64.deb
dpkg-deb --build deb-arm64 modbus-slave_${VER}_arm64.deb

reprepro -b $REPO remove stable modbus-slave || true
reprepro -b $REPO includedeb stable modbus-slave_${VER}_amd64.deb
reprepro -b $REPO includedeb stable modbus-slave_${VER}_arm64.deb

echo "modbus-slave $VER done"
