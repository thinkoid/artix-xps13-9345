#!/bin/sh
# build-stick.sh -- the install stick for the Dell XPS 13 9345. Runs on your
# other Linux machine, x86-64 or ARM. See doc/, chapter 7.
#
#     sudo scripts/build-stick.sh /dev/sdX
#
# Layout: p1 ESP (ARMESP) | p2 live root (ARMLIVE) | p3 payload (ARMPAYLOAD).
# The live root is Arch Linux ARM's generic tarball as shipped (its kernel has
# the X1E80100 drivers on), plus the Qualcomm firmware split and the tools it
# lacks. The payload carries everything install.sh needs, so the install
# itself is offline.
#
# The downloaded sources are read from $SRCDEST, or from the top of this
# repository when SRCDEST is unset: the place `makepkg -o` or scripts/fetch.sh
# put them. A loop device is accepted as the target, for a rehearsal against
# a disk image.
set -eu

DEV=${1:?usage: $0 /dev/sdX}
TOP=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
SRC=${SRCDEST:-$TOP}
DTB=qcom/x1e80100-dell-xps13-9345.dtb
PKGX='--exclude=.PKGINFO --exclude=.MTREE --exclude=.BUILDINFO --exclude=.INSTALL --exclude=.CHANGELOG'

# one() prints the single file matching a pattern, or fails: a payload with
# two kernels or two tarballs is a payload nobody checked.
one() {
    set -- "$SRC"/$1
    [ $# -eq 1 ] && [ -s "$1" ] || { echo "need exactly one of $SRC/$1, have: $*" >&2; exit 1; }
    echo "$1"
}
ALARM=$(one 'ArchLinuxARM-aarch64-latest.tar.gz')
ARMTIX=$(one 'armtix-s6-*.tar.xz')
KERNEL=$(one 'linux-aarch64-*-aarch64.pkg.tar.xz')
DTBL=$(one 'dtbloader-*.efi')
for f in alarm-linux-firmware-qcom alarm-linux-firmware-atheros alarm-linux-firmware-whence \
         alarm-dosfstools alarm-efibootmgr alarm-gptfdisk alarm-wpa_supplicant alarm-iw \
         armtix-efibootmgr armtix-efivar armtix-popt; do
    one "$f-*.pkg.tar.xz" >/dev/null
done
for f in install.sh live.mkinitcpio.conf; do
    [ -s "$TOP/scripts/$f" ] || { echo "missing $TOP/scripts/$f" >&2; exit 1; }
done
for c in sgdisk partprobe mkfs.vfat mkfs.ext4 bsdtar wipefs lsblk udevadm sha256sum chroot; do
    command -v "$c" >/dev/null || { echo "missing tool: $c" >&2; exit 1; }
done

[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
[ -b "$DEV" ] || { echo "$DEV is not a block device" >&2; exit 1; }
case $DEV in
    /dev/loop*) ;;
    *) [ "$(cat /sys/block/"$(basename "$DEV")"/removable 2>/dev/null)" = 1 ] \
           || { echo "$DEV is not removable; refusing" >&2; exit 1; } ;;
esac
part() { case $DEV in *[0-9]) echo "${DEV}p$1" ;; *) echo "${DEV}$1" ;; esac; }

echo "About to wipe $DEV:"; lsblk -o NAME,SIZE,MODEL,TRAN "$DEV"
printf 'Type the device path again to continue: '; read -r ans
[ "$ans" = "$DEV" ] || { echo "aborted"; exit 1; }

umount -q "$(part 1)" "$(part 2)" "$(part 3)" 2>/dev/null || true
wipefs -aq "$DEV"
sgdisk -Z "$DEV" >/dev/null
sgdisk -n1:0:+512M -t1:ef00 -c1:ARMESP \
       -n2:0:+6G   -t2:8300 -c2:ARMLIVE \
       -n3:0:0     -t3:8300 -c3:ARMPAYLOAD "$DEV" >/dev/null
