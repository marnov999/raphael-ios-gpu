# XNU for raphael

Built on GitHub's macOS arm64 runners by `.github/workflows/xnu.yml`, using
[blacktop/darwin-xnu-build](https://github.com/blacktop/darwin-xnu-build) (MIT) at a pinned commit.

- `MACOS_VERSION=13.5` -> xnu-8796 (same generation as iOS 16.6/16.7, the last iOS for iPhone 8/X).
- `MACHINE_CONFIG=RAPHAEL` (default, also for push builds): `-DARM64_BOARD_CONFIG_RAPHAEL
  -DARM64_BOARD_CONFIG_SWEET`. Every shared ios-sweet driver path stays on; raphael deltas sit behind
  `#if defined(ARM64_BOARD_CONFIG_RAPHAEL)` (patch 0082 adds the config).
- `patches/*.patch` are copied into the build script's patch dir and applied to the xnu tree with `git apply`.
  The build script only warns about a patch that does not apply; the workflow fails the run instead
  ("Guard - no silently skipped patches").
- Output: `kernel.development.raphael` in the `xnu-kernel` artifact.

Fetch a build: `gh run download RUN -R marnov999/raphael-ios-gpu -n xnu-kernel -D out/kernel-RUN`
