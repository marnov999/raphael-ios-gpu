#!/usr/bin/env python3
"""Split raphael's MIUI boot.img (header v1) into what tools/mkcombo.py packs behind the XNU payload.

  python3 tools/unpack-miui-boot.py BOOT.img OUTDIR    -> OUTDIR/Image, OUTDIR/ramdisk.cpio, OUTDIR/cmdline.txt

The kernel blob is Xiaomi's UNCOMPRESSED_IMG wrapper (16-byte magic, u32 LE Image size, the raw arm64
Image) followed by the SoC DTBs; a gzip kernel (Image.gz + DTBs) is unpacked too. The DTBs are not
needed: ABL hands the shim the tree it built from the same DTBs and the dtbo overlays, and shim/linux.c
passes that on. The command line is the header's cmdline + extra_cmdline. Use the image the phone
boots now (Magisk-patched: its ramdisk keeps MIUI rooted).
"""
import os, struct, sys, zlib


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    d = open(sys.argv[1], 'rb').read()
    out = sys.argv[2]
    if d[:8] != b'ANDROID!':
        raise SystemExit('not an Android boot image')
    ks, ka, rs, ra, ss, sa, ta, ps, hv = struct.unpack_from('<9I', d, 8)
    if hv > 1:
        raise SystemExit(f'header v{hv}: expected raphael\'s stock v0/v1 layout')
    pg = lambda n: (n + ps - 1) // ps * ps
    kernel = d[ps:ps + ks]
    ramdisk = d[ps + pg(ks):ps + pg(ks) + rs]
    cmdline = (d[64:64 + 512].split(b'\0')[0] + d[608:608 + 1024].split(b'\0')[0]).strip()

    if kernel[:16] == b'UNCOMPRESSED_IMG':
        n = struct.unpack_from('<I', kernel, 16)[0]
        image = kernel[20:20 + n]
    elif kernel[:2] == b'\x1f\x8b':
        dec = zlib.decompressobj(16 + zlib.MAX_WBITS)
        image = dec.decompress(kernel)
    else:
        image = kernel
    if image[56:60] != b'ARMd':
        raise SystemExit('no arm64 Image found in the kernel blob')
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, 'Image'), 'wb').write(image)
    open(os.path.join(out, 'ramdisk.cpio'), 'wb').write(ramdisk)
    open(os.path.join(out, 'cmdline.txt'), 'wb').write(cmdline + b'\n')
    text_offset, image_size = struct.unpack_from('<QQ', image, 8)
    print(f'Image {len(image)} bytes (text_offset {text_offset:#x}, image_size {image_size:#x}), '
          f'ramdisk {len(ramdisk)} bytes (magic {ramdisk[:4].hex()}), cmdline {len(cmdline)} bytes')
    for word in (b'want_initramfs', b'skip_initramfs'):
        if word in image:
            print(f'kernel contains {word.decode()}')


if __name__ == '__main__':
    main()
