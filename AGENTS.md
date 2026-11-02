# Working on raphael-ios-gpu

- Read `NOTES.md` before starting: project goal, hardware facts, current step, local artifact locations
  and the next concrete action.
- The user switches agents frequently. Update the handoff at the end of `NOTES.md` after each milestone
  and before stopping. Record commits, CI run IDs, exact build/boot results and unfinished work.
  Distinguish observations from guesses.
- Commit completed changes. Use `gh` for GitHub Actions kernel builds and logs. A green CI run is not
  enough: the workflow's "no silently skipped patches" guard must pass, and check the board macro step.
- Device bring-up uses temporary `fastboot boot` images. MIUI on this phone is the user's working
  Android (rooted, with a Linux chroot in /data/linux): never write to `userdata`. Scratch writes go to
  `rawdump`. Flashing `boot`, editing the GPT and writing the iOS root each need the user's explicit OK.
  Keep bootloaders, modem, persist and the backups intact.
- XNU's RAM window must stay clear of the bad DRAM at 0x1016a0000-0x1016c0000 (`tools/mkadt.py`
  asserts it). Any Linux this project boots (MIUI chain-load) gets the badram no-map node.
- Keep device dumps, serial numbers, the stock boot image/DTBs and downloaded Apple artifacts out of git.
