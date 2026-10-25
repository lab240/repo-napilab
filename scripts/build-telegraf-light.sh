#!/bin/bash
set -e

REPO=/var/www/apt
WORKDIR=/root/napilab-build/telegraf-light
OUT=$WORKDIR/deb
# Override for testing an unpublished branch: TELEGRAF_LIGHT_GIT=/path/to/repo.git
GIT_URL=${TELEGRAF_LIGHT_GIT:-https://github.com/lab240/telegraf-ligth.git}
BRANCH=${TELEGRAF_LIGHT_BRANCH:-main}

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
echo "Building telegraf-light from $(git -C src log --oneline -1)"

# Telegraf version and plugin list are pinned in telegraf-ligth
# (version.env, plugins.txt); go fetches the toolchain from Telegraf's go.mod.
# Upstream sources are cached in $WORKDIR/build/src.
rm -rf $OUT
OUT_DIR=$WORKDIR/build src/build-deb.sh $OUT arm64

reprepro -b $REPO remove stable telegraf-light || true
for DEB in $OUT/telegraf-light_*.deb; do
    reprepro -b $REPO includedeb stable $DEB
done

echo "telegraf-light done"
