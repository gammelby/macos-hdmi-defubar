# Layout naming and management panel: design

Date: 2026-07-24
Status: approved

## Problem

Saved layouts are labeled by their internal set key
(`b-1552-s4251086178+e-19501-s1536+...`) in the menubar, which is meaningless
to users, and a nested submenu is a poor place to manage layouts.

## Design

### Naming

- `SavedLayout` gains `customName: String?` (Codable optional; old store files
  decode with nil).
- Derived name: display names from the layout, built-in shown as "MacBook",
  built-in first then alphabetical, joined with " + ", adjacent identical
  names collapsed to "N× Name" (e.g. "2× DELL U2720Q").
- UI label everywhere: `customName` when set and non-empty, otherwise the
  derived name. Set keys never appear in UI.
- Saving over an existing set (learner or explicit save) preserves the stored
  `customName`. Renaming to an empty or whitespace string clears the custom
  name, reverting to the derived name.

### Menubar menu

- The "Saved layouts" submenu is removed.
- New item "Manage layouts..." opens the management window and activates the
  app.

### Manage layouts window

SwiftUI `Window` scene, one card per saved layout, currently connected set
first, then by label:

- Editable name field; placeholder shows the derived name.
- "Connected now" badge when the card's set key equals the current set key.
- Per display: name, point resolution and refresh.
- Arrangement thumbnail: stored display frames drawn as scaled rounded
  rectangles in relative position, main display accented.
- Restore button, enabled only when that set is currently connected.
- Delete button.
- Empty state text when the store is empty.

### Unchanged

Matching, learning, restoring, notifications and on-disk keying. This is
presentation plus one optional metadata field.

## Testing

Core unit tests: derived naming (builtin mapping, ordering, duplicate
collapsing), customName preservation across saves, rename semantics
(set, clear on empty). Panel behavior is covered by the manual test
procedure.
