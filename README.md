<p align="center">
  <img src="assets/icon.png" alt="HDMI Defubar icon" width="128">
</p>

# HDMI Defubar

A macOS menubar app that fixes the "my Mac forgot my monitor layout again" problem
for external displays, typically those connected over HDMI.

## The problem

macOS remembers display configurations (resolution, scaling, refresh rate and
arrangement) keyed by a display UUID derived from the monitor's EDID. Some
monitors, especially over HDMI or through adapters, docks and KVMs, don't expose
a usable serial number in their EDID. In that case macOS generates a *random*
UUID every time the monitor connects. Each plug-in then looks like a brand-new,
never-seen display: The saved configuration is ignored, a default one is
created and you have to redo resolution and arrangement by hand. With multiple
externals this gets old fast.

The tell: `~/Library/Preferences/ByHost/com.apple.windowserver.displays.*.plist`
accumulates hundreds of stored configs referencing display UUIDs that each
appear only once or twice.

## The workaround

Even when the UUID churns, CoreGraphics still reports a stable hardware identity
for the monitor: Vendor number and (usually) serial number, with the model
number as a fallback. HDMI Defubar keys layouts on that fingerprint instead of
the UUID:

1. It watches for display reconfiguration events.
2. When you arrange your displays by hand, it learns that layout for the current
   *set* of connected monitors (laptop alone, laptop plus one external, laptop
   plus two, ... each set gets its own entry, with one variant per resolution
   combination you use it in).
3. When a monitor reconnects and macOS assigns it a fresh ID with a default
   config, HDMI Defubar recognizes the physical monitor by fingerprint,
   reapplies your saved resolution, refresh rate, scaling and arrangement in one
   transaction and posts a notification saying it did so.
4. It then puts your windows back where they were the last time that monitor
   combination was up, because macOS piles them all onto one screen when a
   display goes away.

The result: Everything just looks normal, plus a notification telling you the
issue was detected and fixed.

## How it works

- **Display watcher.** Registers a CoreGraphics display reconfiguration
  callback and debounces the event bursts that happen during connect and
  disconnect. Events are classified as topology changes (display added or
  removed) or in-place changes (same displays, new mode or arrangement).
- **Fingerprinting.** Each display is identified by vendor + serial, with the
  model number used only when no serial is exposed. Model is deliberately
  excluded when a serial exists: Some monitors (Samsung Odyssey G7 family)
  report a different EDID product id across reconnects. A layout is keyed by
  the sorted set of fingerprints currently online.
- **Restorer.** After a topology change settles, the saved layout for the
  current monitor set is diffed against reality and applied atomically via
  `CGBeginDisplayConfiguration` / `CGCompleteDisplayConfiguration`. One attempt
  per connect event, never a retry loop. If the exact saved mode isn't offered
  (the same monitor can expose different mode lists per port), the closest mode
  with the same point size is used and the notification says so.
- **Learner.** After an in-place change that wasn't caused by the app itself,
  the new state is snapshotted once it has been stable for a few seconds and a
  notification confirms what was learned. The last arrangement you made by
  hand always wins. A "Save current layout" menu item exists as an explicit
  override.
- **Variants.** A monitor set holds one variant per resolution combination it
  has been seen in, so "MacBook + LG + Odyssey" can exist at 4K and at 1440p at
  the same time. Learning compares the settled modes against the known
  variants: The same modes update that variant in place, so rearranging
  displays never creates one, while a combination you have not used before
  becomes a new variant and takes over as the one a reconnect restores.
  Variants are listed in the menubar and can be named and deleted individually.
- **Window memory.** While a monitor set is up and settled, the position and
  size of every standard window is remembered every 20 seconds, per variant,
  relative to the display the window sits on. On reconnect the windows are put
  back about a second and a half after the displays have settled. Windows
  opened since the last capture are left alone, and so are windows the owning
  application refuses to move. Matching uses the WindowServer window id while
  the window lives, falling back to application plus title plus position in
  that application's window list. This needs the Accessibility permission and
  is off until you enable it from the menu.
- **Mode inheritance.** A never-seen *combination* of known monitors is not
  left at macOS defaults: Each display's resolution and refresh rate are
  borrowed from the layouts it appears in (preferring the layout sharing the
  most displays with the current set) and applied, while the arrangement is
  left to macOS. Nothing is saved until you arrange the combination once.
- **Menubar UI.** Shows connected monitors, the last action taken and every
  saved layout by readable name ("MacBook + LG HDR 4K") for quick restore,
  with a checkmark on the connected set; a set with several resolution
  variants opens as a submenu listing them. Actions: Save current layout, save
  the current state as an extra variant, restore, remember or put back windows,
  pause/resume automatic handling and launch at login. A "Manage layouts"
  window supplements the list with renaming (call one "Home desk", call its
  variants "4K" and "1440p"), an arrangement thumbnail per variant, a
  connected-now badge, how many windows are remembered and use/delete actions.
- **Storage.** Layouts live in `layouts.json` under
  `~/Library/Application Support/hdmi-defubar/`, written atomically. Remembered
  windows live beside them in `windows.json`, deliberately separate: They are
  rewritten far more often and are far less precious, so a damaged window file
  cannot take the display layouts with it. An unreadable file is moved aside
  and the app starts fresh with a notification.
- **Logging.** All decisions (event classification, fingerprints, diffs, chosen
  modes, apply results) go to the unified log; interventions and errors also
  surface as user notifications.

## Out of scope

- Rotation (requires private APIs) and mirroring.
- Rule-based window placement ("always put Mail here"). Windows are put back
  where they were, not where a rule says they belong.
- Root-cause EDID fixes: EDID overrides are largely ignored on Apple Silicon,
  which is why this works around the identity problem instead.

## Limitations

- The hardware fingerprint carries all identity weight: Two identical monitors
  that both lack an EDID serial cannot be told apart reliably.
- Window memory needs the Accessibility permission, which macOS ties to the
  app's code signature. `Scripts/make-app.sh` signs ad hoc, so the permission
  is revoked every time you rebuild and has to be granted again.
- Full-screen and minimized windows are left alone, and some applications
  refuse to be moved or resized; the notification says how many did not budge.
- If macOS restores the correct layout on its own, the app does nothing; it
  only intervenes on mismatch.

## Building

Requires Xcode command line tools on macOS 13 or later.

    swift test          # run the unit tests
    Scripts/make-app.sh # build "build/HDMI Defubar.app"
    cp -R "build/HDMI Defubar.app" /Applications/

The app lives only in the menubar (no dock icon). Launch it once from
/Applications, grant the notification permission and enable "Launch at
login" from its menu. For window memory, turn on "Remember window positions"
and grant Accessibility access when asked. `swift run hdmi-defubar --dump` prints the current
displays, fingerprints and the matched saved layout as JSON for debugging. See
[docs/manual-testing.md](docs/manual-testing.md) for the manual test
procedure.

## Requirements

- macOS 13 or later (SwiftUI `MenuBarExtra`), Apple Silicon or Intel.
