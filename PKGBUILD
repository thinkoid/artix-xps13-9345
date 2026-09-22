# Maintainer: see README.md
#
# The install-media payload for "Artix Linux on the Dell XPS 13 9345".
# This PKGBUILD exists for one command:
#
#     makepkg -o          # download every source, verify every checksum, build nothing
#
# On a machine without makepkg, scripts/fetch.sh reads this same list.
# scripts/build-stick.sh then reads the downloaded files from this directory
# (or from $SRCDEST if you set one). Nothing here needs to be installed.
#
# Every version below is pinned to what the two distributions served on
# 2026-09-22. ARMtix rotates its root filesystem tarballs and deletes the
# old ones; Arch Linux ARM regenerates its "latest" tarball in place. When
# a download 404s or a checksum fails, look at doc/ chapter 7, addendum 7.2.

pkgname=artix-xps13-9345
pkgver=20260922
pkgrel=1
pkgdesc="Install-media payload for Artix Linux (s6) on the Dell XPS 13 9345, Snapdragon X Elite"
arch=('any')
url="https://github.com/thinkoid/artix-xps13-9345"
license=('MIT' 'CC-BY-SA-4.0')
# Arch Linux ARM's build key, which signs the kernel package: the fingerprint
# in the keyring ALARM ships. Import it once (gpg --recv-keys <fingerprint>),
# or pass --skippgpcheck to trust the checksum alone.
validpgpkeys=('68B3537F39A313B3E574D06777193F152BDBE6A6')

_alarm=http://mirror.archlinuxarm.org/aarch64
_alarmos=http://os.archlinuxarm.org/os
_armtix=https://armtix.artixlinux.org
_dtbl=https://github.com/TravMurav/dtbloader/releases/download/1.5.5

