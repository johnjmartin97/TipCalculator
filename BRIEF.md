# Brief

## What we are building

A native iOS tip calculator for the thirty seconds at the end of a meal, when
the check is on the table and someone has to do math. It is for ordinary
diners splitting a bill with friends, not for accountants. A good one answers
"what do I write on the line?" in under five seconds with no typing beyond the
bill amount, gets the cents exactly right, and never makes you hunt for the
number you came for.

## Core behaviour

### Money model

- All money is held as a whole number of **cents** (`Int`), never `Double`.
  Every calculation and every test asserts on cents.
- Rounding rule everywhere: **round half up** on the final cent
  (`(numerator * 2 + denominator) / (denominator * 2)` style, or `Decimal`
  with `.plain` rounding). `15%` of `4999` cents = `749.85` → `750`.
  Chosen over banker's rounding because a diner checking by hand rounds half
  up, and a total that disagrees with their arithmetic reads as a bug.
- Display uses the device locale's currency format. Currency symbol and
  decimal separator come from `Locale.current`; the app does no currency
  conversion.

### Inputs

1. **Bill amount** — entered on an in-app numeric keypad (digits `0`–`9` and
   a delete key). Digits shift in from the right: tapping `4`, `9`, `9`, `9`
   yields `$49.99`. Delete shifts right-to-left. No decimal-point key.
   - Maximum 9 digits (`$9,999,999.99`). Further digit taps are ignored and
     produce no state change.
   - Empty bill is `0` cents and displays as `$0.00`.
2. **Tip percentage** — presets `15%`, `18%`, `20%`, `25%`, plus a custom
   stepper/slider covering `0%`–`100%` in `1%` steps. Exactly one tip value
   is active at a time; tapping a preset deselects the custom value and vice
   versa. Default on first launch is `20%`.
3. **Split count** — integer `1`–`50`, default `1`. Minus is disabled at `1`;
   plus is disabled at `50`.
4. **Round mode** — a three-way control: `Off` (default), `Round total up to
   the next whole currency unit`, `Round total down to the whole currency
   unit`.

### Outputs (recomputed synchronously on every input change)

Let `bill` = bill cents, `pct` = tip percent, `n` = split count.

- `tipTotal = roundHalfUp(bill * pct / 100)`
- `grandTotal = bill + tipTotal`
- If round mode is **up**: `grandTotal` rises to the next multiple of 100
  cents (a total already on a whole unit does not move); `tipTotal` is
  recomputed as `grandTotal - bill` so the two always reconcile.
- If round mode is **down**: `grandTotal` falls to the multiple of 100 cents
  at or below it, but **never below `bill`** — if rounding down would make the
  tip negative, `grandTotal = bill` and `tipTotal = 0`.
- `perPerson = grandTotal / n`, distributed so the parts sum **exactly** to
  `grandTotal`: base share is `grandTotal / n` (integer division) and the
  first `grandTotal % n` people pay one extra cent. The UI shows the base
  share, and when a remainder exists shows a second line: "`k` of you pay
  `<base+1>`".
- `perPersonTip = tipTotal / n` with the same exact-sum distribution.

### Terminal / edge conditions

| Condition | Required behaviour |
|---|---|
| Bill = 0 | All outputs `$0.00`. No error state. Round mode has no effect. |
| Tip = 0% | Tip `$0.00`, total = bill. Valid state, not an error. |
| Split = 1 | Per-person row still shown, equal to the grand total. No remainder line. |
| Split > grand total in cents (e.g. `$0.03` across 10) | Base share `$0.00`, remainder line names the 3 people paying `$0.01`. No divide-by-zero, no crash. |
| Round down when tip would go negative | Total clamps to bill; tip `$0.00`. |
| Round up on an exact whole-unit total | Total unchanged. |
| Max digits reached | Extra taps ignored; no flash, no error text. |
| Delete on empty bill | No-op. |

### Persistence and history

- The last used tip percent, split count, and round mode survive app
  termination and are restored on next launch. The bill amount does **not**
  persist; each launch starts at `$0.00`.
- **Save** writes the current calculation (bill, tip percent, tip amount,
  total, split count, timestamp) to a history list. History is capped at 100
  entries, newest first; the 101st save drops the oldest.
- History rows can be deleted by swipe. "Clear all" requires a confirmation
  dialog.
- Tapping a history row restores that calculation into the calculator.

### Sharing and feedback

- A share button produces plain text: `Bill $49.99 + 20% tip $10.00 = $59.99
  — $30.00 each (2 people)`, handed to the system share sheet.
- Haptics: light impact on every keypad digit, selection feedback on preset
  and split changes, success notification on save. All haptics respect the
  system reduce-motion / silent settings via the standard generators.
- Every value change animates the displayed numbers over `0.2s` with a
  numeric content transition; there is no loading state anywhere because
  everything is local arithmetic.

## Frameworks

