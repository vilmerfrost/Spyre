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

The default themes are calm and clean.

- Use a lot of space. Do not fill every gap.
- Give each card one primary action. Hide other actions until hover or a context menu.
- Put translucent frosted-glass cards on a quiet background.
- Use a large corner radius on cards. Use pill-shaped controls.
- Show key numbers big and calm, for example "3 waiting". Use a light weight and monospaced digits.
- Use graphite text, not pure black. Do not use pure white as the main background.
- Use the accent color rarely: selection, focus, and one primary action. Not as a fill for large areas.
- Use status colors only for status. Do not use them for decoration.
- Keep motion short and fast. The user must never wait for an animation.

This default look stays for the MVP. It respects macOS "Reduce Transparency" (10.2).

### 2.1 Dock (v0.2)

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

### 2.2 Cards

- A session card shows agent, project, branch, status, and last activity.
- The primary action is "Open project".
- A child session card sits under its parent card, indented.

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

Default values are for the built-in light theme.
The dark and high-contrast themes set their own values.

### 5.1 Color

| Token | Default (light) | Use |
|-------|-----------------|-----|
| `color.background.base` | `#E6E8EB` | Quiet mist-gray background |
| `color.background.gradientTop` | `#ECEDEF` | Top of the optional gradient background |
| `color.background.gradientBottom` | `#DADDE2` | Bottom of the optional gradient background |
| `color.surface.card` | `#F7F8F9` | Card fill, before `opacity.card` |
| `color.surface.cardHover` | `#FFFFFF` | Card fill on hover |
| `color.surface.dock` | `#F2F3F5` | Dock fill, before `opacity.dock` |
| `color.border.subtle` | `#1F232814` | Thin card border |
| `color.text.primary` | `#1F2328` | Graphite main text |
| `color.text.secondary` | `#535A64` | Labels, metadata |
| `color.text.onAccent` | `#1F2328` | Text on an accent fill. Spyre derives it from the accent. |
| `color.accent` | `#8FB4D9` | Restrained frost-blue. Selection, focus, primary action. |
| `color.focus` | `#3F7FBF` | Focus ring |
| `color.status.working` | `#2F66A3` | Working |
| `color.status.waiting` | `#8A5300` | Waiting |
| `color.status.idle` | `#5B616B` | Idle |
| `color.status.done` | `#24713F` | Done |
| `color.status.unknown` | `#6A5F52` | Unknown |
| `color.flag.noActivity` | `#8A5300` | No-activity flag on a working row |

### 5.2 Shape, space, and size

| Token | Default | Use |
|-------|---------|-----|
| `radius.card` | `20` | Cards |
| `radius.row` | `12` | Rows inside a card or list |
| `radius.popover` | `14` | Menubar list, tooltips |
| `radius.control` | `capsule` | Buttons, toggles, segmented controls |
| `space.xs` / `sm` / `md` / `lg` / `xl` | `4` / `8` / `12` / `20` / `32` | Spacing scale |
| `size.row.height` | `52` | Session row, comfortable density |
| `size.icon.status` | `14` | Status icon |
| `size.dock.icon` | `36` | Dock icon |
| `size.dock.ring` | `2.5` | Status ring line width |
| `size.dock.maxIcons` | `6` | Icons before "+N" |
| `size.border` | `1` | Border width |
| `size.menu.width` | `320` | Menubar window width |
| `size.window.width` / `size.window.height` | `720` / `480` | Main window minimum size |

### 5.3 Material, font, and motion

| Token | Default | Use |
|-------|---------|-----|
| `opacity.card` | `0.72` | Card translucency |
| `opacity.dock` | `0.80` | Dock translucency |
| `blur.card` | `24` | Frosted-glass blur on cards |
| `blur.dock` | `30` | Frosted-glass blur on the dock |
| `blur.wallpaper` | `40` | Blur for the wallpaper background |
| `shadow.card.color` | `#1F23281A` | Soft card shadow |
| `shadow.card.radius` | `16` | Card shadow blur |
| `shadow.card.y` | `4` | Card shadow offset |
| `font.family` | `system` | System font (SF Pro) |
| `font.body.size` / `font.body.weight` | `13` / `regular` | Body text |
| `font.label.size` / `font.label.weight` | `11` / `medium` | Labels, metadata |
| `font.title.size` / `font.title.weight` | `17` / `semibold` | Section titles |
| `font.stat.size` / `font.stat.weight` | `34` / `light` | Big calm numbers. Always monospaced digits. |
| `motion.duration.fast` | `0.12` | Hover, press |
| `motion.duration.normal` | `0.22` | Card and row changes |
| `motion.duration.ring` | `1.6` | One turn of the working ring |
| `motion.duration.pulse` | `1.2` | One waiting pulse |

### 5.4 Status icons

| Token | Default SF Symbol |
|-------|-------------------|
| `icon.status.working` | `arrow.triangle.2.circlepath` |
| `icon.status.waiting` | `hand.raised.fill` |
| `icon.status.idle` | `pause.circle` |
| `icon.status.done` | `checkmark.circle` |
| `icon.status.unknown` | `questionmark.circle` |
| `icon.flag.noActivity` | `clock.badge.exclamationmark` |
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
    "color.background.base": "#E6E8EB",
    "color.text.primary": "#1F2328",
    "color.accent": "#8FB4D9",
    "color.status.waiting": "#8A5300",
    "radius.card": 20,
    "radius.control": "capsule",
    "opacity.card": 0.72,
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
- `appearance` is `light` or `dark`. It sets the macOS window appearance for system controls.
- `densities.compact` overrides tokens in compact density. It is optional. Spyre has a built-in compact overlay.

### 7.1 Layers

Spyre builds the active token set in this order. A later layer wins.

1. Built-in default theme (complete).
2. Selected theme: built-in or imported.
3. Density overlay.
4. User settings: accent color, background choice.
5. Accessibility overrides (section 10).

## 8. MVP customization

- Three built-in themes: light, dark, high contrast.
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
6. Accept colors only in `#RRGGBB` or `#RRGGBBAA` form.
7. Accept `font.family` only when the font is installed. Otherwise use `system`.
8. A theme holds no URLs and no file paths. Reject any string value that contains a URL scheme such as `http:`, `https:`, or `file:`.
9. Check text contrast (section 10). Show a warning for each failing text pair.
10. Spyre copies the accepted values into its own folder. It never reads the source file again.

## 10. Accessibility

### 10.1 Contrast

- Every built-in theme meets WCAG AA: 4.5:1 for body text, 3:1 for large text and for status icons and rings.
- A test checks every built-in theme.
- Check contrast against the card color composed over the background. For wallpaper blur, set `opacity.card` to at least 0.85. The wallpaper color is not known.
- Imported themes: a theme that fails AA still loads. Spyre shows a warning for each failing text pair. Spyre does not change the colors. The user can switch back to a built-in theme at any time.

### 10.2 Reduce Transparency

When macOS "Reduce Transparency" is on:

- Cards and the dock are opaque: opacity 1.0, blur 0.
- Wallpaper blur changes to the solid background.

### 10.3 Reduce Motion

When macOS "Reduce Motion" is on:

- The working ring does not turn. It shows a static partial arc.
- The waiting pulse is off. The ring stays full and uses a thicker line.
- Cards, rows, and the dock do not slide or spring. They change with a crossfade of at most `motion.duration.fast`, or at once.
- Status changes still show at once. Motion never hides a state change.

### 10.4 Other rules

- Every control has an accessibility label. A dock icon label holds agent, project, and status.
- Focus is always visible. It uses `color.focus`.
- Text sizes come from tokens. Do not set a fixed size in a view.
