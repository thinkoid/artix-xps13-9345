# Keeping it current — the update companion

Companion to [Artix Linux on the Dell XPS 13 9345 — a
blueprint](artix-on-xps13-9345.md). That one gets the machine
installed. This one keeps it installed: what to check before an
update, what to type, what to check afterwards, and which of this
machine's peculiarities bite if you treat it like an ordinary Arch
box. The machine is called **sokath** throughout, as it is there.

**Status:** chapters 1–5 were run on real hardware on 2026-09-19, the
day after the install, and every number below was measured there;
§5.5 and the lid note in §5.4 were added from the second day.
Chapter 6 — the day the kernel moves — is reasoned from the package
layout and has not happened yet; it says so again where it matters.

---

## 0. tl;dr — the checklist

Two facts carry the whole document: **the four pinned packages must
survive the update**, and **`mem=31G` must survive on every boot
entry**. Everything else is how you notice that they did not.

### Before

- [ ] **Room on the ESP.** `df -h /boot` — want **100 MB free or
      more**. The initramfs is ~14 MB and is rebuilt whenever firmware
      moves. There is no fallback image on this machine (§2).
- [ ] **Be at the keyboard, or able to get to it.** An `openssh`
      upgrade drops the session it is delivered over, and the daemon
      wants restarting afterwards (§5.2).
- [ ] **Write the pins down.**
      `pacman -Q linux-aarch64 linux-firmware-qcom linux-firmware-atheros linux-firmware-whence`

### The update

- [ ] `yay -Syu` — that is the whole command.
- [ ] **NEVER TYPE `pacman -Syyuu` ON THIS MACHINE.** Not `-uu`, not
      `-yy`. Chapter 3 says what `-uu` costs.
- [ ] `warning: linux-aarch64: ignoring package upgrade` is the pin
      doing its job. Expected. Read it, do not act on it.
- [ ] Any prompt offering to install an ignored package, or to
      replace one package with another: read it, and the default
      answer is **n**.

### After

Six checks, one paste. Every glob under `/boot` needs the `sh -c`
wrapper, because the ESP is mounted `dmask=0077` and your shell
expands the glob as you, not as root.

```sh
# 1. the pins are still what they were
pacman -Q linux-aarch64 linux-firmware-qcom linux-firmware-atheros linux-firmware-whence

# 2. no compressed firmware where the kernel must read it — must print 0
find /usr/lib/firmware/qcom /usr/lib/firmware/ath12k -name '*.zst' | wc -l

# 3. every boot entry still carries mem=31G
sudo sh -c 'grep -H options /boot/loader/entries/*.conf'

# 4. the images those entries point at, and when they were built
sudo sh -c 'ls -l /boot/Image /boot/initramfs-linux*.img'

# 5. nothing that was up is down
s6 live status | sort

# 6. configuration the update wants merged
sudo find /etc -name '*.pacnew'
```

- [ ] Rebuild `tyler-git` if wlroots or Mesa moved (§5.1).
- [ ] Reboot if the kernel, the firmware or an initramfs moved. Not
      otherwise.

No script is offered for any of this on purpose. It is six lines, and
reading the output is the whole point; a script that prints OK is a
script you will eventually believe.

---

## 1. Why this is not an ordinary Arch box

Three things make the difference, all of them consequences of the
install:

**The kernel is foreign and pinned.** The blueprint installs Arch
Linux ARM's kernel on top of ARMtix because ARMtix's own has the
X1E80100 options off (§7.2 there). `/etc/pacman.conf` therefore
carries:

```
IgnorePkg = linux-aarch64 linux-firmware-qcom linux-firmware-atheros linux-firmware-whence
```

Measured on 2026-09-19, one day after the install:

| package | installed | in the repository |
|---|---|---|
| `linux-aarch64` | 7.2.6-1 | **7.1.5-1** |
| `linux-firmware-qcom` | 20260916-1 | 20260916-1 |
| `linux-firmware-atheros` | 20260916-1 | 20260916-1 |
| `linux-firmware-whence` | 20260916-1 | 20260916-1 |

