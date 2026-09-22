#!/bin/sh
# install.sh -- ARMtix s6 onto the internal disk of a Dell XPS 13 9345. Runs
# as root from the live stick (Arch Linux ARM), after Windows has been shrunk
# and BitLocker turned off (doc/, chapter 6). Every step prints before it
# runs and the destructive ones ask.
#
#     mount -L ARMPAYLOAD /mnt/payload
#     sh /mnt/payload/install.sh /dev/nvme0n1
#
# Edit the four settings below first. The partitions are created in the
# largest free region (the hole shrunk out of Windows): ESP 1G | swap = RAM |
# /tmp | / rest. Nothing existing is touched: Windows, its ESP and its
# recovery partition stay. Linux gets its own ESP; the firmware lists both.
#
# mem=31G on every entry, and not 32G: at EL1 under this firmware no DMA
# master reaches the top 32 GiB of the 64 GB, and the SoC hard-resets on the
# first access. Memory below that block is 31.505 GiB, so 32G would keep
# 507 MiB of it. doc/, section 8.1.
set -eu

HOST=sokath                          # hostname; also the partition labels and the boot entry
LOGIN=user                           # the account created for you, in wheel
TZ=Etc/UTC                           # ls /usr/share/zoneinfo
LOCALE=en_US.UTF-8
SWAP=${SWAP:-64G}                    # = RAM, so hibernation stays possible
TMP=${TMP:-64G}                      # a separate /tmp; set TMP=0 to skip it

DISK=${1:?usage: $0 /dev/nvme0n1}
PAY=$(dirname "$(readlink -f "$0")")
DTB=qcom/x1e80100-dell-xps13-9345.dtb
MEM=mem=31G                          # the EL1 cut, see the header
UHOST=$(printf %s "$HOST" | tr a-z A-Z)
ESPLABEL=${UHOST}ESP                 # FAT labels: 11 characters, upper case

