# Artix Linux on the Dell XPS 13 9345 — a blueprint

Installing a systemd-free Linux on a Snapdragon X Elite laptop, from a
Windows machine as it comes out of the box to a working desktop, with
every acronym spelled out and every decision explained.

The machine is called **sokath** throughout.[^name]

Keeping it current afterwards is a separate document: [the update
companion](artix-on-xps13-9345-updates.md).

---

## 0. tl;dr

The Dell XPS 13 9345 is an **ARM** laptop, not an x86 one, and almost
everything you have read about installing Linux on a laptop silently
assumes x86. The three differences that matter:

1. **The kernel must be told what hardware it is running on.** On a PC
   the firmware describes the hardware to the operating system through
   tables called **ACPI**. On this machine it does not: Linux needs a
   **device tree blob** (**DTB**), a separate file describing the
   hardware, handed to the kernel at boot. If you forget it, you get a
   black screen and a reboot, with no error message anywhere.
2. **Not every ARM Linux kernel has the drivers for this chip turned
   on**, even when the code is upstream. The distribution this
   blueprint installs (ARMtix) ships a kernel with them *off*. The
   installation therefore borrows a kernel from a second distribution
   (Arch Linux ARM) that has them *on*.
3. **Windows stays on the disk**, shrunk. Not out of affection: Dell
   ships firmware updates for ARM machines through Windows only, and a
   laptop you cannot update the firmware on is a laptop with a fixed
   set of bugs forever.

The result is Artix Linux, Arch Linux without systemd, on a Qualcomm
Snapdragon X Elite. Display, keyboard, touchpad, touchscreen, Wi-Fi,
Bluetooth, GPU acceleration, NVMe and USB-C all work. Suspend to RAM
works in both modes; failures have occurred and are under
investigation. The speakers and the internal microphones work with
a kernel carrying three changes (§12.5). Fan control and the camera
are untested. The machine uses 31 GB of its 64 GB until the firmware or
the boot method changes (§8.1). Chapter 3 has the table.

**Time budget:** an evening for stages 1–4 if nothing goes wrong, plus
an hour of downloads beforehand. Chapter 11 is a page: the kernel pin
comes off with an update, not by your hand.

---

## 1. Read this before you start

### 1.1 What is proven and what is not

Each stage carries a status. As of **2026-09-21**:

| Stage | What it does | Status |
|---|---|---|
| 1 | Windows housekeeping | **PROVEN, 2026-09-19.** Every section done on the machine. F2 on the capacitive row must land in the 5 s it shows F1–F12 (§6.4) |
| 2 | Build the install stick | **PROVEN, 2026-09-19**, with an initramfs built by hand. The first stick written by the published `build-stick.sh` (2026-09-22) did **not** boot: it copied the tarball's own initramfs, which holds one module. Since 2026-09-23 the script regenerates the image inside the live root (§7.5, step 6): rehearsed against a disk image, then written to a stick that booted to a login the same morning. **PROVEN with the published script, 2026-09-23** |
| 3 | Boot the live system | **PROVEN, 2026-09-19**, and again on 2026-09-22 on a stick from the published tree with the regenerated initramfs. Boots to a login with `mem=31G`. Without it the machine hard-resets on the first DMA into the top 32 GiB (§8.1). The `-safe` entry was never needed |
| 4 | Install to the internal disk | **PROVEN, 2026-09-19**, with the January tarball. The installer preflights the tools the live root lacks (§9.2) and writes the three fixes the installed system needs for USB, Wi-Fi and its DSPs (§9.4). **Rehearsed 2026-09-22 with the September tarball**: the published `install.sh`, run from the stick's live root against a disk image partitioned like Dell's, produced the four partitions, the pinned kernel, the readable firmware and the two boot entries; not booted, since the machine it would boot on was busy running the rehearsal |
| 5 | First boot and setup | **PROVEN, 2026-09-19.** The default entry reaches a login, no bring-up flags. The first update, Wi-Fi under s6, services and a Wayland compositor on the GPU are chapter 10. Chapter 12 is the first days of use |
| 6 | Get off the pinned kernel | **Not a stage you perform.** The kernel package with the X1E80100 options is with ARMtix as a merge request, filed 2026-09-21 (chapter 11); once their repository ships it, the pin comes off with a normal update |

Every chapter marked PROVEN is written from what the hardware did.
Read what each command does before you run it. A different tarball or a later kernel will
hold surprises of the same kind this machine held. The fastest way
through them is the logs.

### 1.2 Who this is for

You can type commands into a terminal and read what comes back. You
have installed some Linux before. You do not need to know anything
about ARM, device trees, bootloaders or partition tables. That is what
this document is for.

You need a **second computer running Linux** to build the install
stick. It cannot be done from Windows: the stick is assembled by
unpacking Linux archives and creating Linux filesystems on it.

### 1.3 What you risk

**Your data.** Stage 1 shrinks the Windows partition. Stage 4 writes
new partition table entries. Back up anything you care about, to
something that is not this laptop, before you start. Chapter 14 is the
way back to a Windows-only machine and says what that does not
restore.

---

## 2. Why this laptop is different

### 2.1 The vocabulary, before anything else

The rest of the document is unreadable without these. Appendix A has
the full list.

**ARM** is a processor architecture. **x86** (x86-64, **AMD64**) is
the architecture of Intel and AMD laptops. Phones, Apple's M-series
Macs and the Raspberry Pi are ARM. **aarch64** and **arm64** both name
the 64-bit version. A package ending `-aarch64.pkg.tar.xz` is built
for this machine. One ending `-x86_64.pkg.tar.xz` is not.

**SoC**, *System on Chip*. On a PC the processor, graphics, memory
controller, USB controller and sound hardware are separate chips that
the operating system discovers over standard buses. On this laptop
they are one chip, and most of the pieces inside it cannot be
discovered. The operating system has to be told. This is the cause of
nearly everything unusual in this document.

**Device tree** (**DT**) and **device tree blob** (**DTB**), the file
that does the telling. A compiled description of what is inside the
SoC and how it is wired: memory addresses, pins, clocks. The source
lives in the Linux kernel and the `.dtb` is produced when the kernel
is built. This laptop's is `x1e80100-dell-xps13-9345.dtb`. The whole
boot process is about getting that file into the kernel's hands.

**ACPI**, *Advanced Configuration and Power Interface*, the tables a
PC's firmware hands the operating system to describe the hardware.
This laptop's firmware has them. They are written for Windows and
Linux does not use them. Hence the device tree.

**UEFI**, *Unified Extensible Firmware Interface*, the replacement
for the **BIOS**. The software in the laptop that runs before any
operating system. It reads one kind of partition and runs programs
from it.

**ESP**, *EFI System Partition*, that partition. Formatted **FAT32**,
an old Microsoft filesystem every firmware can read. It holds
bootloaders as `.efi` files. This machine ends up with two, Windows'
and ours.

**Secure Boot**, a UEFI feature that refuses to run bootloaders not
signed by a trusted key. The bootloader used here is unsigned, so
Secure Boot gets turned off.

**BitLocker**, Windows' full-disk encryption. It watches the firmware
settings and demands a recovery key when they change. Turning Secure
Boot off is a change. Hence chapter 6, in that order.

**initramfs**, *initial RAM filesystem*, a small compressed archive
of programs and drivers the kernel unpacks into memory to find the
real disk. **mkinitcpio** generates it.

**ALARM**, *Arch Linux ARM*, the port of Arch Linux to ARM. Its
kernel is the one this install borrows. In capitals it always means
the distribution.

**ARMtix**, the official ARM port of Artix Linux, the target
distribution. Artix is Arch Linux with **systemd** replaced by a
simpler init system. This install uses the **s6** variant.

**init system**, the first program the kernel starts. It starts and
supervises everything else. systemd is the common one. s6 is a
smaller one built from many tiny programs. `systemctl` and
`journalctl` do not exist on the installed system.

**package**, the unit in which Arch-family distributions ship
software: one compressed archive of the files a component installs,
with metadata files at the front naming it, its version and its
dependencies. **pacman** unpacks it, records every file in its
database, and runs the hooks that follow. The kernel is a package
like any other. The one this blueprint installs is
`linux-aarch64-7.2.6-1-aarch64.pkg.tar.xz`.

**root filesystem tarball**, one compressed `tar` archive holding a
complete installed system: every file under `/`, a kernel in `/boot`,
and the package database. Unpack it onto an empty partition and you
have an installed system minus the boot chain and the per-machine
settings. Both distributions publish one. ARMtix keeps its under
`images/`. It is not a disk image; there is no partition table
inside, only files. "Image" below means the kernel image and the
initramfs.

### 2.2 The chip

| | |
|---|---|
| SoC | Qualcomm Snapdragon X Elite **X1E-80-100**; the kernel calls the family `x1e80100` |
| CPU | 12 Oryon cores, 64-bit ARM |
| Memory | 64 GB LPDDR5X, soldered |
| Storage | 2 TB NVMe, replaceable |
| Display | 2880×1800 OLED at 60 Hz |
| Graphics | Qualcomm Adreno X1, driven by the open-source Mesa drivers (**freedreno** for OpenGL, **turnip** for Vulkan) |
| Wi-Fi/Bluetooth | Qualcomm WCN7850, driver `ath12k` |

The device tree for this laptop has been in the mainline kernel since
late 2024, under the Dell codename `tributo`. Dell's firmware blobs
have shipped in `linux-firmware` since March 2026. Nothing has to be
extracted from the Windows partition.

---

## 3. What works and what does not

What this machine did on kernel 7.2.6, 2026-09-19 to -21. "Not
tested" means exactly that.

| Hardware | State | Notes |
|---|---|---|
| Display, backlight | Works | 2880×1800 at 60 Hz from EDID. Backlight over the DisplayPort AUX channel |
| Keyboard, touchpad, touchscreen | Works | All three tested |
| Fingerprint reader | Not tested | |
| GPU acceleration | Works | Needs the Qualcomm firmware split (§7.1). Adreno X1-85, OpenGL ES 3.2 through freedreno. The GPU resets itself now and then; a compositor that ignores a lost context runs blind (§12.3). Browsers flicker under a GLES compositor until one driconf line is in place (§12.9) |
| NVMe storage | Works | |
| Wi-Fi | Works | Firmware from 2026-09-16 or newer (§9.4) |
| Bluetooth | Works | |
| USB-C, charging, external display | Works | DisplayPort alt mode at 3840×2160, power delivery both ways, the monitor's hub, on either port. The machine occasionally resets when a charging external panel with a SuperSpeed hub is moved between ports. With a 4-lane DisplayPort link the monitor's hub loses its USB 2.0 half too, and with it the mouse and keyboard; setting the monitor to prefer USB data makes that rarer, not impossible (§12.2) |
| Suspend to RAM | Works | s2idle and deep, bare and under a compositor. The lid suspends and wakes it. Failures have occurred: one lid close never slept and looped for 100 minutes (§12.7). Investigation ongoing |
| Speakers | Works | All four, in stereo. With a kernel carrying the sound node, the machine driver and one volume fix, none of them in the installed kernel yet; three small PipeWire and WirePlumber fragments (§12.5). Bluetooth and USB audio work on any kernel |
| Microphones | Works | The internal ones, with the speakers' kernel and no configuration of their own (§12.5) |
| Fan control, keyboard backlight, thermal sensors | Not tested | Of interest. All three live in the EC, which has no kernel driver yet |
| Camera | Not tested | Low priority |
| Battery gauge | Works, minus the percent | The `capacity` file is missing; a one-line driver fix is on `linux-pm` (§12.1) |
| Battery life | About 7½ h | 6.9–7.2 W at light interactive load (§12.1). Idle not measured |
| Memory | 31 GB of 64 usable | A firmware limit at the privilege level Linux boots at (§8.1) |
| Power off | Works | `halt -p` is a full off. Opening the lid boots the powered-off machine because the firmware's *Power On Lid Open* is on by default (§12.4) |

