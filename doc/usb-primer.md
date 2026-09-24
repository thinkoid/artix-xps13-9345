# The USB-C ports on the XPS 13 9345: a primer

How a USB-C port on the Dell XPS 13 9345 becomes a USB host port under
Linux, link by link, and why a live stick's initramfs has to carry the
whole chain. Written 2026-09-23, the morning after the first stick
written by the published `build-stick.sh` failed to boot for want of
it. Part of the blueprint in this directory; §7.5 step 6 there is the
short form.

## 0. tl;dr

On a PC a USB port is a host port at power-on; the firmware hands the
kernel a working controller. On this laptop a port is nothing until a
DSP, reached through three layers of transport, says what it is. The
kernel has to bring up, in order: the controller's PHYs, the Type-C
lane mux, the DSP that runs the port manager, the IPC to reach it, and
the UCSI protocol that carries its verdict. Each link is a loadable
module in Arch Linux ARM's kernel (7.1.6 on the live stick). The
tarball's own initramfs, generated on their build host with
`autodetect`, held one module, `lz4`, so a stick booted with it could
never see itself: the kernel printed, then waited forever for
`/dev/disk/by-label/ARMLIVE`. `scripts/live.mkinitcpio.conf` names
the chain; `build-stick.sh` regenerates the image with it. Bisect
history: on 2026-09-19 the glink clients were blacklisted as the
killer of early boots; they were not, the DMA into the top 32 GiB was
(blueprint §8.1). The chain is required, not dangerous.

## 1. The chain, bottom to top

The order is the order the kernel needs it. A missing link lower down
defers everything above it.

### 1.1 The controller: dwc3

A Synopsys DesignWare USB 3 block per port, with Qualcomm glue
(`dwc3`, `dwc3-qcom`; both built into the 7.1.6 kernel, so never the
missing piece). It speaks USB, but on its own it has no signal path to
the connector and no idea whether it should be a host or a device. It
stays parked until the rest of the chain tells it. The port under the
right-hand connector is `a600000.usb`, the left `a800000.usb`; there is
a third controller for the internal devices.

### 1.2 The PHYs: eUSB2 and its repeater

The analog transceivers between the controller and the pins. Qualcomm
uses **eUSB2**, embedded USB 2.0: a low-voltage variant that lives
inside the SoC and cannot drive a real connector's 3.3 V levels. So
the USB 2.0 side is two pieces:

| Module | Driver | What it is |
|---|---|---|
| `phy-snps-eusb2` | `drivers/phy/phy-snps-eusb2.c` | the eUSB2 PHY in the SoC |
| `phy-qcom-eusb2-repeater` | `drivers/phy/qualcomm/` | the level shifter on the PMIC that turns eUSB2 into standard USB 2.0 at the connector |

