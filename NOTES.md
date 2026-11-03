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
- **13:38 `fastboot boot out/raphael-ios-t1.img` (serial 53d545e6): STEP 1 DONE.** Console on the panel; log
  pulled from MIUI (root) with `adb exec-out "su -c 'dd if=/dev/block/by-name/rawdump bs=4096 skip=31743'"`
  (= last 4198400 bytes; ring header SWEETLOG v1, 29443 bytes; shim block SHIMCRMB, 5 records). Local copy
  out/logs/t1-kernel.log. Observed:
  - shim: FDT 0x84521000 valid, payload 0x110000000/0xecc00000, 10 segments, jump to 0x11148f488.
  - vm_page_bootstrap 239108 free pages (3.65 GiB); 8/8 CPUs (PSCI CPU_ON rc=0, SGI1 OK).
  - SWEET FB: DSI ctrl0 ctrl=0x20030000 probe ok, panel DCS enabled; AppleCLCD 1080x2340 stride 4320 at
    0x9c000000, presented 1125x2436 (scaled).
  - SWEET UFS: rawdump LUN 0 first block 0x20000, 128 MiB, rw; log ring at block 0x27bff.
  - keys: power and volume events (PON + PM8150 GPIO); key census printed.
  - touch starts 45 s after boot: GT9886 pid "9886", 784 B cfg sent, 1080x2340, poll 10 ms.
  - battery: "static fallback, 100%" (real fg-gen4 readout not active in this config).
  - root: `hfs_ValidateHFSPlusVolumeHeader: unknown Volume Signature : 0`, errno 19, retried forever (expected).
  - **Ghost touches = two fixed rows: y=101 and y=318** (many down/up pairs, random x, no finger). Real
    touches were the swipes at y 1700-1900. Looks like two bad sensor lines; filter or re-tune later (step 4).

