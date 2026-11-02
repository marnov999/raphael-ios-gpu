# Credits and licences

This repository keeps ios-sweet's [MIT License](LICENSE) for its own code. `xnu/patches/` modify Apple's XNU,
which is under the **Apple Public Source License 2.0**; the patched files stay under the APSL 2.0.

- **ios-sweet** (dipa-studio, <https://github.com/dipa-studio/ios-sweet>, MIT): patches 0001-0081, the shim
  and most of `tools/`.
- **ios-raphael** (Gsjsjzhznsz and contributors, <https://github.com/Gsjsjzhznsz/ios-raphael>, a fork of
  ios-sweet under its licence): patches 0082-0102 (`raphael-*`), the shim's `RAPHAEL` paths and the
  raphael parts of `tools/mkadt.py`.
- **davinci-ios-gpu** (<https://github.com/marnov999/davinci-ios-gpu>): `tools/mkcombo.py`,
  `tools/sweet-root-overlay.py`, `shim/build-clang.sh`.
- **HeliumStudio's HakiOS raphael port** (<https://github.com/HeliumStudio-Dev/hackios-xnu-kernel>,
  APSL 2.0 for its XNU files): the Adreno 640 bring-up order and values `bsd/dev/sweet_gpu.c` follows from
  stage 6 on (GMU memory blocks, PDC/RSCC sequencer words, HFI v2 messages, the GPU SMMU entries). The driver
  itself is davinci-ios-gpu's, adapted; no file is copied from it.
- **davinci-ios-gpu's GPU driver** (`bsd/dev/sweet_gpu.c` there): structure, cmd-db reading and RPMh votes.
- **XNU** (Apple, APSL 2.0): xnu-8796.141.3, built with
  **blacktop/darwin-xnu-build** (<https://github.com/blacktop/darwin-xnu-build>, MIT).
- **AOSP mkbootimg** (`tools/mkbootimg.py`, Apache 2.0).
- Hardware facts from Xiaomi's published raphael kernel sources and mainline Linux (GPL-2.0), as noted in
  NOTES.md.

Nothing from Apple's iOS, Xiaomi's firmware or this phone's partitions is in this repository.
