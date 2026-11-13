#!/bin/bash
set -e

REPO=/var/www/apt
WORKDIR=/root/napilab-build/napi-avahi
# Override for testing an unpublished branch: NAPI_AVAHI_GIT=/path/to/repo.git
GIT_URL=${NAPI_AVAHI_GIT:-https://github.com/lab240/napi-avahi.git}
BRANCH=${NAPI_AVAHI_BRANCH:-main}

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

VER=$(grep -E '^VERSION' Makefile | head -1 | grep -oP '[\d.]+')~git.$(git rev-parse --short HEAD)
echo "Building napi-avahi $VER"

# Tests of the script on a fake board, then the package (shell only: Architecture all)
make clean
make test
make deb DEB_VERSION=${VER}

reprepro -b $REPO remove stable napi-avahi || true
reprepro -b $REPO includedeb stable build/napi-avahi_${VER}_all.deb

echo "napi-avahi $VER done"
