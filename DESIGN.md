# Spyre Design System

Status: draft for MVP.
Read `SPEC.md` first. It defines the surfaces: menubar item and main window in the MVP, and the dock in v0.2.

## 1. Principle

Spyre has no fixed brand look. The user owns the look.

- Every visual value is a design token.
- A theme is a set of token values.
- The user can change the theme, and parts of it, without code.
- The default theme is a good starting point. It is not the brand.

## 2. Default theme direction

The default themes follow the rules below. When two rules conflict, atmosphere and light win: the app rests on a calm, layered fog, never on a flat white page.
In short: a precise, calm tool that floats over quiet fog and distant mountains.

- The window content rests on an atmospheric background (2.1). The background is never one flat color.
- Use graphite text, not pure black. Do not use pure white as the main surface.
- Compact but breathable. Show what matters first. Fold the rest (progressive disclosure).
- Hierarchy comes from layout, spacing, type, and contrast first. Color comes last.
- Use thin, crisp, low-contrast borders. Use restrained shadows.
- Use mixed radius by hierarchy: small radius on panels and rows, a pill shape only on the section switcher.
- No giant rounded cards. A group of sessions is one thin bordered panel with rows and hairline dividers.
- Show key numbers big and calm, with a light weight and tabular digits, for example "2 needs you".
- Use frost-blue (`color.accent`) as a signature only: focus, selection, and the one primary button.
- Use status colors only for status. Only "needs you" uses the waiting color in the count line.
- Status indicators are sparing: one glyph per row, and text where the group header does not say it.
- Reveal secondary actions on hover, and always also in a context menu.
- Keep motion short and fast. The user never waits for an animation.
- Glass is rare. The MVP uses opaque surfaces.

This direction replaces the v0.1 default ("frosted-glass cards, large radius"). The design system and the
approved redesign supersede the earlier "keep the default look" decision.

### 2.1 Atmosphere

Every window has an atmospheric background: soft layered fog over faint, low-contrast mountain ridges.
Spyre draws it natively (SwiftUI shapes and blur). It uses no image and no network.

- Layers, back to front: sky-to-horizon tonal falloff, faint warm light, far ridge, fog band, middle ridge,
  fog band, near ridge. Far ridges sit higher and are softer.
- The scene geometry is fixed (`Atmosphere` in SpyreCore). Colors, opacity, blur, and drift are tokens.
- Strength: `opacity.atmosphere.scenery` on key screens (the welcome window).
  Dense screens (the session list, the menubar window) multiply it by `opacity.atmosphere.dense`.
  The atmosphere is reduced there, never removed.
- Ambient motion: the two fog bands drift very slowly in opposite directions, `size.atmosphere.drift` points
  each way, one cycle per `motion.duration.drift` seconds. The ridges stay still.
  Core Animation runs the drift in the render server, so it costs almost no app CPU and never re-lays out
  the window. Under Reduce Motion the scene stays and the drift stops.
- The fog bands are radial fades (no blur filter). The ridges use `blur.atmosphere.ridge`.
- The scenery (ridges, fog bands, warm light) stays in the lower third of the view. The far ridge has one
  sharper peak, off the center axis, with the faint warm light behind it.
- The environment never changes with app state. State shows in the UI only.
- It is decoration: hidden from VoiceOver and never hit-tested.

### 2.2 Light and dark

Spyre follows the macOS appearance, live:

- Light appearance: **Fog Light** (`light.json`). Cloud-gray and mist-gray, graphite text.
- Dark appearance: **Fog Dark** (`dark.json`). A night fog: deep blue-graphite sky, distant ridges a little lighter
  than near ones (night atmospheric perspective), a very faint warm light, and soft gray text. It is designed
  as its own theme, not an inverted light theme. Reason: Spyre is a monitoring tool that stays open for long
  sessions, often next to dark terminals.
- **High Contrast** (`high-contrast.json`) is light only. Spyre does not pick it automatically. It is for a later
  theme setting.
- Spyre sets each window's macOS appearance (`NSWindow.appearance`) to the theme's `appearance`. The title bar,
  scroll bars, and any system control always match the theme.
- Spyre reads the system appearance from `NSApp.effectiveAppearance` and observes it (key-value observing).
  Spyre never sets the app-wide appearance, so this value always reflects the system.
