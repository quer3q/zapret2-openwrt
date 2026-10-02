# zapret2-openwrt

Signed OpenWrt apk feed for [zapret2](https://github.com/bol-van/zapret2): `apk add zapret2`, then `apk upgrade` for new versions.

- **No compiling:** repacks upstream's prebuilt static `nfqws2`, `mdig` and `ip2net`, its OpenWrt init and ipset scripts, and the `files/fake` blobs. `blockcheck2` is left out (it needs extra packages).
- **Minimal deps:** only `kmod-nft-queue`.
- **procd respawn** instead of a watchdog; upgrades restart the service.
- **Auto-updated:** CI checks upstream daily and publishes a release when it changes.
- OpenWrt 25.12+ (apk), **aarch64_generic** and **x86_64**.

## Install

On the router:

```sh
mkdir -p /etc/apk/keys /etc/apk/repositories.d
wget -O /etc/apk/keys/zapret2.pem https://github.com/quer3q/zapret2-openwrt/releases/latest/download/zapret2.pem
sha256sum /etc/apk/keys/zapret2.pem
```

Compare the key's SHA-256 with the release notes before adding the feed:

```sh
echo "https://github.com/quer3q/zapret2-openwrt/releases/latest/download/packages-$(cat /etc/apk/arch).adb" >> /etc/apk/repositories.d/customfeeds.list
apk update && apk add zapret2
```

Edit `/etc/zapret2/config`; custom scripts go in `/etc/zapret2/custom.d/`. Both survive sysupgrade, and the config is preserved on package upgrades (a new default lands as `config.apk-new`). The service is enabled automatically; the default config has `NFQWS2_ENABLE=0`. Set it to `1`, configure your strategy using the [upstream documentation](https://github.com/bol-van/zapret2), then run `/etc/init.d/zapret2 restart`. Use `apk upgrade zapret2` for updates.

OpenWrt's firewall flow offloading makes traffic bypass nfqws2, and the package doesn't run upstream's installer, which normally deals with it. If it's on, turn it off (`uci set firewall.@defaults[0].flow_offloading=0; uci set firewall.@defaults[0].flow_offloading_hw=0; uci commit firewall; fw4 reload`). If you still want offloading, set `FLOWOFFLOAD=software` (or `hardware`) in `/etc/zapret2/config` so zapret2 runs a compatible one.
