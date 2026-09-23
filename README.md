# Artix Linux on the Dell XPS 13 9345

A blueprint for installing Artix Linux, Arch without systemd, on Dell's
Snapdragon X Elite laptop (X1E-80-100, codename *tributo*): from a
Windows machine as it comes out of the box to a working Wayland desktop
on the GPU, with every acronym spelled out and every decision explained.
Written from one machine, every stage run on real hardware.

- [**The blueprint**](doc/artix-on-xps13-9345.md) — the install, stages
  1 to 5, what works, what does not, and what the first days found.
- [**The update companion**](doc/artix-on-xps13-9345-updates.md) —
  keeping it installed: the pins, the checks, the prompts.

## The short of it

The laptop boots Linux at EL1 under Qualcomm's hypervisor, so only 31
of its 64 GB are usable until that changes (`mem=31G` on every boot
entry, or the machine resets seconds in). ARMtix's own kernel has the
platform options off, so the install borrows Arch Linux ARM's kernel
and firmware and pins them. Windows stays, shrunk, because firmware
updates only arrive through it. The rest is detail, and the detail is
in the documents.

## The scripts

| | |
|---|---|
| `PKGBUILD` | the payload: every file, its URL, its checksum. `makepkg -o` fetches and verifies |
| `scripts/fetch.sh` | the same, for a build machine without makepkg (bash, curl, sha256sum) |
| `scripts/build-stick.sh` | writes the install stick from the payload; regenerates the live system's initramfs in a chroot, so an x86-64 build machine needs `qemu-user-static` with binfmt |
| `scripts/live.mkinitcpio.conf` | the modules that initramfs needs: the Type-C host chain, without which the stick cannot see itself |
| `scripts/install.sh` | rides on the stick; installs ARMtix onto the internal disk |

```sh
git clone https://github.com/thinkoid/artix-xps13-9345 && cd artix-xps13-9345
gpg --recv-keys 68B3537F39A313B3E574D06777193F152BDBE6A6   # Arch Linux ARM's build key, once
makepkg -o                                                 # or: scripts/fetch.sh
sudo scripts/build-stick.sh /dev/sdX                       # your USB stick
```

Then the blueprint, chapter 8 onwards. Read chapter 1 first; stage 1
shrinks Windows and stage 4 partitions the disk.

## Feedback

Issues and pull requests here. A different unit, a later tarball or a
newer kernel will hold surprises of the same kind this machine held;
the logs are the fastest way through them, and a report with the log
attached is the fastest way to a fix in the text.

## License

The documents under `doc/` are
[CC BY-SA 4.0](doc/LICENSE). The scripts and the `PKGBUILD` are
[MIT](LICENSE).
