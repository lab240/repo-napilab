#!/bin/bash
set -e

REPO=/var/www/apt
WORKDIR=/root/napilab-build/napi-switch
OUT=$WORKDIR/deb
# Override for testing an unpublished branch: NAPI_SWITCH_GIT=/path/to/repo.git
GIT_URL=${NAPI_SWITCH_GIT:-https://github.com/lab240/napiswitch.git}
BRANCH=${NAPI_SWITCH_BRANCH:-main}

mkdir -p $WORKDIR
cd $WORKDIR

if [ -d src/.git ]; then
    git -C src remote set-url origin "$GIT_URL"
    git -C src fetch origin
    git -C src checkout -q $BRANCH
    git -C src reset -q --hard origin/$BRANCH
else
    git clone -b $BRANCH "$GIT_URL" src
fi
echo "Building napi-switchd + napi-mrp from $(git -C src log --oneline -1)"

# napi-switchd (arm64) + napi-mrp (arm64, amd64 for MRP test PCs).
# go fetches the toolchain from go.mod; mrp_server links against pinned
# Debian trixie libraries unpacked into a sysroot by build-deb.sh.
rm -rf $OUT
src/backend/deploy/build-deb.sh $OUT

for PKG in napi-switchd napi-mrp; do
    reprepro -b $REPO remove stable $PKG || true
    for DEB in $OUT/${PKG}_*.deb; do
        reprepro -b $REPO includedeb stable $DEB
    done
done

echo "napi-switchd + napi-mrp done"