### 2026-11-02 (step 2 started: boot menu + MIUI chain-load, t2)
- Shim: davinci's spmi/menu/linux/charge modules ported; console.c, mmu.c (mmu_fast_copy), fdt.c
  (fdt_chosen_has, fdt_size, fdt_rebuild_for_linux) taken from davinci (three-way merge with upstream as
  base; raphael files were re-tabbed first, their tab->space drift made every line differ). loader.c
  merged cleanly (davinci's I-cache off before the XNU jump; shim.c turns it on at entry).
  - PPIDs: PON 0x008 (power bit 0, RESIN = vol-down bit 1; idle 0x4 = cable), vol-up PM8150 GPIO6 0x0c5,
    USBIN PM8150B 0x213 (bit 4).
  - linux.c: MIUI kernel at 0xc0000000 (+0x80000), else 0x140000000; never over FB (0x2400000), the bad
    DRAM, the ramdisk, the tree or the shim. **The tree MIUI gets carries badram@1016a0000 (no-map)**:
    fdt_rebuild_for_linux(..., bad_base, bad_size), skipped if the input tree has one. Host-tested with
    dtb_2 (SM8150 v2): dtc parses it, node identical to kbuild/boot-resv.img's.
  - Menu: "Boot MIUI" enabled when the image carries MIUI (linux_present), since userdata is MIUI's.
- MIUI parts: `boot` partition read from the phone = kbuild/raphael_magisk_boot_legacysar.img (sha256 of
  the used part 98485627...). `tools/unpack-miui-boot.py backup/boot-current-20261102.img backup/miui`:
  UNCOMPRESSED_IMG wrapper, Image 41963536 bytes (text_offset 0x80000, want_initramfs = Magisk), cpio
  ramdisk 427332, cmdline 333 bytes. `MIUI=backup/miui tools/mkiosimg.sh NAME KERNEL` packs it.
- Normal MIUI boot (reference, out/logs/miui-normal-cmdline.txt): ABL picks `androidboot.dtb_idx=2`
  (SM8150 v2, msm-id 339: this phone), dtbo_idx=10; DTB bootargs first ("ramoops_memreserve=4M rcu..."),
  then the image cmdline, then ABL's words (verity dm=, vbmeta, skip_initramfs ...). Panel:
  `msm_drm.dsi_display0=dsi_ss_fhd_ea8076_global_cmd_display` (Samsung EA8076, command mode).
  /proc/iomem: System RAM c0000000-1ffffffff in one piece (bad pages in use) before the fix.
- Image: out/raphael-ios-t2.img (61 MB = shim + XNU payload + MIUI kernel/ramdisk/cmdline), CONSOLE=1,
  ufsroot=rawdump. To test with fastboot boot: menu; Boot MIUI (expect rooted MIUI, iomem hole
  1016a0000-1016bffff); Boot iOS (as t1); Power off.
- **13:56-13:57 t2 on the phone:** menu shown; Power off works; Boot MIUI works: MIUI ready 25 s after
  `fastboot boot`, rooted (magisk), cmdline = the normal boot's 76 words + sweet.t0/tc/hz,
  /proc/iomem System RAM `c0000000-10169ffff` + `1016c0000-1ffffffff` (hole = badram), node
  /proc/device-tree/reserved-memory/badram@1016a0000, MemTotal 5633752 kB (= boot-resv.img's).
- Menu default: `sweetdefault=miui` in the boot image's cmdline (DEFAULT=miui tools/mkiosimg.sh) makes the
  countdown boot MIUI: the image to flash while iOS has no root. t3 = t2 + that.
- **14:01-14:03 t3 on the phone (sha256 f6fd80d8...):** countdown with no key -> MIUI by itself (shim
  ~11.1 s from entry to hand-off = 10 s countdown + copy), `sweetdefault=miui` absent from MIUI's
  /proc/cmdline, badram hole present; Boot iOS (vol-up, power) -> XNU console + mount-root loop as t1.
  All three menu paths verified. Next: flash t3 to `boot` (user's OK pending); then test off-mode charging.

### 2026-11-02 (step 2 flashed, step 3 done: userdata split, MIUI unencrypted)
- **14:14 t3 flashed to `boot`** (sha256 f6fd80d8...); boots the menu -> MIUI by countdown. Rollback:
  `fastboot flash boot backup/boot-current-20261102.img` (= kbuild/raphael_magisk_boot_legacysar.img).
- Old userdata: ext4, **FBE** (`fileencryption=ice,wrappedkey`, TrustZone-wrapped keys), 51 GB, 45 GB used of
  which 39 GB /data/local/tmp/cp2077 (deleted on the user's word). Raw image impossible (PC 27 GB free, and
  only restorable to this phone). File backup (root tar over adb, 5.3 GB, SHA256SUMS):
  `/home/marnov/xmiphones/raphael_backup/userdata-files-20261102/` = magisk (/data/adb), adbkeys
  (misc/adb), linux (chroot 2.7 GB), localtmp, media (/data/media/0), system, net (wifi WifiConfigStore,
  bluedroid), apps (/data/app), appdata (data + user_de), packages-3rdparty.txt, getprop, cmdline.
- **MIUI without FBE** (tools/miui-overlay.py): Magisk overlay.d in the chain-loaded ramdisk carries a copy
  of /vendor/etc/fstab.qcom whose /data line drops fileencryption/wrappedkey/inlinecrypt and adds
  formattable, and an rc `on late-fs: mount_all ${MAGISKTMP}/fstab.qcom --late`. Magisk merges it into
  init.rc, whose late-fs actions run before vendor's init.target.rc: ours mounts /data, vendor's
  `mount_all /vendor/etc/fstab.qcom --late` then fails with "queue_fs_event() failed: Invalid code: -1"
  (harmless). Dead ends, both on the encrypted data with an unchanged fstab: init `mount ... bind` over
  the vendor file = avc denied mounton (vendor_configs_file); `exec u:r:magisk:s0 -- mount -o bind` in
  early-fs or on init = MIUI recovery `--prompt_and_wipe_data --reason=enablefilecrypto_failed` (user
  picked Reboot to System; data intact). Verified the mount_all variant with the FBE fstab first.
  /vendor is dm-verity (dm-0): editing the real file is not an option.
- **GPT split** (tools/gpt-split.py, from the live sectors; phone GPT == Sept EDL dump): #31 iosdata
  507904-7061503 (25 GiB, new GUID), #32 userdata 7061504-14026746 (26.57 GiB, old GUID); 32-entry table,
  slot 32 was free. Written from rooted MIUI. toybox dd: `conv=fsync` unknown and without `notrunc` it
  ftruncates -> the tail write failed before copying (rewritten with conv=notrunc, both halves read back
  OK). Undo = original sectors in backup/gpt-lun0-20261102/lun0-{head,tail}.bin. ABL getvar after reboot:
  iosdata 0x640000000, userdata 0x6A47FB000.
- **t4 flashed** (sha256 1087e860..., MIUI=backup/miui-unenc, ROOT=iosdata, DEFAULT=miui) and
  `fastboot format:ext4 userdata` (needed chmod +x platform-tools/mke2fs). 14:59 reboot into MIUI's
  first boot. Next: user does setup + USB debugging; verify ro.crypto.state=unencrypted; restore
  magisk/adb keys/wifi/chroot/tmp from the backup; then step 4 (iOS root into iosdata).
- **15:05-15:20 MIUI fresh, unencrypted, restored.** `ro.crypto.state=unsupported`, /data = sda32 26 GB ext4
  without inlinecrypt. Root: magiskd (ramdisk) installs the stub app; it fetched the full Magisk 30.7 app
  over Wi-Fi, "additional setup" + reboot from the app -> `su` = /product/bin/su (before that only
  /debug_ramdisk/su, prompt timed out once); shell granted on the phone.
  Restored (exec-in `su -c 'tar -xf - -C /data'`, then restorecon): /data/linux (2.7 GB), /data/local/tmp,
  /data/media/0. Not restored on purpose: magisk.db (policies keyed by old app UIDs; old modules dir was
  empty), system settings, app data. adb_keys: old = the same single key. Wi-Fi: old store had one network
  ("wifi", wpa2) -> `cmd wifi add-network` next to the new TP-Link_02E4_5G (no file replace).
  /data/lxc.sh was NOT in the backup (lived in /data itself): recreated (bind /dev, /dev/pts, proc, sysfs,
  resolv.conf, chroot bash -l); tested: Ubuntu 24.04.5, /dev/kgsl-3d0 visible, DNS ok.
- Open: off-mode charging through the flashed image (power off, plug charger); 6 third-party apps
  (packages-3rdparty.txt, APKs in apps.tar) if wanted. Next: step 4, the iOS root into iosdata.

### 2026-11-02 (step 4 done: iOS lock screen)
- Root: `tools/build-root.sh` (ubuntu:22.04 --privileged container, IPSW dmgs from davinci-ios/ipsw, apfs-fuse,
  mkiosroot + sweet-root-tweaks, no davinci overlay): out/root/ios16-root-raphael.img, 26835156992 bytes
  (= iosdata - 8 MiB), 12 GB used, fsck clean, sha256 88652eb0...
- Write: first try (gzip | adb exec-in su -c 'gzip -dc | dd') wrote NOTHING - Magisk su's stdin relay makes
  toybox dd stop after one 4 MiB block and toybox gzip -dc output nothing; only the final sha256 caught it.
  `tools/write-root.sh` now pushes 512 MiB chunks with adb push, dd's them from the file, verifies each on
  the partition, writes all-zero chunks from /dev/zero: 50/50 verified, 12792 MiB sent, 12 min.
- **16:10 `fastboot boot out/raphael-ios-t5.img`, Boot iOS: lock screen** after a long first boot (> 15 min
  on the Apple logo; user saw it on the lock screen later). Unlock works (very laggy: CPU compositing),
  display off/on works, Settings > storage 27 GB, 13.69 GB free.
- Next: step 5, the GPU (Adreno 640) and the GLES path as on davinci.

### 2026-11-02 (full RAM: 5 GiB)
- t6 (0xb0000000 + 0x14cc00000, pmap_next_page skipping the bad pages): panic vm_resident.c:2627
  `phys_page == VM_PAGE_GET_PHYS_PAGE(mem)`: arm64 derives a vm_page's address from its index in vm_pages[],
  the array cannot have holes. 0103 now marks the bad pages vmp_error (retired, stay wired) in pmap_startup
  and vm_get_delayed_page; pmap_next_page_hi (steal) panics if it would hand one out.
- t7/t9 (same window, retired pages: "8 bad pages retired", 336975 free pages): userland hung after
  usermanagerd's UMD_INIT, kernel alive (keys, SMP samples), and t9 never wrote its log ring (iosdata tail =
  t7's byte for byte): UFS DMA stalled. 0104 (davinci 0084: recover + log 32-bit PA truncations) added.
- Cause: this phone's /memory node (MIUI /sys/firmware/devicetree/base/memory/reg) = <0x80000000 0x3cc00000>
  <0xc0000000 0x80000000> <0x140000000 0xc0000000>: the firmware keeps 0xbcc00000-0xc0000000 (52 MB, in the
  middle; davinci keeps the top 52 MB). The window crossed it.
- **t10: 0xc0000000-0x200000000 (5 GiB, mkadt --raphael --fullram) -> lock screen.** The 204 MB at
  0xb0000000-0xbcc00000 would need a second keep-out plus cutting the hole out of the physmap (speculative
  reads of firmware memory); not done.
- **20:51 flashed f10** (FLASH=1: no sweetnocharger; iOS default; kernel run 41507798047 = 0103+0104;
  sha256 d8ac15f2...). Rollback: backup/boot-current-20261102.img or backup/flashed/*.


### 2026-11-02 (step 5: Adreno 640, layers 1-2)
- Firmware (NOT in git): research/fw-raphael/ from the vendor partition backup (debugfs on
  raphael_backup/full/lun4/vendor.bin): a640_gmu.bin, a630_sqe.fw (= davinci's), a640_zap.mdt/.b00-.b02, SHA256SUMS.
  `tools/mkadt.py OUT --raphael --fullram --fw=research/fw-raphael` puts the GMU/SQE/zap pieces into ADT /sweet-fw
  (out/raphael-full-fw.adt, 91652 bytes); sweet_gpu.c reads them from there.
- **0105 (layer 1, sweetgpu=1..5), g1 via fastboot boot, verified:** `CX: gdscr 0xf8222000 hw_ctrl 0x80001fe0 -> on`,
  `gmu_clk_src cfg 0x602 (was 0)`, GMU window reachable (cm3_sysreset=1, fw_init=0). Open: PAS_IS_SUPPORTED(13)
  answered x0=0 x1=0 (query form? retest with a real zap load in layer 3). Log: out/logs/g1-kernel.log.
- **0106 (layer 2, sweetgpu=6) = GMU boot, written, compiles (proton-clang via tools/xnu-cc.py), commit 9038dd4,
  CI run 41519518380.** Sequence (Helium hakios.adreno.c + Linux a6xx_gmu.c + davinci values): GMU memory through
  GPU SMMU context 1 (SMR 1 = stream 5 mask 0x400, ACTLR 0x303, 39-bit 3-level 4K tables, PTE 0xE03),
  blocks 0x4000/0x44000 (0x3c000), 0x60000000, firmware "needs" blocks, log 0x60002000, HFI 0x60006000;
  a640_gmu.bin TCM blocks via registers (read back); PDC (TCS1/TCS3 from cmd-db mx/cx/xo.lvl) + RSCC sequencer;
  register_config; release reset -> wait 0xBABEFACE; HFI v2 table (3 queues); PERF_TABLE (speed bin 0 levels
  257..585 MHz), BW_TABLE, CORE_FW_START, GX_BW_PERF_VOTE (sweetgpu_speed=N, default 1 = 257 MHz); OOB bit 30 ->
  bit 31; HFI START; RBBM readout. Every failure prints the SMMU fault registers.
- Test plan g2: `ADT=out/raphael-full-fw.adt ROOT=iosdata MIUI=backup/miui-unenc tools/mkiosimg.sh g2 K sweetgpu=6
  sweetusb=2`; live log over USB ethernet: host nmcli con `sweetusb` (enx02005e77ee01, 192.168.7.1), `nc -ukl 5140`.
  NOTE the gadget MAC/IPs equal davinci's: only one phone may run sweetusb=2 at a time.
- **g2 (0106+0107, sweetgpu=6 sweetusb=2) 21:41: phone reset early**, fell back to the flashed f10 (iOS default),
  whose boot overwrote the log ring (proof: ring's boot-args = f10's, trailing space). Nothing from USB either.
- 0108 (commit 4c914db, CI 41523313469): sweet_log_sync() + 14 logged/synced GMU steps, sweetgpu_stop/_delay.
- **g3 (0108, sweetgpu=6 sweetgpu_delay=5, NO sweetusb=2) 22:00: GMU BOOTS, 3D CORE POWERED, iOS lock screen.**
  out/logs/g3-kernel.log: smmu idr0 0x4c017e06; stream 5 -> context 1 (smr 0x84000005) accepted by the hypervisor;
  5464 TCM words, 0 wrong, versions core 0x20000105 power 0x20000012 hfi 0x20000001; cmd-db mx 0x30010 cx 0x30000
  xo 0x30090; `fw_init 0xbabeface`; HFI version 0x20000001; PERF/BW tables, CORE_FW_START, GX vote (257 MHz),
  START all accepted; OOB grant intr_info 0x80000000, gx_gdscr 0xf8222800; rbbm_status 0x1 int0 0.
  => g2's reset was almost certainly sweetusb=2 (davinci's gadget: QUSB2-era code, SM8150 has the SNPS femto HS
  PHY): USB live log on raphael is OPEN, do not use sweetusb=2 until fixed.
- Next: layer 3 = GPU SMMU context 0 (stream 0 mask 0x400 per dt, ACTLR 0x303), ringbuffer, SQE (a630_sqe.fw), CP init
  with A640 UBWC values, zap via PAS (a640_zap.mdt + .b02 in /sweet-fw), self tests.
- **g4 (0109, commit 81f25f8, CI 41527020707; sweetgpu=7 sweetgpu_delay=5) 22:26: COMMAND PROCESSOR WORKS, lock screen.**
  out/logs/g4-kernel.log: stream 0 mask 0x401 -> context 0 (smr 0x84010000, our 3-level tables, HUPCF); zap:
  PAS_INIT_IMAGE(mdt as shipped) 0/0, MEM_SETUP(0x98f15000, 0x1000) 0/0, AUTH_AND_RESET 0/0 (dt
  pil_gpu_region@98f15000; no PAS_SHUTDOWN first); hw_init a640 values; SQE start clean (sgfsr 0); ME_INIT (8 words)
  consumed; SET_SECURE_MODE 0 consumed; CP_MEM_WRITE 0x600dc0de + CACHE_FLUSH_TS 0x12345678 read back.
  GPU VAs: ring 0x01000000 (0x8000), SQE 0x01100000, scratch 0x01200000; RB_CNTL 0x800020c (no rptr shadow, poll
  CP_RB_RPTR). Next: shader tests (compute store, triangle) on this ring, then port davinci's KGSL/DRM UAPI.
- **g5 (0110, commit 1f2a737, CI 41530678205; sweetgpu=8) 22:50: SHADERS RUN, FIRST TRIANGLE, lock screen.**
  out/logs/g5-kernel.log: compute stg 0xdeadbeef + TS 0xc0de; triangle centre 0xff0000ff, corner 0xff400000,
  181/1024 samples red, TS 0xd3ad/0xd3ae. a640 values that matter: Mesa magic_regs GPUId(640), RB_CCU_CNTL
  0x10000000 (sysmem, 2 CCUs). Test VAs: shaders 0x01300000, VBO 0x01400000, target 0x02000000.
- Next (layer 4): port davinci's /dev/kgsl-3d0 + MSM-DRM UAPI (davinci sweet_gpu.c ~2979-5350: ring/fence,
  gpumem alloc/mmap, GPU_COMMAND/GEM_SUBMIT, iOS surface import, present) onto this ring/context-0 tables; then
  the userland stack (Mesa freedreno, libredwood-gl FD_MESA_GMEM 1 MB, SweetGLES/RedwoodMetal, root overlay).
- **0111-0113 (commit a156ff7): davinci's kernel stack ported** (3-way: ios-sweet 0081 base built in
  scratchpad m3/O, davinci = devtools/work/replay @0195, raphael = CI tree + 0105-0110).
  0111 generic davinci deltas as-is (sched big cores SWEET_BIG_CPU=4 on SM8150, kmsg sig off, IOKit root,
  profiler, AMFI dyld/extension policy, sweettrace). 0112 davinci SweetSurface/SweetFramebuffer/SweetBacklight/
  sweet_dpu + SweetHID scaled touch (raphael 2340 rows) + new sweet_panel.c (raphael panel hooks over the DSI
  TPG FIFO; NOTE Gsjsjzhznsz's brightness packet lacked the 0x51 byte, ours sends 0x51 hi lo) + fbcon globals.
  0113 davinci KGSL/DRM front-ends (sliced from davinci sweet_gpu.c by scratchpad port_kgsl.py) on the A640
  ring: sweetgpu=9 publishes ring (now contiguous + NC view) + result page (GPU VA 0x01800000) + buffers at
  4..8 GB; chip 0x06040001, gpu_id 640, GMEM 1 MB, hbb 15; speed = HFI GX_BW_PERF_VOTE. Not ported (davinci
  hardware): camera, qg battery, Wi-Fi, cpufreq/dvfs, PMIC fastboot reboot, davinci panel DSI driver.
- **g6 (0111-0113 + fix 991ca30, CI 41537831411; sweetgpu=9) 23:38: lock screen; KGSL + MSM-DRM SELF-TESTS PASS.**
  out/logs/g6-kernel.log: [KGSL] ring at word 351, result page gpu 0x1800000, buffers from 0x100000000;
  /dev/kgsl-3d0 devinfo chip 0x6040001 gpu 640, [U] submit readback 0x5afe600d; /dev/dri/renderD128 (msm) [V]
  GEM_NEW+SUBMIT+fence 2 readback 0x5afeda7a. davinci SweetFramebuffer runs (1080x2340 scaled from 1125x2436),
  SweetBacklight published, SweetHID scaled touch; SWEET PANEL: DSI ctrl0 takes commands; sel 50 brightness
  10000 -> 2047 OK. IOAcceleratorES NOT published (needs sweetmetal=1 AND the userland in the root: SweetGLES,
  RedwoodMetal, Mesa) -> backboardd polls for it; software compositing as before.
- Next: userland (davinci's Mesa freedreno a6xx build, libredwood-gl FD_MESA_GMEM 1 MB, SweetGLES, RedwoodMetal,
  shims, root overlay) -> rewrite iosdata root (needs the user's OK) -> sweetmetal=1. USB gadget (sweetusb=2) on
  SM8150 still resets the phone: fixing it would give davinci's sweet_push fast loop (no root rewrites).

### 2026-11-03 (userland: davinci's overlay on the live root)
- The root on iosdata had a dirty HFS+ journal (every iOS run so far ended in a forced reset): Linux cannot replay
  it, and patching under it would be undone/corrupted by XNU's replay. Clean way: iOS Settings > General > Shut
  Down (power+vol-up 15 s = hardware reset, not clean); it then panics "halt/reset timed out" (no power-off
  hook on raphael yet) AFTER unmounting -> tools/hfs-journal.py: cleanly unmounted, journal EMPTY.
- tools/sync-root-from-phone.sh (pull only chunks whose sha differs) -> out/root image = phone root (11+12
  chunks); tools/overlay-root.sh (privileged ubuntu container, Linux fsck_hfs only reports iOS's hard-link
  counts) ran tools/sweet-root-overlay.py --accept-changed: 277 changes (Mesa freedreno/turnip, libredwood-gl,
  metalshim + shims, RedwoodMetal, SweetGLES, launchd edits, staged apps, 2 dyld-cache patches, tools, assets).
  Phone's pre-overlay copies of the 17 changed chunks: backup/root-preoverlay-20261103/ (CHUNKS.txt: index,
  4M-block seek, count, sha) -> rollback = dd them back. tools/write-root.sh --changed wrote 17 chunks, all
  verified (8704 MiB).
- NOTE libredwood-gl sets FD_MESA_GMEM=524288 (davinci's A618): safe on the A640 (1 MB), only smaller bins.
- **g7 (out/raphael-ios-g7.img, sweetgpu=9 sweetmetal=1) 01:0x: Apple logo for 24+ min.** Sampler
  (SpringBoard, backboardd) symbolicated with ipsw dyld a2s: SpringBoard main thread in +[AVSystemController
  sharedInstance], backboardd t1 in vfbremote_connect, both synchronous XPC to mediaserverd, which launchd never
  started ("Missing executable ... /usr/local/lib/sweet_media_shim"): the overlay edited the job but never wrote
  the launchd group's files. Also seen: bluetoothd and nanotimekitcompaniond respawn loops (not looked at).
- 09:00 fix (20a8dd3): overlay writes the group's files; --no-media-shim (raphael has no davinci camera: Apple's
  mediaserverd job unchanged). The forced reset left the journal dirty again (17 lists / 77 blocks) ->
  tools/hfs-journal-replay.py --apply (also sets the clean-unmount bit: Linux hfsplus mounts read-only without
  it, even with force). Synced 9 chunks, overlay --accept-changed --no-media-shim (3 changes; re-run 0),
  phone copies of the 4 chunks it changed in backup/root-pre-g7b-20261103/, write-root --changed 4 chunks ok.
  09:07 g7 booted again via fastboot boot. Result: (pending)
- Every later root patch: sync -> hfs-journal-replay.py (dry run, then --apply) -> overlay -> back up the phone
  copies of the chunks that differ -> write-root.sh --changed. Disk: ~3 GB free after this.
