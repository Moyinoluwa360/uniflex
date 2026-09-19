# Uniflex

Campus food ordering, delivery, and on-demand errand app for Redeemer's
University, Nigeria.

Uniflex is **one Flutter app** serving three roles — **Student**, **Rider**,
and **Admin** (Admin absorbs Kitchen Staff duties; there's no separate
kitchen login). Which experience a person sees is decided after login,
based on their account role. There is no separate web dashboard —
everything lives in this one codebase. See [ARCHITECTURE.md](ARCHITECTURE.md)
for how that's structured.

This repository is being built in phases. **Phase 1** (current) wires up
real Supabase authentication and the Student onboarding flow, plus
invite-only Rider/Admin login — no ordering/catalog/other feature screens
yet. See [CHANGELOG.md](CHANGELOG.md) for what's shipped so far.

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable
  channel). Run `flutter doctor` and resolve anything it flags before
  continuing.
- Android Studio (for the Android SDK/emulator) and/or Xcode (for iOS —
  macOS only).
- A device or emulator/simulator to run on.

## Install dependencies

```bash
flutter pub get
```

## Add local environment variables

The app reads config (API keys, service URLs) from a local `.env` file,
which is **not** committed to git.

```bash
cp .env.example .env
```

Then fill in real values in `.env` as each service is wired up.
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `TERMII_API_KEY` are required as
of Phase 1 (auth and phone OTP won't work without them); the rest can
stay blank until their phase. Before testing sign-up/login against a
real Supabase project, run `supabase/schema.sql` once in that project's
SQL editor — see the comments at the top of that file. See
`.env.example` for the full list of keys and what each is for.

## Run locally

```bash
flutter run
```

This launches the splash screen, then the Login screen (or straight to
the right role's home if a session is already persisted). Create Account
signs up a Student; Rider/Admin accounts are invite-only and must be
seeded by hand in Supabase first (see `supabase/schema.sql`). See
[ARCHITECTURE.md](ARCHITECTURE.md) for how the auth flow is wired.

Useful variants:

```bash
flutter run -d <device-id>   # target a specific device/emulator
flutter devices              # list available devices/emulators
flutter test                 # run the test suite
```

## Project status

Phased build — see [CHANGELOG.md](CHANGELOG.md) for what each phase adds.
Do not build feature screens (onboarding, ordering, delivery tracking,
admin dashboards, etc.) outside of their designated phase; see
[ARCHITECTURE.md](ARCHITECTURE.md) for where new work should live.