- Hidden launch argument for visual checks: `-SpyreAppearance light` or `-SpyreAppearance dark`.
  It forces the followed appearance. It is read from the launch arguments only. Nothing is stored.
  (The `-AppleInterfaceStyle` argument does not change the app appearance on current macOS.)

### 2.3 Visual checks

Hidden launch arguments, for looking at the UI without a change to system settings or real data:

- `-SpyreAppearance light|dark`: see 2.2.
- `-SpyreDemo`: show the fixed fake sessions of `FakeAdapter` instead of reading `~/.claude` and `~/.codex`.
  `-SpyreDemo calm` shows a set where nothing needs you (with idle rows old enough to fold and to hide).
  `-SpyreDemo empty` shows no sessions (the empty state).
- `-SpyreMenuPreview` (debug builds only): show the menubar window content in a normal window. Use it when the
  menubar hides the Spyre icon, so the real menubar window opens off screen.
  Run the debug binary directly: `swift build`, then `.build/debug/Spyre -SpyreMenuPreview -SpyreDemo`.

Example: `open -n Spyre.app --args -SpyreAppearance dark -SpyreDemo`, then `open Spyre.app` again for the main window.

### 2.4 Dock (v0.2)

The dock is not in the MVP. It is planned for v0.2.
The MVP defines the dock tokens now, so that themes stay valid in v0.2.

The dock is a vertical strip on one screen edge.

- It shows one icon per live session.
- Each icon has a status ring. See 6.2 for how the ring shows status without color alone.
- Sort order is the same as the session list (`SPEC.md` 4.2).
- When there are more sessions than the dock can show, the last slot shows "+N".
- Click an icon to open the session's project (`SPEC.md` 4.3).
- Hover an icon to show a tooltip with project name and status label.
- Position: left, right, or hidden. Default: hidden.

### 2.5 Rows and groups

- The main window height fits its content, from `size.window.height` to `size.window.maxHeight`. The top edge stays
  put. The width is the user's, from `size.window.width` to `size.window.maxWidth`. The fog fills the rest.
- macOS keeps the window frame (`NSWindow` frame autosave name `SpyreMainWindow`), not `config.json`.
  A restored frame is moved onto a visible screen.
- The content column has a maximum width (`size.content.maxWidth`). In a wide window it is centered.
- Group headers align with the panel's leading edge. Every header uses this rule.
- A group of sessions is one panel: `color.surface.row`, `color.border.row`, `radius.panel`, hairline dividers.
- "Needs you" is first. Its panel has a faint warning-tinted border (`color.border.waiting`) and a near-neutral
  surface (`color.surface.waiting`). Inside the panel, amber is only on the glyph and the waiting reason.
- Idle and Done are folded by default behind a disclosure row with a count.
- In Idle, rows older than `idleFoldAfter` sit behind an "Earlier N" disclosure row at the end of the panel
  (`size.row.disclosureHeight`). Its chevron sits in the glyph column.
- A row is about `size.row.height` high. Line 1: title. Line 2 (muted): project · branch · agent, then tags.
- Right side, on line 1's baseline: the waiting reason (`font.reason`) or the no-activity flag, then the relative
  last activity in tabular digits. The time sits on line 1's baseline in every row.
- Tags (`experimental`, `stale`) have no border: a faint fill (`color.surface.tag`), `font.tag`, secondary text.
  `exec` is plain text at the end of line 2.
  In the compact menubar rows this note moves to the start of line 2, so the title keeps its room.
- Idle and Done row titles use `color.text.secondary`, so rows that need attention lead.
- A working row shows a slow spinner (one turn per `motion.duration.ring`, run by Core Animation).
  Under Reduce Motion it is a static partial arc.
- A child row sits under its parent with a small corner arrow (`icon.child`) in the parent's glyph column, and the
  "experimental" tag. The child's glyph sits at the parent's title edge. The child title is `size.child.indent`
  right of the parent title.
- The count line: when something needs you, big numbers and labels on one shared baseline, `space.xs` apart.
  When nothing needs you, one line: "Nothing needs you." (`font.calm`, secondary) and "1 working · 7 idle"
  (`font.body`). Zero parts are left out.
- No sessions: a still outline ice cube (`icon.empty`, `size.icon.empty`, secondary), "Nothing running.", and
  what to do next. No animation.
- The shortcut hint (⌃⌥S) uses `font.hint` and `color.text.secondary`, quieter than the switcher labels.
- Hover shows "Open folder". The context menu has the same action.

## 3. Token rules

These rules are mandatory.