partprobe "$DEV"; udevadm settle
mkfs.vfat -F32 -n ARMESP "$(part 1)" >/dev/null
mkfs.ext4 -q -L ARMLIVE "$(part 2)"
mkfs.ext4 -q -L ARMPAYLOAD "$(part 3)"

R=$(mktemp -d); E=$(mktemp -d); P=$(mktemp -d)
# Bind mounts first; nothing here may fail, or set -e turns a clean exit
# into umount's status.
trap 'umount -q "$R/dev" "$R/proc" "$R/sys" "$R" "$E" "$P" 2>/dev/null || true; rmdir "$R" "$E" "$P" 2>/dev/null || true' EXIT
mount "$(part 2)" "$R"; mount "$(part 1)" "$E"; mount "$(part 3)" "$P"

echo "== live root: Arch Linux ARM tarball"
bsdtar -xpf "$ALARM" -C "$R"
echo "== live root: qcom firmware, September wifi firmware, and the tools the tarball lacks"
# Unpacked, not installed: package files minus their metadata, straight into
# the live root. dosfstools is among them because install.sh formats an ESP
# and the generic tarball has no mkfs.vfat (doc 9.2).
for p in "$SRC"/alarm-*.pkg.tar.xz; do
    # shellcheck disable=SC2086
    bsdtar -xpf "$p" -C "$R" $PKGX
done
[ -f "$R/boot/dtbs/$DTB" ] || { echo "no $DTB in the tarball: its kernel is too old" >&2; exit 1; }
# The generic tarball's systemd waits ~90 s twice at boot: for a getty on the
# DT console (ttyMSM0, not wired out on this laptop) and for a TPM the firmware
# advertises but the DT-booted kernel never exposes (doc 8.2). Masked here.
mkdir -p "$R/etc/systemd/system"
ln -sf /dev/null "$R/etc/systemd/system/serial-getty@ttyMSM0.service"
ln -sf /dev/null "$R/etc/systemd/system/tpm2.target"
echo sokath-live > "$R/etc/hostname"
cat > "$R/etc/fstab" <<FS
LABEL=ARMLIVE     /            ext4  rw,relatime  0 1
LABEL=ARMESP      /boot        vfat  rw,umask=0077 0 2
LABEL=ARMPAYLOAD  /mnt/payload ext4  rw,relatime  0 2
FS
mkdir -p "$R/mnt/payload"

