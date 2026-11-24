# Using the Drawer

Group, pin and reorder plugins, search them and run their actions, drive the drawer from the
keyboard, and keep readouts on screen in the floating HUD.

## Overview

How a plugin declares its category, actions, badges, toasts and HUD readout is in
<doc:WritingPlugins>, and where the drawer appears on each platform is in <doc:InstallingInSwiftUI>.

### Grouping, pinning and ordering

The drawer lists global plugins by `category`, a string a plugin may declare. A plugin that
declares none is in `General`, listed last. Right-click a plugin's header (long-press on iOS) to
pin it to the top, or to move it up or down its group. The drawer remembers pins, order and the
plugin last used, and opens at that plugin after a relaunch.

### Searching plugins and actions

The open drawer has a search field that finds plugins by title and runs the actions they declare.
Cmd-K focuses it while the drawer is open; it never opens the drawer. The arrow keys move through
the results and Return picks one. Picking a plugin scrolls to it and expands it; picking an action
runs it.

### Keyboard

The app's own trigger opens the drawer (Ctrl-D in the example apps). While the drawer is open it
adds these shortcuts, on macOS and on iOS with a hardware keyboard. None of them exists while the
drawer is closed, so they never open it or take a key from the app.

| Keys | Does |
|---|---|
| Cmd-K | Focuses the search field |
| Cmd-Option-Down / Cmd-Option-Up | Scrolls to the next or previous plugin's section and moves focus to its header; with one plugin shown alone, shows the next or previous one |
| Escape | Clears the search field if it holds text, otherwise returns from a plugin shown alone to the list, otherwise closes the drawer |

With keyboard navigation turned on (Full Keyboard Access on iOS, Keyboard navigation in macOS's
settings), Tab reaches every section header, and Space expands or collapses the section.

### Badges, toasts and silencing a plugin

A plugin can raise a problem while the drawer is closed. A badge puts a count on the plugin's
section header until the plugin clears it. A toast appears in the window's corner while the drawer
is closed. Tapping it opens the drawer with that plugin expanded and scrolled into view, and its
close button dismisses it. Posts from one plugin coalesce into one toast, which shows the latest
message and how many posts it stands for. A post made while the drawer is open is dropped. The
toast goes away by itself `DebugDrawer.toastLifetime` (6) seconds after its last post, and stays
while the pointer is over it or VoiceOver's focus is on it.

To quiet a plugin that posts too often, choose Silence Notices from its section header's context
menu. Its badge and toast go away, what it posts afterwards is dropped, and a crossed-out bell
marks its header until you choose Allow Notices. The drawer remembers the choice across launches.

### Floating HUD

A plugin can offer a compact readout for the floating HUD, which stays on screen while the drawer
is closed. Choose Show in HUD from a plugin's context menu in the drawer to pin its readout. To
take it off, choose Unpin from the readout's own context menu (touch and hold it, or
Control-click it on the Mac). Drag the HUD anywhere in the window. Only the HUD itself takes
touches; the rest of the window reaches the app. The drawer remembers the pinned readouts and the
HUD's position across launches, and the Screenshot plugin leaves the HUD out of its captures.

Among the shipped plugins, Performance offers its frame rate and memory, Network its active
conditioning profiles, and Screen Recording a Record button that becomes the elapsed time and
Stop. Design Overlay and Color Vision each offer a switch of their own.

### What the drawer remembers

The drawer saves its state (collapsed sections, pins, the HUD, and plugin settings such as Deep
Link's history) in a defaults suite of its own, `<bundle identifier>.debugdrawer`, never among
the app's standard defaults.
