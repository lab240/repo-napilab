#!/bin/bash
set -e

REPO=/var/www/apt
WORKDIR=/root/napilab-build/mbus-gw-t2r

mkdir -p $WORKDIR
cd $WORKDIR

if [ -d .git ]; then
    git pull
    git submodule update --init
else
    git clone git@github.com:napilab/mbus-gw-t2r.git .
    git submodule update --init
fi

VER=1.0.0~git.$(git rev-parse --short HEAD)
echo "Building mbus-gw-t2r $VER"

cat > arm_linux_aarch64.cmake << 'TOOLCHAIN'
SET(CMAKE_SYSTEM_NAME Linux)
SET(CMAKE_SYSTEM_PROCESSOR aarch64)
SET(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
SET(CMAKE_FIND_ROOT_PATH /usr/aarch64-linux-gnu)
SET(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
SET(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
SET(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
TOOLCHAIN

rm -rf build-amd64 build-arm64

cmake -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -B build-amd64 -S . > /dev/null 2>&1
make -C build-amd64 -j$(nproc)

cmake -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE=$WORKDIR/arm_linux_aarch64.cmake \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -B build-arm64 -S . > /dev/null 2>&1
make -C build-arm64 -j$(nproc)

for ARCH in amd64 arm64; do
    rm -rf deb-${ARCH}
    mkdir -p deb-${ARCH}/DEBIAN \
             deb-${ARCH}/usr/bin \
             deb-${ARCH}/etc/mbus-gw-t2r
    cat > deb-${ARCH}/DEBIAN/control << CTRL
Package: mbus-gw-t2r
Version: ${VER}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: NapiLab <info@napilab.ru>
Description: Modbus TCP to RTU gateway
 Multithreaded gateway for MODBUS TCP to RTU protocol.
CTRL
    cp modbus-t2r_settings.conf deb-${ARCH}/etc/mbus-gw-t2r/
done

cp build-amd64/mbusgw-t2r deb-amd64/usr/bin/mbus-gw-t2r
cp build-arm64/mbusgw-t2r deb-arm64/usr/bin/mbus-gw-t2r

dpkg-deb --build deb-amd64 mbus-gw-t2r_${VER}_amd64.deb
dpkg-deb --build deb-arm64 mbus-gw-t2r_${VER}_arm64.deb

reprepro -b $REPO remove stable mbus-gw-t2r || true
reprepro -b $REPO includedeb stable mbus-gw-t2r_${VER}_amd64.deb
reprepro -b $REPO includedeb stable mbus-gw-t2r_${VER}_arm64.deb

echo "mbus-gw-t2r $VER done"
