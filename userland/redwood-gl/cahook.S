/*
 * cahook.S (raphael, 2026-11-03): the stubs of cahook.c's inline hooks. A hooked function's head jumps to
 * its stub, which keeps every argument register, has ch_log(id, x0, x1, d0) note the call, and goes on
 * into the function through its trampoline (its first four instructions, then back), with the caller's
 * lr untouched: the function returns to its caller itself.
 */
	.text
/*
 * The trampolines, made here: each hooked function's first four instructions (iOS 16.7's shared cache;
 * cahook.c checks them before it hooks), then on into the function past them (ch_back). Written at run
 * time into this text they were not executable again (backboardd: "Data/Stack execution not permitted").
 */
.macro CH_TRAMP n, w0, w1, w2, w3
	.globl _ch_tramp_\n
	.p2align 2
_ch_tramp_\n:
	.long	\w0, \w1, \w2, \w3
	adrp	x16, _ch_back@PAGE
	add	x16, x16, _ch_back@PAGEOFF
	ldr	x16, [x16, #(\n * 8)]
	br	x16
.endm
	CH_TRAMP 0, 0xd10503ff, 0x6d0d23e9, 0xa90e6ffc, 0xa90f67fa      /* IOMFBServer::vsync_callback */
	CH_TRAMP 1, 0xd101c3ff, 0xa9035ff8, 0xa90457f6, 0xa9054ff4      /* IOMFBServer::timer_callback */
	CH_TRAMP 2, 0xd10143ff, 0xa9034ff4, 0xa9047bfd, 0x910103fd      /* Server::timer_callback */
	CH_TRAMP 3, 0x6db63bef, 0x6d0133ed, 0x6d022beb, 0x6d0323e9      /* Server::render_for_time */
	CH_TRAMP 4, 0xa9bd57f6, 0xa9014ff4, 0xa9027bfd, 0x910083fd      /* Render::Context::will_commit */
	CH_TRAMP 5, 0xd10183ff, 0x6d0123e9, 0xa9025ff8, 0xa90357f6      /* Render::Context::did_commit */
	CH_TRAMP 6, 0xaa0103e0, 0xaa0203e1, 0xaa0303e2, 0x52800023      /* Display::DisplayLink::callback (a program's) */
	CH_TRAMP 7, 0x6db733ed, 0x6d012beb, 0x6d0223e9, 0xa9036ffc      /* Display::DisplayLink::dispatch_items */
	CH_TRAMP 8, 0xd10383ff, 0x6d062beb, 0x6d0723e9, 0xa9086ffc      /* Transaction::commit */
	CH_TRAMP 9, 0x6db733ed, 0x6d012beb, 0x6d0223e9, 0xa9036ffc      /* Context::commit_transaction */
	CH_TRAMP 10, 0x6dbb2beb, 0x6d0123e9, 0xa90257f6, 0xa9034ff4     /* Display::DisplayLinkItem::set_preferred_fps_range */
	CH_TRAMP 11, 0x6db92beb, 0x6d0123e9, 0xa90267fa, 0xa9035ff8     /* DynamicFrameRateSource::set_preferred_fps_range */

.macro CH_STUB n
	.globl _ch_stub_\n
	.p2align 2
_ch_stub_\n:
	sub	sp, sp, #0xb0
	stp	x0, x1, [sp, #0x00]
	stp	x2, x3, [sp, #0x10]
	stp	x4, x5, [sp, #0x20]
	stp	x6, x7, [sp, #0x30]
	stp	x8, x30, [sp, #0x40]
	stp	d0, d1, [sp, #0x50]
	stp	d2, d3, [sp, #0x60]
	stp	d4, d5, [sp, #0x70]
	stp	d6, d7, [sp, #0x80]
	stp	x29, x30, [sp, #0x90]
	add	x29, sp, #0x90
	mov	x2, x1
	mov	x1, x0
	mov	x0, #\n
	bl	_ch_log
	ldp	x0, x1, [sp, #0x00]
	ldp	x2, x3, [sp, #0x10]
	ldp	x4, x5, [sp, #0x20]
	ldp	x6, x7, [sp, #0x30]
	ldp	x8, x30, [sp, #0x40]
	ldp	d0, d1, [sp, #0x50]
	ldp	d2, d3, [sp, #0x60]
	ldp	d4, d5, [sp, #0x70]
	ldp	d6, d7, [sp, #0x80]
	ldr	x29, [sp, #0x90]
	add	sp, sp, #0xb0
	b	_ch_tramp_\n
.endm

	CH_STUB 0
	CH_STUB 1
	CH_STUB 2
	CH_STUB 3
	CH_STUB 4
	CH_STUB 5
	CH_STUB 6
	CH_STUB 7
	CH_STUB 8
	CH_STUB 9
	CH_STUB 10
	CH_STUB 11

	.data
	.p2align 3
	.globl _ch_back
_ch_back:
	.space 8 * 16
