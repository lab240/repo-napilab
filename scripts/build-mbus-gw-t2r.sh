#!/bin/bash
set -e

REPO=/var/www/apt
WORKDIR=/root/napilab-build/mbus-gw-t2r
STARLET_DIR=/root/napilab-build/utility_routines
# DRY_RUN=1: build the .deb files, do not touch the repository.
DRY_RUN=${DRY_RUN:-0}

mkdir -p $WORKDIR
cd $WORKDIR

# The checkout is detached at a release tag: fetch, do not pull.
[ -d .git ] || git clone git@github.com:napilab/mbus-gw-t2r.git .

# Built from the latest release tag (v0.13.5 -> 0.13.5). Epoch 1: the old
# packages were 1.0.0~git.<hash>. PKG_REV: packaging changes of one release.
git fetch -q --tags origin
TAG=$(git describe --tags --abbrev=0 --match 'v[0-9]*' origin/HEAD)
git checkout -q "$TAG"
PKG_REV=1
VER=1:${TAG#v}-${PKG_REV}
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

# StarLet (UTILITY$ROUTINES) is a CMake package the gateway links statically:
# built per architecture into $WORKDIR/starlet-<arch>, nothing in /usr/local.
if [ -d $STARLET_DIR/.git ]; then
    git -C $STARLET_DIR pull
else
    git clone https://gitlab.com/SysMan-One/utility_routines $STARLET_DIR
fi
echo "StarLet $(git -C $STARLET_DIR rev-parse --short HEAD)"

rm -rf build-amd64 build-arm64 starlet-build-* starlet-amd64 starlet-arm64

cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$WORKDIR/starlet-amd64 \
    -B starlet-build-amd64 -S $STARLET_DIR > /dev/null
make -s -C starlet-build-amd64 -j$(nproc) starlet
cmake --install starlet-build-amd64 > /dev/null

cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$WORKDIR/starlet-arm64 \
    -DCMAKE_TOOLCHAIN_FILE=$WORKDIR/arm_linux_aarch64.cmake \
    -B starlet-build-arm64 -S $STARLET_DIR > /dev/null
make -s -C starlet-build-arm64 -j$(nproc) starlet
cmake --install starlet-build-arm64 > /dev/null

cmake -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH=$WORKDIR/starlet-amd64 \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -B build-amd64 -S . > /dev/null
make -C build-amd64 -j$(nproc)

# The toolchain searches only the sysroot; the StarLet prefix is added to it.
# arm64 pkg-config data, or the host library dir ends up in RUNPATH.
PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig cmake -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE=$WORKDIR/arm_linux_aarch64.cmake \
    -DCMAKE_FIND_ROOT_PATH="/usr/aarch64-linux-gnu;$WORKDIR/starlet-arm64" \
    -DCMAKE_PREFIX_PATH=$WORKDIR/starlet-arm64 \
    -DLIBCONFIG_STATIC_LIB=/usr/lib/aarch64-linux-gnu/libconfig.a \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -B build-arm64 -S . > /dev/null
make -C build-arm64 -j$(nproc)

for ARCH in amd64 arm64; do
    rm -rf deb-${ARCH}
    mkdir -p deb-${ARCH}/DEBIAN \
             deb-${ARCH}/usr/bin \
             deb-${ARCH}/etc/mbus-gw-t2r \
             deb-${ARCH}/lib/systemd/system
    # libconfig is static (T2R_STATIC_LIBCONFIG): only glibc is needed.
    GLIBC=$(strings build-${ARCH}/mbusgw-t2r | grep -oE 'GLIBC_[0-9.]+' | sort -Vu | tail -1)
    cat > deb-${ARCH}/DEBIAN/control << CTRL
Package: mbus-gw-t2r
Version: ${VER}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: NapiLab <info@napilab.ru>
Depends: libc6 (>= ${GLIBC#GLIBC_})
Description: Modbus TCP to RTU gateway
 Multithreaded gateway for MODBUS TCP to RTU protocol.
 Service mbus-gw-t2r.service is installed disabled: configure
 /etc/mbus-gw-t2r/modbus-t2r_settings.conf (or the napiconfig web UI),
 then systemctl enable --now mbus-gw-t2r.
CTRL
    cp modbus-t2r_settings.conf deb-${ARCH}/etc/mbus-gw-t2r/
    # Settings are edited by hand or by napiconfig: keep them on upgrade.
    echo /etc/mbus-gw-t2r/modbus-t2r_settings.conf > deb-${ARCH}/DEBIAN/conffiles

    # Options (T2R_OPTS, e.g. /trace) come from /etc/default/mbus-gw-t2r.
    cat > deb-${ARCH}/lib/systemd/system/mbus-gw-t2r.service << 'UNIT'
[Unit]
Description=MODBUS TCP to RTU gateway (mbus-gw-t2r)
Documentation=https://github.com/napilab/mbus-gw-t2r
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=-/etc/default/mbus-gw-t2r
ExecStart=/usr/bin/mbus-gw-t2r /settings=/etc/mbus-gw-t2r/modbus-t2r_settings.conf $T2R_OPTS
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

    cat > deb-${ARCH}/DEBIAN/postinst << 'SCRIPT'
#!/bin/sh
set -e
# Installed disabled; a running gateway is restarted on upgrade.
if [ "$1" = configure ] && [ -d /run/systemd/system ]; then
    systemctl daemon-reload || true
    systemctl try-restart mbus-gw-t2r.service || true
fi
exit 0
SCRIPT
    cat > deb-${ARCH}/DEBIAN/prerm << 'SCRIPT'
#!/bin/sh
set -e
if [ "$1" = remove ] && [ -d /run/systemd/system ]; then
    systemctl stop mbus-gw-t2r.service || true
fi
exit 0
SCRIPT
    cat > deb-${ARCH}/DEBIAN/postrm << 'SCRIPT'
#!/bin/sh
set -e
if [ "$1" = remove ] || [ "$1" = purge ]; then
    systemctl disable mbus-gw-t2r.service >/dev/null 2>&1 || true
    [ -d /run/systemd/system ] && systemctl daemon-reload || true
fi
if [ "$1" = purge ]; then
    rm -f /etc/default/mbus-gw-t2r
fi
exit 0
SCRIPT
    chmod 755 deb-${ARCH}/DEBIAN/postinst deb-${ARCH}/DEBIAN/prerm deb-${ARCH}/DEBIAN/postrm
done

cp build-amd64/mbusgw-t2r deb-amd64/usr/bin/mbus-gw-t2r
cp build-arm64/mbusgw-t2r deb-arm64/usr/bin/mbus-gw-t2r

FVER=${VER#*:}
dpkg-deb --root-owner-group --build deb-amd64 mbus-gw-t2r_${FVER}_amd64.deb
dpkg-deb --root-owner-group --build deb-arm64 mbus-gw-t2r_${FVER}_arm64.deb

if [ "$DRY_RUN" = 1 ]; then
    ls -l mbus-gw-t2r_${FVER}_*.deb
    echo "mbus-gw-t2r $VER built (DRY_RUN, repository not changed)"
    exit 0
fi

reprepro -b $REPO remove stable mbus-gw-t2r || true
reprepro -b $REPO includedeb stable mbus-gw-t2r_${FVER}_amd64.deb
reprepro -b $REPO includedeb stable mbus-gw-t2r_${FVER}_arm64.deb

echo "mbus-gw-t2r $VER done"