The kernel row is the dangerous one: the repository's version is
*older*, so a normal `-u` will never touch it, and only an explicit
downgrade can. The three firmware rows carry the **same version
string on both sides** and differ only in how they are compressed —
ARMtix's are `zstd`-compressed, the installed ones are not, and this
kernel reads `xz` only. Same version, so an upgrade is never offered;
the pin is there against the reinstall, the `--overwrite` and the
`-uu`.

**`/boot` is the EFI System Partition**, 1022 MB of it, and the kernel
package writes straight into it: `Image`, `Image.gz` and 125 MB of
device trees. 464 MB were in use the day after the install. That is
comfortable, not roomy — see the pre-flight check.

**The bootloader is not managed by anything.** `systemd-bootaa64.efi`,
`BOOTAA64.EFI` and the dtbloader driver were copied onto the ESP by
hand during the install; `pacman -Qo` reports no owner for any of
them, and there is no `bootctl` on the machine. No update will ever
move them, and none needs to. The corollary is §6.4: nothing will
update the *second* copy of the device tree under `/boot/dtbloader`
either.

---

## 2. Before

**Room on the ESP.** `df -h /boot`. The initramfs is ~14 MB and is
rebuilt in place whenever the kernel or a `linux-firmware-*` package
moves; a truncated initramfs is a machine that boots to a rescue
prompt, so keep 100 MB free. **There is no fallback initramfs on this
machine, on purpose:** the firmware resets the box before the kernel
runs when the loader reads an initrd larger than about 224 MB
(bracketed 2026-09-21: 224 MB boots, 256 MB resets, the 272 MB
fallback image never loaded once), so the fallback entry and the
preset are gone. **A kernel package install puts the preset back**
(`/etc/mkinitcpio.d/linux-aarch64.preset` is not a pacman config
file); after every `linux-aarch64` upgrade, check it and cut it down
again, then delete the image it built:

```sh
grep '^PRESETS' /etc/mkinitcpio.d/linux-aarch64.preset     # want ('default') only
sudo sed -i "s/^PRESETS=.*/PRESETS=('default')/" /etc/mkinitcpio.d/linux-aarch64.preset
sudo rm -f /boot/initramfs-linux-fallback.img
```

**Be able to reach the keyboard.** Updating over the network is fine;
updating over a network you cannot get back to is not. `openssh`
upgrades end the session that delivers them.

**Keep the package cache.** `/var/cache/pacman/pkg` held 460 packages
and 1.8 GB the day after the install. ARMtix has **no package
archive** — there is no equivalent of the Arch Linux Archive to fetch
last week's build from — so that directory is the only rollback this
machine has. Do not run `pacman -Sc`. If it genuinely needs trimming,
trim it to the last two versions of each package rather than to the
installed one.

---

## 3. The update

```sh
yay -Syu
```

`yay`, not `pacman`: the AUR is load-bearing on this machine — the
compositor is packaged there — and one command covers both halves of
the world so neither can quietly fall behind.

Read-only queries (`pacman -Q`, `-Qi`, `-Ql`, `-Qo`) stay `pacman` and
are often clearer.

**Not `-yy`.** The second `y` forces every database to be downloaded
again whether or not it changed. It is for a mirror you suspect of
having rolled backwards, and it buys nothing else.

**NEVER TYPE `pacman -Syyuu` ON THIS MACHINE.** The second `u` means
"make the installed version match the repository's, downgrading where
the repository is behind". Here the repository is behind by the entire
reason the install worked: `7.2.6-1` installed against `7.1.5-1` in
the repository, the kernel with pin control, the interconnect driver
and the display and GPU clock controllers switched off. `IgnorePkg`
catches it. But some of pacman's ignore prompts default to *yes*, and
the reward for getting it wrong is a laptop that does not boot and
cannot be fixed from itself. Nothing on this machine needs a
downgrade. There is never a reason to type it.

**The prompts that matter**, in the order they tend to appear:

| prompt | what it means | answer |
|---|---|---|
| `warning: <pkg>: ignoring package upgrade (A => B)` | the pin working; not a question | nothing to do |
| `<pkg> is in IgnorePkg. Install anyway? [Y/n]` | something is trying to pull a pinned package in as a dependency | **n**, then find out what wanted it |
| `Replace X with Y? [Y/n]` | a package rename or a swap of implementations | read it; the daemons on this machine were chosen deliberately |