1. Every color, radius, spacing, font, size, blur, opacity, shadow, and animation duration is a token.
2. Views read tokens only. A hardcoded color or size in a view is a bug.
3. A theme is a set of token values in a JSON file.
4. Light and dark are two themes. They are not special cases in code.
5. A view never checks which theme is active. It reads the token value.
6. A token that a theme does not set uses the value from the built-in default theme.

## 4. Token naming

Token names use dot-separated parts: `category.role.variant`.

- Use lowercase words. Use camelCase inside a part when needed, for example `color.text.onAccent`.
- Name a token by its role, not by its value. Write `color.status.waiting`, not `color.amber`.
- Do not add a new category without a change to this file.

### 4.1 Categories

| Category | Unit | Example |
|----------|------|---------|
| `color` | Hex `#RRGGBB` or `#RRGGBBAA` | `color.text.primary` |
| `opacity` | 0.0 to 1.0 | `opacity.card` |
| `blur` | Points | `blur.card` |
| `radius` | Points. `capsule` means pill shape. | `radius.control` |
| `space` | Points | `space.md` |
| `size` | Points, or a count for `size.dock.maxIcons` | `size.row.height` |
| `font` | Family name, size in points, or weight name | `font.stat.size` |
| `shadow` | Color, radius, y offset | `shadow.card.radius` |
| `motion` | Seconds | `motion.duration.fast` |
| `icon` | SF Symbol name | `icon.status.waiting` |

## 5. Core tokens

Default values are for the built-in light theme (Fog Light). It holds the full token set.
Fog Dark and High Contrast set their own colors and atmosphere strength. Other tokens come from Fog Light.
The Dark column shows the Fog Dark value. "=" means the light value.

### 5.1 Color

| Token | Light | Dark | Use |
|-------|-------|------|-----|
| `color.background.base` | `#E3E5E8` | `#14171B` | Window base, under the atmosphere |
| `color.background.gradientTop` / `gradientBottom` | not set | not set | Reserved for the gradient background choice (8) |
| `color.atmosphere.sky` | `#E7E8EA` | `#121519` | Top of the atmosphere |
| `color.atmosphere.horizon` | `#D8DCE1` | `#1E2329` | Horizon tone, at `Atmosphere.horizonStop` |
| `color.atmosphere.fog` | `#E9EAEB` | `#1A1E23` | Foreground mist and fog bands |
| `color.atmosphere.ridgeFar` | `#A9B1BC` | `#353D48` | Far ridge (blue-gray) |
| `color.atmosphere.ridgeMid` | `#BEC4CC` | `#2A3139` | Middle ridge |
| `color.atmosphere.ridgeNear` | `#D0D4D9` | `#1E2328` | Near ridge |
| `color.atmosphere.light` | `#EAD9BE` | `#4A4032` | Faint warm light behind the far ridge |
| `color.surface.card` | `#F2F2F1` | `#1C2025` | Welcome panel |
| `color.surface.row` | `#E9EBED` | `#1C2025` | Session panel and row fill (cloud-gray, not white) |
| `color.surface.rowHover` | `#F0F1F2` | `#22272D` | Row on hover, disclosure row on hover |
| `color.surface.waiting` | `#F0EFEC` | `#201F1D` | "Needs you" panel fill (near neutral) |
| `color.surface.control` | `#1F23280D` | `#FFFFFF0D` | Section switcher track (translucent) |
| `color.surface.controlSelected` | `#F8F8F7` | `#2A3037` | Selected switcher segment, secondary button |
| `color.surface.tag` | `#1F23280F` | `#FFFFFF0F` | Row tag fill (about 6 %) |
| `color.border.subtle` | `#1F232814` | `#FFFFFF14` | Thin borders on controls |
| `color.border.segment` | `#1F23281A` | `#FFFFFF1A` | Selected switcher segment border (about 10 %) |
| `color.border.row` | `#1F23281F` | `#FFFFFF17` | Panel border |
| `color.border.divider` | `#1F232812` | `#FFFFFF0D` | Hairline between rows |
| `color.border.waiting` | `#8A53004D` | `#E0A84E4D` | Warning-tinted "Needs you" panel border (30 %) |
| `color.text.primary` | `#1F2328` | `#E4E7EA` | Graphite main text |
| `color.text.secondary` | `#545B65` | `#9AA2AC` | Labels, metadata, muted counts |
| `color.text.onAccent` | `#1F2328` | `#14171B` | Text on the accent fill |
| `color.accent` | `#8FB4D9` | `#8FB4D9` | Frost-blue signature. Focus, selection, primary button. |
| `color.focus` | `#3F7FBF` | `#8FB4D9` | Focus ring |
| `color.status.working` | `#2A5E98` | `#83AEDF` | Working |
| `color.status.waiting` | `#8A5300` | `#E0A84E` | Waiting ("needs you") |
| `color.status.idle` | `#5B616B` | `#98A0AA` | Idle |
| `color.status.done` | `#20663A` | `#6DBF8A` | Done |
| `color.status.unknown` | `#6A5F52` | `#B3A797` | Unknown, starting |
| `color.flag.noActivity` | `#8A5300` | `#E0A84E` | No-activity flag on a working row |
| `color.shadow.panel` | `#1F23280F` | `#00000040` | Soft panel shadow |
| `color.shadow.segment` | `#1F23280F` | `#00000033` | Selected switcher segment shadow (about 6 %) |
| `color.surface.dock` | not set | not set | Reserved: dock fill (v0.2) |

