# Radar manual tests

Checks that unit tests cannot cover: real keyboard focus, VoiceOver, and the macOS accessibility settings.
Run them on a release build (`scripts/build-app.sh`) before a release. Use `-SpyreDemo` for fake sessions
(`DESIGN.md` 2.3), so no real titles or paths show. Write down the macOS version and the result of each step.

## Keyboard (main window)

1. Open the main window (⌃⌥S). Press Tab. The section switcher shows a frost-blue capsule ring.
2. Press → and ←. The section changes. Press ⌘1, ⌘2, ⌘3. The section changes.
3. Press ⌘1, then Tab. Press ↓. The first group header gets the ring. ↓ moves row by row and stops at the last item.
   ↑ stops at the first header.
4. On a child row, press ←. The ring moves to the parent row.
5. On the Idle header, press → (unfolds), ← (folds), Space, and Return (toggle). Same on "Earlier".
6. On a row, press Space. The detail line opens and the row shows the selection line. Space again closes it.
7. On a row, press Return. The host app comes to the front (with real sessions), or nothing happens for a demo row.
8. Press Esc. The ring moves to the switcher.
9. Click a row. The ring hides. Press ↓. The ring shows again.
10. Press ⌘W. The main window closes. The menubar icon stays. ⌃⌥S opens the window again.
11. Scroll the list with the keyboard past the window height. The focused row scrolls into view.

## Keyboard (menubar window)

1. Open the menubar window. Press Tab until the rows have focus. ↑/↓ move the ring. Return runs "Show app".
2. Press Tab: "Open Spyre", then "More". Press Esc. The window closes.
3. Open "More". "Quit Spyre" shows ⌘Q. ⌘Q quits Spyre.

## VoiceOver (⌘F5)

1. Move to a row. VoiceOver reads "{Title}. {Status}. … Last activity … ago." Check a waiting row (reason), a child
   row ("Child session of …"), and a stale row ("Stale.").
2. Move to the count line. It is one element: "2 need you, 2 working, 1 idle" or "Nothing needs you. …".
3. Group headers are headings (VO-⌘H). The Idle header reads "Idle, N sessions" and "Collapsed" or "Expanded".
4. Open the rotor (VO-U). The "Needs you" rotor lists the waiting rows. Pick one; VoiceOver moves to it.
5. On a row, open the actions (VO-⌘Space): Show app, Open folder in Finder, Copy path, Show details.
6. With real sessions: let a session wait for a permission prompt. After about 3 s VoiceOver says
   "{Title} needs you. Permission prompt." once. Two prompts within 5 s give "2 sessions need you.".
   A prompt answered within 2 s gives nothing. Working, idle, and done changes give nothing.
7. Turn VoiceOver off. Repeat step 6. Nothing is announced.
8. The agent mark (sparkle / terminal) is never read.

## Reduce Motion (System Settings > Accessibility > Display)

1. The working spinner is a still partial arc. The fog does not drift.
2. Folds (Idle, Done, Earlier) are instant. Hover changes color only: no fade. Count numbers change without a roll.

## Reduce Transparency

1. The switcher track is opaque. Tags have an opaque fill. The atmosphere stays.
2. The focus ring is clearly visible on the switcher and on rows.

## Increase Contrast

1. The theme stays Fog Light or Fog Dark. Panel borders are stronger. The focus ring is 3 pt.

## Live appearance switch

1. Open the main window. Focus a row with the keyboard, open the Idle group, scroll down a little.
2. Switch Light/Dark in System Settings. Only colors change. The focused row, the scroll position, the open groups,
   and the row order stay. VoiceOver announces nothing new.

## Window

1. Fold and unfold Idle. The window height follows the content between 440 and 640 pt. The top edge stays.
2. Move the window, quit Spyre, open it again. The window opens at the same place. Move it to a second screen and
   disconnect the screen: the window opens on the main screen.