On the unsigned ARMtix repositories, see addendum 10.1 of the
blueprint. Nothing about updating changes that picture.

---

## 4. After — the six checks

Each one, and what a bad answer means.

1. **The pins.** Four versions, unchanged from before the update. A
   changed kernel version without your having removed the pin is the
   one result that means *do not reboot yet*.

2. **`.zst` under `qcom/` and `ath12k/` must be `0`.** Anything else
   means ARMtix's compressed firmware came back over the uncompressed
   set, and at the next boot the Wi-Fi, the GPU and the DSPs will each
   fail to load their blobs — because this kernel is built without
   `CONFIG_FW_LOADER_COMPRESS_ZSTD`. The cure is to reinstall the
   three ALARM packages and check the pin. The 5917 `.zst` files
   elsewhere on the machine are Intel, AMD, TI and Nvidia firmware for
   hardware this laptop does not have; they are noise, and harmless.

3. **`mem=31G` on every entry.** This is the platform limit, not a
   tuning knob: the firmware cannot let anything DMA into the top
   32 GiB of a 64 GB machine, and the SoC hard-resets on the first
   access. An entry without it boots and dies seconds later, with
   nothing in any log. Nothing in an update edits the entries, so this
   check is cheap insurance against your own earlier hand.

4. **The images.** `Image` should carry the kernel package's
   timestamp; the two initramfs images should be newer than any
   firmware package you just installed. The install hook rebuilds them
   automatically whenever `usr/lib/firmware/*` or `usr/lib/initcpio/*`
   moves; chapter 6 has the check for the kernel itself.

5. **The services.** `s6 live status` prints one line per supervised
   service, `name/longrun//up/explicit` when healthy. Compare it with
   what was up before. Logs are plain files: `/var/log/<service>/current`.

6. **`.pacnew`.** Merge them or delete them, but do not leave them; the
   next update will add more and the pile becomes unreadable.

---

## 5. What needs a hand afterwards

### 5.1 The compositor, after wlroots or Mesa

```sh
yay -S tyler-git
```

`tyler-git` is built against the wlroots and Mesa on the machine, so a
bump in either wants a rebuild. Its AUR recipe lists `aarch64` since
r37 (2026-09-20); older copies of the recipe were `x86_64` only and
needed `--mflags -A`.

A rebuilt compositor takes effect at the **next login**, never in the
running session; nothing about the session you are typing in changes.

### 5.2 `sshd`, after openssh

Restart the daemon without disturbing anything that depends on it:

```sh
sudo s6 process restart sshd-srv
```

Do that at the keyboard. Restarting the daemon you are connected
through, over the connection it is serving, is a way to find out how
good your backup access is.

### 5.3 s6, after an `s6-rc` or service-package bump

The pacman hooks recompile the service database and print what they
did. An `invalid service database` line on the console after such a
bump refers to the *old* compiled directories, not to the live
database; the machine boots on the live one.

### 5.4 When to reboot

Reboot when the kernel, the firmware or an initramfs moved. Do not
reboot to "settle" anything else — an update this machine survives is
one you can verify while it is still running, and a reboot is how you
find out about a boot-path mistake at the worst moment. When you do,
the verbose entry and the kept previous kernel are in the boot menu
for a reason.

`halt -p` and a later power-on is as good as a reboot: it is a full
off (blueprint §12.4). One thing to know: a powered-off machine boots
the moment the lid opens, because the firmware's **Power → Lid Switch
→ Power On Lid Open** is on by default. Turn it off in firmware setup
once if that bothers you.

### 5.5 Kernel headers, and a module built out of tree

If you ever build a kernel module on this machine — the battery
driver's missing percent (blueprint §12.1) was first fixed that way —
you will reach for `linux-aarch64-headers`, and the ARMtix repository
will hand you **7.1.5**, the headers of the kernel that does not boot
this laptop. The headers that match the running 7.2.6 come from the
Arch Linux ARM mirror, `linux-aarch64-headers-7.2.6-1`, and the safest
way to use them is to extract the package somewhere under your home
rather than install it. If you do install it, it is a **fifth pin**:
add it to `IgnorePkg` beside the kernel, for the same reason, or the
next `-uu` anyone types offers to downgrade it.

