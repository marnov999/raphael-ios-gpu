# RedwoodMetal + Mesa AIR changes for third-party Metal games (2026-11-19)

The Metal driver (RedwoodMetal.bundle) and its compiler library (libredwoodair.dylib) are built from
davinci's tree, which is not in this repository:

- `davinci-ios/gpu/userland/metal/redwood/redwoodmetal.m` (+ `redwooddrawable.m`)
- `davinci-ios/gpu/userland/mesa/src-mesa/src/compiler/air/` (Mesa 24.2.8 + our AIR frontend), build tree
  `davinci-ios/gpu/userland/mesa/build-fdgl`

The two patches here are the changes made for raphael's games, against the `.bak-20261119` copies in those
directories:

| patch | what |
|---|---|
| `redwoodmetal-games.patch` | (1) a recorded draw/dispatch RETAINS its buffers, textures, samplers and pipelines until its command buffer is freed (MRC file; LIMBO's autoreleased `setVertexBytes:` buffer was freed before commit: "unrecognized selector" in runDraw); (2) PIPELINE REFLECTION: `newRenderPipelineStateWithDescriptor:options:reflection:error:` returns `vertexArguments` / `fragmentArguments` built from `rwa_function_arguments` (LIMBO binds only what reflection lists: with nil it bound nothing); (3) one recursive lock over every Mesa call, `-commit` held under it, handlers delivered after (LIMBO commits from two threads); (4) a draw without a depth attachment runs with the library's depth-off state (LIMBO's 2D pass kept the scene pass's depth test: NULL zsbuf in batch_draw_tracking); (5) unbound fragment texture / sampler slots 0-7 get a 1x1 zero texture / default sampler (Apple reads zeros; `/usr/local/gltest/rw_unbound_strict` keeps the refusal); (6) debug: `/usr/local/gltest/rw_log_host` = `IP[:PORT]` (raphael: `192.168.9.1:5152`, listener `tools/usblog.py out/logs/rw-5152.log 5152`), `/usr/local/gltest/rw_trace_bind` = process name logs binds/encoders/reflection, `/usr/local/gltest/rw_no_reflection` disables (2). |
| (later the same day) | (7) ETC2/EAC + ASTC formats (Angry Birds' levels were black), block-aware uploads; (8) Metal VIEWPORT and SCISSOR rectangles applied (Minecraft drew 1x1-viewport passes over the whole screen: white); (9) integer vertex formats feeding float attributes as Gallium SCALED formats (Minecraft's world pipelines were refused); (10) a render pass that draws nothing still clears (`rwa_clear`); (11) `pipe_surface_reference`/`pipe_sampler_view_reference` instead of destroying surfaces a pending batch still holds (use-after-free in lookup_gmem_state on flush); (12) reflection objects are real subclasses of MTLArgument / MTLStructType / MTLStructMember / MTLRenderPipelineReflection (apps add categories: Real Racing 3); debug `/usr/local/gltest/rw_frame_dump` = process name (touch it again to re-arm) dumps the next 60 command buffers' draws/clears, BIG UPLOAD lines for >=1 Mpx uploads. Deployed binaries: `backup/redwood-deployed-20261119/` (not in git). |
| (staged, not yet on the phone) | (13) MSAA resolve (`rwa_resolve`) -- deployed; (14) uniform ARRAYS in reflection as MTLDataTypeArray + MTLArrayType (Minecraft's Gameface UI keeps all constants in `float4 Data_VS[128]` / `Data_PS[128]`: reported as one float4, the new menus never drew); (15) per-process feature profile, `/usr/local/gltest/metal_profile` lines "PROCESS N" / "* N" (Unity decodes ASTC on the CPU under Apple1). Binary: backup/redwood-deployed-20261119/RedwoodMetal.staged-arrays. |
| (staged 2026-11-19 pm) | (16) PVRTC 160-167 stored as RGBA8 and decoded on upload (`pvrtc_decode.h`, from hakios-metal, MIT; verified on the PC against Real Racing 3's .pvr files); binaries backup/redwood-deployed-20261119/*.staged-pvrtc*. |
| `mesa-air-reflection.patch` | `struct air_resource` gains the buffer's struct members (from `air.struct_type_info`), and `rwa_function_arguments()` lists a function's direct buffer / texture / sampler arguments with names, indices and members. |

Build (as for davinci):

```sh
ninja -C davinci-ios/gpu/userland/mesa/build-fdgl src/gallium/drivers/freedreno/libredwoodair.dylib
cd davinci-ios/gpu/userland/metal
SDK=../mesa/sdk/repo/iPhoneOS16.5.sdk
/home/marnov/xmiphones/kbuild/proton-clang/bin/clang -target arm64-apple-ios16.0 -isysroot $SDK -fuse-ld=lld -O1 \
  '-DNS_FORMAT_ARGUMENT(A)=' -bundle -framework Foundation -framework IOKit -framework Metal -framework QuartzCore \
  -framework IOSurface -lobjc -o OUT/RedwoodMetal redwood/redwoodmetal.m redwood/redwooddrawable.m
ldid -Hsha256 -Cadhoc -S OUT/RedwoodMetal      # and the same ldid for libredwoodair.dylib
```

On the phone: `/System/Library/Extensions/RedwoodMetal.bundle/RedwoodMetal` and `/usr/local/lib/libredwoodair.dylib`
(push 0644, then `gbx chmod 755`: sweet_push spawns files that arrive executable). Backups of the phone's
previous copies: `backup/RedwoodMetal.phone-20261119`, `backup/libredwoodair.phone-20261119.dylib`.
A process only gets Metal if its name is in `/usr/local/gltest/metal_allow` (backup `backup/metal_allow.phone-20261119`).
