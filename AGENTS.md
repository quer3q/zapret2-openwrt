# AGENTS.md

Signed OpenWrt apk feed for upstream zapret2. README.md has install and maintainer docs.

## Layout

- `build.sh`: the whole package. It downloads the pinned upstream `openwrt-embedded` tarball, checks `PKG_HASH`, stages `/opt/zapret2`, the init + hotplug scripts as real files in `/etc` (an absolute symlink breaks ImageBuilder service enabling), patches procd `respawn` into the init, writes OpenWrt's `lib/apk/packages/zapret2.{list,conffiles,conffiles_static}` and lifecycle scripts (as the SDK's `include/package-pack.mk` does), then runs `apk mkpkg`.
- `.github/workflows/release.yml`: `check` (daily upstream check, bumps `PKG_VERSION`/`PKG_HASH` in build.sh, pushes main + tag; a manual run with no upstream update tags main's current version; an existing tag means do nothing, never overwrite) → `build` (build.sh per arch in Alpine, signs `packages-<arch>.adb`, installs on stock `openwrt/rootfs`) → `publish` (GitHub release, Latest).

## Rules

- **Never build from source or use the OpenWrt SDK.** Repack upstream's prebuilt static binaries only.
- Keep deps at `kmod-nft-queue` only. The package carries nfqws2, mdig, ip2net, `files/fake` blobs and the init/ipset scripts. Don't add LuCI, UCI layers or blockcheck2 (it needs curl and other extra packages).
- `PKG_VERSION=`, `PKG_RELEASE=` and `PKG_HASH=` lines in build.sh are rewritten by CI with sed. Keep that exact format.
- Release assets are flat, so everything is per arch: `zapret2-<ver>-<arch>.apk`, `packages-<arch>.adb`. The published index uses an absolute `--pkgname-spec` pointing at `releases/download/v<ver>/`, so routers with a cached index survive a new Latest. New arch = `ARCHES` in the workflow + a `case` row in build.sh.
- Signing key: secrets `APK_SIGNING_KEY` / `APK_PUBLIC_KEY` (ECDSA P-256 PEM; usign keys don't work with apk v3). Secrets go only to the check and sign steps. Never write them to the host or commit them.
- Don't commit or push unless the user asks.

## Test locally (Docker)

```sh
docker run --rm -v "$PWD:/w" -w /w alpine:3.24 sh build.sh aarch64_generic dist
```

Then install it on `openwrt/rootfs:aarch64_generic-v25.12.5` (runs natively on Apple Silicon) with `apk add --allow-untrusted /dist/zapret2-*.apk`, or extract the workflow's `run:` blocks and run them with a throwaway key. Inside the container nftables/ubus errors are expected; `apk add` must still succeed, `nfqws2 --version` must run, and `/etc/rc.d/S*zapret2` must exist.