Check the match before trusting a build: the headers' `.config`
against the running kernel's `/proc/config.gz` should differ in zero
lines, and the module's `vermagic` must equal `uname -r`. This kernel
has neither `CONFIG_MODVERSIONS` nor module signature enforcement, so
that diff is the only check there is. A module loaded with `insmod`
does not survive a reboot; one installed under `/usr/lib/modules/`
does, and has to be rebuilt the day the kernel moves (chapter 6).

---

## 6. The day the kernel moves

**Performed once, 2026-09-21, with a locally built package of the same
layout as the one ARMtix will ship.** It applies the first time the pin
comes off — when ARMtix's repository carries the kernel chapter 11 of
the blueprint describes.

**6.1 The initramfs rebuilds itself — check that it did.** mkinitcpio's
install hook triggers on `usr/lib/initcpio/*` among other paths, and
this kernel package ships `usr/lib/initcpio/<version>` for exactly that
reason (its image goes to `/boot/Image`, not to the `vmlinuz` path the
hook also watches). On 2026-09-21 a kernel install rebuilt both images
without help. The old module tree is removed by the same install, so
look at the timestamps before rebooting, and only if either image is
older than the kernel run it by hand:

```sh
sudo mkinitcpio -P
sudo sh -c 'ls -l /boot/Image /boot/initramfs-linux*.img'
```

**6.2 Three warnings are normal** and appear on every build:

```
==> WARNING: Could not find kernel image for version <ver>
==> WARNING: architecture 'aarch64' not supported, skipping hook
==> WARNING: No module containing the symbol 'drm_privacy_screen_register' found
```

The first is mkinitcpio looking for an x86-shaped `vmlinuz` that this
package does not ship. None of the three affects the image; the line
that matters is `Initcpio image generation successful`.

**6.3 Keep the working kernel package.** Before removing the
`IgnorePkg` line, copy the installed kernel's package file out of
`/var/cache/pacman/pkg` somewhere safe. It is the machine's way back.

**6.4 The second device tree.** The boot entries load the kernel
package's copy, `/dtbs/qcom/x1e80100-dell-xps13-9345.dtb`, which a
kernel upgrade refreshes. The copy under `/boot/dtbloader/dtbs/` is
the fallback path's, was placed by hand, and is owned by no package.
If you ever fall back to dtbloader, refresh that copy yourself.

---

## 7. When it goes wrong

*Kiteo, his eyes closed.*[^kiteo]

| Symptom | Most likely cause | Where to look |
|---|---|---|
| Boots, then hard-resets after a few seconds | an entry lost `mem=31G` | §4 check 3 |
| No Wi-Fi, no GPU acceleration, DSP errors in `dmesg` | compressed firmware came back | §4 check 2; the recovery command is in the blueprint, §9.4 |
| Rescue prompt: root not found, modules missing | initramfs not rebuilt for the running kernel | §6.1 |
| Rescue prompt after an update that touched firmware | ESP filled up mid-write | §2, then rebuild from the stick |
| Black screen, no output at all, right after a kernel change | the pin came off and ARMtix's kernel is booting | §3, and the blueprint §7.2 |
| Compositor starts but applications are slow | Mesa moved and `tyler-git` was not rebuilt | §5.1 |
| Compositor freezes about 30 s into a session; input works, nothing redraws | a GPU reset and a lost GL context, which this platform does on its own; not the update | blueprint §12.3 |
| A module you built stops loading after a kernel change | built against the old headers | §5.5, chapter 6 |
| The machine boots by itself when the lid opens | the firmware's Power On Lid Open switch, on by default | §5.4, blueprint §12.4 |
| Session died mid-update, machine unreachable | `openssh` upgraded under you | §5.2 |

**Keep the install stick.** It is still the rescue environment the
blueprint says it is: boot it, mount the root and the ESP, and undo
whatever the update did.

---

[^kiteo]: **Kiteo, his eyes closed** — the Tamarian for a failure to
understand, or a refusal to; from *Darmok* (Star Trek: The Next
Generation, 1991), the episode that also gives this machine its name.
It is the right epigraph for a chapter whose entries are, almost
without exception, a prompt that was answered without being read.