| Surface | Choice | Why |
|---|---|---|
| UI toolkit | SwiftUI (iOS 17.0 minimum deployment target) | Native, no storyboards, and the whole app is one screen plus a sheet. iOS 17 unlocks `@Observable`, `.contentTransition(.numericText())`, and `.sensoryFeedback`. |
| State management | Observation (`@Observable` model class + `@State` in the root view) | One `TipCalculator` model holds bill cents, percent, split, round mode, and computes outputs as pure properties — directly unit-testable with no UI. |
| Layout | SwiftUI `Grid` for the keypad, `VStack`/`HStack` for the rest, inside a `ScrollView` that only scrolls on small devices | `Grid` gives equal-width keypad columns without manual frame math. |
| Iconography | SF Symbols 5 (`delete.backward`, `plus`/`minus`, `square.and.arrow.up`, `clock.arrow.circlepath`) | Ships with the OS, scales with Dynamic Type, no asset work. |
| Animation | SwiftUI implicit animation (`.animation(.snappy, value:)`) plus `.contentTransition(.numericText())` on the money labels | Digits roll instead of popping, which is the single detail that makes the totals feel alive. |
| Haptics | `.sensoryFeedback` view modifier (UIKit `UIFeedbackGenerator` under the hood) | Declarative, correct by default, no Core Haptics engine lifecycle to manage for taps this simple. |
| Audio | None | A tip calculator used in a restaurant must be silent. Haptics carry all feedback. |
| Persistence | SwiftData (one `@Model` `SavedCalculation` entity) for history; `@AppStorage` for the three sticky settings | SwiftData handles the list, ordering, and deletes with no serialization code; `@AppStorage` is right for three scalars. |
| Number formatting | Foundation `Decimal.FormatStyle.Currency` with `Locale.current` | Correct symbol, grouping, and separator for every locale without hand-rolled strings. |
| Testing | Swift Testing (`import Testing`) for the model, XCTest UI tests for the keypad flow | Model is pure, so the arithmetic table above becomes parameterized tests. |
| Project generation | XcodeGen (`project.yml`), bundle id `com.powerplant.tipcalculator` | Proven in earlier runs: xcodegen + `xcodebuild -scheme <name>` builds and launches on simulator. |

## Quality bar

1. From cold launch, entering `4 9 9 9` and reading the per-person total takes
   no more than four taps and no system keyboard ever appears.
2. Every arithmetic case in the edge-condition table above produces exactly
   the stated cents, verified by passing unit tests — including that split
   shares sum to the grand total with zero cents lost.
3. The grand total and per-person amounts are legible at arm's length on an
   iPhone SE: the primary total is at least 40pt and never truncates or
   wraps, at any Dynamic Type size up to Accessibility Large.
4. Rotating the device, backgrounding the app, and returning restores the
   exact same on-screen numbers.
5. Tip percent, split count, and round mode are the same after force-quitting
   and relaunching; the bill resets to `$0.00`.
6. Every interactive control has a VoiceOver label that reads its meaning and
   value (e.g. "20 percent tip, selected"), and the totals are announced when
   they change.
7. The app renders correctly in both light and dark appearance with no
   hardcoded colors that fail contrast in either.
8. Saving a calculation, killing the app, and relaunching shows that entry at
   the top of history with the right bill, tip, total, and split.

## Assets needed

- **App icon** — a flat 1024×1024 mark: a stylised receipt or check with a
  bold percent sign, on a warm single-hue gradient (deep teal to green reads
  as "money" without being literal dollar-bill green). Needs light, dark, and
  tinted variants for iOS 18+ icon appearance modes. Appears on the home
  screen and in Settings.
- **Accent color** — one color set in the asset catalog with light and dark
  values, used for selected tip presets, the save button, and the total. Must
  clear 4.5:1 contrast on both backgrounds.
- **Keypad key background** — no image asset; a rounded-rectangle shape style
  defined in code so it adapts to appearance. Listed here so nobody goes
  looking for a PNG.
- **Launch screen** — solid background color matching the app background, no
  logo, so launch is invisible rather than a flash.
- **No sound files, no textures, no celebration effects.** Deliberate: the app
  is used in public and any confetti or chime would be a defect, not a
  delight.

## Risks

- **Floating-point money.** The most likely defect is somebody reaching for
  `Double` for the bill or the percentage math. Cents-as-`Int` must be
  enforced in the model's public surface, not just its internals.
- **Split remainders silently lost.** `total / n` displayed n times is the
  classic bug: `$10.00` across 3 shows `$3.33` each and loses a cent. The
  remainder line is a real requirement, not a nicety.
- **Round mode interacting with split.** Rounding must be applied to the
  grand total *before* splitting, and the tip recomputed from the rounded
  total, or the tip and total stop reconciling on screen.
- **Locale formatting.** Testing only in `en_US` hides broken layout for
  locales with a trailing currency symbol or comma decimal separator, and
  hides overflow for long formatted amounts.
- **Dynamic Type overflow.** Large text sizes are where the keypad and the
  totals collide; this needs checking on the smallest supported device, not
  just a Pro Max simulator.
- **SwiftData in a single-screen app** could be over-engineering if history is
  cut from scope. If that happens, replace it with a JSON file in
  Application Support rather than leaving an unused model layer behind.
