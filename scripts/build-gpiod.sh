#!/bin/bash
set -e

REPO=/var/www/apt
WORKDIR=/root/napilab-build/gpiod

mkdir -p $WORKDIR
cd $WORKDIR

[ -d .git ] && git pull || git clone https://github.com/brgl/libgpiod.git .

# Use stable v2.2.x branch
git checkout v2.2.x
git pull

VER=$(grep -oP 'AC_INIT\(\[libgpiod\], \[\K[^\]]+' configure.ac)~git.$(git rev-parse --short HEAD)
echo "Building gpiod $VER"

# Prepare autotools
./autogen.sh
make distclean || true

##############################
# amd64 (native)
##############################
rm -rf build-amd64
mkdir build-amd64
cd build-amd64
../configure --prefix=/usr --enable-tools
make -j$(nproc)
make DESTDIR=$(pwd)/install install
cd ..

##############################
# arm64 (cross)
##############################
rm -rf build-arm64
mkdir build-arm64
cd build-arm64
../configure --prefix=/usr --enable-tools \
    --host=aarch64-linux-gnu \
    CC=aarch64-linux-gnu-gcc
make -j$(nproc)
make DESTDIR=$(pwd)/install install
cd ..

##############################
# Package
##############################
for ARCH in amd64 arm64; do
    INSTALL="build-${ARCH}/install"
    rm -rf deb-${ARCH}
    mkdir -p deb-${ARCH}/DEBIAN deb-${ARCH}/usr/bin deb-${ARCH}/usr/lib
    cat > deb-${ARCH}/DEBIAN/control << CTRL
Package: gpiod
Version: ${VER}
Section: utils
Priority: optional
Architecture: ${ARCH}
Depends: libc6
Maintainer: NapiLab <info@napilab.ru>
Description: Tools and library for Linux GPIO character device
 libgpiod v2 library and CLI tools: gpiodetect, gpioget, gpioinfo,
 gpiomon, gpionotify, gpioset. Replaces the legacy sysfs GPIO interface.
CTRL

    # ldconfig
    cat > deb-${ARCH}/DEBIAN/postinst << 'POST'
#!/bin/sh
set -e
ldconfig
POST
    chmod 755 deb-${ARCH}/DEBIAN/postinst

    cat > deb-${ARCH}/DEBIAN/postrm << 'POST'
#!/bin/sh
set -e
ldconfig
POST
    chmod 755 deb-${ARCH}/DEBIAN/postrm

    # Binaries
    cp $INSTALL/usr/bin/gpio* deb-${ARCH}/usr/bin/

    # Shared library
    cp -a $INSTALL/usr/lib/libgpiod.so* deb-${ARCH}/usr/lib/
done

dpkg-deb --build deb-amd64 gpiod_${VER}_amd64.deb
dpkg-deb --build deb-arm64 gpiod_${VER}_arm64.deb

reprepro -b $REPO remove stable gpiod || true
reprepro -b $REPO includedeb stable gpiod_${VER}_amd64.deb
reprepro -b $REPO includedeb stable gpiod_${VER}_arm64.deb

echo "gpiod $VER done"
