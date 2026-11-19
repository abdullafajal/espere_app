# Espere design rules

The app uses one look everywhere, so people always know what they can tap.

## Colours: only ink, white and lime

| Token (`AppColors`) | Value | Use |
|---|---|---|
| `dark` | `#141414` | Text, primary buttons, dark cards, nav bar, all amounts |
| `card` | `#FFFFFF` | Cards, sheets |
| `background` | `#F5F6F2` | Screen ground |
| `accent` | `#C8E64A` | Espere lime: Add, selected item, active tab, highlights on dark |
| `accentSoft` | `#EFF7CF` | Light lime: selected rows, text selection |
| `surface` | `#F2F3EE` | Inputs, chips, icon circles |
| `muted` / `mutedLight` | `#5B6058` / `#8E938A` | Second line of text / placeholders |
| `darkCard`, `darkMuted` | `#222520`, `#B9BDB5` | Boxes and text inside dark cards |

- No other colours (no red, green, blue). Errors are ink, not red.
- Categories and groups have **no colour**: their icon sits on a grey circle
  (`categoryFill` / `categoryInk`). The `color` field is still stored for the server but
  never shown.
- Money in / out: `+₹` / `−₹` (true minus sign). Arrows: in ↙ (`south_west_rounded`),
  out ↗ (`north_east_rounded`).
- Charts without category colours use `AppColors.chartAt(i)` (ink, lime, greys).
- There is no wallpaper / dynamic colour. The user can swap lime for another light accent
  in **Settings → App colour** (`AppAccent.options`: Lime, Mint, Sky, Lavender, Pink,
  Peach, Sun). So `AppColors.accent` / `accentSoft` are getters, not `const`: never put
  them inside a `const` widget. The Android home-screen widget stays lime.

## Type

Plus Jakarta Sans, bundled in `assets/fonts/` (works offline). Styles in `AppText`:
`hero` (big amounts), `screenTitle`, `section`, `label`, `rowTitle`, `rowSub`, `amount`.

## Components

| Thing | Look |
|---|---|
| Main action | Lime pill / circle with ink text (`FilledButton`, `EspereActionButton(primary: true)`) |
| Primary button | Ink, lime text (`ElevatedButton`) |
| Secondary | Ink outline (`OutlinedButton`) or grey pill |
| Header | `EspereHeader`: round 44 px back button, bold title; top-level tabs have no back button |
| Filter chips | `EspereFilterChip`: white pill, ink when active; `dropdown: false` for toggles |
| List rows | Grey icon circle, bold title, grey second line, amount on the right, visible `⋮` for Edit/Delete (swipe still works) |
| Switches | Ink track, lime knob |
| Icons | Material `_rounded` icons everywhere (`IconMapper` maps category names) |

Touch targets are at least 44 px.

## Navigation

Floating dark bar: **Home · Activity · ( + ) · Budgets · Split**. The middle `+` opens
**Quick add** (`lib/screens/quick_add_screen.dart`): keypad, tap a category to save, Undo.
Editing a transaction and checking a scanned receipt use the same screen
(`QuickAddScreen.edit` / `.prefilled`): a category tap selects it and the lime Save button
stores the change; the bin icon deletes.

Settings (avatar on Home) holds Currency, Categories, Reports, Auto-track, reminders,
password and Log out. Export is the share button on Activity.
Friends is inside Split (`SplitSwitcher`: Groups | Friends).

## Checking screens without a phone

`flutter test test_preview --update-goldens` renders every screen with made-up data into
`test_preview/goldens/*.png` (git-ignored; not part of CI). Add a screen to
`test_preview/screens_preview_test.dart` or `more_preview_test.dart` when you build one.
