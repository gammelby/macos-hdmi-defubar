# Manual test procedure

Prerequisites: at least one external monitor, the app built and running
(`Scripts/make-app.sh && open "build/HDMI Defubar.app"`).

## Baseline and learning

1. With all monitors connected, arrange displays as desired in
   System Settings > Displays.
2. Wait about 7 seconds (2 s settle plus 5 s stability). The menubar should show "Last action: Learned adjusted
   layout" (or use Save current layout).
3. Run `swift run hdmi-defubar --dump` and confirm `savedLayout` is non-null
   for the current `setKey`.

## Restore on reconnect

4. Unplug the HDMI monitor, wait for displays to settle, replug it.
5. If macOS assigns a new display ID and a default config, the app should
   restore resolution and arrangement within a few seconds of the settle
   window and post a notification saying it did so.
6. If macOS happens to restore the correct config itself, the app should do
   nothing (no notification).

## Learner does not fight the restorer

7. After a restore, make no changes; confirm no "Learned" action appears
   (self-caused events must not be learned).
8. Rearrange displays manually; after 5 seconds of stability the app should
   learn the new arrangement. Unplug and replug to confirm the new
   arrangement is what gets restored.

## Pause

9. Enable "Pause automatic handling". Unplug and replug a monitor and let
   macOS mess up the layout; the app must not intervene.
10. Disable pause and use "Restore saved layout" to fix it manually.

## Store corruption

11. Quit the app, corrupt the store
    (`echo garbage > ~/Library/Application\ Support/hdmi-defubar/layouts.json`),
    relaunch. The app should notify about the unreadable store, move it to
    `layouts.json.corrupt` and start fresh.

## Resolution variants

12. With all monitors connected and a layout learned, change one external to a
    different resolution in System Settings and wait for the stability window.
    The notification should say a resolution variant was learned, and the
    menubar entry for the set should become a submenu with two variants.
13. Set the resolution back and wait. The first variant should be picked up
    again, not overwritten: Manage layouts must still show exactly two
    variants, with the first one marked Active.
14. Rename the set to "Home desk" and one variant to "4K" in Manage layouts.
    Click into a name field: The current name must already be there and be
    appendable, not vanish on the first keystroke. Click elsewhere without
    pressing Enter; the name must still stick.
15. Clear a name field completely. The derived name should come back.

## Window memory

16. Enable "Remember window positions" in the menu and grant Accessibility
    access when the prompt appears (the app must be launched from
    /Applications, and the permission has to be granted again after every
    rebuild because the ad-hoc signature changes).
17. Spread windows across all monitors, wait 20 seconds, then confirm
    `swift run hdmi-defubar --dump` reports a non-zero `rememberedWindows`.
18. Unplug a monitor, wait for the windows to pile up, replug it. About a
    second and a half after the displays settle the windows should go back
    where they were, with one notification covering both the display and the
    window restore.
19. Open a new window before replugging. It must be left where it is.
20. Use "Put windows back" from the menu with everything already in place; it
    should report that nothing needed moving rather than shuffling windows.
21. Delete a variant in Manage layouts and confirm its remembered windows go
    with it (`windows.json` should no longer carry that variant id).
