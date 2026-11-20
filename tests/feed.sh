#!/bin/sh
set -eu

feed=$1
version=$2

for arch in $ARCHES; do
    image_arch=$arch
    if [ "$arch" = aarch64_cortex-a53 ]; then
        image_arch=aarch64_generic
    fi

    docker run --rm -i -e OPENWRT -e FILOGIC_KERNEL_ABI \
        -v "$PWD/dist:/dist:ro" "openwrt/rootfs:$image_arch-v$OPENWRT" \
        sh -s -- "$arch" "$feed" "$version" <<'CONTAINER'
set -eu
arch=$1
feed=$2
version=$3
repo=/etc/apk/repositories.d/customfeeds.list
key=/etc/apk/keys/zapret2.pem
mkdir -p /var/lock

if [ "$arch" = aarch64_cortex-a53 ]; then
    # Use the generic ARM64 userspace with Banana's real package architecture and kernel ABI.
    printf '%s\n' "$arch" > /etc/apk/arch
    releases="https://downloads.openwrt.org/releases/$OPENWRT"
    target="$releases/targets/mediatek/filogic"
    printf '%s\n' "$target/packages/packages.adb" \
        "$target/kmods/$FILOGIC_KERNEL_ABI/packages.adb" \
        "$releases/packages/$arch/base/packages.adb" > /etc/apk/repositories.d/distfeeds.list
fi

if [ "$feed" = local ]; then
    cp /dist/zapret2.pem "$key"
    printf '%s\n' "/dist/fixture/old-$arch.adb" > "$repo"
    apk update
    apk add zapret2
    ls /etc/rc.d/S*zapret2
    /etc/init.d/zapret2 disable
    printf '\n# Upgrade test marker\n' >> /etc/zapret2/config
    cp /etc/zapret2/config /tmp/zapret2-config.expected
    printf '%s\n' '# Local hook' > /etc/zapret2/custom.d/test-hook

    printf '%s\n' "/dist/test-$arch.adb" > "$repo"
    apk update
    apk upgrade zapret2
    apk info -e "zapret2=$version"
    cmp /tmp/zapret2-config.expected /etc/zapret2/config
    grep -qx '# Local hook' /etc/zapret2/custom.d/test-hook
    if /etc/init.d/zapret2 enabled; then
        echo "Upgrade unexpectedly enabled zapret2" >&2
        exit 1
    fi
else
    wget -O "$key" "$feed/zapret2.pem"
    cmp /dist/zapret2.pem "$key"
    printf '%s\n' "$feed/packages-$arch.adb" > "$repo"
    apk update
    apk add "zapret2=$version"
    ls /etc/rc.d/S*zapret2
fi

apk info -e kmod-nft-queue
/opt/zapret2/nfq2/nfqws2 --version
grep -q 'procd_set_param respawn' /etc/init.d/zapret2
/etc/init.d/zapret2 enable
apk del zapret2
test ! -e /etc/init.d/zapret2
test ! -e /opt/zapret2/nfq2/nfqws2
for link in /etc/rc.d/*zapret2; do
    test ! -L "$link"
done
CONTAINER
done
