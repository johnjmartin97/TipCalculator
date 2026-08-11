# Art direction

## Idea

A paper check on a dark green table: one tall card of numbers, a torn receipt
edge, and a keypad that feels like pressing real keys. It suits the product
because the whole job is reading one number in a dim restaurant — so the
number is huge, the chrome is quiet, and nothing else asks for attention.

## Palette

Two values per role: light appearance / dark appearance. These are the only
colours in the app. Every one is defined once in
`App/Sources/DesignSystem/Palette.swift` as a `Color` that switches on
appearance — there are no hardcoded hexes in view code.

| Role | Light | Dark | Used for |
|---|---|---|---|
| Background | `#F2F5F3` | `#0B1311` | Screen behind everything |
| Surface | `#FFFFFF` | `#18221F` | Totals card, keypad keys, history rows, sheets |
| Surface raised | `#E8EDEA` | `#22302C` | Pressed key, selected segment track |
| Primary | `#067A58` | `#35D6A4` | Selected tip preset, save button, grand total |
| Primary on-colour | `#FFFFFF` | `#052018` | Text sitting on a filled primary shape |
| Secondary | `#0F4C46` | `#7FC9B4` | Per-person label, section headings |
| Accent | `#E08A18` | `#F5B14A` | The percent mark in the icon, the remainder line |
| Success | `#067A58` | `#35D6A4` | Save confirmation |
| Danger | `#B3372C` | `#FF7A6B` | Delete, clear-all confirmation |
| Text primary | `#10201C` | `#F2F7F5` | Amounts, key digits, row titles |
| Text muted | `#5B6B66` | `#93A5A0` | Captions, disabled keys, timestamps |
| Separator | `#DDE4E1` | `#2B3835` | Hairlines, card outlines |

Contrast, measured against the background of the same appearance: primary
`#067A58` on `#FFFFFF` is 5.4:1; primary `#35D6A4` on `#0B1311` is 10.2:1;
text primary is above 14:1 in both. All clear 4.5:1.

## Type

Family: **SF Rounded** for every number and for keypad digits — rounded
figures read as money and stay friendly at large sizes. **SF Pro Text** for
all labels and body copy. Both ship with iOS; no font files.

| Role | Size | Weight | Face | Used for |
|---|---|---|---|---|
| Display | 56 pt | Bold | SF Rounded | Grand total |
| Title | 30 pt | Semibold | SF Rounded | Per-person amount |
| Amount | 22 pt | Medium | SF Rounded | Bill, tip total, history amounts |
| Key | 26 pt | Medium | SF Rounded | Keypad digits |
| Body | 17 pt | Regular | SF Pro Text | Labels, presets, buttons |
| Caption | 13 pt | Medium | SF Pro Text | Remainder line, timestamps, hints |

Every size scales with Dynamic Type from its matching text style (Display
from `.largeTitle`, Body from `.body`, and so on). The display total is
capped with `minimumScaleFactor(0.6)` and one line — it shrinks, it never
wraps or truncates. Numbers use `monospacedDigit()` everywhere so digits do
not jitter while they roll.

## Motion

| Interaction | Duration | Curve | What moves |
|---|---|---|---|
| Any amount changes | 200 ms | `.snappy` + `.contentTransition(.numericText())` | Digits roll in place; nothing else moves |
| Keypad key press down | 90 ms | `.easeOut` | Key fills with Surface raised, scales to 0.96 |
| Keypad key release | 140 ms | `.spring(response: 0.14, dampingFraction: 0.8)` | Key returns to 1.0 |
| Tip preset select | 180 ms | `.snappy` | Filled pill slides to the new preset; label colour crossfades |
| Split +/− | 160 ms | `.snappy` | Count rolls; disabled button fades to Text muted |
| Round mode change | 180 ms | `.snappy` | Segment highlight slides |
| Remainder line appears | 200 ms | `.snappy` | Opacity 0→1 with a 6 pt upward slide |
| History sheet | 350 ms | system sheet default | Standard sheet presentation |
| Save button confirm | 260 ms | `.spring(response: 0.26, dampingFraction: 0.7)` | Label swaps to a checkmark, scales 1.0→1.08→1.0 |

Nothing exceeds 400 ms. There is no celebration animation — the app is used
in public. Every animation is driven by `.animation(_, value:)` on a specific
value, so a change in one number never animates the layout around it. All of
it respects Reduce Motion: when it is on, durations collapse to a crossfade.

## Layout

- **Spacing scale:** 4, 8, 12, 16, 24, 32, 48. Nothing between these.
- **Screen margin:** 20 pt horizontal.
- **Corner radii:** keypad key 16, card 20, pill/preset 999 (full round),
  sheet 28, history row 14. All continuous corners
  (`RoundedRectangle(cornerRadius:style: .continuous)`).
- **Stroke widths:** hairline separator 1 pt in Separator; card outline 1 pt;
  selected control outline 2 pt in Primary.
- **Keypad:** 4 rows × 3 columns `Grid`, 12 pt gutters, keys with a minimum
  height of 56 pt and a minimum tap target of 44 × 44 pt.
- **Totals card:** full width, 24 pt inner padding, torn receipt edge along
  its bottom — a repeating triangular notch 10 pt wide and 6 pt deep, drawn
  as a SwiftUI `Shape`.
- **Shadow:** one only, on the totals card — y offset 2, blur 12, black at
  6% in light, none in dark (dark uses the Surface step instead).

## Feel

It should feel like the check itself answered you. You tap four digits and
the big number is simply there, rolling into place before you finish lifting
your thumb — no spinner, no lag, nothing to confirm. Each key press gives a
small, dry click under the finger, so the thing feels physical rather than
glassy. Reading it across a dim table at arm's length should take one glance
and no squinting, and putting the phone down should feel like the calculation
is done rather than abandoned.
