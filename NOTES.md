# raphael-ios-gpu: working notes

iOS 16 (XNU xnu-8796 + the iPhone X 16.7.16 userland) on the Xiaomi Mi 9T Pro / Redmi K20 Pro
(`raphael`, SM8150 / Snapdragon 855, Adreno 640). Second port next to
[davinci-ios-gpu](https://github.com/marnov999/davinci-ios-gpu) (Mi 9T, SM7150): same layout, same tools,
same plan, adapted to the SM8150.

Read this file first. Update the handoff at the bottom after each milestone: commits, CI run IDs, exact
boot results, unfinished work. Keep observations and guesses apart.

## Where the code comes from

| Part | Origin |
| --- | --- |
| `xnu/patches/0001-0081`, `shim/`, `tools/` base | [dipa-studio/ios-sweet](https://github.com/dipa-studio/ios-sweet) (MIT) |
| `xnu/patches/0082-0102` (`raphael-*`), shim `RAPHAEL` paths, `mkadt.py --raphael` | [Gsjsjzhznsz/ios-raphael](https://github.com/Gsjsjzhznsz/ios-raphael) @ `1da7f47`: their t-series port, booted to the lock screen on a K20 Pro (8 cores, display + brightness, GT9886 touch, keys, PM8150B battery) |
| `tools/mkcombo.py`, `tools/sweet-root-overlay.py`, `shim/build-clang.sh`, `tools/mkbootimg.py` | davinci-ios-gpu |
| Our changes so far | breadcrumbs and kernel log go to `rawdump`, not `userdata`; XNU RAM window moved above the bad DRAM; header v2 packaging with all four stock DTBs (`tools/mkiosimg.sh`, `tools/stock-dtbs.py`); clang shim build |

Reference ports for later phases (verified by cloning, 2026-11-02):
- [HeliumStudio-Dev/hackios-xnu-kernel](https://github.com/HeliumStudio-Dev/hackios-xnu-kernel) branch
  `raphael-bringup`: HackiOS on raphael: A640 GLES (freedreno FD640) + command-mode TE scanout,
  SM8150 cpufreq, ath10k-SNOC Wi-Fi (WPA2/WPA3), docs/RAPHAEL.md, docs/RAPHAEL-WIFI.md.
- [Gsjsjzhznsz/hackios-xnu-kernel](https://github.com/Gsjsjzhznsz/hackios-xnu-kernel): `raphael_adreno.c`
  (GPU power/GMU/zap steps), docs/RAPHAEL-WIFI-PORT-PLAN.md; TrustZone refused the zap shader once
  (-3145797), later got the GPU pipeline.
- [NWylynko/ios-flame](https://github.com/NWylynko/ios-flame) (Pixel 4, SM8150, ios-sweet lineage):
  Metal on Turnip via metal2vulkan, userland Wi-Fi (`wland`) for the WCN3990, all 8 cores.
- [wochgn/ios-guacamole](https://github.com/wochgn/ios-guacamole) (OnePlus 7 Pro): A640 GMU cold boot probes.

## This phone

| Item | Value |
| --- | --- |
| Model | Mi 9T Pro, 6 GB / 64 GB (UFS WDC SDINDDH4-64G), global |
| Firmware | MIUI V12.5.2.0.RFKMIXM (Android 11), kernel 4.14.180, legacy SAR, A-only |
| State | Bootloader unlocked (Mi Unlock), rooted (Magisk; patched boot in `kbuild/raphael_magisk_boot_legacysar.img`) |
| Backups | `/home/marnov/xmiphones/raphael_backup/full/` (all LUNs except userdata, rawprogram XMLs, SHA256SUMS), unlock state in `raphael_backup/unlock_state/` |
| EDL | `fastboot oem edl`; loader `loaders/raphael_sm8150/ff1_sdm855_ddr.elf` (pass it explicitly) |
| Known faults | ghost touches (hardware); weak DRAM cells, see below |
| UART | debug UART serial@a90000 on USB-C SBU (1.8 V; CC1+CC2 5.1 k to GND = debug accessory mode; SBU2 = phone TX) |

**Bad DRAM.** 18 weak cells in the pages 0x1016aa000, 0x1016ab000, 0x1016bc000, 0x1016bd000 (bit 12 recurs:
one marginal DQ/column, bursty when the DDR is ~60 C). Found with a userspace March C- tester
(`kbuild/pmemtest.c`); 70 hits before the reservation, 0 after.
- XNU: the managed RAM window (`tools/mkadt.py --raphael --highmem`) is **0x110000000 + 0xecc00000**
  (top 0x1fcc00000), above the hole; mkadt asserts it never overlaps 0x1016a0000-0x1016c0000.
- MIUI: `/reserved-memory/badram@1016a0000 { reg = <0x1 0x016a0000 0x0 0x20000>; no-map; }` in each SoC
  DTB, validated 2026-09-24 with `fastboot boot kbuild/boot-resv.img` (/proc/iomem hole, hot stress clean).
  `tools/stock-dtbs.py BOOT OUT --badram` writes the same node. Not flashed yet: to do when our image goes
  into `boot` (the chain-loaded MIUI must get it too; see phase 2).

**Bootloader (ABL) rules learned the hard way:**
- `fastboot boot` images must be **boot header v2** with the DTB in its own section (dtb_offset 0x1f00000).
  A v1 image (DTB appended to the kernel) loads and is never run (the K20 Pro port lost rounds to it).
- Raw kernels over ~20-32 MB fail with "Load Error"; ABL decompresses gzip. Our shim is tiny, the payload is
  the ramdisk, so this does not bite us, but keep the combo image (phase 2) in mind.
- The stock image is header v1 with four SoC DTBs appended to Image.gz (SM8150P v2, SM8150P v1, SM8150 v2,
  SM8150 v1, msm-id 0x169 / 0x153). We put all four into the v2 DTB section and let ABL choose.

**LUN 0 (4 KiB sectors)** from `raphael_backup/full/lun0/rawprogram0.xml`: ... persist 49152 (64 MiB),
logdump 81920 (64 MiB), minidump 98304 (128 MiB), **rawdump 131072 (128 MiB, our scratch partition)**,
recovery 163840, cache 180224 (256 MiB), cust 245760 (1 GiB), **userdata 507904-14026746 (13518843
sectors, 51.6 GiB)**. Same shape as davinci's LUN 0.

## SM8150 platform facts (from the K20 Pro port, cross-checked with mainline)

| Item | Value |
| --- | --- |
| GICD / GICR | 0x17a00000 / 0x17a60000 (stride 0x20000), GICv3, two security states |
| Timer | 19.2 MHz, phys INTID 18, virt INTID 19 |
| UFS host | ufshc@1d84000, initialized by ABL |
| SPMI | core 0xc440000, obsrvr 0xe600000, cnfg 0xc40a000 |
| RPMh apps RSC | 0x18220000, TCS 0x18220d00 |
| PSHOLD | 0x0c264000; imem restart_reason 0x146bf65c |
| Framebuffer | ABL cont_splash 0x9c000000 (0x2400000), panel 1080x2340 AMOLED (samsung,ams639rq08), command mode |
| CPUs | 8x Kryo 485, MPIDR Aff1 = core: cpu0 Prime 2.8416 GHz, cpu1-3 Gold 2.4192 GHz, cpu4-7 Silver 1.8048 GHz; ARMv8.2, no PAC |
| Touch | Goodix GT9886/GT9889 @ 0x5d on SE19 (0xc88000), TLMM GPIO 98/100 power, reset 54, IRQ 122; flash firmware boots slowly (0102 retry ladder) |
| Keys | power = PON KPDPWR, vol-down = PON RESIN, vol-up = PM8150 GPIO6 |
| Battery | PM8150B fg-gen4 (SID 2): SOC 0x4000, batt-info 0x4100; SMB5 charger CHGR 0x1000, USBIN 0x1300 |
| USB | DWC3 0x0a600000, HS PHY 0x088e2000 (7 nm snps femto v2); QUSB2PHY_PRIM_BCR 0x26000 (not mainline's 0x12000); USB gadget bring-up was rolled back in the K20 Pro port |
| GPU | Adreno 640 (A6xx, GMU), firmware a640_gmu.bin / a640_zap / a630_sqe.fw from vendor |
| Wi-Fi | WCN3990 (ath10k SNOC) behind the modem (MPSS, PAS 4); same chip family as davinci |

## Logs and test loop

- The shim appends breadcrumbs to the last 4 KiB of **rawdump**; the kernel copies its 4 MiB console ring to
  the last 4 MiB + 4 KiB of the `ufsroot=` partition (rawdump until the iOS root exists).
- After a test boot: back in MIUI (rooted), `adb shell su -c 'tail -c 4198400 /dev/block/by-name/rawdump' >
  out/rawdump-tail.bin`, then `tools/sweet-log.py` / `strings`.
- `sweetfb_noconsole=0` (`CONSOLE=1 tools/mkiosimg.sh ...`) keeps the kernel console on screen.

## Build

```sh
shim/build-clang.sh                                                # shim/out-clang/Image
python3 tools/mkadt.py out/raphael.adt --raphael --highmem         # needs research/ipsw-x/d22ap.adt for /product
python3 tools/stock-dtbs.py STOCK_BOOT.img dtb/raphael-stock.dtb   # e.g. kbuild/stock_boot.img
gh workflow run xnu.yml -R marnov999/raphael-ios-gpu               # or push to main touching xnu/patches
gh run download RUN -R marnov999/raphael-ios-gpu -n xnu-kernel -D out/kernel-RUN
CONSOLE=1 tools/mkiosimg.sh t1 out/kernel-RUN/kernel.development.raphael
fastboot boot out/raphael-ios-t1.img
```

`research/ipsw-x/d22ap.adt`: `ipsw img4 im4p extract .../Firmware/all_flash/DeviceTree.d22ap.im4p -o ...`
(the IPSW copy is in `davinci-ios/ipsw/`).

## Plan

1. **Kernel + display over `fastboot boot`** (current). XNU console on the panel, 8 cores, keys, touch probe.
   No iOS root yet: the kernel stops waiting for/failing to mount the root on rawdump. Nothing on userdata
   is touched.
2. **Boot partition image like davinci**: shim + XNU payload + MIUI's own kernel (`tools/mkcombo.py`,
   shim `linux.c` chain-load for charger mode and "Boot MIUI", boot menu). Needs davinci's shim parts
   (menu/linux/charge/battery/panel/spmi/diag) ported to the PM8150/PM8150B and raphael's panel, and the
   bad-RAM node in the FDT handed to MIUI. Then `fastboot flash boot` (keep the Magisk boot for rollback).
3. **Split userdata** into `iosdata` + `userdata` (GPT edit like davinci-ios/dualboot/PLAN.md: 64-entry table
   in LBA 2-5, iOS partition first, MIUI keeps the old GUID and is formatted fresh). **Wipes MIUI's data,
   including the /data/linux chroot** - explicit go-ahead first.
4. **iOS root** (`tools/mkiosroot.sh` + `tools/sweet-root-tweaks.py` + `tools/sweet-root-overlay.py`) written
   to iosdata; boot with `ROOT=iosdata`. Goal: lock screen, home screen, touch.
5. **GPU** like davinci: A640 power/GMU/zap/SQE, `sweet_gpu.c` (davinci 0083/0085, the HackiOS redwood
   port), surfaces, scanout, frame pacing, Metal/GLES. A640 vs A618: same A6xx family, other register
   values, other zap shader; the reference ports above show the A640 specifics.
6. Then davinci's other working parts, one at a time: USB networking + SSH, cpufreq/DVFS, battery %
   + charging, brightness/panel power, power off (0148), Wi-Fi, camera.

davinci patches to port (by area): touch 0082/0127/0128/0166; GPU 0083 0085 0133 0141 0145 0146 0189-0193;
display/scanout 0086-0093 0103-0108 0113 0116 0119-0122 0125 0126 0142 0151 0155 0157 0158 0183; surfaces
0096-0102 0123 0124 0136 0138 0169; profiler 0094 0095 0109 0117 0118 0129 0134 0139 0140 0143; sched/DVFS
0110-0112 0114 0115 0137 0144 0147; memory 0084 0130; power/panel 0148 0150 0153 0162-0165 0168; battery
0159 0172; system 0131 0135 0149 0152 0154 0156; RPMh 0174 0175; camera 0160 0161 0171 0173 0176-0188 0194 0195.

## Handoff

### 2026-11-02 (repo created, first test image)
- Kernel: CI run 41443364491 (commit 094c770), 7m39s, all 0082-0102 applied (only blacktop's own
  TrustCache/monterey/sonoma patches skipped, as on every build), board-macro guard passed.
  kernel.development.raphael sha256 271bb2a0...e210bf.
- QEMU (`tools/qemu-sweet.py`, ADT `--raphael --highmem --qemu`, cpus=1, needs proton-clang's llvm-nm on
  PATH): boots at phys_base 0x110000000 through MMU, platform expert, AKS, WDT, IOSurface root, HID
  buttons/touch, CPU init, BSD, battery service; then a synchronous external abort in AppleCLCD::start+0x420
  = the first read of `ml_io_map(0x0ae94000)` (DSI0 ctrl, raphael brightness probe 0098/0100). QEMU has no
  device there; on the phone ABL leaves DSI0 running. Expected, QEMU-only.
- Images (out/, not in git): `raphael-ios-t1.img` (cpus=8, sha256 9408d501...4442) and
  `raphael-ios-t1-1cpu.img` (fallback, a36207dc...744f); both CONSOLE=1, ufsroot=rawdump.
- Not run on the phone yet. Expected: kernel console on the panel, then no root (rawdump has no HFS+).