### 5.2 Shape, space, and size

| Token | Default | Use |
|-------|---------|-----|
| `radius.card` | `10` | Welcome panel |
| `radius.panel` | `8` | Session group panel |
| `radius.row` | `6` | Disclosure row, row hover inside a panel |
| `radius.button` | `6` | Buttons |
| `radius.tag` | `4` | Row tags (`exec`, `experimental`, `stale`) |
| `radius.popover` | `14` | Reserved: tooltips (v0.2) |
| `radius.control` | `capsule` | Reserved. The section switcher is a pill shape. |
| `space.xxs` / `xs` / `sm` / `md` / `lg` / `xl` | `2` / `4` / `8` / `12` / `20` / `32` | Spacing scale |
| `size.row.height` | `44` | Session row, main window |
| `size.row.compactHeight` | `40` | Session row, menubar window |
| `size.row.disclosureHeight` | `32` | "Earlier N" disclosure row in the Idle panel |
| `size.child.indent` | `20` | Child title indent from the parent title |
| `size.icon.empty` | `16` | Ice cube in the empty state |
| `size.content.maxWidth` | `760` | Maximum width of the main window content column |
| `size.icon.status` | `13` | Status glyph |
| `size.status.column` | `16` | Width of the status glyph column, so titles align |
| `size.spinner.line` | `1.5` | Working spinner line width |
| `size.switcher.height` | `26` | Section switcher height |
| `size.dock.icon` | `36` | Dock icon (v0.2) |
| `size.dock.ring` | `2.5` | Status ring line width (v0.2) |
| `size.dock.maxIcons` | `6` | Icons before "+N" (v0.2) |
| `size.border` | `1` | Border width |
| `size.menu.width` | `360` | Menubar window width |
| `size.menu.maxRows` | `5` | Rows in the menubar window before "+N more" |
| `size.window.width` / `size.window.height` | `560` / `440` | Main window minimum size |
| `size.window.maxWidth` / `maxHeight` | `880` / `640` | Main window maximum size. It first opens at the maximum width. |
| `size.welcome.width` | `480` | First-run window width. The height fits the content. |
| `size.welcome.scenery` | `120` | Open band under the first-run content, where the scenery shows |
| `size.welcome.sceneHeight` | `340` | Height of the scenery (ridges, fog) at the bottom of the first-run window |
| `size.atmosphere.drift` | `28` | Largest fog drift offset, in points |

### 5.3 Material, font, and motion