---

## 4. What you need

- **The laptop**, with Windows as it shipped, and its charger.
- **A second computer running Linux**, root access, 8 GB of free
  disk. x86-64 or ARM, any distribution. It needs `curl`, `bsdtar`,
  `sgdisk`, `partprobe`, `mkfs.vfat` and `mkfs.ext4`,[^tools] and on
  x86-64 also `qemu-user-static` with its binfmt registration, because
  one step of building the stick runs inside the ARM live system
  (§7.5, step 6).
- **A USB stick, 16 GB or larger.** It will be erased.
- **A wired network connection, or your Wi-Fi password.** The install
  is offline. The first update after it is not.
- **A USB-C hub or adapter**, with Ethernet if possible. The laptop
  has USB-C ports only.
- **Two hours**, plus the downloads.

Optional: a **USB-to-serial adapter**. When the machine shows nothing
at all, a serial console is the difference between a diagnosis and a
guess. Without one, rely on the verbose boot entry in §9.3.

---

## 5. How this machine boots

Five links in the chain:

```
  1. UEFI firmware           (in the laptop, cannot be replaced)
         |  reads the ESP, a FAT32 partition
         v
  2. EFI/BOOT/BOOTAA64.EFI   (systemd-boot, the bootloader)
         |  reads its own configuration, shows a menu
         v
  3. a boot entry            (a text file naming a kernel, an initramfs and a DTB)
         |
         v
  4. the kernel + initramfs + DTB, loaded into memory together
         |  the kernel reads the DTB and now knows what hardware it is on
         v
  5. the root filesystem     (mounted from the NVMe, init starts)
```

Two details differ from a PC:

**The `aa64` in `BOOTAA64.EFI`** is the ARM equivalent of a PC's
`x64`. Firmware looks for that filename as its fallback when no boot
entry is configured. The stick carries a copy under that name.

**Step 4 is where the device tree gets attached.** Two ways:

- *The bootloader hands it over.* The boot entry names the DTB with a
  `devicetree` line, as it names the kernel. The default here.
- *A firmware driver finds it.* **dtbloader** sits in the ESP. The
  firmware loads it, it identifies the machine and picks the matching
  DTB from a directory.

This blueprint installs both and offers a boot entry for each. When a
machine gives no output at all, a second mechanism to try is worth
more than a theory to test.

---

## 6. Stage 1 — Windows housekeeping

**Status: proven, 2026-09-18 and -19.** Do these in order. The order
is the point.

### 6.0 Getting through Windows setup

Two obstacles before the desktop.

**The function keys are not keys.** A capacitive touch strip sits
where F1–F12 belong and shows media controls by default. Hold `Fn`
and the strip shows the function keys. `Fn`+`Esc` locks it there.
Every `Shift`+`F10` in this chapter means `Fn`+`Shift`+`F10`, or a
plain `Shift`+`F10` once the row is locked. `Esc` and `Delete` sit at
the ends of the strip and do not toggle.

**Make a local account, not a Microsoft one.** At the setup screen
press `Shift`+`F10` for a command prompt and run:

```
start ms-cxh:localonly
```

That opens the local-account dialog. Recent Windows 11 builds have
removed every visible route to it. Leave the password blank and
Windows skips the three security questions. If the command does
nothing, the older path is:

```
reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE /v BypassNRO /t REG_DWORD /d 1 /f
shutdown /r /t 0
```

Verified on the factory image, 2026-09-18.

Nothing here needs a Microsoft account. Firmware updates arrive
through Windows Update and Dell Update regardless.

### 6.1 Boot Windows once and update the firmware

Sign in, let it finish its first-run work, and take every firmware
update on offer. This is why the Windows partition survives.

**Plug the charger in first.** Dell firmware updates refuse to run on
battery. The symptom is an update button that does nothing.

Three delivery routes, and they do not carry the same set. Do not stop
after the first one comes back empty:

1. **Dell's own updater**: *Dell Update*, *Dell Command | Update* or
   *SupportAssist*, whichever Dell installed. Scan, and take every
   driver and firmware. Decline the "optimize your PC" and
   hardware-scan features. SupportAssist may crash while updating
   itself; restart it. The flash does not happen inside Windows, so an
   updater crash is not a firmware problem.
2. **Windows Update**, then **Advanced options → Optional updates →
   Driver updates**. Dell firmware sits there, and nothing on that
   page installs unless you tick it.
3. **By hand** from the support site, by service tag. One executable
   stages the same capsule.

Then **scan again**. BIOS versions chain: a machine on one version is
offered the next, which offers another. Repeat until two consecutive
scans come back empty.

**A BIOS update does not install inside Windows.** It stages a capsule
and reboots. The flash happens at power-on: the Dell logo, a progress
bar, several black screens over five to ten minutes. It looks like a
dead machine. Do not touch the power button.

**Take the non-firmware drivers too.** Linux will never load them. A
Windows partition where the speakers, camera and fingerprint reader
work is a measuring instrument: when one of them is silent under
Linux, it says whether the hardware is fine or you broke something.

There is no separate embedded-controller update. The EC firmware
rides inside the BIOS capsule.

Note the **BIOS version**. Open **PowerShell** (`Win`+`X` → Terminal)
and run:

```
(Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion
```

It must be PowerShell. The old command prompt answers
`SMBIOSBIOSVersion was unexpected at this time`. From `cmd`, this
works:

```
reg query "HKLM\HARDWARE\DESCRIPTION\System\BIOS"
```

Neither needs administrator rights. `msinfo32` shows the same in a
window. `wmic` is gone from recent Windows 11 builds.

### 6.2 Turn the encryption off — before touching Secure Boot

From an Administrator prompt:

```
manage-bde -status C:
manage-bde -off C:
manage-bde -status C:
```

The first line shows what you are about to undo. Repeat the third
until it reads `Fully Decrypted`, `Percentage Encrypted: 0.0%`,
`Protection Off` and `Key Protectors: None Found`, all four. Settings
→ Privacy & security → Device encryption may offer no usable toggle in
this state. The command works.

**If the percentage stalls, reboot.** Conversion state lives on disk
and is re-evaluated at boot. Restarting mid-conversion is safe.
Conversion also pauses on battery, so check the charger.

The next stage needs a volume that is **not mid-conversion**. Disk
Management refuses to resize one that is still converting. Fully
encrypted is as good a resting place as fully decrypted.

**Why the volume is encrypted, and why there is no key.** The factory
image ships *pre-provisioned* encryption, with a local account or
without one. The volume is encrypted with a key held in the clear on
the disk, so that switching device encryption on later only has to
add protectors. Until then `manage-bde -status` reports:

```
Conversion Status:    Encryption in Progress
Protection Status:    Protection Off
Key Protectors:       None Found
```

Encrypted, unprotected, no recovery key. There is nothing to recover
from. `manage-bde -protectors -get C:` says so with an error.

A recovery-key prompt after a firmware change needs a protector that
binds the volume to the boot chain. None exists. Secure Boot can be
flipped on a volume in this state and Windows asks for nothing. Turn
the encryption off anyway. It costs one command and removes the
chance of it arming itself later.

### 6.3 Make room

From an Administrator command prompt:

```
powercfg /h off
```

Then, in the graphical settings: System protection off for `C:`, and
the page file set to none (System → About → Advanced system settings →
Performance → Advanced → Virtual memory). **Reboot.** Windows shrinks
a partition only down to its last unmovable file, and three features
plant unmovable files near the end of the disk: the hibernation image
(`hiberfil.sys`, which `powercfg /h off` deletes), the page file, and
System protection's store.

Right-click the Start button → Disk Management → right-click `C:` →
Shrink Volume. Leave Windows **150 GB**. It idles at about 30 GB, and
150 leaves room for Windows-only Dell and Qualcomm utilities.

> **Addendum 6.1 — if Windows refuses to shrink far enough.** Do not
> reach for a third-party partition tool. Re-run `powercfg /h off`,
> confirm the page file is gone, disable Windows Search indexing on
> `C:`, reboot, and try again. If it still refuses, accept the number
> it offers.

Shrink `C:` and nothing else. **DO NOT DELETE THE WINDOWS BOOT ENTRY,
AND DO NOT TOUCH ITS ESP. LINUX GETS ITS OWN.**

### 6.4 Turn Secure Boot off

Reboot and press **F2** at the Dell logo to enter firmware setup.
Find Secure Boot and disable it. Windows still boots with it off.

**The capacitive row gives you a window for F2.** At power-on the
strip shows media icons for about three seconds, then F1–F12 for
about five, then the icons again. The five seconds are the window. A
press outside it is swallowed and looks like F2 not working. A USB
keyboard has no window. Or skip the press. From an elevated prompt in
Windows:

```
shutdown /r /fw /t 0
```

That reboots straight into firmware setup. The same window serves F12
for the boot menu in chapter 8.

**DO NOT DELETE THE WINDOWS BOOT ENTRY, AND DO NOT TOUCH ITS ESP.
LINUX GETS ITS OWN.**

---

## 7. Stage 2 — Build the install stick

**Status: proven.** Everything in this chapter happens on your *other*
Linux machine.

Three scripts ship with this blueprint. Details follow in their
sections.

| Script | Does | Runs on |
|---|---|---|
| `PKGBUILD`, or `scripts/fetch.sh` | Downloads the payload and verifies every checksum (§7.3) | the other machine |
| `scripts/build-stick.sh` | Partitions the stick and writes the live system, the boot entries and the payload onto it (§7.4, §7.5) | the other machine |
| `scripts/install.sh` | Rides on the stick. Installs ARMtix onto the internal disk (§9.2) | the laptop, from the stick |

### 7.1 Why the stick has this shape

The stick carries three partitions:

| # | Size | Label | What it holds |
|---|---|---|---|
| 1 | 512 MB, FAT32 | `ARMESP` | The bootloader, the kernel, the initramfs and this laptop's DTB — everything the firmware needs to start something |
| 2 | 6 GB, ext4 | `ARMLIVE` | A complete **Arch Linux ARM** system, which is what you will be running while you install |
| 3 | rest, ext4 | `ARMPAYLOAD` | The parts of the installed system, kept separate until stage 4 assembles them: the ARMtix root filesystem tarball as published (it still carries ARMtix's own kernel, which the installer removes), **Arch Linux ARM's** kernel package and its three firmware packages, the tools the live root lacks, and `install.sh`. Everything stage 4 needs, so stage 4 needs no network at all |

The live system on partition 2 is **Arch Linux ARM, not ARMtix**.
Three reasons:

1. ARMtix publishes **no aarch64 EFI bootloader**. Artix's
   systemd-free systemd-boot package is x86-64 only. ARMtix ships
   GRUB, Limine and rEFInd.
2. **ARMtix's kernel will not boot this laptop** (§7.2).
3. Arch Linux ARM's generic tarball is a known-good environment on
   this chip, and it stays useful as a rescue stick.

The live system is borrowed. Only the installed system is ARMtix.
Both are Arch derivatives and their package files are the same
format.

Two things are added to the borrowed system:

- **The Qualcomm firmware split.** Since 2026 `linux-firmware` is
  split, and the Qualcomm part, with the GPU zap shader[^zap], the
  DSP firmware and the battery manager, is a separate package. Without
  it the GPU does not initialise.
- **Boot, disk and network tools**: `efibootmgr` and `gptfdisk` for
  the install; `dosfstools`, because the generic tarball ships neither
  `mkfs.vfat` nor `partprobe` (§9.2); `wpa_supplicant` and `iw` for
  Wi-Fi.

### 7.2 Why ARMtix's own kernel will not do

**Install ARMtix, then put Arch Linux ARM's kernel package on top of
it and pin it**, so that an update cannot replace it with one that
cannot boot.

ARMtix's `linux-aarch64` at 7.1.5 was built with these options
**off**:

| Option | What it drives |
|---|---|
| `PINCTRL_X1E80100` | Pin control — which physical pins are wired to what. Without it, essentially nothing works |
| `INTERCONNECT_QCOM_X1E80100` | The buses between blocks inside the SoC |
| `SND_SOC_X1E80100` | Audio |
| `DISPCC`, `GPUCC` | The clock controllers for display and GPU |

Arch Linux ARM's `linux-aarch64` at 7.2.6 has them all **on**, with
pin control, interconnect and the global clock controller built in
rather than as modules. A driver needed to reach the disk cannot live
in a module on the disk.

ARMtix's kernel configuration is not derived from Arch Linux ARM's:
it is a separate profile that never carried the Qualcomm platform layer
these laptops need, while Arch Linux ARM's has had it on since before
7.1.5.
A merge request to ARMtix closes that gap (chapter 11); until it is
merged and shipped, the pin of §9.2 is how you live with it.

### 7.3 Fetch the payload

You fetch nothing by hand. The `PKGBUILD` at the top of the
repository is the list: every file, its URL and its checksum. On an
Arch-family host, from the top of the repository:

```sh
gpg --recv-keys 68B3537F39A313B3E574D06777193F152BDBE6A6   # Arch Linux ARM's build key, once
makepkg -o        # downloads every source, verifies every checksum, builds nothing
```

On any other Linux:

```sh
scripts/fetch.sh  # reads the same PKGBUILD; the same downloads and the same checks
```

Either one puts about 2.2 GB into the top of the repository, or into
`$SRCDEST` if you export one, fetched over HTTPS from the two
distributions and from the dtbloader releases page, and refuses to
finish on a checksum mismatch. That directory is what
`build-stick.sh` reads.

What they fetch:

- Arch Linux ARM's generic aarch64 root filesystem tarball, from
  `os.archlinuxarm.org`.
- The ARMtix s6 root filesystem tarball, from
  `armtix.artixlinux.org/images/`.
- Arch Linux ARM's `linux-aarch64` kernel package, 7.2.6 or newer, and
  its `.sig`, from the `core` repository.
- Arch Linux ARM's `linux-firmware-qcom`, `linux-firmware-atheros` and
  `linux-firmware-whence`, dated 20260916. Not ARMtix's: same names,
  same versions, but compressed in a format the kernel cannot read
  (§9.4). Not the `linux-firmware` meta package: it depends on vendor
  splits the payload does not carry.
- `efibootmgr`, `efivar`, `popt` from both; `gptfdisk`, `dosfstools`,
  `wpa_supplicant`, `iw`, `pcsclite` from Arch Linux ARM.[^pcsc]
- `dtbloader.efi` from the dtbloader releases page.

> **Addendum 7.1 — signatures versus checksums.** A checksum proves
> the file arrived intact. A **GPG signature** proves who made it.
> Every file is pinned by checksum in the `PKGBUILD`. The kernel
> package also carries Arch Linux ARM's signature, and `makepkg`
> verifies it, which is why the key import above comes first; the
> key's fingerprint is the one in the `PKGBUILD`'s `validpgpkeys`, and
> the one Arch Linux ARM ships in its own keyring. To trust the
> checksum alone, `makepkg -o --skippgpcheck`. `fetch.sh` checks
> checksums only. The installed system never sees the signature:
> ARMtix's repositories are unsigned anyway (addendum 10.1).

> **Addendum 7.2 — version drift, and the tarball that disappears.**
> Every version in the `PKGBUILD` is what the servers carried on
> 2026-09-22. Newer is fine and usually better. The hard requirements:
> a kernel with the X1E80100 options on (7.2.6 and later qualify);
> `linux-firmware` from 20260910 or later, when the Dell 9345 blobs
> landed; `linux-firmware-atheros` from 20260916 or later, because the
> January Wi-Fi firmware never finishes the handshake; and firmware
> files the kernel can actually read (both §9.4). Two of the files
> move under you. **ARMtix rotates its root filesystem tarballs and
> deletes the old ones**: the January image this blueprint was
> installed from vanished on 2026-09-21, the day the September images
> appeared, and a fetch of it returns a 404 page. **Arch Linux ARM
> regenerates its `-latest` tarball in place** under the same name, so
> its checksum changes without warning. When `makepkg -o` stops on
> either, read the current name from `armtix.artixlinux.org/images/`
> and its checksum from the `sha256sums` file beside it, or the new
> checksum from the `.md5` beside the Arch Linux ARM tarball, put them
> in the `PKGBUILD`, and run again. Or open an issue; the pin will be
> refreshed.

### 7.4 Write the stick

`scripts/build-stick.sh` does the whole of §7.5 in one run, from the
top of the repository:

```sh
sudo scripts/build-stick.sh /dev/sdX
```

It reads the payload from where §7.3 put it (export the same
`SRCDEST` if you used one), refuses a non-removable device, shows you
the disk, and makes you type the path a second time before it erases
anything. Find the path with `lsblk` and check the size and model
twice. A loop device is accepted too, for a rehearsal against a disk
image. One step runs inside the ARM live system it has just unpacked
(step 6 below), so on an x86-64 machine the script checks for
`qemu-user-static`'s binfmt registration first and stops with a
message if it is missing.

### 7.5 What it does, step by step

For installing by hand, or debugging a stick that will not boot.

1. **Partition.** A GPT partition table[^gpt], then the three
   partitions of §7.1: type `ef00` (EFI system) for the first, `8300`
   (Linux filesystem) for the others. FAT32 on the ESP, the only
   filesystem the firmware reads; ext4 on the other two.
2. **Unpack the live system** onto partition 2 with `bsdtar -xpf`.
   The `-p` preserves permissions.
3. **Unpack the firmware and tool packages into it.** Unpack, not
   install. Package files are compressed archives with metadata at the
   front. Extracting them with the metadata excluded puts the files in
   place without a package database. Correct for a throwaway live
   system.
4. **Confirm the DTB is there**:
   `boot/dtbs/qcom/x1e80100-dell-xps13-9345.dtb` inside the unpacked
   root. If it is missing, the kernel in that tarball is too old.
5. **Write an `/etc/fstab`** naming the three partitions by label. The
   live system mounts its ESP at `/boot` and the payload at
   `/mnt/payload`.
6. **Regenerate the initramfs inside the live root, naming the
   modules.** The fault this step fixes: the tarball's own initramfs
   was made by relying on mkinitcpio's *autodetect*, which keeps only
   the modules the machine generating the image is using. That
   machine was Arch Linux ARM's build host, so the image holds
   exactly one module, a compressor, and misses everything this
   architecture needs before it can boot from USB. On this laptop a
   USB-C port is not a host port until a chain of modules is up: the
   eUSB2 PHY and its repeater, the Type-C mux, the PMIC glink client,
   UCSI, and the DSP that answers them (`usb-primer.md` beside this
   document walks the chain). A stick booted with the tarball's image
   never sees itself: the kernel prints, then waits forever for
   `/dev/disk/by-label/ARMLIVE`. The fix: autodetect is turned off,
   and `scripts/live.mkinitcpio.conf` names the modules outright and
   lists the board's firmware, so the DSP can boot inside the
   initramfs. The script copies that file into the live root's
   `/etc/mkinitcpio.conf.d/`, bind-mounts `/dev`, `/proc` and `/sys`,
   and runs mkinitcpio in a chroot of the live root, with the `kms`
   step off too so the display driver stays out of the image: about
   400 modules, 50 MB, well under the loader's limit (§12.8). The
   chroot runs ARM binaries, which is why an x86-64 build machine
   needs `qemu-user-static` and its binfmt registration (chapter 4).
   Found on 2026-09-22: the first stick written by the published
   script skipped this, and the image was the whole difference.
7. **Populate the ESP**: the kernel image, the initramfs, the DTB in
   two places (one for the boot entry, one for dtbloader),
   `systemd-bootaa64.efi` at both `EFI/BOOT/BOOTAA64.EFI` and
   `EFI/systemd/`, and `dtbloader.efi` under `EFI/systemd/drivers/`.
8. **Write three boot entries:**

   | Entry | Differs how | Use when |
   |---|---|---|
   | `live` | DTB named by the boot entry | the default |
   | `live-safe` | same, plus `clk_ignore_unused pd_ignore_unused loglevel=7` | the screen goes black — see §9.3 |
   | `live-dtbloader` | no DTB in the entry; the dtbloader driver supplies it | the default entry produces nothing at all |

   All three carry `mem=31G` on their `options` line. Without it the
   live system does not survive its first minute. §8.1 has the reason.

9. **Copy the payload** onto partition 3: the ARMtix tarball, the
   kernel package, the three firmware packages, ARMtix's `efibootmgr`
   and its two libraries, `dtbloader.efi`, `install.sh`, this document
   and its companion, and a `SHA256SUMS` file the installer checks
   before it touches the disk. Then `sync` before unplugging.

A verified stick shows roughly: 512 MB ESP with about 94 MB used, a
2.6 GB live root, a 1.4 GB payload.

---

## 8. Stage 3 — Boot the live system

**Status: proven, 2026-09-19, only with `mem=31G`; proven again on
2026-09-23 on a stick written by the published script (§7.5, step 6). Read §8.1 before your first
boot.**

Plug the stick in, power on, press **F12** at the Dell logo in the
five seconds the capacitive row shows F1–F12 (§6.4), and choose the
USB device. The menu shows the three entries from §7.5. Take `live`.

Expect a wall of kernel messages and then a login prompt, inside a
minute. (A stick built by hand from the tarball also pauses twice for
about 90 seconds, §8.2; the published stick does not.) Arch Linux ARM's documented
credentials are `root` / `root` (and a normal user `alarm` / `alarm`).
Log in as root.

Sanity checks, in order:

```sh
ls /sys/firmware/efi        # if this is missing, you booted in legacy mode — go back to F12
free -g                     # about 30, not 64: that is mem=31G doing its job, §8.1
lsblk                       # the internal disk must appear, usually /dev/nvme0n1
ip link                     # network interfaces; the Wi-Fi one is usually wlan0
```

If you need Wi-Fi at this point:

```sh
wpa_passphrase '<your-ssid>' > /etc/wpa_supplicant/wlan0.conf   # then type the password
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wlan0.conf
dhcpcd wlan0
```

Nothing in stage 4 needs the network. This is for comfort.

**If the screen stays black**, go to §9.3 before doing anything else.
**If the machine resets itself** seconds after the kernel starts
printing, that is §8.1, and it is not a black-screen problem.

### 8.1 Why `mem=31G`, and why not 32

**The symptom.** The kernel boots, prints for a few seconds, and the
machine hard-resets. No panic, no message, back to the Dell logo.
Sometimes it reaches a login and dies at the first disk or USB
traffic. `dmesg` shows the NVMe controller reporting a bus error
(`AER`) about a second into the boot. The `-safe` entry makes no
difference. Blacklisting drivers moves the moment of death and never
removes it.

**The cause.** Linux does not run on the bare metal here. Qualcomm's
firmware keeps a hypervisor (Gunyah) resident at **EL2** and starts
the operating system one privilege level down, at **EL1**. The
hypervisor decides which physical memory the SoC's DMA masters, the
disk controller, the USB controllers and the GPU, may reach. It does
not grant them the top 32 GiB. The CPU can use that memory. The first
device pointed at it resets the SoC. A kernel with all 64 GB allocates
a disk buffer up there almost at once and is dead within seconds.

The physical layout, from the kernel's memory map:

| block | where | size |
|---|---|---|
| low | below 4 GiB | about 2 GiB |
| middle | from `0x8_8000_0000` | 30 GiB |
| high | `0x88_0000_0000` – `0x8f_ffff_ffff` | 32 GiB, **unreachable by DMA at EL1** |

**The fix.** `mem=31G` on the kernel command line, on every boot
entry of the stick and of the installed system. The parameter is a
size, not an address: it keeps the first 31 GiB counted from the
bottom. The low and middle blocks hold 31.505 GiB together, so 31G
takes all of them and nothing above. **32G would keep 507 MiB of the
high block** and the machine would die on the first buffer that
landed there. Linux then reports about 30 GB.

**What does not work:**

- Restoring the older device tree. Until November 2025 the tree
  described the bus as 36 bits wide, and the kernel bounced every DMA
  above 64 GiB through a low buffer. The patch that widened it to 40
  bits (commit `b38dd256e11a`, "arm64: dts: qcom: x1e: bus is
  40-bits") exposed the limit. Putting the 36-bit values back does not
  help: the USB controllers sit behind an IOMMU the kernel programs,
  so the bus width bounds nothing for them, and the hypervisor's limit
  applies to every master.
- `iommu.passthrough=1` with the 36-bit tree. The hypervisor refuses
  to bypass the IOMMU. The display goes with it and the machine freezes
  early instead of resetting.
- A kernel built with 39-bit virtual addresses. Same cut in disguise:
  a 39-bit linear map cannot reach the high block, so the kernel drops
  it.

**Getting the rest back** is not an install-time concern. Two possible
roads: booting the kernel at EL2 through `slbounce`, an EFI program
that takes the hypervisor out of the picture, or a Dell firmware
release that lifts the limit. BIOS 2.14.0 does not. **slbounce is
untested here.** Nothing in this document says whether it works on
this machine.

### 8.2 Two long pauses at boot, and why they are not yours

A live system built by hand from the tarball waits about 90 seconds,
twice, before the login prompt: once for a serial console the device
tree names but the laptop does not wire out (`ttyMSM0`), once for a
TPM the firmware does not expose. Both are the tarball's systemd
defaults for other boards. Harmless. `build-stick.sh` masks the two
units (`serial-getty@ttyMSM0.service` and `tpm2.target`), and a stick
it wrote went from the boot menu to the login with no wait at all
(2026-09-22). On a stick built by hand, expect the pauses.

---

## 9. Stage 4 — Install onto the internal disk

**Status: proven, 2026-09-19. Read §9.2 before running anything.**

### 9.1 The partition plan

Stage 1 left a hole on the disk. The install fills it and touches
nothing else:

| # | Owner | Size | What |
|---|---|---|---|
| 1 | Dell | ~300 MB | Windows' ESP — **untouched** |
| 2 | Dell | 16 MB | **MSR**, a reserved Microsoft area — **untouched** |
| 3 | Dell | 150 GB | Windows `C:`, shrunk in stage 1 |
| 5 | **new** | 1 GB, FAT32 | Linux ESP, mounted at `/boot` |
| 6 | **new** | = your RAM | swap |
| 7 | **new** | 64 GB, ext4 | `/tmp` (optional, see below) |
| 8 | **new** | the rest | `/`, the root filesystem |
| 4 | Dell | 1–2 GB | **WinRE**, the Windows recovery partition, at the tail — **untouched** |

The numbering looks wrong and is not: Dell's four partitions were
created first and keep their numbers, the new ones go into the hole
in the middle, and the recovery partition stays at the end of the
disk with its original number 4.

**DO NOT DELETE THE WINDOWS BOOT ENTRY, AND DO NOT TOUCH ITS ESP.
LINUX GETS ITS OWN.** Partition 5 is that ESP. Partition 1 stays as
Dell left it.

Two choices:

- **Swap equal to RAM.** Needed only for **hibernation**, which writes
  all of memory into swap. Hibernation on this machine is untested.
  Without it, 8–16 GB is plenty.
- **A separate 64 GB `/tmp`.** A habit. It stops a runaway program
  filling the root filesystem. Drop it and give the space to `/` if
  you prefer.

### 9.2 What the installer does

From the live system:

```sh
mount -L ARMPAYLOAD /mnt/payload
sh /mnt/payload/install.sh /dev/nvme0n1
```

It prints every step, and asks you to type the disk path again before
it creates any partition. In order, it:

1. **Checks** that it is running as root, that the target is a real
   block device, that the machine booted via UEFI, that every tool it
   will call exists, and that the payload matches its `SHA256SUMS`.
2. **Creates the four partitions** in the largest free region and
   makes the filesystems. Three, with `TMP=0` in the environment: no
   separate `/tmp`.
3. **Unpacks the ARMtix root filesystem tarball** onto the new root.
4. **Moves `/boot` onto the ESP.** The kernel must live where the
   firmware can read it, so the tarball's `/boot` contents are copied to
   the ESP and the ESP is then mounted at `/boot`. From then on,
   writing a kernel to `/boot` writes it where the firmware will look.
5. **Writes `/etc/fstab`**, naming every filesystem by **label**
   rather than by device path. Device paths shift when you plug in a
   USB disk; labels do not.
6. **Sets hostname, timezone and locale.** The four settings at the
   top of the script: `HOST=sokath`, `LOGIN=user` (your account),
   `TZ=Etc/UTC`, `LOCALE=en_US.UTF-8`. Edit them before running;
   `ls /usr/share/zoneinfo` lists the timezones. The hostname also
   names the partition labels (`SOKATHESP`, `sokath-swap`,
   `sokath-tmp`, `sokath`) and the boot entries, so keep it short: the
   ESP label has eleven characters to spend.
7. **Trims the initramfs configuration, and writes two small files
   for the first boot.** ARMtix's default initramfs configuration is
   aimed at single-board computers and forces in modules this laptop
   does not have. `/etc/modules-load.d/` gets one line naming
   `qcom_pd_mapper`, without which the installed system has no USB
   and no Type-C (§9.4); `/etc/vconsole.conf` gets a 16×32
   console font, because the kernel's built-in 8×16 is unreadable on
   a 2880×1800 panel.
8. **Pins the kernel and its firmware.**
   `IgnorePkg = linux-aarch64 linux-firmware-qcom linux-firmware-atheros linux-firmware-whence`
   goes into `/etc/pacman.conf`, so that a later system update cannot
   replace the working kernel with ARMtix's own, nor the readable
   firmware with ARMtix's compressed files (§9.4). **Remember this
   line exists.** It comes off the day ARMtix ships a kernel with the
   X1E80100 options (chapter 11). The [update
   companion](artix-on-xps13-9345-updates.md) is how you live with it
   until then.
9. **Enters a chroot**[^chroot] and, inside it, removes ARMtix's
   headers and its long-term-support kernel, installs Arch Linux ARM's
   kernel package plus the firmware packages, regenerates the
   initramfs, and deletes the fallback image the tarball's own `/boot`
   brought along: 170 MB that nothing points at and that this
   firmware must never load (§12.8).
10. **Installs the bootloader**: `systemd-bootaa64.efi` copied from
    the live system, the one piece borrowed rather than packaged;
    dtbloader as a driver; two boot entries, the default and a verbose
    one with the bring-up flags; and an `efibootmgr -c` call that
    registers the entry with the firmware for the F12 menu. There is
    **no fallback-initramfs entry, on purpose**: this firmware resets
    the machine before the kernel runs when the loader reads an initrd
    larger than about 224 MB, and the fallback image is 272 MB by
    construction (§12.8). The kernel package ships that preset off;
    the script leaves it off.
11. **Asks for a root password**, creates your user in the `wheel`
    group with passwordless `sudo`, and asks for its password. Edit
    `/etc/sudoers` afterwards if you want to be asked.

Nothing in that list touches Windows, its ESP or its recovery
partition. The firmware ends up listing both systems. Installing by
hand: **DO NOT DELETE THE WINDOWS BOOT ENTRY, AND DO NOT TOUCH ITS
ESP. LINUX GETS ITS OWN.**

**Before it touches the disk, the script checks for every tool it
will call.** Arch Linux ARM's generic tarball ships neither
`partprobe` nor `mkfs.vfat`. The stick unpacks `dosfstools` into the
live root (§7.1), and the script re-reads the partition table with
`blockdev --rereadpt` from `util-linux`. It also **resumes**: if the
four partition labels exist it skips partitioning, confirms once, and
formats. Installing by hand, check for those two tools first.

### 9.3 When the screen goes black

Power light on, screen never lights, machine reboots after a while.
Almost always the device tree. A machine that resets seconds after
the kernel starts printing is §8.1, not this list; a kernel that
printed and then waits on a start job for `ARMLIVE` is §7.5, step 6,
not this list either.

1. **Try the `live-dtbloader` entry.** If that boots, the boot entry's
   `devicetree` line is at fault: a typo in the path, or the DTB
   missing from `/dtbs/qcom/` on the ESP.
2. **Try the `-safe` entry.** `clk_ignore_unused` and
   `pd_ignore_unused` stop the kernel switching off clocks and power
   domains it thinks nothing uses. Switching off the display
   controller's clock produces this symptom. `loglevel=7` makes the
   kernel verbose.
3. **Check the DTB filename** against what the kernel produced:
   `ls /boot/dtbs/qcom/ | grep 9345` in the live system.
4. **Confirm Secure Boot is off** (§6.4).
5. **Serial console**, if you have the adapter.

### 9.4 What the installer adds, and why it has to stay

Following the script, you meet none of this. Two of the installer's
steps are rules the installed system must keep obeying. A hand
install, a different tarball or a package bump breaks them. Broken,
each looks like a hardware fault. The symptoms are in chapter 13.

**Firmware the kernel can read.** ARMtix packages every file under
`/usr/lib/firmware` **zstd-compressed** (`.zst`). The Arch Linux ARM
kernel reads `xz`-compressed firmware and nothing else
(`CONFIG_FW_LOADER_COMPRESS_XZ=y`, `CONFIG_FW_LOADER_COMPRESS_ZSTD`
unset). To that kernel every ARMtix firmware file is invisible. The
DSP never starts (`request_firmware failed: -2`), the Wi-Fi driver
times out (`ath12k … -110`), the GPU cannot load its zap shader.

The installer puts **Arch Linux ARM's** `linux-firmware-qcom`,
`linux-firmware-atheros` and `linux-firmware-whence` on the ARMtix
root, same names, same versions, uncompressed, and **pins all three**
beside the kernel (§9.2 step 8). Without the pin the next
`pacman -Syu` reinstalls ARMtix's compressed set over them, since the
version strings are equal. A reboot in that state has no Wi-Fi and no
DSPs. Recovery is the same install with `--overwrite`:

```sh
pacman -U --overwrite '/usr/lib/firmware/*' \
    linux-firmware-qcom-*.pkg.tar.xz linux-firmware-atheros-*.pkg.tar.xz \
    linux-firmware-whence-*.pkg.tar.xz
mkinitcpio -P
```

A one-off `find /usr/lib/firmware -name '*.zst' -exec unzstd -q --rm {} +`
also works, but leaves files pacman does not own. The proper fix is a
kernel that reads zstd, one configuration line; it is part of the
merge request chapter 11 describes.

The atheros package must be 20260916 or newer. The January 2026 set
in the ARMtix tarball associates and then times out in the WPA 4-way
handshake every time, and scans fail with `-16` (busy). The September
set connects first time.

**The protection-domain mapper.** The Type-C ports are managed
through a service on the DSP. The kernel finds the DSP's services
through a module, `qcom_pd_mapper`, that nothing on the ARMtix root
loads. The installer writes one line, `qcom_pd_mapper`, into a file
under `/etc/modules-load.d/`. s6's `modules` service reads that
directory at boot. Without it the installed system has no Type-C and
no USB: `/sys/class/typec` stays empty and no USB device is ever
seen.

**Wi-Fi under s6.** The tarball ships the `wpa_supplicant` service
but not its configuration. The service reads the interface name from
`/etc/s6/config/wpa_supplicant.conf` (default `wlan0`) and the network
from `/etc/wpa_supplicant/wpa_supplicant.conf`, which does not exist.
Write the latter (`wpa_passphrase` generates it), then

```sh
s6 set enable wpa_supplicant
s6 set commit
s6 live install
```

`s6` is the front end this document uses for every service operation.
§10.2 introduces it. The older pair in the Artix wiki,
`s6-service add default …` then `s6-db-reload`, edits the same
database. Pick one vocabulary and stay with it.

Install `wireless-regdb` and set your country (`WIRELESS_REGDOM` in
`/etc/conf.d/wireless-regdom`, `country=` in the supplicant file). The
tarball has neither.

---

## 10. Stage 5 — First boot and setup

**Status: proven, 2026-09-19, through to a Wayland desktop on the
GPU.** Most of it was done over `ssh` from the second computer once
the first update had gone through. Typing on the laptop at the
console font is slow.

Reboot, F12, choose `sokath`. The default entry reaches a login
without the bring-up flags. Log in as the user the installer created.

### 10.1 The first update, and its three traps

```sh
sudo pacman -Syu                # first full update
```

> **Addendum 10.1 — unsigned repositories.** As of 2026-09-16
> ARMtix's repositories are not signed, and its `pacman.conf` carries
> `SigLevel = Never`. Package downloads are trusted on the transport
> alone. Know it now rather than discover it later.

How big the update is depends on the tarball's age. The January 2026
tarball was some 150 packages behind its repositories, the whole s6
stack among them; the September one was published current. Three
things in a large update look like breakage and are not:

1. **`Error: invalid service database in /run/s6-rc/db`** on the
   console, when the update moves `s6-rc` to a new database format
   (it did, between the January and the September tarballs). The hook
   compiles a fresh boot database. The error is about the old compiled
   directories beside it, which are dead. The next reboot is safe.
2. **Your `ssh` session drops at key exchange** when `openssh` is
   upgraded. Restart the daemon at the keyboard:
   `sudo s6 process restart sshd-srv`.
3. **The firmware comes back compressed** unless the pin from §9.2
   step 8 is in place. Then the next reboot has no Wi-Fi and no DSPs
   (§9.4). After the update, `ls /usr/lib/firmware/qcom/*.zst` must
   print nothing.

**NEVER TYPE `pacman -Syyuu` ON THIS MACHINE.** The repository's
kernel is older than the installed one. The second `-u` offers the
downgrade to the kernel that cannot boot this laptop, and pacman's
"ignore this package?" prompt defaults to yes. The [update
companion](artix-on-xps13-9345-updates.md) is the checklist for every
update after this one.

### 10.2 What the tarball does not have

Install before you miss them: `iw`, `which`, `wireless-regdb`,
`man-db` and `man-pages` (there is no `man` in the tarball),
`terminus-font`, `sshfs` if you mount anything, and a **font with
emoji**. The base font set has none, and `fc-match emoji` falls
through to a music-notation font. tyler's status bar (§10.3) draws
icon glyphs: add a Nerd Fonts symbols package and point the
`monospace` fontconfig alias at a family that carries them
(`~/.config/fontconfig/fonts.conf`). Prefer the non-`Mono` Nerd
variants; their icons keep their designed width.

Services are managed through the `s6` front end: `s6 set` for what
boots, `s6 live` for what runs now, `s6 process` for one supervised
daemon, each with a `help` subcommand. Package names carry an `-s6`
suffix. Logs are plain files under `/var/log/<service>/`. A
`systemctl enable something` from a web search does not apply here.
Two s6 facts:

- **A package's install hook adds its service to the database but
  not to the boot set.** After installing `bluez-s6`:
  `s6 set enable bluetoothd`, `s6 set commit`, `s6 live install`.
- The s6 wrapper is sometimes a **separate package** from the daemon
  (`openntpd` and `openntpd-s6`), and some pairs conflict
  (`elogind-s6` in the tarball against `seatd-s6`). Install the one
  you mean.

Then: a DHCP client or `connman` under s6; your public key in
`~/.ssh/authorized_keys` and `PasswordAuthentication no`; an NTP
client (`openntpd` + `openntpd-s6`; this laptop has no battery-backed
clock and drifts); `avahi` + `avahi-s6` + `nss-mdns` for
`sokath.local`; a syslog (`syslogd-s6`), since `journalctl` does not
exist. The s6 `dmesg` service keeps `/var/log/dmesg/current` across
boots. Leave it on. Raise its retention (§12.3).

**Any glob under `/boot` needs `sudo sh -c`.** The ESP is mounted
`dmask=0077` and the pattern expands as your user to nothing.

### 10.3 A desktop on the GPU

The desktop on this machine is **tyler**, a Wayland compositor in the
dwl lineage on **wlroots** 0.19: one binary, a `config.h`, no
protocol extensions beyond what wlroots gives it, and it exits cleanly
when the GPU resets under it (§12.3), which is what made the GPU
finding diagnosable. Source at `github.com/thinkoid/tyler`, packaged
on the AUR as `tyler-git` for x86_64 and aarch64 alike.

Any other compositor on wlroots 0.19 or later works the same way.
Mesa's freedreno driver is in the repositories (`mesa`,
`vulkan-freedreno`, `wlroots0.19`). Measured on 2026-09-19: the
compositor comes up from a VT login on `/dev/dri/card0` (`msm`),
OpenGL ES 3.2 on Adreno X1-85, the panel at 2880×1800 @ 60 Hz, and
`light` drives the backlight over the DisplayPort AUX channel.

Three things to have in place first:

- **Your user must be in the `seat` group** (and `video`, `input`,
  `audio`, `render`). seatd's socket is `root:seat` mode 0770. Without
  the group the compositor fails to take the seat, and the message
  does not say why.
- Check that the compositor advertises `linux-dmabuf`. Without it
  applications fall back to software rendering while the GPU sits
  idle.
- The panel is 252 DPI. Toolkits that size fonts at a fixed 96 DPI
  need two to three times their usual point size. Electron needs
  `--force-device-scale-factor=2`.

The GPU resets itself now and then. A compositor that does not treat
a lost GL context as fatal runs blind until you quit it (§12.3).

From here on the machine is yours to maintain: a pinned foreign
kernel, an ESP the kernel package writes into, firmware that must
stay uncompressed, a kernel command line that must keep `mem=31G`.
The [update companion](artix-on-xps13-9345-updates.md) is the
checklist. Chapter 12 is what the first days of use found.

---

## 11. The kernel pin — next step, not yet nailed down

At the end of stage 5 you are on a pinned foreign kernel: Arch Linux
ARM's, because ARMtix's had the X1E80100 options off and cannot read
ARMtix's own zstd-compressed firmware (§9.4). The fix is ARMtix's own
kernel recipe bumped to Arch Linux ARM's version and configuration,
plus `CONFIG_FW_LOADER_COMPRESS_ZSTD=y`; that package exists and boots
this laptop. It is filed with ARMtix as merge request !2 (2026-09-21),
carrying the battery fix of §12.1 and one more configuration line:
`CONFIG_LSM` naming `landlock`, without which pacman 7's download
sandbox fails on every download. Until their repository ships it, the
pin of §9.2 stays and the [update
companion](artix-on-xps13-9345-updates.md) is how you live with it.
The day it lands, and the steps that take the pin off, will be written
here once they have been done rather than predicted.

---

## 12. Living with it — what the first days found

Findings from the first three days of use, 2026-09-19 to -21, kernel
7.2.6. None of them stops the machine being a workstation. Each one
will meet the next person, and each looked like something else at
first.

### 12.1 The battery reports everything but the percent

The battery driver (`qcom-battmgr-bat`, talking to the charger
service on the DSP) exposes `energy_now`, `energy_full`,
`energy_full_design`, `voltage_now`, `temp`, `cycle_count`, the model
and manufacturer strings, and `status`. **No `capacity`.** Anything
that reads only `capacity`, most status bars, shows no battery. It is
a one-line omission: the property was added to the driver's SC8280XP
table in May 2025 (commit `3f87baacea4d`), and the X1E80100 table
made in September 2025 (commit `cc3e883a0625`) was copied without it.
A patch adding it went to `linux-pm` on 2026-09-20 and is reviewed.
Check whether your kernel has it. Until then, derive the percent:

```sh
d=/sys/class/power_supply/qcom-battmgr-bat
echo $(( 100 * $(cat $d/energy_now) / $(cat $d/energy_full) ))
```

A Bluetooth or USB keyboard's battery appears in the same directory
with `scope` = `Device`.

The driver's vocabulary: `status` says `Not charging` when the pack
is full on the charger; there is no `Full`. `energy_now` is **held at
`energy_full`** while the machine is on external power and drops to
the real figure at the first sample on battery. `power_now` goes
negative on discharge. `charge_control_start_threshold` and
`_end_threshold` read 0 and 0, the no-limit default, and are writable
by root (§12.6). A USB-C monitor with power delivery **runs the laptop
from the video cable**. To measure discharge, unplug both cables.

Measured, light interactive load (OLED at working brightness, Wi-Fi, a
terminal session, a Bluetooth keyboard): **6.9–7.2 W**. About 7.4
hours on the 52.8 Wh the pack held, 7.8 on a full 55 Wh. Idle not
measured.

### 12.2 The PHY that DisplayPort holds

A USB-C monitor works as a display, a charger and a USB hub on either
port. DisplayPort alt mode, power delivery and both halves of the hub,
SuperSpeed and the USB 2.0 side that mice and keyboards attach to,
come up together within a couple of seconds. Two things not to do
with such a port:

- **Do not unbind and rebind the USB controller** (`dwc3-qcom` on
  `a600000.usb` or `a800000.usb`) while a monitor is on that port. The
  port's USB 3 PHY is a *combo* PHY shared with the DisplayPort
  controller; while DisplayPort is driving the panel the PHY will not
  re-initialise (`phy init failed --> -110`), and the USB side of the
  port is then gone until a reboot.
- Do not read anything into `Failed to create device link (0x180)`
  lines for `typec-mux` or `pmic-glink` at boot. They appear on
  working boots too.

**The monitor's USB 2.0 hub sometimes does not come up.** The
SuperSpeed hub enumerates, the USB 2.0 hub never appears, mice and
keyboards on it stay dark, and about ten seconds later that port's
xHCI controller is declared dead (`HC died`). It happens on either
port and under Windows too, so it is not the device tree or any driver
in this document. Whether it is this unit, the model, or this laptop
with this monitor is unknown. Recipe: **when the mouse stays dark,
move the plug to the other port.** Three of four moves gave the hub.
A fault that fails half the plugs is not localised by one trial. Count
before concluding, and test under Windows before blaming Linux. Note
the plug orientation (`normal` / `reverse` under each port in
`/sys/class/typec`) on every attempt; it was `reverse` on every
success recorded and was not read on the failures.

**Do not move a charging panel between ports with the machine
running.** The fourth move above reset the machine at the plug: the
panel was the only power source, it left the left port, and the
machine went dark the instant it landed in the right one. No panic,
no log line, a reset from below the kernel. The three resets this
machine has shown all came from below the kernel, and the mechanism
is not known. Rule until it is: shut down, move the plug, boot. If
a hot move must happen, put the charger in the other port first.

**A port with a 4-lane DisplayPort link loses the whole hub, not
only USB 3.** Type-C pin assignment C gives DisplayPort all four
lanes, so the SuperSpeed hub cannot appear on that port. In principle
the USB 2.0 half, on its own pair of wires, keeps working. On this
laptop it does not. Every boot goes the same way until the display
driver starts, about two seconds in: the firmware left the port in
plain USB, the USB 2.0 hub is up, mouse and keyboard work. Then the
port switches to the negotiated DisplayPort mode and the hub
disconnects, on every boot. With two lanes (assignment D) the
SuperSpeed hub is back a second later, the USB 2.0 hub after it, and
everything works. With four lanes the controller's SuperSpeed port
keeps trying to address a device on lanes that now carry DisplayPort,
and the console fills for about forty seconds:

```
xhci-hcd xhci-hcd.1.auto: Timeout while waiting for setup device command
usb 2-1: device not accepting address 2, error -62
usb usb2-port1: attempt power cycle
usb usb1-port1: unable to enumerate USB device
```

Both halves of the port share that controller, and the USB 2.0 hub
never comes back. Mouse and keyboard stay dark until a reboot. The
firmware picks the lane count at each boot and does not say so;
consecutive boots with nothing changed went 4, 2, 2, 4, 2, 4. In 31
boots, every one with these timeouts had four lanes and every one
with two lanes had a working hub.

**Workaround, partial: ask the monitor for two lanes.** Dell monitors
call the setting *USB-C Prioritization* in the on-screen menu: *High
Resolution* allows four lanes, *High Data Speed* asks for two lanes
plus USB 3. Other makes have an equivalent, often called USB 3 or
data priority.
The laptop's DisplayPort runs at DisplayPort 1.4 rates (HBR3, 8.1
Gbit/s per lane), so two lanes still carry 3840×2160 at 60 Hz, at 8
bits per colour instead of 10. **Reboot right after changing it.**
Flipped with a session up, the link retrained at the slower HBR2
rate, which cannot carry 4K60 on two lanes, and the panel went black
until the reboot. After the boot, `dp_debug` should read:

```
rate = 810000
num_lanes = 2
bpp = 24
```

**The setting does not guarantee two lanes.** Tested on one monitor
(a Dell U2720QM): of the first three boots on *High Data Speed*, two
came up with two lanes and a whole hub, and the third negotiated four
lanes anyway, at the faster HBR3 rate and 10 bits per colour, with
the menu still reading *High Data Speed*. That boot lost the hub
exactly as above:

```
rate = 810000
num_lanes = 4
bpp = 30
```

So the setting shifts the odds and does not pin the mode; the lane
count is still chosen by the firmware at each boot, out of the
kernel's sight. When a boot comes up with four lanes, reboot. If the
mouse and keyboard must work on every boot, keep them off the
monitor's hub: Bluetooth, or the laptop's other port.

What a port negotiated is always in
`/sys/kernel/debug/dri/0/DP-*/dp_debug`. Read it before deciding a
hub is absent.

The port map, since bus numbers shuffle between boots: the right-hand
port is `port0` in `/sys/class/typec`, on controller `a600000.usb`;
the left-hand port is `port1` on `a800000.usb`; the fingerprint
reader is internal on `a400000.usb`.

### 12.3 The GPU resets, and the compositor goes blind

The GPU's management unit (GMU) sometimes fails a register write, and
the driver resets the GPU:

    platform 3d6a000.gmu: fenced register write (0x807) fail
    [msm] hangcheck detected gpu lockup rb 0!
    [msm] hangcheck recover!  offending task: <the compositor>

