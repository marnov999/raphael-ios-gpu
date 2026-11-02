#pragma once

enum boot_choice { BOOT_IOS, BOOT_MIUI, BOOT_OFF };

/* The boot menu; have_miui: whether the image carries an Android kernel to pick; def: what the
 * 10 s countdown boots (BOOT_IOS or BOOT_MIUI). */
enum boot_choice boot_menu(int have_miui, enum boot_choice def);