| Token | Light | Dark | Use |
|-------|-------|------|-----|
| `opacity.card` | `1.0` | = | Surface opacity. Surfaces are opaque in the MVP. |
| `opacity.atmosphere.scenery` | `1.0` | `1.0` | Scenery strength on key screens (High Contrast: `0.6`) |
| `opacity.atmosphere.dense` | `0.55` | `0.7` | Multiplier on dense screens (High Contrast: `0.5`) |
| `opacity.atmosphere.fog` | `0.7` | `0.7` | Fog band opacity at the band center |
| `opacity.atmosphere.light` | `0.45` | `0.2` | Warm light strength (High Contrast: `0.2`) |
| `blur.atmosphere.ridge` | `3` | = | Ridge softness. The far ridge uses 1.5×, the middle 1.25×. |
| `opacity.dock` / `blur.dock` | not set | not set | Reserved: dock material (v0.2) |
| `blur.wallpaper` | not set | not set | Reserved: wallpaper blur background choice (8) |
| `shadow.panel.radius` / `shadow.panel.y` | `12` / `2` | = | Soft panel shadow |
| `shadow.segment.radius` / `shadow.segment.y` | `2` / `1` | = | Selected switcher segment shadow |
| `font.family` | `system` | = | System font (SF Pro) |
| `font.body.size` / `.weight` | `13` / `regular` | = | Body text |
| `font.label.size` / `.weight` | `11` / `regular` | = | Metadata, line 2 of a row |
| `font.rowTitle.size` / `.weight` | `13` / `medium` | = | Line 1 of a row |
| `font.section.size` / `.weight` | `11` / `semibold` | = | Group headers |
| `font.control.size` / `.weight` | `12` / `medium` | = | Switcher, buttons |
| `font.tag.size` / `.weight` | `10` / `medium` | = | Row tags |
| `font.hint.size` / `.weight` | `11` / `regular` | = | Shortcut hint (⌃⌥S) |
| `font.reason.size` / `.weight` | `12` / `regular` | = | Waiting reason and other row notes, main window |
| `font.calm.size` / `.weight` | `20` / `light` | = | "Nothing needs you." in the main window |
| `font.calmCompact.size` / `.weight` | `15` / `light` | = | "Nothing needs you." in the menubar window |
| `font.title.size` / `.weight` | `17` / `semibold` | = | Window titles |
| `font.count.size` / `.weight` | `28` / `light` | = | Count line numbers. Always tabular digits. |
| `font.countCompact.size` / `.weight` | `22` / `light` | = | Count line in the menubar window |
| `font.stat.size` / `.weight` | `34` / `light` | = | Reserved: large single numbers |
| `motion.duration.fast` | `0.12` | = | Hover, press |
| `motion.duration.normal` | `0.22` | = | Fold and unfold a group |
| `motion.duration.ring` | `1.6` | = | One turn of the working spinner (Core Animation) |
| `motion.duration.pulse` | `1.2` | = | One waiting pulse (v0.2) |
| `motion.duration.drift` | `90` | = | One slow fog drift cycle (there and back) |

### 5.4 Icons

| Token | Default SF Symbol |
|-------|-------------------|
| `icon.status.working` | `arrow.triangle.2.circlepath` (the row draws a spinner instead) |
| `icon.status.waiting` | `hand.raised.fill` |
| `icon.status.idle` | `pause.circle` |
| `icon.status.done` | `checkmark.circle` |
| `icon.status.unknown` | `questionmark.circle` |
| `icon.flag.noActivity` | `clock.badge.exclamationmark` |
| `icon.action.openFolder` | `folder` |
| `icon.disclosure` | `chevron.right` |
| `icon.child` | `arrow.turn.down.right` |
| `icon.empty` | `cube` (still outline ice cube, empty state) |
| `icon.app` | `dot.radiowaves.left.and.right` |

## 6. Status display

### 6.1 Never color alone

Every status shows three things: a color, an icon, and a text label.
In the dock, the label is in the tooltip and the accessibility label.
The ring also has a different shape per status (6.2).

### 6.2 Status ring

| Status | Ring |
|--------|------|
| `working` | Partial arc that turns |
| `waiting` | Full ring. Pulses after the `alertDelay` config value (`SPEC.md` 4.4). |
| `idle` | Thin full ring |
| `done` | Full ring with a check mark badge |
| `unknown` | Dashed ring |

## 7. Theme file

A theme is one JSON file. Keys in `tokens` are flat token names.

```json
{
  "spyreTheme": 1,
  "name": "Fog Light",
  "appearance": "light",
  "tokens": {
    "color.background.base": "#E3E5E8",
    "color.atmosphere.ridgeFar": "#A9B1BC",
    "color.text.primary": "#1F2328",
    "color.accent": "#8FB4D9",
    "color.status.waiting": "#8A5300",
    "radius.panel": 8,
    "font.count.weight": "light",
    "motion.duration.fast": 0.12
  },
  "densities": {
    "compact": {
      "space.md": 8,
      "size.row.height": 40
    }
  }
}
```

- `spyreTheme` is the format version.
- `appearance` is `light` or `dark`. It sets the macOS window appearance (title bar, system controls).
- A string token value is a color, a weight name (`light`, `regular`, `medium`, `semibold`, `bold`),
  an SF Symbol name, or `capsule`.
