#!/bin/bash
set -e

# donoff-server: the local server of the donoff sockets (mosquitto + influxdb2 + donoff-panel),
# arm64 and amd64. The package files are in donoff-plate packaging/donoff-server.
REPO=/var/www/apt
WORKDIR=/root/napilab-build/donoff-server
# Override for testing an unpublished branch: DONOFF_PLATE_GIT=/path/to/repo.git
GIT_URL=${DONOFF_PLATE_GIT:-https://github.com/dmnovikov/donoff-plate.git}
BRANCH=${DONOFF_PLATE_BRANCH:-main}

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

VER=$(cat packaging/donoff-server/VERSION)~git.$(git rev-parse --short HEAD)
echo "Building donoff-server $VER"

# go fetches the toolchain of go.mod
go test ./...
rm -rf build
VERSION=$VER packaging/donoff-server/build-deb.sh build arm64 amd64

reprepro -b $REPO remove stable donoff-server || true
for DEB in build/donoff-server_${VER}_*.deb; do
    reprepro -b $REPO includedeb stable $DEB
done

echo "donoff-server $VER done"