Seen twice on 2026-09-20, each about 30 seconds into a fresh
compositor session. The GMU also logs `delay in fenced register write
(0x807)` on its own, with no lockup and no USB activity. It misbehaves
by itself; a USB storm on the same boot at most tips a delay into a
failure.

What the reset does to a wlroots 0.19 compositor: the GL context is
lost, the compositor logs `GPU reset (guilty)` and then
`GL_CONTEXT_LOST` for every frame, input keeps working, nothing
redraws. wlroots does not rebuild the context. A compositor that does
not exit on a lost context runs blind and records a clean exit. tyler
exits with status 1 on the reset (§10.3).

The driver writes a GPU crash state to
`/sys/class/devcoredump/devcd*/data`. The device **deletes itself
after five minutes**. Copy it out within that window if you want
anything to report upstream.

**Spontaneous resets.** Three times in two days the machine reset
itself with no panic and no shutdown record: once seconds after a GPU
lockup, once at an unattended moment, once at a hot port move
(§12.2). Nothing on the kernel side can do that here: `panic=0`, the
hard lockup detector is unavailable on this CPU, no process holds the
watchdog, pstore is empty. The resets come from below the kernel.
Investigation ongoing. Two things to arm before the next one: log
retention above the s6 default (`n3` keeps three files and lost the
boot that mattered; `n30` in `/etc/s6/config/*.conf`), and a shorter
page-cache writeback so the last seconds reach the disk:

```
# /etc/sysctl.d/60-log-tail.conf
vm.dirty_expire_centisecs = 200
vm.dirty_writeback_centisecs = 100
```

With the stock 3000/500 a firmware reset takes the last 30 s of every
log with it. With these it takes about 3 s.

### 12.4 Off, and the lid that boots it

`halt -p` is a kernel `poweroff` through `s6-linux-init`, then PSCI
`SYSTEM_OFF` to the firmware. It is a full off: the SoC, its power
management IC and every light including the capacitive function row,
with or without a charger attached.

**Opening the lid boots a powered-off machine.** That is the
firmware's **Power → Lid Switch → Power On Lid Open**, on by default,
acting from full off. Turn it off in Setup if the self-boot bothers
you (a laptop shut down and put in a bag, opened later on a train,
boots). Leave **Enable Lid Switch** on; that one makes closing the
lid mean anything.

A 10-second hold of the power button is an EC-level power cycle. It
is not a second level of off; it is what brings the machine back
when it will not resume from suspend (§12.7), and what clears the
embedded controller after one of the firmware resets in §12.8 leaves
it in a strange state — a function row lit on a machine that is off
was seen once, right after two such resets, and never since.

### 12.5 Audio

**The four speakers work** (2026-09-23): both channels, volume
control, desktop and browser playback through PipeWire. **The
internal microphones work** too: PipeWire's `Internal microphones`
source, two channels from `hw:X1E80100DellXPS,3` through the UCM HiFi
profile, with nothing configured for them. Bluetooth audio works (`bluez`,
`bluez-utils`, `bluez-s6`, and the s6 boot-set step in §10.2), and so
does **USB audio**: a USB-C headset or a USB-C-to-3.5 mm adapter is a
USB Audio Class device with its own DAC, `snd-usb-audio` binds it on
the spot, and nothing on the SoC's audio path is involved.