- `densities.compact` overrides tokens in compact density. It is optional. Spyre has a built-in compact overlay.

### 7.1 Layers

Spyre builds the active token set in this order. A later layer wins.

1. Built-in default theme (complete).
2. Selected theme: built-in or imported.
3. Density overlay.
4. User settings: accent color, background choice.
5. Accessibility overrides (section 10).

## 8. MVP customization

- Three built-in themes: Fog Light, Fog Dark, High Contrast. Built today: Fog Light and Fog Dark follow the macOS
  appearance (2.2). The theme setting below is not built yet.
- Accent color picker. Spyre sets `color.text.onAccent` to the graphite or white value with the higher contrast.
- Background choice:
  - solid: `color.background.base`,
  - gradient: `color.background.gradientTop` to `color.background.gradientBottom`,
  - wallpaper blur: the desktop wallpaper behind the window, blurred by `blur.wallpaper`.
- Density: comfortable or compact.
- Theme JSON import.

Later, not in MVP:

- Dock position: left, right, or hidden (v0.2, with the dock).

- A full theme editor.
- Community theme sharing.

## 9. Safe theme import

Theme import must never crash Spyre and must never use the network.

1. Read only a local file the user picks. Reject files larger than 64 KB.
2. Reject the file if it is not valid JSON, or if `spyreTheme` is missing or newer than Spyre supports.
3. Ignore unknown token names. Show a warning that lists them. Reason: a newer Spyre version can add tokens.
4. Check the type of each value. A value with the wrong type is dropped. The default value is used.
5. Clamp numbers to a safe range. Examples: opacity 0.0 to 1.0, radius 0 to 40, `font.body.size` 10 to 24, motion durations 0 to 2 s.
   Exception: `motion.duration.drift` 20 to 600 s, and `size.atmosphere.drift` 0 to 64.
6. Accept colors only in `#RRGGBB` or `#RRGGBBAA` form.
7. Accept `font.family` only when the font is installed. Otherwise use `system`.
8. A theme holds no URLs and no file paths. Reject any string value that contains a URL scheme such as `http:`, `https:`, or `file:`.
9. Check text contrast (section 10). Show a warning for each failing text pair.
10. Spyre copies the accepted values into its own folder. It never reads the source file again.

## 10. Accessibility

### 10.1 Contrast

- Every built-in theme meets WCAG AA: 4.5:1 for body text, 3:1 for large text and for status icons and rings.
- A test checks every built-in theme.
- The test checks text and status colors against every surface text sits on: `color.background.base`,
  `color.surface.card`, `color.surface.row`, `color.surface.rowHover`, `color.surface.waiting`,
  `color.surface.controlSelected`, the atmosphere tones (`sky`, `horizon`, `fog`), and the translucent
  `color.surface.control` composed over `color.atmosphere.sky`. It also checks the faint tag fill (`color.surface.tag`) composed over
  `color.surface.row` and `color.surface.waiting`. It also checks `color.text.onAccent` on `color.accent`.
- Text never sits on a ridge. Rows and panels are opaque, so the scenery behind them does not change contrast.
- Check contrast against the card color composed over the background. For wallpaper blur, set `opacity.card` to at least 0.85. The wallpaper color is not known.
- Imported themes: a theme that fails AA still loads. Spyre shows a warning for each failing text pair. Spyre does not change the colors. The user can switch back to a built-in theme at any time.

### 10.2 Reduce Transparency

When macOS "Reduce Transparency" is on:

- Cards and the dock are opaque: opacity 1.0, blur 0.
- The translucent switcher track (`color.surface.control`) is drawn as the opaque `color.surface.row`.
- Wallpaper blur changes to the solid background.
- The atmosphere stays. It is a background, not a transparent surface.

### 10.3 Reduce Motion

When macOS "Reduce Motion" is on:

- The working ring does not turn. It shows a static partial arc. The row spinner is the same.
- The atmosphere stays, and its drift stops.
- The waiting pulse is off. The ring stays full and uses a thicker line.
- Cards, rows, and the dock do not slide or spring. They change with a crossfade of at most `motion.duration.fast`, or at once.
- Status changes still show at once. Motion never hides a state change.

### 10.4 Other rules

- Every control has an accessibility label. A dock icon label holds agent, project, and status.
- Focus is always visible. It uses `color.focus`.
- Text sizes come from tokens. Do not set a fixed size in a view.