Without both, the dwc3 driver defers its probe indefinitely
(`-EPROBE_DEFER` on the PHY handle) and the controller never
initialises. The SuperSpeed lanes have their own PHY, the QMP combo
PHY shared with DisplayPort (`phy-qcom-qmp-combo`): built into 7.1.6,
a module in the ARMtix 7.2.6 build of chapter 11 (it is in that
system's initramfs, next to `phy-qcom-qmp-usb` and `phy-qcom-edp`).

### 1.3 The Type-C mux: ps883x and the SBU mux

A USB-C connector is reversible, and its four high-speed lane pairs
are shared between USB 3 and DisplayPort. Between the SoC and the
connector sits a Parade PS8830 retimer/mux (`ps883x`,
`drivers/usb/typec/mux/`) that routes the lanes according to plug
orientation and the negotiated mode; the side-band pins go through
`gpio-sbu-mux`. Until somebody programs the mux, the lanes go nowhere.
The same mux is why a 4-lane DisplayPort alternate mode (pin
assignment C) leaves the port with no USB 3 at all, only the USB 2.0
pair, and a 2-lane mode (assignment D) keeps two lanes for USB 3
(`dp_debug` under `/sys/kernel/debug/dri/0/DP-*/` shows the lane
count). On this laptop the USB 2.0 pair does not survive assignment C
either: a monitor's hub loses both halves. Asking the monitor for two
lanes makes that rarer but does not rule it out; the firmware still
picks the mode at each boot (blueprint §12.2).

### 1.4 The port manager: firmware on the aDSP, spoken to over UCSI

Who decides orientation, data role, power role and alternate mode is
not a chip the kernel drives. On this laptop the Type-C port manager
is firmware running on the aDSP, the always-on DSP, the `charger_pd`
service that also owns charging and the battery. The kernel talks to
it with **UCSI**, the USB Type-C Connector System Software Interface: a
standard command set through which a port manager reports "connector 1
attached, orientation reversed, data role host" and takes role
requests. Three modules:

| Module | Role |
|---|---|
| `typec_ucsi` | the UCSI core: turns the port manager's reports into role switches and mux settings |
| `ucsi_glink` | the transport: UCSI messages over glink to the aDSP |
| `pmic_glink` | the multiplexer on the glink channel for the PMIC-side services: UCSI, alt-mode, battery manager |

`pmic_glink_altmode` carries the DisplayPort alternate-mode
notifications on the same channel; `qcom_battmgr` is the battery
manager on it, not part of the USB path but the same family and the
same transport. When UCSI says "host", the core programs the mux of
1.3 and flips dwc3 of 1.1 into host mode.

### 1.5 The DSP itself: remoteproc, the IPC router, the domain mapper

None of 1.4 answers unless the aDSP is running and has announced its
services.

| Module | Role |
|---|---|
| `qcom_q6v5_pas` | remoteproc: loads the aDSP firmware, has the hypervisor authenticate it (PAS, Peripheral Authentication Service), starts the DSP |
| `qrtr`, `qrtr-smd` | the Qualcomm IPC router the DSP announces its services on, and its shared-memory link |
| `qcom_pd_mapper` | answers the DSP's query of which protection domain hosts which service; without it `charger_pd` never reports ready |
| `pdr_interface`, `qcom_pdr_msg` | protection-domain restart notifications |
| `rpmsg_ctrl` | the rpmsg control device the glink channels hang off |

The firmware is the reason the initramfs also carries files:
`qcom/x1e80100/dell/xps13-9345/qcadsp8380.mbn` and its `.jsn`
descriptors (symlinks into `LENOVO/21N1/`, both ends needed). The
remoteproc driver requests them at probe and declares no
`MODULE_FIRMWARE`, so mkinitcpio will not add them on its own; the
drop-in's `FILES` line does. On the installed system the
`qcom_pd_mapper` line in `modules-load.d` is the same requirement in
its other form (blueprint §9.4): no mapper, no UCSI, no Type-C, no USB.

### 1.6 Then the ordinary part

dwc3 is a host; its xHCI half enumerates the stick; `usb-storage`,
`sd_mod` and `ext4` (all built in) produce `/dev/sda` and its
filesystems; udev reads the labels; `ARMLIVE` appears; systemd mounts
the root. On 2026-09-19, with the rebuilt image, the aDSP's
`charger_pd` announced itself at about 1.2 s and the root was mounted
at 5.7 s.

## 2. What the drop-in lists, and what it does not

`scripts/live.mkinitcpio.conf`:

```
phy-qcom-eusb2-repeater phy-snps-eusb2 ps883x gpio-sbu-mux
pmic_glink pmic_glink_altmode typec_ucsi ucsi_glink
qcom_q6v5_pas qcom_pd_mapper qcom_pdr_msg pdr_interface
qrtr qrtr-smd rpmsg_ctrl qcom_battmgr
i2c-hid-of i2c-hid hid-multitouch
```

The last line is not the chain: it is the internal keyboard and
touchpad, so an emergency shell inside the initramfs can be typed
into. `qcom_wdt` and `hid-generic`, which the hand-built image of
2026-09-19 also named, are not listed because 7.1.6 does not ship them
as modules (built in or absent;
mkinitcpio fails the build on a module it cannot find). `kms` is
skipped as a hook so the `msm` display driver does not load early.

## 3. The lessons

1. **An initramfs generated elsewhere is empty here.** `autodetect`
   keeps what the generating host uses. The distribution's image had
   one module. Any tarball's image, any version, has the same shape;
   regenerate inside the target root, natively on aarch64 or through
   `qemu-user-static` on x86-64 (`build-stick.sh` step 6).
2. **A loop rehearsal proves the writing, not the booting.** Two
   rehearsals passed with the empty image. Only a stick in the machine
   finds this class of fault.
3. **The chain is required, not dangerous.** The 2026-09-19 bisect
   blamed early glink for the resets and blacklisted it; the resets
   were the DMA hole above 32 GiB, and glink only ever brought the port
   up so that USB traffic could hit the hole (blueprint §8.1).
4. **Symptom to recognise:** kernel prints, `A start job is running
   for /dev/disk/by-label/ARMLIVE`, no login ever. Blueprint chapter
   13 has the row.

## 4. Glossary

Terms and abbreviations as this document uses them, in the order a
reader meets them.

| Term | Meaning |
|---|---|
| **USB-C** | the reversible 24-pin connector. A connector, not a protocol: USB 2.0, USB 3, DisplayPort and power all run over it, which is why a mux and a port manager exist at all |
| **host / device (data role)** | which end of a USB link controls it. A laptop talking to a stick is the host; the same port plugged into a PC could be the device. On this laptop the role is decided at run time, per plug |
| **DSP** | digital signal processor. Qualcomm SoCs carry several Hexagon DSPs running their own firmware; the **aDSP** ("audio", historically) is the always-on one that also runs the charger and Type-C port manager, the **cDSP** is the compute one |
| **charger_pd** | the aDSP firmware service that owns charging, the battery and the Type-C ports (PD = Power Delivery). It announces itself on the IPC router about a second into boot |
| **dwc3** | Synopsys DesignWare Core USB 3, the USB controller block Qualcomm licenses; `dwc3-qcom` is the wrapper that ties it to the SoC's clocks, interrupts and PHYs |
| **xHCI** | eXtensible Host Controller Interface, the standard register interface a USB 3 host controller presents; the host half of dwc3 is an xHCI controller, driven by `xhci-hcd` |
| **PHY** | physical layer: the analog transceiver between a controller's digital side and the wire. Every USB port has one for USB 2.0 and one for USB 3 |
| **eUSB2** | embedded USB 2.0, a USB-IF variant with low-voltage signalling meant to stay inside a package or board. It cannot drive a connector; a repeater converts it |
| **repeater** | in eUSB2 terms, the level shifter that turns eUSB2 signalling into standard USB 2.0 at the connector. Here it lives on the PMIC |
| **PMIC** | power management IC, the companion chip that regulates supplies and carries oddments such as the eUSB2 repeater, the RTC and the power button |
| **QMP PHY** | Qualcomm's multi-protocol SerDes PHY; the **combo** variant drives the SuperSpeed lanes as either USB 3 or DisplayPort |
| **SuperSpeed** | USB 3 at 5 Gb/s and up, on the high-speed lane pairs; USB 2.0 uses its own separate pair (D+/D-) and should keep working when the lanes are given to DisplayPort; on this laptop it does not (blueprint §12.2) |
| **lanes** | the four high-speed differential pairs of USB-C. USB 3 needs two (one each way); DisplayPort takes two or all four |
| **mux / retimer** | the switch that routes the lanes to the SoC's USB 3 or DisplayPort PHY according to orientation and mode (mux), and re-times the signal for the cable length (retimer). Here one Parade PS8830 does both |
| **SBU** | side-band use, two spare pins of USB-C that DisplayPort alternate mode uses for its AUX channel; `gpio-sbu-mux` steers them |
| **alternate mode (alt mode)** | a negotiated USB-C mode in which some lanes carry something other than USB; DisplayPort alt mode is the one in use here |
| **pin assignment C / D** | DisplayPort alt-mode configurations: C gives DisplayPort all four lanes (no USB 3 left), D gives it two and keeps two for USB 3 |
| **Type-C port manager (TCPM)** | the entity that runs the Type-C state machine: attach detection, orientation, role and power negotiation, alt-mode entry. On PCs a small chip; here firmware on the aDSP |
| **UCSI** | USB Type-C Connector System Software Interface, a USB-IF specification for how an OS talks to a port manager it does not run itself: commands and notifications over some transport. Linux: `typec_ucsi` |
| **glink** | Qualcomm's shared-memory message channel between the application cores and a DSP; `ucsi_glink` and `pmic_glink` are the UCSI and PMIC services carried over it |
| **rpmsg** | the kernel's remote-processor messaging framework that glink plugs into; `rpmsg_ctrl` exposes its control device |
| **QRTR** | Qualcomm IPC Router, the addressing layer on which DSP services are announced and found (`qrtr`, `qrtr-smd`) |
| **SMD** | shared memory driver, the older shared-memory transport `qrtr-smd` binds the router to |
| **remoteproc** | the kernel framework for loading firmware into, starting and stopping a co-processor; `qcom_q6v5_pas` is the remoteproc driver for Hexagon (Q6) DSPs on this SoC |
| **PAS** | Peripheral Authentication Service: the hypervisor / secure-world call that verifies a DSP firmware image's signature before the DSP may run it. The `.mbn` files are signed for it |
| **`.mbn` / `.jsn`** | the DSP firmware image (multi-boot-image, Qualcomm's container) and the JSON descriptors beside it that name the protection domains it hosts |
| **protection domain (PD)** | a service partition inside a DSP's firmware; `charger_pd` is one. The **PD mapper** (`qcom_pd_mapper`) tells the DSP which domain provides which service, and **PDR** (`pdr_interface`, `qcom_pdr_msg`) is protection-domain restart, the notifications when one goes down and comes back |
| **initramfs** | the initial RAM filesystem: the small archive the bootloader loads with the kernel, holding the modules and tools needed to find and mount the real root |
| **mkinitcpio** | Arch's initramfs generator; **hooks** are its build steps, **`autodetect`** the hook that trims the module list to what the generating host is using, **`kms`** the hook that adds the display driver for early graphics |
| **udev** | the device manager that names devices, reads filesystem labels and creates `/dev/disk/by-label/*`; systemd's root mount waits on it |
| **`i2c-hid`** | the driver for keyboards and touchpads attached over I²C, as this laptop's internal ones are; `hid-multitouch` handles the touchpad |
| **DMA** | direct memory access, a device writing to memory without the CPU; the resets of 2026-09-19 were DMA into memory the firmware would not let a device reach (blueprint §8.1) |

## 5. Sources

- Kernel 7.1.6 module tree on the stick's live root,
  `usr/lib/modules/7.1.6-1-aarch64-ARCH/` (paths in the tables);
  `modules.builtin` for dwc3, scsi, sd, ext4, usbhid.
- The blueprint beside this file: §7.5 step 6, §8.1, §9.4, §12.2,
  chapter 13.
- UCSI: the USB-IF "USB Type-C Connector System Software Interface"
  specification; kernel `Documentation/driver-api/usb/typec.rst`.