**What the kernel needs.** Three pieces, none of them in the kernel
this document installs (Arch Linux ARM's 7.2.6) or in merge request
!2:

1. **The machine driver**, `CONFIG_SND_SOC_X1E80100=m`. Arch Linux
   ARM's configuration already has it.
2. **The sound node in the 9345's device tree**, not in mainline or
   linux-next yet: the out-of-tree series by Sibi Sankar and Alex
   Vinarskis, carried in
   [linux-x1e80100-dell-tributo](https://github.com/alexVinarskis/linux-x1e80100-dell-tributo).
   It describes four WSA8845 amplifiers on two SoundWire buses and the
   digital microphones. Without it `/proc/asound/cards` is empty.
3. **A volume fix in `lpass-wsa-macro`**: rewrite the digital volume
   register after the playback path's clock is enabled. Upstream
   removed that rewrite in 902f497a1ff5 (6.19); without it a volume set
   while nothing plays does not take effect when playback starts, so
   the speakers sit at whatever level they last played. Three lines in
   `wsa_macro_enable_interpolator()`, not upstream.

A kernel package carrying all three has run this laptop since
2026-09-23 and will be published with the kernel work of chapter 11.
Until then the pieces are the ones above. With the device tree
changed and the stock volume code, the speakers play and the volume
quirk of item 3 remains; that was tested with the machine driver
built separately, not on Arch Linux ARM's kernel itself.
The driver caps the amplifiers at -3 dB digital and 0 dB amplifier
gain; leave those caps alone, a wrong amplifier configuration can
damage the speakers.

**What userspace needs.** `alsa-ucm-conf` and the audio topology in
`linux-firmware` already carry this model; nothing to add there.
PipeWire, WirePlumber and `pipewire-pulse` (plus `rtkit`), started
with the graphical session: Artix starts no per-user services by
itself, so the compositor's startup or a small supervised tree has to
start them. Two WirePlumber fragments in
`~/.config/wireplumber/wireplumber.conf.d/`, and one PipeWire fragment:

```
# 51-xps13-speakers.conf
# Raw channel order: right woofer, left woofer, right tweeter, left tweeter.
monitor.alsa.rules = [
  {
    matches = [ { device.name = "alsa_card.platform-sound" } ]
    actions = { update-props = { api.alsa.soft-mixer = true } }
  }
  {
    matches = [ { node.name = "alsa_output.platform-sound.HiFi__Speaker__sink" } ]
    actions = {
      update-props = {
        audio.position = [ FR FL RR RL ]
      }
    }
  }
]
```

```
# 52-no-v4l2.conf
wireplumber.profiles = {
  main = { monitor.v4l2 = disabled }
}
```

```
# 51-xps13-upmix.conf, in both ~/.config/pipewire/client.conf.d/
# and ~/.config/pipewire/pipewire-pulse.conf.d/
stream.properties = {
    channelmix.upmix        = true
    channelmix.upmix-method = simple
}
```

The first corrects the channel map: the raw channel order is right
woofer, left woofer, right tweeter, left tweeter, so without it
stereo comes out mirrored. It also moves volume to a
software mixer, which behaves predictably where the amplifier gain
controls do not. The second works around a WirePlumber stall: the
video decoder's V4L2 device fails to open (its Dell firmware is
missing), and WirePlumber's camera discovery then blocks audio
policy. The speaker nodes appear with no ports, and `pw-play` waits
forever. Remove it when the camera is worked on and needs V4L2.

The PipeWire fragment sends stereo to all four speakers. The sink has
four channels and a stereo stream fills only the first two, the
woofers, unless the stream upmixes; PipeWire converts on the stream's
side, so the setting belongs to the clients (native and PulseAudio),
not to the sink. With it, the left channel plays on the left woofer
and, 3 dB lower, the left tweeter, and the same on the right.
Restart `pipewire-pulse` after adding it. To check what the speakers
receive, record the sink's monitor on four named channels while a
one-sided test tone plays:

```
pw-record --target <speaker sink id> -P '{ stream.capture.sink=true }' \
    --channels 4 --channel-map FL,FR,RL,RR monitor.wav
```

A left-only tone should show in FL and RL and nowhere else.

Not verified: audio across suspend.

### 12.6 Keeping the pack off 100 %

The charge thresholds work on this platform, and the durable form of
them is a udev rule:

```
# /etc/udev/rules.d/99-battery-charge-thresholds.rules
ACTION=="add|change", SUBSYSTEM=="power_supply", KERNEL=="qcom-battmgr-bat", \
  ATTR{charge_control_end_threshold}="80", ATTR{charge_control_start_threshold}="75"
```

`sudo udevadm control --reload` then `sudo udevadm trigger
--subsystem-match=power_supply --action=add` applies it without a
reboot. It fires on its own at boot; verified by reading the two files
after a reboot before anything else touched them. A rule, because
**the controller does not keep the pair across a power cycle**: set to
80/75, rebooted with the rule moved aside, both files read `0`. And
because this firmware has no page to hold it.

To try a pair by hand, or to raise the end to 100 for a day that needs
the whole battery (the rule puts it back at the next boot):

```sh
d=/sys/class/power_supply/qcom-battmgr-bat
sudo sh -c "echo 80 > $d/charge_control_end_threshold"
sudo sh -c "echo 75 > $d/charge_control_start_threshold"
```

The files reach the embedded controller through `pmic-glink` and the
battery manager. Four rules the firmware enforces without an error
message:

- **It clamps silently.** Every write returns success. Read the files
  back.
- **The floor for start is 50.** A lower value is ignored, not
  clamped.
- **End must be at least start + 5.** A smaller end becomes
  `start + 5`. `0` does the same; it does not restore no-limit.
- **Set end first, then start.** A start write that lands above
  `end - 5` is dropped.

**A threshold never brings a full pack down.** It gates charging and
nothing else. A pack at 100 % stays there until something draws on it,
and on a desk fed by the monitor cable nothing does. `energy_now` is
held at `energy_full` on external power (§12.1), so a falling pack
would read full anyway. Unplug both cables, run down past the start
threshold, plug back in: `Charging` stops at the end value. There is
no force-discharge; the driver exposes no `charge_behaviour`.

**Why 80/75.** Most of the cycle-life benefit, and a useful afternoon
in the pack when it is unplugged in a hurry. The start value decides
one thing: what happens when you plug in with the pack between the
two numbers. A start of 75 tops it up. A wider band, 60 say, runs
from the adapter until the pack drifts past 60 and hands you a machine
at 61 % when you meant to leave with a full afternoon.

**Why it lives in a rule.** The four rules above are the ones Dell's
**Battery Configuration → Custom** enforces on its x86 laptops, so the
EC implements the feature. **This firmware does not expose it.** Setup
on BIOS 2.14.0 has no battery page: the Power page holds Thermal
Management and the two lid switches, a search for *battery* returns
three unrelated settings, a search for *threshold* returns none.
Nothing holds the limit before the kernel loads. The rule is the
whole mechanism.

### 12.7 Suspend

Suspend to RAM works in both modes. Failures have occurred.
Investigation ongoing.

```sh
cat /sys/power/mem_sleep                # s2idle [deep]; deep is the default for "mem"
sync; echo freeze > /sys/power/state    # s2idle, ~6 s round trip
sync; echo mem    > /sys/power/state    # deep: the 11 non-boot cores go down over PSCI
```

Tested 2026-09-20, bare and then under a running compositor: the
compositor came back with the same pid and logged nothing, the panel
lit on the first keypress, every `failed_*` counter stayed zero. Deep
adds about 12 ms to offline and reboot the secondary cores and a
cosmetic `IRQ…: set affinity failed(-22)` for four interrupts pinned
to the boot core. Wi-Fi deauthenticates on the way down and
reassociates about 15 s after resume, so an ssh session across the
sleep drops. Drive anything longer than the write under `setsid`,
writing to a file in home.

**The lid suspends the machine, through elogind.** elogind is on the
system as polkit's dependency, bus-activated at every tty login by
`pam_elogind`. There is no `logind.conf`, so its defaults are the
policy: `HandleLidSwitch=suspend`, `HandleLidSwitchDocked=ignore`,
**`HandlePowerKey=poweroff`**. A short press of the power button is a
clean shutdown, not a sleep. This machine keeps that on purpose. Lid
closed: elogind wrote `mem`, 103 s of deep sleep, lid opened, back
with the compositor untouched and Wi-Fi reassociated within 16 s.

**The failure.** One lid close, left overnight, never slept. elogind's
suspend returned `Invalid argument`, and elogind retried every 30 s
for 100 minutes, 198 attempts, each one cycling the display path. The
machine was found awake with a drained battery and the panel showing
noise (chapter 13). Why that suspend failed is not known; the boot's
kernel log was lost to the `n3` log rotation (§12.3). Check
`/sys/power/suspend_stats` before trusting a closed lid overnight:
`success` must have gone up by one and `fail` by none.

Four traps:

1. **There is no RTC alarm.** The PMIC RTC carries `qcom,no-alarm`,
   `/sys/class/rtc/rtc0` has no `wakealarm`, and `rtcwake` fails with
   `set rtc wake alarm failed: Invalid argument`. There is no timed
   wake. A machine that will not resume comes back only by the 10 s
   power hold (§12.4).
2. **printk timestamps cannot show how long it slept.** They are
   `CLOCK_MONOTONIC`, frozen during suspend. Measure with
   `CLOCK_BOOTTIME` minus `CLOCK_MONOTONIC`, and read
   `/sys/power/suspend_stats/success` for the fact of it. The
   wall-clock stamps the logging service puts on `PM: suspend entry`
   and `PM: suspend exit` bracket the sleep.
3. **`gpio-keys` is the lid, not the power button.** It reports
   `EV_SW`/`SW_LID`. The power key is `pmic_pwrkey`.
4. **Do not write `/sys/power/state` by hand and close the lid in the
   same motion.** elogind's suspend and yours queue on the same lock,
   the machine dips twice, and the second dip lands inside
   wpa_supplicant's reassociation. The interface stays down until the
   supplicant is restarted.

Not measured: the sleep drain, the power button as a wake source, and
a docked suspend with DisplayPort holding the shared PHY (§12.2).

---

### 12.8 The initrd size limit: under 224 MB, and no fallback image

Found on 2026-09-21, the hard way. The fallback initramfs — every
module, no autodetect, the entry you reach for when the default image
cannot find the root — reset this machine the moment it was chosen:
no kernel output, no log, the firmware logo and then the reset. Twice,
with and without peripherals. The default image booted every time.

The variable turned out to be the size of the file the loader reads.
The default image padded with zeros to the fallback's size reset the
machine the same way, so the content had nothing to do with it, and a
series of padded images bracketed the line:

| Initrd file size | Result |
|---|---|
| 14 MB (the default image) | boots |
| 192 MB | boots |
| 224 MB | boots |
| 256 MB | reset before any output |
| 272 MB (the fallback image) | reset before any output |

**The rule:** keep the initrd well under 224 MB. The default image is
14 MB; nothing in normal use comes near. **The fallback image cannot
be used on this machine**, and this blueprint's install script no
longer builds it or offers an entry for it. Recovery is the install
stick and, once you have had a kernel upgrade, the previous kernel
kept under its own entry (the updates runbook, §6.3).

**The preset comes back.** The kernel package overwrites
`/etc/mkinitcpio.d/linux-aarch64.preset` on every install (it is not
a pacman-tracked config file), and ALARM's copy already lists only
the default image — but if you or a script ever turned the fallback
on, check after each kernel upgrade that `PRESETS=('default')` is
what it says, and delete any `initramfs-linux-fallback.img` on the
ESP.

**Why, as far as it is known.** The reset happens before the kernel
exists, so `mem=31G` (§8.1) has no say in it. The reading that fits:
UEFI hands out memory from the top, this machine's DRAM ends with
32 GiB above 36 bits that the firmware's own DMA cannot reach at EL1
(§8.1 again), and a buffer that no longer fits a free hole in low
memory lands up there, where the firmware's NVMe path fills it and
the SoC resets. That would make the threshold the size of a hole in
the firmware's low memory, which is why it is not a round number. Not
proven; `efi=debug` on the kernel command line prints the firmware
memory map and would show it.

### 12.9 Browsers flicker: the driver drops implicit sync

A region a browser paints once and then leaves alone, a dropdown, a
menu, a hover panel, shows on every other frame while any small
region keeps repainting. On and off at half the refresh rate, for as
long as a cursor blinks or a scrollbar fades. Firefox and Chrome,
native Wayland, on the internal panel and on an external monitor;
Chrome worse, because it repaints small regions more often. Found
2026-09-22.

For the mechanism: the Adreno GPU driver, freedreno, took the path
of disabling implicit sync once explicit sync is on. Because of this,
a compositor (like the one in chapter 10) that serves clients that do
not speak explicit sync ends up copying them mid-frame, and the region
painted once ends up in one of the compositor's two buffers and not in
the other. Mesa makes an exception for Xwayland for exactly this
reason, its mix of clients. Finally, the freedreno maintainer's
position is that a compositor doing explicit sync must bridge the
client fences itself (mesa/mesa#16387, since closed); wlroots' Vulkan
renderer does, its GLES2 renderer does not.

Until wlroots does, one file fixes it, naming your compositor's
executable:

```xml
<!-- ~/.drirc -->
<driconf>
  <device driver="msm">
    <application name="tyler" executable="tyler">
      <option name="disable_explicit_sync_heuristic" value="true"/>
    </application>
  </device>
</driconf>
```

Takes effect at the next session. Two other ways out, if you would
rather not carry the file: `WLR_RENDERER=vulkan` in the compositor's
environment (turnip imports client fences explicitly), or
`WLR_RENDER_NO_EXPLICIT_SYNC=1` (no fence to KMS at all). Buffer
compression, the tiled or direct render path and buffer modifiers
have nothing to do with it; each was tried.

## 13. When it goes wrong

*Shaka, its kernel panicked.*[^shaka]

| Symptom | Most likely cause | Where to look |
|---|---|---|
| Black screen, reboot loop, no output at all | device tree not applied | §9.3 |
| Firmware complains about an unsigned bootloader | Secure Boot still on | §6.4 |
| Windows asks for a BitLocker recovery key at every boot | Secure Boot changed while BitLocker was genuinely armed — protectors present, not the pre-provisioned state of §6.2 | The key is wherever the protector escrowed it: a Microsoft account, or printed at the time you enabled it. If you never enabled it and never signed in with a Microsoft account, see §6.2 — you are probably not in this row at all |
| Live system prints, then `A start job is running for /dev/disk/by-label/ARMLIVE`, and no login ever comes | the initramfs on the ESP is the tarball's own, without the Type-C host chain: the stick cannot see itself | §7.5, step 6 |
| Live system boots, internal disk absent from `lsblk` | NVMe driver or pin control missing → wrong kernel | §7.2 |
| The machine resets the instant a boot entry is chosen, no kernel output at all | the entry's initrd is larger than ~224 MB (a fallback image, or an image that grew) | §12.8: shrink it, or pick an entry with a normal-sized image |
| Installed system boots to an `initramfs` rescue prompt | root filesystem not found: wrong label in the boot entry, or the initramfs lacks a driver | §9.2 steps 5 and 7 |
| Everything works but graphics are slow | Qualcomm firmware split missing, GPU not initialised | §7.1 |
| `pacman -Syu` replaces the kernel and it stops booting | the `IgnorePkg` pin was removed too early, or someone typed `-Syyuu`. **NEVER TYPE `pacman -Syyuu` ON THIS MACHINE** | §9.2 step 8, §10.1 |
| Machine resets itself seconds after the kernel starts printing | DMA into the top 32 GiB, a firmware limit | §8.1 |
| Machine resets itself at a plug, a GPU lockup, or an unattended moment; no panic, no log | a reset from below the kernel; mechanism unknown, investigation ongoing | §12.3, §12.2 |
| Lid closed overnight, machine found awake with a drained battery | the suspend failed and elogind looped on it | §12.7 |
| Panel shows full-screen noise from the Dell logo up, on every boot, through power holds | a latched state inside the panel. Run the LCD self-test: hold `D` and press power. The next boot was normal | §12.7 |
| Installer dies at `partprobe` or `mkfs.vfat` | the live root lacks them; the payload carries `dosfstools` | §9.2 |
| Installed system: no USB, no Type-C, `/sys/class/typec` empty | `qcom_pd_mapper` not loaded | §9.4 |
| `request_firmware failed: -2`, no Wi-Fi, no DSPs — after the install or after an update | compressed firmware the kernel cannot read | §9.4; the update companion |
| Wi-Fi associates, then the 4-way handshake times out | January Wi-Fi firmware, only on a hand install | §9.4 |
| Compositor fails to take the seat | user not in the `seat` group | §10.3 |
| Compositor freezes about 30 s in; input works, nothing redraws | GPU reset, lost GL context | §12.3 |
| A menu or dropdown in a browser blinks on and off at half the refresh rate | freedreno dropped implicit sync for the compositor after its first fence | §12.9 |
| Mouse or keyboard on the monitor's hub is dark, console full of `Timeout while waiting for setup device command` | a 4-lane DisplayPort link; reboot, and set the monitor to prefer USB data (Dell: *USB-C Prioritization → High Data Speed*), which makes it rarer but does not rule it out | §12.2 |
| Mouse or keyboard on the monitor's hub is dark, no errors, SuperSpeed hub present | the hub's USB 2.0 half did not come up; move the plug to the other port | §12.2 |
| Battery sits at 100 % all day on a USB-C monitor | power delivery over the video cable, no charge limit set | §12.6 |
| A charge threshold write "succeeds" and nothing changes | the firmware clamped or ignored it | §12.6 |
| Status bar shows no battery | no `capacity` file on this SoC | §12.1 |
| Opening the lid boots a machine you powered off | the firmware's Power On Lid Open switch, on by default | §12.4 |
| No sound card, `/proc/asound/cards` empty | the device tree has no sound node | §12.5 |
| Speaker sink exists but nothing plays, `pw-play` waits forever | WirePlumber's camera discovery stalled audio policy | §12.5 |
| Stereo comes out mirrored | channel map; the first WirePlumber fragment | §12.5 |
| Only the woofers play, tweeters silent | stereo streams are not upmixed; the PipeWire fragment | §12.5 |
| Fans never spin up | no EC driver; not tested | chapter 3 |

**Keep the stick.** It is a complete rescue environment: boot it,
mount the installed root and ESP, and fix whatever you broke.

---

## 14. Getting back to Windows only

Boot the install stick, then:

1. Delete the four Linux partitions with `sgdisk -d <number>` (or
   `cgdisk`, which is interactive and harder to get wrong). Delete
   only the ones you created. Check the labels first with
   `lsblk -o NAME,SIZE,PARTLABEL`. **DO NOT DELETE THE WINDOWS BOOT
   ENTRY, AND DO NOT TOUCH ITS ESP.** Partition 1 is Windows' ESP;
   partition 5 is the one you made.
2. Remove the Linux firmware boot entry only: `efibootmgr -v` lists
   them, `efibootmgr -b <id> -B` deletes ours. Leave `Windows Boot
   Manager` alone.
3. Boot Windows and extend `C:` back over the free space with Disk
   Management.
4. Optionally re-enable Secure Boot and BitLocker.

What this does **not** restore: the page file, system protection and
hibernation you turned off in §6.3. Turn them back on by hand.

---

## Appendix A — Glossary

**aarch64 / arm64** — the 64-bit ARM instruction set; the two names
mean the same thing. **ACPI** — firmware tables describing hardware to
the operating system; present here but unused by Linux. **ALARM** —
Arch Linux ARM, the distribution whose kernel this install borrows.
**ARM** — the processor architecture this laptop uses. **ARMtix** —
the ARM port of Artix Linux; the distribution installed here.
**BIOS** — the older firmware interface UEFI replaced; Dell's setup
screen is still called that. **BitLocker** — Windows full-disk
encryption. **bsdtar** — an archive tool that reads more formats than
GNU tar, used here to unpack package files. **chroot** — running
commands with a different directory as the root of the filesystem;
how you configure a system you are not currently booted into.
**DSP** — digital signal processor; small dedicated cores in the SoC
handling audio and sensors, each needing its own firmware. **DT /
DTB** — device tree / device tree blob, the file describing the
hardware to the kernel. **dtbloader** — a small EFI program that picks
the right DTB automatically. **EC** — embedded controller, the small
always-on chip managing fans, battery and keyboard backlight.
**EDID** — the identification data a display reports about itself.
**EL1 / EL2** — ARM's privilege levels: an operating system normally
runs at EL1 and a hypervisor, if any, at EL2. On this machine the
firmware's own hypervisor keeps EL2 and hands Linux EL1, which is why
DMA above 32 GB is out of reach (§8.1). **ESP** — EFI System Partition, the FAT32 partition holding
bootloaders. **ext4** — the standard Linux filesystem. **FAT32** — an
old Microsoft filesystem, the one every firmware can read.
**freedreno / turnip** — the open-source OpenGL and Vulkan drivers for
Adreno GPUs. **GPT** — GUID Partition Table, the modern partition
table format. **GMU** — graphics management unit, the small controller
inside the Adreno GPU that manages its power and clocks (§12.3).
**Gunyah** — Qualcomm's hypervisor, resident under Linux on this
machine (§8.1). **initramfs** — the small in-memory filesystem the
kernel uses to find the real disk. **init system** — the first process
started by the kernel; systemd or, here, s6. **LPDDR5X** — the memory
type, soldered to the board. **makepkg / PKGBUILD** — the tool and
recipe file used to build Arch-style packages. **mkinitcpio** — the
tool that generates the initramfs. **MSR** — Microsoft Reserved
Partition, a small area Windows keeps for itself. **NVMe** — the
interface modern solid-state disks use. **package** — one compressed
archive of the files a program installs, plus metadata; the unit pacman
installs (§2.1). **pacman** — the package
manager of Arch and its derivatives. **PHY** — the transceiver that
drives a physical link; the combo PHY here serves USB 3 and
DisplayPort on the same port (§12.2). **pin control (pinctrl)** — the
driver deciding what each physical pin of the SoC is wired to.
**PSCI** — Power State Coordination Interface, the firmware call the
kernel makes to power the SoC off or reset it (§12.4). **root filesystem
tarball** — a `tar` archive of a complete installed system, unpacked
onto a partition to install it; both distributions publish one (§2.1).
**s6** — the init and service supervision system Artix uses in place
of systemd. **Secure Boot** — a firmware feature refusing unsigned
bootloaders. **SoC** — system on chip. **swap** — disk space used as
overflow for memory, and the destination of a hibernation image.
**systemd-boot** — a small, simple UEFI bootloader; despite the name
it does not require systemd. **UEFI** — the modern firmware interface.
**wlroots** — the library most Wayland compositors are built on.
**WinRE** — the Windows recovery partition. **zap shader** — a small
signed GPU program required to bring an Adreno GPU out of reset.

## Appendix B — Roads not taken

**Why not install ARMtix directly onto the stick?** No aarch64 EFI
bootloader in its repositories, and its kernel does not boot this
machine. Arch Linux ARM as the live environment solves both.

**Why not GRUB?** It works, and ARMtix packages it. systemd-boot's
configuration is three text files, and its `devicetree` key makes the
DTB handling explicit.

**Why not Arch Linux ARM alone?** The goal was a systemd-free machine.
If you do not care, install Arch Linux ARM and stop at the end of
chapter 8.

**Why keep Windows?** Firmware updates for ARM Dells ship through
Windows. Delete it and the firmware never updates again.

**Why not wait for everything to be upstream?** The audio and EC
drivers may take another year. Everything else works now.

## Appendix C — Sources

- Arch Linux ARM: `archlinuxarm.org`, and its package sources on
  GitHub (`archlinuxarm/PKGBUILDs`).
- ARMtix: `armtix.artixlinux.org` for root filesystem tarballs (under
  `images/`) and repositories; its package sources are on GitLab.
- dtbloader: the project's releases page carries prebuilt, checksummed
  binaries.
- The out-of-tree patch set and hardware status for this exact model
  is maintained publicly under the Dell codename `tributo`; search for
  `linux-x1e80100-dell-tributo`.
- Kernel mailing list archives, for the embedded controller driver's
  progress.
- Phoronix covered both the Dell firmware upstreaming in March 2026
  and the general state of Snapdragon X Elite on Linux at the end of
  2025; both are useful for calibrating expectations.

---

## Notes

[^name]: **sokath**, from *Sokath, his eyes uncovered*: Tamarian for
the moment understanding arrives, in the *Star Trek: The Next
Generation* episode *Darmok*. A fit patron for a machine whose
firmware and kernel must agree on a device tree before either says
anything.

[^shaka]: *Shaka, when the walls fell*: the Tamarian for failure. A
failed boot on this machine communicates the same way, in silence.

[^tools]: `bsdtar` comes from `libarchive`, `sgdisk` from `gptfdisk`.
On Debian and Ubuntu: `apt install libarchive-tools gdisk dosfstools`.

[^zap]: Adreno GPUs start in a locked state and are released by a
small signed program, universally called the *zap shader*, loaded from
the firmware package. Without it the GPU never initialises: the
system works, but everything is drawn in software.

[^pcsc]: `pcsclite` is pulled in only because `wpa_supplicant` links
against `libpcsclite.so.1`; nothing here uses smart cards, and its
daemon is not needed.

[^chroot]: `chroot` runs a command with some other directory treated
as `/`. It is how you configure a system you are not booted into: the
package manager, `mkinitcpio` and `passwd` all run *inside* the newly
unpacked system, writing to its files and reading its configuration,
while the kernel and hardware underneath are still the live stick's.
The pseudo-filesystems `/proc`, `/sys`, `/dev` and `/run` are bound
into it first, because those tools stop working without them.

[^gpt]: **GPT** replaced the old MBR partition table. It allows more
than four partitions without tricks, stores a backup copy at the end
of the disk, and gives every partition a stable identifier and a
label. That is why this blueprint names filesystems by label
everywhere rather than by `/dev/sdX` paths that change between boots.
