# raphael-ios-gpu

**Apple's iOS 16 on the Xiaomi Mi 9T Pro / Redmi K20 Pro (`raphael`, Snapdragon 855).**

A port of Apple's open-source XNU kernel (xnu-8796, the iOS 16 generation) to the SM8150, running the
unmodified iOS 16.7.16 (20H392) userland of the iPhone X. It is the sibling of
[davinci-ios-gpu](https://github.com/marnov999/davinci-ios-gpu) (Mi 9T, SM7150) and follows the same layout
and plan: first boot over `fastboot boot`, then our image in the boot partition with MIUI still bootable,
the iOS root in its own partition, and the GPU (Adreno 640).

> Experimental bring-up, not a usable phone OS. Apple's security model is mostly switched off. Installing
> the iOS root (a later step) replaces Android's user data.

## Status

| Step | State |
| --- | --- |
| 1. XNU + display via `fastboot boot` | first test image built, not yet run on this phone |
| 2. Boot-partition image (shim + XNU + MIUI kernel, boot menu, charger mode) | planned |
| 3. userdata split into `iosdata` + `userdata` | planned |
| 4. iOS root, lock screen, home screen, touch | planned |
| 5. GPU (Adreno 640), Metal/GLES, frame pacing | planned |
| 6. USB networking, cpufreq, battery, Wi-Fi, camera, ... | planned |

Details, hardware facts and the handoff log: [NOTES.md](NOTES.md).

## How it boots

```
ABL (Xiaomi bootloader, unlocked)
  -> fastboot boot raphael-ios-NAME.img     boot header v2: shim = kernel, xnu payload = ramdisk,
                                            the four stock SoC DTBs in the DTB section (ABL picks one)
     -> shim: own MMU setup, reads the live FDT, breadcrumbs to rawdump, loads the payload
        -> XNU Mach-O + generated Apple Device Tree (ADT) + boot-args
           -> XNU -> UFS driver -> HFS+ root (ufsroot=) -> launchd -> backboardd + SpringBoard
```

## Repository

| Path | What |
| --- | --- |
| `xnu/patches/` | 0001-0081 from ios-sweet, 0082-0102 raphael board patches (`MACHINE_CONFIG=RAPHAEL`) |
| `shim/` | the bare-metal shim ABL boots (`shim/build-clang.sh`) |
| `tools/` | ADT, payload and boot image builders (`mkadt.py`, `mkpayload.py`, `stock-dtbs.py`, `mkiosimg.sh`), iOS root scripts, log tools |
| `.github/workflows/xnu.yml` | kernel build on GitHub's macOS runners (blacktop/darwin-xnu-build) |

## Build a test image

```sh
shim/build-clang.sh
python3 tools/mkadt.py out/raphael.adt --raphael --highmem
python3 tools/stock-dtbs.py path/to/stock-boot.img dtb/raphael-stock.dtb
gh run download RUN -R marnov999/raphael-ios-gpu -n xnu-kernel -D out/kernel-RUN
CONSOLE=1 tools/mkiosimg.sh t1 out/kernel-RUN/kernel.development.raphael
fastboot boot out/raphael-ios-t1.img
```

Not in git (gitignored): your phone's boot image and DTBs, partition backups, and anything of Apple's
(the IPSW, `research/ipsw-x/d22ap.adt`, the iOS root image).

## Credits

[CREDITS.md](CREDITS.md). Built on ios-sweet by dipa-studio and the K20 Pro port by Gsjsjzhznsz and
contributors. iOS, iPhone and Apple are trademarks of Apple Inc.; this project is not affiliated with Apple.
