# UI rules (Uniflex)

Presentation work only. Never change services, repositories, provider data
logic, models, SQL, Edge Functions, payment/PIN or fee logic, or status values.

## Colour
- Read colours from `context.colors.<token>` (`AppColors`, a ThemeExtension).
  **No** `Color(0x..)`, `Color.fromRGBO`, `Colors.<x>` (except `transparent`)
  and **no legacy `AppColors.emerald/orange/info/...`** outside `lib/shared/theme/`.
  `test/ui_polish/ui_guard_test.dart` enforces it; its allowlist
  (`ui_guard_allowlist.txt`) may only shrink. Never add a file to it.
- Cards: plain `surface` + `border`. No tinted fills, no coloured glow.
- Green (`brand`/`brandText`) = main action, money in, live status.
- Orange (`promoOrange*`) = ads/promos and the cart button ONLY. Never for
  spending amounts or status.
- Red = warnings (`dangerText`). Solid red (`dangerSolid`) only on the final
  confirm inside `AppDialog` (`destructive: true`).
- Purple and blue are retired. Status = dot + words, never a coloured pill.
- Do not branch on `Brightness`/`isDark` in feature code; the tokens already
  have both themes.

## Components (`lib/shared/widgets/`) — use these, don't hand-roll
- Buttons: `AppButton` (primary / secondary / text / quietDanger / disabled).
  **Every Cancel is `quietDanger`.** Never a raw `FilledButton`/`ElevatedButton`
  for a new screen. `PrimaryButton`/`SecondaryButton` are thin wrappers.
- `AppCard`, `AppListGroup`+`AppListRow` (plain 22px icon, no coloured box),
  `AppSegmentedTabs`, `AppStatusLabel`, `AppIconButton`, `AppSectionLabel`,
  `AppAvatar`, `AppDialog`, `AppSheet`, `AppInlineNotice`, `TierHeader`,
  `AppAccordionCard`, `AppTextField`, `AppGlassNavBar`.
- Scrollables under the glass nav bar pad their bottom with
  `AppSpacing.navClearanceOf(context)`.

## Helpers
- Money: `Money.format/hero/minus/plus/signed`, `MoneyText`, `MoneyHero`.
  Never `'₦${x.toStringAsFixed(0)}'`. Spending is neutral; money in is `brandText`.
- Status: `StatusPresenter.order/group/gift/raw` -> label + tone. Don't write
  another status->colour switch.
- Icons: `AppIcons.*` only (outline family). Sizes 22 / 20 / 18. No filled glyphs.

## Type
- UI font is Plus Jakarta Sans (bundled). Wordmark/splash only: Clash Display.
- Use `Theme.of(context).textTheme` or `AppTypography.*`. No negative letter
  spacing except -0.01em on 28px+ headings; no negative word spacing.
- Amounts use tabular figures (`AppTypography.tabular`).

## Radii / spacing
Card 20 (large 24), button 14 (small 12), input 14, sheet top 28, nav 34.
Gutter 20, card padding 16, list row min 56.

## Checks
No emulator here. Verify with `flutter analyze`, `flutter test`, `grep`; say
plainly what could not be verified (the owner tests on TestFlight).