one() {
    set -- "$PAY"/$1
    [ $# -eq 1 ] && [ -s "$1" ] || { echo "need exactly one of $PAY/$1, have: $*" >&2; exit 1; }
    echo "$1"
}
ARMTIX=$(one 'armtix-s6-*.tar.xz')
KERNEL=$(one 'linux-aarch64-*-aarch64.pkg.tar.xz')
DTBL=$(one 'dtbloader-*.efi')
# Firmware from Arch Linux ARM, not ARMtix: ARMtix ships every firmware file
# zstd-compressed and this kernel reads xz-compressed firmware only, so
# ARMtix's DSP, wifi and GPU files are invisible to it (doc 9.4). Same package
# names, same versions, uncompressed. Plus efibootmgr and its two libraries.
FW="$(one 'alarm-linux-firmware-qcom-*.pkg.tar.xz') \
    $(one 'alarm-linux-firmware-atheros-*.pkg.tar.xz') \
    $(one 'alarm-linux-firmware-whence-*.pkg.tar.xz') \
    $(one 'armtix-efibootmgr-*.pkg.tar.xz') \
    $(one 'armtix-efivar-*.pkg.tar.xz') \
    $(one 'armtix-popt-*.pkg.tar.xz')"

[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
[ -b "$DISK" ] || { echo "$DISK is not a block device" >&2; exit 1; }
[ -d /sys/firmware/efi ] || { echo "not booted via UEFI" >&2; exit 1; }
[ ${#ESPLABEL} -le 11 ] || { echo "HOST too long for a FAT label: $ESPLABEL" >&2; exit 1; }
# Preflight: every tool this script runs outside the chroot, checked before
# anything is touched. The generic tarball lacks partprobe and mkfs.vfat;
# the stick unpacks dosfstools and the partition table is re-read with blockdev.
for c in sgdisk blockdev udevadm mkfs.vfat mkswap mkfs.ext4 mktemp bsdtar chroot lsblk sha256sum; do
    command -v "$c" >/dev/null || { echo "missing tool on the live root: $c" >&2; exit 1; }
done
echo "== payload"
(cd "$PAY" && sha256sum -c --quiet SHA256SUMS) || { echo "payload does not match SHA256SUMS" >&2; exit 1; }

ESP=/dev/disk/by-partlabel/$ESPLABEL
SWP=/dev/disk/by-partlabel/$HOST-swap
TMPP=/dev/disk/by-partlabel/$HOST-tmp
ROOT=/dev/disk/by-partlabel/$HOST

echo "== $DISK now:"; sgdisk -p "$DISK"
# Resumable: a run that died after partitioning picks up here with the
# partitions it already made.
if [ -b "$ESP" ] && [ -b "$SWP" ] && [ -b "$ROOT" ] && { [ "$TMP" = 0 ] || [ -b "$TMPP" ]; }; then
    echo "== the $HOST partitions exist already; keeping them"
else
    echo "== largest free region gets: ESP 1G | swap $SWAP | /tmp $TMP | / (rest)"
    printf 'Type the disk path again to create the partitions: '; read -r ans
    [ "$ans" = "$DISK" ] || { echo "aborted"; exit 1; }
    sgdisk -n0:0:+1G     -t0:ef00 -c0:"$ESPLABEL" "$DISK" >/dev/null
    sgdisk -n0:0:+"$SWAP" -t0:8200 -c0:"$HOST-swap" "$DISK" >/dev/null
    [ "$TMP" = 0 ] || sgdisk -n0:0:+"$TMP" -t0:8300 -c0:"$HOST-tmp" "$DISK" >/dev/null
    sgdisk -n0:0:0       -t0:8305 -c0:"$HOST" "$DISK" >/dev/null
    blockdev --rereadpt "$DISK" || true; udevadm settle
fi
# udev names the new partitions by label a moment after the table is
# re-read; wait for the names rather than race them.
for i in 1 2 3 4 5 6 7 8 9 10; do
    [ -b "$ESP" ] && [ -b "$SWP" ] && [ -b "$ROOT" ] && { [ "$TMP" = 0 ] || [ -b "$TMPP" ]; } && break
    sleep 1
done
[ -b "$ESP" ] && [ -b "$ROOT" ] || { echo "the new partitions did not appear under /dev/disk/by-partlabel" >&2; exit 1; }
printf 'Type the disk path again to format them and install: '; read -r ans
[ "$ans" = "$DISK" ] || { echo "aborted"; exit 1; }
mkfs.vfat -F32 -n "$ESPLABEL" "$ESP" >/dev/null
mkswap -L "$HOST-swap" "$SWP" >/dev/null
[ "$TMP" = 0 ] || mkfs.ext4 -q -L "$HOST-tmp" "$TMPP"
mkfs.ext4 -q -L "$HOST" "$ROOT"

R=/mnt/$HOST; mkdir -p "$R"; mount "$ROOT" "$R"
echo "== root: ARMtix s6 tarball"
bsdtar -xpf "$ARMTIX" -C "$R"
# The kernel lives on the ESP: move the tarball's /boot there, then mount over it.
mkdir -p "$R/boot"; E=$(mktemp -d); mount "$ESP" "$E"
cp -a "$R/boot/." "$E/"; rm -rf "$R/boot"/*; umount "$E"; rmdir "$E"
mount "$ESP" "$R/boot"

{
    printf 'LABEL=%-12s /      ext4  rw,relatime,discard  0 1\n' "$HOST"
    printf 'LABEL=%-12s /boot  vfat  rw,umask=0077        0 2\n' "$ESPLABEL"
    [ "$TMP" = 0 ] || printf 'LABEL=%-12s /tmp   ext4  rw,relatime,discard  0 2\n' "$HOST-tmp"
    printf 'LABEL=%-12s none   swap  defaults             0 0\n' "$HOST-swap"
} > "$R/etc/fstab"
echo "$HOST" > "$R/etc/hostname"
ln -sf "/usr/share/zoneinfo/$TZ" "$R/etc/localtime"
sed -i "s/^#$LOCALE/$LOCALE/" "$R/etc/locale.gen"
echo "LANG=$LOCALE" > "$R/etc/locale.conf"
# ARMtix's initramfs config is for single-board computers; drop its forced modules.
sed -i 's/^MODULES=.*/MODULES=()/' "$R/etc/mkinitcpio.conf"
# The DSP's services are found through the in-kernel protection-domain
# mapper, which nothing autoloads on the installed root: without it, no UCSI,
# no Type-C, no USB (doc 9.4). The s6 `modules` service reads this file.
# The directory is not in every tarball (September 2026's lacks it).
mkdir -p "$R/etc/modules-load.d"
echo qcom_pd_mapper > "$R/etc/modules-load.d/$HOST.conf"
# A 16x32 console font on the 2880x1800 panel; console-setup reads this.
printf 'KEYMAP=us\nFONT=latarcyrheb-sun32\n' > "$R/etc/vconsole.conf"
# Pin the Arch Linux ARM kernel: ARMtix's own build has the X1E drivers off.
# Pin the three firmware packages with it: ARMtix carries the same names at
# the same versions, zstd-compressed, and the first pacman -Syu would put them
# back over the readable set (doc 9.2 step 8, 9.4).
grep -q '^IgnorePkg' "$R/etc/pacman.conf" \
    || sed -i 's/^\[options\]/[options]\nIgnorePkg = linux-aarch64 linux-firmware-qcom linux-firmware-atheros linux-firmware-whence/' "$R/etc/pacman.conf"

echo "== chroot: kernel, firmware, efibootmgr"
mkdir -p "$R/pkgs"; cp "$KERNEL" $FW "$R/pkgs/"
for d in proc sys dev run; do mount --rbind "/$d" "$R/$d"; mount --make-rslave "$R/$d"; done
cp /etc/resolv.conf "$R/etc/resolv.conf" 2>/dev/null || true
chroot "$R" /bin/sh -e <<CH
locale-gen >/dev/null
pacman -Rdd --noconfirm linux-aarch64-headers linux-aarch64-lts linux-aarch64-lts-headers 2>/dev/null || true
pacman -U --noconfirm /pkgs/*.pkg.tar.xz
rm -f /boot/ltsImage.gz; rm -rf /boot/dtbs-lts
# The tarball's /boot came with its own fallback image (170 MB in September
# 2026's): nothing points at it, the firmware must never load it (below), and
# it is a sixth of the ESP. The lts images likewise, if the tarball had any.
rm -f /boot/initramfs-linux-fallback.img /boot/initramfs-linux-lts*.img
# No fallback initramfs, on purpose. This firmware resets the machine before
# the kernel runs when the loader reads an initrd larger than ~224 MB, and the
# fallback image is ~272 MB by construction (doc 12.8). The kernel package
# ships PRESETS=('default') only; keep it that way after every kernel install.
P=/etc/mkinitcpio.d/linux-aarch64.preset
sed -i "s/^PRESETS=.*/PRESETS=('default')/" \$P
mkinitcpio -P
[ -s /boot/initramfs-linux.img ] || { echo "no initramfs" >&2; exit 1; }
CH
rm -rf "$R/pkgs"

echo "== bootloader: systemd-boot binary from the live root, dtbloader, entries"
B=$R/boot
mkdir -p "$B/EFI/BOOT" "$B/EFI/systemd/drivers" "$B/loader/entries" "$B/dtbloader/dtbs/qcom"
cp /usr/lib/systemd/boot/efi/systemd-bootaa64.efi "$B/EFI/BOOT/BOOTAA64.EFI"
cp /usr/lib/systemd/boot/efi/systemd-bootaa64.efi "$B/EFI/systemd/systemd-bootaa64.efi"
cp "$DTBL" "$B/EFI/systemd/drivers/dtbloaderaa64.efi"
cp "$B/dtbs/$DTB" "$B/dtbloader/dtbs/qcom/"
printf 'default %s.conf\ntimeout 3\nconsole-mode keep\n' "$HOST" > "$B/loader/loader.conf"
cat > "$B/loader/entries/$HOST.conf" <<EN
title      $HOST (ARMtix s6)
linux      /Image
initrd     /initramfs-linux.img
devicetree /dtbs/$DTB
options    root=LABEL=$HOST rw resume=LABEL=$HOST-swap $MEM
EN
cat > "$B/loader/entries/$HOST-safe.conf" <<EN
title      $HOST, verbose + unused clocks kept
linux      /Image
initrd     /initramfs-linux.img
devicetree /dtbs/$DTB
options    root=LABEL=$HOST rw resume=LABEL=$HOST-swap $MEM clk_ignore_unused pd_ignore_unused loglevel=7
EN
# No fallback entry: see the preset note above. A fallback-initramfs entry on
# this machine is a menu line that resets the box.
case $DISK in
    /dev/loop*) echo "== loop device: rehearsal, the firmware boot entry is not written" ;;
    *) PN=$(lsblk -no PARTN "$ESP")
       chroot "$R" efibootmgr -c -d "$DISK" -p "$PN" -L "$HOST" -l '\EFI\systemd\systemd-bootaa64.efi' ;;
esac

echo "== accounts (root, then $LOGIN)"
chroot "$R" passwd root
chroot "$R" useradd -m -G wheel -s /bin/bash "$LOGIN" 2>/dev/null || true
chroot "$R" passwd "$LOGIN"
grep -q '^%wheel ALL=(ALL:ALL) NOPASSWD: ALL' "$R/etc/sudoers" 2>/dev/null \
    || echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' >> "$R/etc/sudoers"

for d in run dev sys proc; do umount -R "$R/$d" 2>/dev/null || true; done
umount "$R/boot"; umount "$R"; sync
echo "== done."
case $DISK in /dev/loop*) ;; *) echo "efibootmgr now:"; efibootmgr ;; esac
echo "Reboot, F12, pick '$HOST'. Entries: $HOST, $HOST-safe."
echo "$HOST boots without clk/pd_ignore_unused, which the live stick never needed either;"
echo "if it does not reach a login, $HOST-safe is the same entry with them."
echo "First boot: pacman -Syu, then doc/ chapter 10."
