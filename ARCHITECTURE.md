# Architecture

This document explains how the Uniflex codebase is organized, the role
router pattern, the state management approach, and where future phases'
work should live. Keep this file updated as the project grows — it's the
map for anyone (including future-you) opening this repo cold.

## Big picture

Uniflex is **one Flutter app**, not three. A single codebase compiles to
a single binary that serves Student, Rider, and Admin users. There is no
separate web dashboard or separate app per role — everything routes
through role-based navigation inside this one app.

## Folder structure

```
lib/
  main.dart                  # Entry point: loads env, wraps app in ProviderScope
  app.dart                   # Root MaterialApp — theme + RoleRouter, nothing role-specific

  shared/                    # Used by ALL three roles. Nothing here should
                              # know which role is using it.
    theme/                   # Design system: colours, typography, spacing, ThemeData
    widgets/                 # Reusable components: buttons, cards, inputs, app bar,
                              # bottom nav shell, wordmark, dev placeholder screen
    services/
      auth/                  # UserRole enum, session provider (see "Auth" below)
    config/                  # Env var loading (EnvConfig / flutter_dotenv)
    router/                  # RoleRouter + the Phase 0 mock role picker

  student/                   # Student-only screens and navigation. Root: student_shell.dart
  rider/                     # Rider-only screens and navigation. Root: rider_shell.dart
  admin/                     # Admin-only screens and navigation. Root: admin_shell.dart
                              # (Admin also covers Kitchen Staff duties — no separate login)
```

**The rule that matters most:** `student/`, `rider/`, and `admin/` must
never import from each other. Each is a self-contained navigation stack.
The only things they're allowed to share are `shared/theme`,
`shared/widgets`, `shared/services`, and `shared/config`. If a change
needs a student screen to know about a rider screen, that's a sign the
feature belongs in `shared/` instead, or that the role boundary is being
violated — stop and reconsider rather than adding the import.

Within a role folder, group by feature, not by widget type — e.g.
`student/ordering/`, `student/tracking/`, not `student/screens/` +
`student/widgets/` as siblings of everything else. `home/` and `profile/`
in Phase 0 are the first two feature folders for each role; later phases
add more alongside them (e.g. `student/ordering/`, `student/cart/`,
`rider/jobs/`, `admin/orders/`, `admin/kitchen/`).

## The role router pattern

Entry point: `lib/shared/router/role_router.dart`.

1. `currentUserRoleProvider` (a Riverpod `StateProvider<UserRole?>` in
   `lib/shared/services/auth/session_provider.dart`) holds the signed-in
   user's role, or `null` if nobody is signed in.
2. `RoleRouter` watches that provider. Based on its value it returns
   **exactly one** of `StudentShell`, `RiderShell`, or `AdminShell` — never
   more than one, never a partial mix of two roles' UI.
3. Each `*Shell` widget (`student_shell.dart`, `rider_shell.dart`,
   `admin_shell.dart`) is the root of a fully separate widget tree /
   navigation stack for that role, built from the shared
   `AppBottomNavShell` component but with its own tabs and screens.

```
RoleRouter
 ├─ role == null    → MockRoleSelectScreen  (Phase 0 only, see below)
 ├─ role == student → StudentShell
 ├─ role == rider   → RiderShell
 └─ role == admin   → AdminShell
```

### Phase 0's mock auth

There is no real authentication yet. `MockRoleSelectScreen`
(`lib/shared/router/mock_role_select_screen.dart`) is a dev-only stand-in
that lets you set `currentUserRoleProvider` directly with three buttons,
purely to prove the router switches shells correctly. **Phase 1
(Onboarding & Auth) deletes this screen** and replaces it with a real
sign-in flow (Supabase auth, OTP via Termii, etc.) that sets
`currentUserRoleProvider` on success. The read side — `RoleRouter`
watching the provider — does not need to change when that happens; only
what writes to the provider changes.

## State management: Riverpod

The whole app uses [flutter_riverpod](https://riverpod.dev). Conventions
so far:

- `StateProvider` for simple mutable state (`currentUserRoleProvider`,
  `themeModeProvider`).
- Widgets that read/write providers extend `ConsumerWidget` (or use
  `Consumer`/`ConsumerStatefulWidget` where local state is also needed).
- `ProviderScope` wraps the whole app once, in `main.dart`.

As real features arrive (ordering, live rider tracking, admin dashboards),
prefer `Notifier`/`AsyncNotifier` for anything with real logic or async
data loading, and keep providers colocated with the feature that owns
them (e.g. `student/ordering/cart_provider.dart`) rather than piling
everything into `shared/`. Only promote a provider to `shared/` if more
than one role genuinely needs it.

## Design system

`lib/shared/theme/`:

- `app_colors.dart` — the only place brand hex values should be defined.
- `app_typography.dart` — the text scale (Inter, via `google_fonts`).
- `app_spacing.dart` — spacing and radius constants.
- `app_theme.dart` — builds the light and dark `ThemeData`. Both modes are
  first-class; `themeModeProvider` defaults to `ThemeMode.system`.

`lib/shared/widgets/` is the component library every screen should build
from: `buttons/` (`PrimaryButton` for CTAs, `SecondaryButton` for
secondary actions), `cards/app_card.dart`, `inputs/app_text_field.dart`,
`app_bar/uniflex_app_bar.dart`, `navigation/app_bottom_nav_shell.dart`,
and `wordmark/uniflex_wordmark.dart` (the text-only "Uniflex" wordmark —
swap in a real logo asset here once one exists, nowhere else).

Don't hardcode colours, fonts, or one-off paddings in screen code — pull
from these files so a design change only has to happen in one place.

## Config / environment variables

`lib/shared/config/env_config.dart` wraps `flutter_dotenv`. `main.dart`
calls `EnvConfig.load()` before `runApp`. Add new keys to **both**
`.env.example` (placeholder, committed) and a getter in `EnvConfig` — screens
and services should call `EnvConfig.xxx`, never read `dotenv.env[...]`
directly, so there's one place that knows every key the app depends on.

## Where future phases' work goes

| Phase (indicative)         | Lives in |
|-----------------------------|----------|
| Onboarding & Auth            | Replace `MockRoleSelectScreen`; new `student/`, `rider/`, `admin/` auth screens if role-specific; real auth service under `shared/services/auth/` |
| Student ordering flow        | `student/ordering/`, `student/cart/`, `student/checkout/` |
| Rider delivery flow          | `rider/jobs/`, `rider/navigation/`, `rider/earnings/` |
| Admin / kitchen management   | `admin/orders/`, `admin/kitchen/`, `admin/riders/`, `admin/menu/` |
| Payments (Paystack)          | `shared/services/payments/`, consumed from `student/checkout/` |
| Backend (Supabase)           | `shared/services/backend/` or `shared/services/<domain>/repositories` |
| Push notifications (Firebase)| `shared/services/notifications/` |
| Maps / live tracking         | `shared/services/maps/`, consumed from `student/tracking/` and `rider/navigation/` |

Update this table as phases land so it stays a reliable map of the repo.
