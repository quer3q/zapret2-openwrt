#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Packs upstream zapret2's (https://github.com/bol-van/zapret2) prebuilt static nfqws2,
# mdig and ip2net, the scripts its OpenWrt init and ipset lists need, and the fake-packet
# blobs into an OpenWrt apk. Nothing is compiled; blockcheck2 is left out (it needs curl etc.).
# Needs apk-tools 3 and root (file owners go into the package), e.g.:
#   docker run --rm -v "$PWD:/w" -w /w alpine:3.24 sh build.sh aarch64_generic dist
set -eu

PKG_VERSION=1.0.5.2
PKG_RELEASE=1
PKG_HASH=9a2b08ec8c4b40f908e55684ea29d40b2316a1f2eebb08ea6afcb1e5c9c0fc89

arch=$1
out=$2
# OpenWrt arch -> upstream binaries/<dir>.
# ponytail: only the arches CI builds; add a row and a matrix arch together.
case $arch in
	aarch64_*) bin=linux-arm64 ;;
	x86_64) bin=linux-x86_64 ;;
	*) echo "zapret2: no upstream binary dir for $arch" >&2; exit 1 ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
wget -qO "$work/src.tar.gz" \
	"https://github.com/bol-van/zapret2/releases/download/v$PKG_VERSION/zapret2-v$PKG_VERSION-openwrt-embedded.tar.gz"
echo "$PKG_HASH  $work/src.tar.gz" | sha256sum -c -
tar -xzf "$work/src.tar.gz" -C "$work"
# The embedded tarball has no license; MIT requires shipping the notice.
wget -qO "$work/LICENSE.txt" "https://raw.githubusercontent.com/bol-van/zapret2/v$PKG_VERSION/docs/LICENSE.txt"
grep -q 'Permission is hereby granted' "$work/LICENSE.txt"
s=$work/zapret2-v$PKG_VERSION
r=$work/root
o=$r/opt/zapret2

# The init script finds /opt/zapret2 by resolving the /etc/init.d/zapret2 symlink.
mkdir -p "$o/init.d/openwrt" "$o/nfq2" "$o/mdig" "$o/ip2net" "$o/files" "$r/etc/zapret2/custom.d" \
	"$r/etc/init.d" "$r/etc/hotplug.d/iface" "$r/lib/upgrade/keep.d" "$r/lib/apk/packages"
cp -R "$s/common" "$s/ipset" "$s/lua" "$s/config.default" "$work/LICENSE.txt" "$o/"
# Fake-packet blobs for --blob=...@/opt/zapret2/files/fake/*.bin strategies.
cp -R "$s/files/fake" "$o/files/"
for f in zapret2 90-zapret2 functions firewall.zapret2; do
	cp "$s/init.d/openwrt/$f" "$o/init.d/openwrt/"
done
cp "$s/binaries/$bin/nfqws2" "$o/nfq2/"
# ipset/def.sh runs these to resolve hostlists and collapse IP ranges.
cp "$s/binaries/$bin/mdig" "$o/mdig/"
cp "$s/binaries/$bin/ip2net" "$o/ip2net/"
chmod 755 "$o/nfq2/nfqws2" "$o/mdig/mdig" "$o/ip2net/ip2net" "$o/init.d/openwrt/zapret2" "$o/init.d/openwrt/90-zapret2"
ln -s /etc/zapret2/config "$o/config"
ln -s /etc/zapret2/custom.d "$o/init.d/openwrt/custom.d"
cp "$s/config.default" "$r/etc/zapret2/config"
ln -s /opt/zapret2/init.d/openwrt/zapret2 "$r/etc/init.d/zapret2"
ln -s /opt/zapret2/init.d/openwrt/90-zapret2 "$r/etc/hotplug.d/iface/90-zapret2"
echo /etc/zapret2/ > "$r/lib/upgrade/keep.d/zapret2"

# Upstream's run_daemon() starts nfqws2 without procd respawn: add it after the command.
init=$o/init.d/openwrt/zapret2
sed -i 's/^\([[:space:]]*\)procd_set_param command .*/&\n\1procd_set_param respawn/' "$init"
[ "$(grep -c 'procd_set_param respawn' "$init")" = 1 ] ||
	{ echo "zapret2: respawn patch did not apply once: upstream init.d/openwrt/zapret2 changed" >&2; exit 1; }

# OpenWrt package metadata, as the SDK's package-pack.mk writes it.
p=$r/lib/apk/packages
(cd "$r" && find . -type f -o -type l | sed 's/^\.//' | sort) > "$work/list"
mv "$work/list" "$p/zapret2.list"
echo /etc/zapret2/config > "$p/zapret2.conffiles"
echo "/etc/zapret2/config $(sha256sum < "$r/etc/zapret2/config" | cut -d' ' -f1)" > "$p/zapret2.conffiles_static"
chown -R 0:0 "$r"

# default_postinst enables and starts /etc/init.d entries of the .list; default_prerm stops them.
# On upgrade, start is a no-op for a running nfqws2, so restart it onto the new files.
body='[ -s "${IPKG_INSTROOT}/lib/functions.sh" ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
export root="${IPKG_INSTROOT}"
export pkgname="zapret2"'
printf '#!/bin/sh\n[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0\n%s\nadd_group_and_user\ndefault_postinst\n' "$body" > "$work/post-install"
{
	printf '#!/bin/sh\nexport PKG_UPGRADE=1\n'
	sed 1d "$work/post-install"
	echo 'if [ -z "$root" ] && /etc/init.d/zapret2 enabled; then /etc/init.d/zapret2 restart; fi'
} > "$work/post-upgrade"
printf '#!/bin/sh\n%s\ndefault_prerm\n' "$body" > "$work/pre-deinstall"

mkdir -p "$out"
apk mkpkg \
	--info name:zapret2 \
	--info "version:$PKG_VERSION-r$PKG_RELEASE" \
	--info "description:zapret2 DPI circumvention: upstream static nfqws2, mdig, ip2net, fake blobs and OpenWrt init scripts in /opt/zapret2, with procd respawn. Configure in /etc/zapret2/config and /etc/zapret2/custom.d." \
	--info "arch:$arch" \
	--info "license:MIT GPL-2.0-or-later" \
	--info origin:zapret2 \
	--info url:https://github.com/bol-van/zapret2 \
	--info maintainer:Quer3q \
	--info depends:kmod-nft-queue \
	--script "post-install:$work/post-install" \
	--script "post-upgrade:$work/post-upgrade" \
	--script "pre-deinstall:$work/pre-deinstall" \
	--files "$r" \
	--output "$out/zapret2-$PKG_VERSION-r$PKG_RELEASE-$arch.apk"
