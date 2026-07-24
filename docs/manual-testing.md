# Manual test procedure

Prerequisites: at least one external monitor, the app built and running
(`Scripts/make-app.sh `Scripts/make-app.sh && open build/hdmi-defubar.app``Scripts/make-app.sh && open build/hdmi-defubar.app` open "build/HDMI Defubar.app"`).

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
