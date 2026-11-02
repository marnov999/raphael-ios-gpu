#!/bin/bash
# build-clang.sh [OUTDIR] [extra CFLAGS] -> OUTDIR/Image (default out-clang): the raphael shim (-DRAPHAEL),
# built with proton-clang + ld.lld (no aarch64 gcc on this PC). -fno-builtin and -fno-jump-tables: the image
# runs unrelocated, so no absolute addresses (checked below) and no libc calls. Package it with
# tools/mkiosimg.sh, which wraps it in the boot header v2 raphael's ABL needs.
set -euo pipefail
cd "$(dirname "$0")"
P=${PROTON:-/home/marnov/xmiphones/kbuild/proton-clang/bin}
OUT=${1:-out-clang}; shift || true
CF="--target=aarch64-linux-gnu -O2 -ffreestanding -fno-builtin -nostdlib -fno-pic -fno-jump-tables -mgeneral-regs-only -mstrict-align -fno-stack-protector -Wall -Wextra -DRAPHAEL $*"
OBJ="start shim console mmu fdt loader ufs spmi menu linux charge"
mkdir -p "$OUT"
for f in $OBJ; do s=$f.c; [ $f = start ] && s=start.S; $P/clang $CF -c $s -o $OUT/$f.o; done
abs=$(for f in $OBJ; do [ $f = start ] || $P/llvm-readelf -r $OUT/$f.o; done | grep -c ABS64 || true)
[ "$abs" = 0 ] || { echo "error: $abs absolute relocations" >&2; exit 1; }
$P/ld.lld -T shim.ld --build-id=none -N -static $(for f in $OBJ; do echo $OUT/$f.o; done) -o $OUT/shim.elf
$P/llvm-objcopy -O binary $OUT/shim.elf $OUT/Image
truncate -s "$($P/llvm-nm $OUT/shim.elf | awk '$3=="_end"{print strtonum("0x"$1)}')" $OUT/Image
echo "$OUT/Image"
