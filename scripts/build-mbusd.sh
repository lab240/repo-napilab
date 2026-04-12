#!/bin/bash
set -e

REPO=/var/www/apt
WORKDIR=/root/napilab-build/mbusd

mkdir -p $WORKDIR
cd $WORKDIR

[ -d .git ] && git pull || git clone https://github.com/3cky/mbusd.git .

# Тулчейн для arm64
cat > cmake/arm_linux_aarch64.cmake << 'TOOLCHAIN'
SET(CMAKE_SYSTEM_NAME Linux)
SET(CMAKE_SYSTEM_PROCESSOR aarch64)
SET(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
SET(CMAKE_FIND_ROOT_PATH /usr/aarch64-linux-gnu)
SET(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
SET(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
SET(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
SET(CPACK_DEBIAN_PACKAGE_ARCHITECTURE arm64)
TOOLCHAIN

VER=$(grep -oP 'project\(mbusd VERSION \K[\d.]+' CMakeLists.txt)~git.$(git rev-parse --short HEAD)

echo "Building mbusd $VER"

rm -rf build-amd64 build-arm64

cmake -DCMAKE_BUILD_TYPE=Release \
    -DSYSTEMD_SERVICES_INSTALL_DIR=/lib/systemd/system \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -B build-amd64 -S . > /dev/null 2>&1
make -C build-amd64 -j$(nproc)

cmake -DCMAKE_BUILD_TYPE=Release \
    -DSYSTEMD_SERVICES_INSTALL_DIR=/lib/systemd/system \
    -DCMAKE_TOOLCHAIN_FILE=cmake/arm_linux_aarch64.cmake \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -B build-arm64 -S . > /dev/null 2>&1
make -C build-arm64 -j$(nproc)

for ARCH in amd64 arm64; do
    rm -rf deb-${ARCH}
    mkdir -p deb-${ARCH}/DEBIAN deb-${ARCH}/usr/bin deb-${ARCH}/lib/systemd/system
    cat > deb-${ARCH}/DEBIAN/control << CTRL
Package: mbusd
Version: ${VER}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: NapiLab <info@napilab.ru>
Description: Modbus TCP to Modbus RTU gateway
 Open-source Modbus TCP to Modbus RTU (RS-232/485) gateway.
CTRL
done

cp build-amd64/mbusd deb-amd64/usr/bin/mbusd
cp build-arm64/mbusd deb-arm64/usr/bin/mbusd
cp build-amd64/mbusd@.service deb-amd64/lib/systemd/system/
cp build-arm64/mbusd@.service deb-arm64/lib/systemd/system/

dpkg-deb --build deb-amd64 mbusd_${VER}_amd64.deb
dpkg-deb --build deb-arm64 mbusd_${VER}_arm64.deb

reprepro -b $REPO remove stable mbusd || true
reprepro -b $REPO includedeb stable mbusd_${VER}_amd64.deb
reprepro -b $REPO includedeb stable mbusd_${VER}_arm64.deb

echo "mbusd $VER done"