echo "== live root: the initramfs, regenerated for this laptop"
# The tarball's initramfs relies on mkinitcpio's autodetect, which keeps the
# modules of the machine generating the image: the distribution's build host.
# It carries one module (lz4) and none of the Type-C host chain this laptop
# needs before a USB root can appear, so a stick with it never finds its own
# root. Regenerated here, inside the live root, with autodetect off and the
# modules named in scripts/live.mkinitcpio.conf (doc 7.5, step 6). The chroot
# runs aarch64 binaries: native on an ARM builder, through binfmt_misc on
# x86-64 (qemu-user-static).
KVER=$(ls "$R/usr/lib/modules")
[ "$(echo "$KVER" | wc -l)" = 1 ] || { echo "expected one kernel under the live root, have: $KVER" >&2; exit 1; }
if [ "$(uname -m)" != aarch64 ] && [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
    echo "cannot run aarch64 binaries on $(uname -m): install qemu-user-static and" >&2
    echo "qemu-user-static-binfmt (Arch) or qemu-user-static + binfmt-support (Debian)" >&2
    exit 1
fi
cp "$TOP/scripts/live.mkinitcpio.conf" "$R/etc/mkinitcpio.conf.d/live.conf"
# The board's firmware, so the DSP that owns the Type-C port can boot inside
# the initramfs; the remoteproc driver declares no MODULE_FIRMWARE, so
# mkinitcpio would not add it by itself. The .jsn files are symlinks into the
# LENOVO directory; both ends are listed.
{
    printf 'FILES=('
    (cd "$R" && find usr/lib/firmware/qcom/x1e80100/dell/xps13-9345 \
                     usr/lib/firmware/qcom/x1e80100/LENOVO/21N1 \
                     \( -type f -o -type l \) -printf ' /%p')
    printf ')\n'
} >> "$R/etc/mkinitcpio.conf.d/live.conf"
for d in dev proc sys; do mount --bind "/$d" "$R/$d"; done
LC_ALL=C chroot "$R" mkinitcpio -k "$KVER" -S autodetect,kms -g /boot/initramfs-linux.img
N=$(LC_ALL=C chroot "$R" lsinitcpio -a /boot/initramfs-linux.img | sed -n 's/^==> Included modules (\([0-9]*\)).*/\1/p')
for d in sys proc dev; do umount "$R/$d"; done
[ "${N:-0}" -ge 100 ] || { echo "the regenerated initramfs has ${N:-0} modules; expected hundreds" >&2; exit 1; }
# The firmware's loader resets the machine on an initrd of 224 MB or more
# (doc 12.8); 200 MB is the line here.
SZ=$(stat -c %s "$R/boot/initramfs-linux.img")
[ "$SZ" -lt 209715200 ] || { echo "the initramfs is $SZ bytes, too large for this firmware (doc 12.8)" >&2; exit 1; }
echo "   $N modules, $((SZ / 1048576)) MiB"

echo "== ESP"
cp "$R/boot/Image" "$R/boot/initramfs-linux.img" "$E/"
mkdir -p "$E/dtbs/qcom" "$E/dtbloader/dtbs/qcom" "$E/EFI/BOOT" "$E/EFI/systemd/drivers" "$E/loader/entries"
cp "$R/boot/dtbs/$DTB" "$E/dtbs/qcom/"
cp "$R/boot/dtbs/$DTB" "$E/dtbloader/dtbs/qcom/"
cp "$R/usr/lib/systemd/boot/efi/systemd-bootaa64.efi" "$E/EFI/BOOT/BOOTAA64.EFI"
cp "$R/usr/lib/systemd/boot/efi/systemd-bootaa64.efi" "$E/EFI/systemd/systemd-bootaa64.efi"
cp "$DTBL" "$E/EFI/systemd/drivers/dtbloaderaa64.efi"
printf 'default live.conf\ntimeout 5\nconsole-mode keep\n' > "$E/loader/loader.conf"
# mem=31G on every entry, and not 32G: doc 8.1.
cat > "$E/loader/entries/live.conf" <<EN
title      Arch Linux ARM live (sokath)
linux      /Image
initrd     /initramfs-linux.img
devicetree /dtbs/$DTB
options    root=LABEL=ARMLIVE rw mem=31G
EN
cat > "$E/loader/entries/live-safe.conf" <<EN
title      Arch Linux ARM live, verbose + unused clocks kept
linux      /Image
initrd     /initramfs-linux.img
devicetree /dtbs/$DTB
options    root=LABEL=ARMLIVE rw mem=31G clk_ignore_unused pd_ignore_unused loglevel=7
EN
cat > "$E/loader/entries/live-dtbloader.conf" <<EN
title      Arch Linux ARM live, DTB from dtbloader only
linux      /Image
initrd     /initramfs-linux.img
options    root=LABEL=ARMLIVE rw mem=31G
EN

echo "== payload"
cp "$ARMTIX" "$KERNEL" "$KERNEL.sig" "$DTBL" "$SRC"/alarm-linux-firmware-*.pkg.tar.xz "$SRC"/armtix-*.pkg.tar.xz "$P/"
cp "$TOP/scripts/install.sh" "$P/"; chmod +x "$P/install.sh"
mkdir -p "$P/doc"; cp "$TOP"/doc/*.md "$P/doc/"; cp "$TOP/README.md" "$P/" 2>/dev/null || true
# install.sh verifies the payload against this before it touches the disk.
(cd "$P" && sha256sum ./*.tar.xz ./*.efi ./*.sig > SHA256SUMS)

sync
echo "== done"; df -h "$R" "$E" "$P" | sed 1d; find "$E" -type f | sed "s|$E||" | sort
