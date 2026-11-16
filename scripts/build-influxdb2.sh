#!/bin/bash
set -e

# InfluxDB 2 (MIT) is not in Ubuntu/Debian/Armbian: the official packages of InfluxData are put
# into the repo as they are (arm64, amd64), after the check of their signature. The history of
# donoff-server needs it; the CLI (influx) is the separate influxdb2-cli package.
REPO=/var/www/apt
WORKDIR=/root/napilab-build/influxdb2
INFLUXDB_VER=${INFLUXDB_VER:-2.9.1}
CLI_VER=${INFLUXDB_CLI_VER:-2.7.5}
URL=https://dl.influxdata.com/influxdb/releases
# InfluxData Package Signing Key <support@influxdata.com>
KEY_FPR=24C975CBA61A024EE1B631787C3D57159FC2F927

mkdir -p $WORKDIR
cd $WORKDIR

# a keyring of its own: the default one signs the repo (reprepro)
KEYS=$WORKDIR/gnupg
mkdir -p -m 700 $KEYS
G="gpg --batch --homedir $KEYS"
if ! $G --list-keys $KEY_FPR >/dev/null 2>&1; then
    curl -fsSL https://repos.influxdata.com/influxdata-archive.key -o key.asc
    $G --import key.asc
    $G --list-keys $KEY_FPR >/dev/null
fi

DEBS=()
for ARCH in arm64 amd64; do
    DEBS+=(influxdb2_${INFLUXDB_VER}-1_${ARCH}.deb influxdb2-client-${CLI_VER}-${ARCH}.deb)
done
for DEB in "${DEBS[@]}"; do
    [ -f $DEB ] || curl -fsSLO $URL/$DEB
    curl -fsSLO $URL/$DEB.asc
    $G --status-fd 1 --verify $DEB.asc $DEB 2>/dev/null | grep -q "VALIDSIG.* $KEY_FPR\$" || {
        echo "ERROR: $DEB: no valid signature of $KEY_FPR"; exit 1; }
    echo "$DEB: signature OK"
done

reprepro -b $REPO remove stable influxdb2 influxdb2-cli || true
for DEB in "${DEBS[@]}"; do
    reprepro -b $REPO includedeb stable $DEB
done

echo "influxdb2 $INFLUXDB_VER, influxdb2-cli $CLI_VER done"