source=(
    # The live system on the stick: Arch Linux ARM's generic root filesystem.
    "$_alarmos/ArchLinuxARM-aarch64-latest.tar.gz"
    # The system that gets installed: ARMtix s6.
    "$_armtix/images/armtix-s6-20260921.tar.xz"
    # The kernel the installed system runs: Arch Linux ARM's, X1E80100 options on.
    "$_alarm/core/linux-aarch64-7.2.6-1-aarch64.pkg.tar.xz"
    "$_alarm/core/linux-aarch64-7.2.6-1-aarch64.pkg.tar.xz.sig"
    # alarm-*: unpacked into the live root (all of them), and the three firmware
    # packages also ride in the payload for the installed system (doc 9.4).
    "alarm-linux-firmware-qcom-20260916-1-any.pkg.tar.xz::$_alarm/core/linux-firmware-qcom-20260916-1-any.pkg.tar.xz"
    "alarm-linux-firmware-atheros-20260916-1-any.pkg.tar.xz::$_alarm/core/linux-firmware-atheros-20260916-1-any.pkg.tar.xz"
    "alarm-linux-firmware-whence-20260916-1-any.pkg.tar.xz::$_alarm/core/linux-firmware-whence-20260916-1-any.pkg.tar.xz"
    "alarm-dosfstools-4.2-5-aarch64.pkg.tar.xz::$_alarm/core/dosfstools-4.2-5-aarch64.pkg.tar.xz"
    "alarm-efibootmgr-18-4-aarch64.pkg.tar.xz::$_alarm/core/efibootmgr-18-4-aarch64.pkg.tar.xz"
    "alarm-efivar-39-2-aarch64.pkg.tar.xz::$_alarm/core/efivar-39-2-aarch64.pkg.tar.xz"
    "alarm-popt-1.19-2-aarch64.pkg.tar.xz::$_alarm/core/popt-1.19-2-aarch64.pkg.tar.xz"
    "alarm-wpa_supplicant-2.12-1-aarch64.pkg.tar.xz::$_alarm/core/wpa_supplicant-2:2.12-1-aarch64.pkg.tar.xz"
    "alarm-iw-6.17-1-aarch64.pkg.tar.xz::$_alarm/core/iw-6.17-1-aarch64.pkg.tar.xz"
    "alarm-gptfdisk-1.0.10-2-aarch64.pkg.tar.xz::$_alarm/extra/gptfdisk-1.0.10-2-aarch64.pkg.tar.xz"
    "alarm-pcsclite-2.5.2-1-aarch64.pkg.tar.xz::$_alarm/extra/pcsclite-2.5.2-1-aarch64.pkg.tar.xz"
    # armtix-*: installed into the ARMtix root by the installer (efibootmgr and its two libraries).
    "armtix-efibootmgr-18-4-aarch64.pkg.tar.xz::$_armtix/repos/system/os/aarch64/efibootmgr-18-4-aarch64.pkg.tar.xz"
    "armtix-efivar-39-2-aarch64.pkg.tar.xz::$_armtix/repos/system/os/aarch64/efivar-39-2-aarch64.pkg.tar.xz"
    "armtix-popt-1.19-2-aarch64.pkg.tar.xz::$_armtix/repos/system/os/aarch64/popt-1.19-2-aarch64.pkg.tar.xz"
    # The firmware driver that supplies the device tree when the boot entry does not.
    "dtbloader-1.5.5.efi::$_dtbl/dtbloader.efi"
)
sha256sums=('42a4eeaa038994ffd31fa173256ef2f0ef511358eeb41b9ea1f8626391b9b319'
            '16d977aa4ea74f66b88b38184eba47e33e6c66e2e367ba3dfc3b57689a5fa046'
            '634e5104b59aa827f43bb5d9497944de4179776a77bc710a887a5d9e9e0a4103'
            'SKIP'
            '95800ecb86fe2a6438339215e2da47b452f7c516a486400fc0fd24f6ef164e13'
            '3585438c34b7014dd156d814104c8d2f60ea11d642a4a31354239e8602418708'
            '52671ff7275c0a62029150ef700778da7e448f36b381e73da964751e8862bdbc'
            'c41120c6c89469f259d5248ea2ed0a7bea19f8a38d493682f7ff82037a862c21'
            'a443637e3c1171f9dcf60b5a2cf46bea8f397bb03168c38745084ca11dfa14d7'
            '6abe1962460263cb7f0c2213de8221ce570b83c301010afc13319b5a9cd97bba'
            '92da201e571426ab38ac690107e97e870862c005be9b1ecb3e1ab699ac20a022'
            'd5c3968fb3c9292c1097da0de8b07e4309258cf4b03701c3525c97b3b2443183'
            'e925035ffa55196d8627810ec30be3c4a87291ff61e8881aa22767d76c85f3e7'
            '1a27b82c004a661a483fa2f1daf37253f997424c178992337655e054219a6bfe'
            '17650c837779b3e2ead8cfb89f25c22267d8c6dce2c6b00ad9038a5a0d38b47d'
            '12c694ed61aa5b3f01977f5365abd11220ca99076fd18755c1a808586b8488e2'
            'b42dbc25a09682a867ee96d01bff2f977d38618ba48925cb4d04cf23ff65e75a'
            '9480d72c5ba34d0e76c108391acca1cf4cdd7ebb2140531593b1e0f426676c86'
            'ba6005a514f8ce22e6e7d02379400eaa5d72526766c9381dca847c2af270fd62')
# Nothing is unpacked by makepkg; build-stick.sh reads the archives whole.
noextract=()
for _s in "${source[@]}"; do
    _n=${_s%%::*}; [[ $_n == "$_s" ]] && _n=${_s##*/}
    noextract+=("$_n")
done
unset _s _n

package() {
    install -Dm755 -t "$pkgdir/usr/share/$pkgname/scripts" "$startdir"/scripts/*.sh
    install -Dm644 -t "$pkgdir/usr/share/doc/$pkgname" "$startdir"/doc/*.md "$startdir"/README.md
    install -Dm644 "$startdir/LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
