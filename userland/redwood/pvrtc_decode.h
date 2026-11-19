/*
 * PVRTC1 (2 and 4 bits a texel) to RGBA8, a whole level at a time. Ported to C from hakios-metal's
 * src/texture.cpp (decodePvrtc, pvrtcTwiddle, pvrtcColours), MIT License, Copyright (c) 2025-2026 the HakiOS
 * authors (github.com/oosexgang/hakios-xnu-kernel, hakios-metal/LICENSE): Permission is hereby granted, free of
 * charge, to any person obtaining a copy of this software and associated documentation files, to deal in the
 * Software without restriction, subject to the copyright notice and permission notice being included.
 * The A6xx texture unit has no PVRTC decoder; Real Racing 3 and Monument Valley upload PVRTC (Metal 162/164/166).
 */
#include <stdint.h>
#include <math.h>

static uint32_t
pvrtc_twiddle(uint32_t x, uint32_t y, uint32_t wb, uint32_t hb)
{
   uint32_t min_dim = wb < hb ? wb : hb, idx = 0, shift = 0;
   for (uint32_t bit = 1; bit < min_dim; bit <<= 1) {
      if (y & bit) idx |= 1u << shift;
      shift++;
      if (x & bit) idx |= 1u << shift;
      shift++;
   }
   uint32_t rest = (wb > hb ? x : y) >> (shift / 2);
   return idx | (rest << shift);
}

static void
pvrtc_colours(uint32_t c, int a[4], int b[4])
{
   if (c & 0x8000) {
      a[0] = (c >> 10) & 0x1f; a[1] = (c >> 5) & 0x1f; a[2] = (c & 0x1e) | ((c & 0x1e) >> 4); a[3] = 0xf;
   } else {
      a[0] = ((c >> 7) & 0x1e) | ((c >> 11) & 0x1); a[1] = ((c >> 3) & 0x1e) | ((c >> 7) & 0x1);
      a[2] = ((c << 1) & 0x1c) | ((c >> 2) & 0x3); a[3] = (c >> 11) & 0xe;
   }
   if (c & 0x80000000u) {
      b[0] = (c >> 26) & 0x1f; b[1] = (c >> 21) & 0x1f; b[2] = (c >> 16) & 0x1f; b[3] = 0xf;
   } else {
      b[0] = ((c >> 23) & 0x1e) | ((c >> 27) & 0x1); b[1] = ((c >> 19) & 0x1e) | ((c >> 23) & 0x1);
      b[2] = ((c >> 15) & 0x1e) | ((c >> 19) & 0x1); b[3] = (c >> 27) & 0xe;
   }
}

static uint32_t
pvrtc_word(const uint8_t *data, uint32_t bx, uint32_t by, uint32_t wb, uint32_t hb, int half)
{
   const uint8_t *p = data + 8ull * pvrtc_twiddle(bx % wb, by % hb, wb, hb) + 4 * half;
   return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

/* bytes of one level */
static uint64_t
pvrtc_level_bytes(uint32_t w, uint32_t h, uint32_t bpp)
{
   uint32_t bw = bpp == 2 ? 8 : 4, wb = (w + bw - 1) / bw, hb = (h + 3) / 4;
   return (uint64_t)(wb < 2 ? 2 : wb) * (hb < 2 ? 2 : hb) * 8;
}

static void
pvrtc_decode(const uint8_t *data, uint32_t w, uint32_t h, uint32_t bpp, uint8_t *rgba)
{
   const uint32_t bw = bpp == 2 ? 8 : 4, bh = 4;
   uint32_t wb = (w + bw - 1) / bw, hb = (h + bh - 1) / bh;
   if (wb < 2) wb = 2;
   if (hb < 2) hb = 2;
   for (uint32_t y = 0; y < h; y++) {
      for (uint32_t x = 0; x < w; x++) {
         const int px = (int)x - (int)(bw / 2), py = (int)y - (int)(bh / 2);
         const int bx0 = px >= 0 ? px / (int)bw : (px - (int)bw + 1) / (int)bw;
         const int by0 = py >= 0 ? py / (int)bh : (py - (int)bh + 1) / (int)bh;
         const float fx = (float)(px - bx0 * (int)bw) / bw, fy = (float)(py - by0 * (int)bh) / bh;
         float A[4] = { 0, 0, 0, 0 }, B[4] = { 0, 0, 0, 0 };
         for (int k = 0; k < 4; k++) {
            uint32_t qx = (uint32_t)(bx0 + (k & 1) + (int)wb) % wb, qy = (uint32_t)(by0 + (k >> 1) + (int)hb) % hb;
            float wgt = ((k & 1) ? fx : 1 - fx) * ((k >> 1) ? fy : 1 - fy);
            int a[4], b[4];
            pvrtc_colours(pvrtc_word(data, qx, qy, wb, hb, 1), a, b);
            for (int c = 0; c < 4; c++) {
               A[c] += wgt * a[c];
               B[c] += wgt * b[c];
            }
         }
         uint32_t ox = x / bw, oy = y / bh;
         uint32_t mod = pvrtc_word(data, ox, oy, wb, hb, 0), colour = pvrtc_word(data, ox, oy, wb, hb, 1);
         float m;
         int clear = 0;
         uint32_t i = (y % bh) * bw + (x % bw);
         if (bpp == 2) {
            m = ((mod >> i) & 1) ? 1.0f : 0.0f;
         } else {
            uint32_t v = (mod >> (2 * i)) & 3;
            if (colour & 1) {
               m = v == 0 ? 0.0f : v == 3 ? 1.0f : 0.5f;
               clear = v == 2;
            } else {
               m = v == 0 ? 0.0f : v == 1 ? 3.0f / 8 : v == 2 ? 5.0f / 8 : 1.0f;
            }
         }
         uint8_t *out = rgba + ((uint64_t)y * w + x) * 4;
         for (int c = 0; c < 3; c++) {
            float v = A[c] + (B[c] - A[c]) * m;
            v = v < 0 ? 0 : v > 31 ? 31 : v;
            out[c] = (uint8_t)lroundf(v * 255.0f / 31.0f);
         }
         float al = A[3] + (B[3] - A[3]) * m;
         al = al < 0 ? 0 : al > 15 ? 15 : al;
         out[3] = clear ? 0 : (uint8_t)lroundf(al * 255.0f / 15.0f);
      }
   }
}
