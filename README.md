# Uniflex

Campus food ordering, delivery, and on-demand errand app for Redeemer's
University, Nigeria.

Uniflex is **one Flutter app** serving three roles — **Student**, **Rider**,
and **Admin** (Admin absorbs Kitchen Staff duties; there's no separate
kitchen login). Which experience a person sees is decided after login,
based on their account role. There is no separate web dashboard —
everything lives in this one codebase. See [ARCHITECTURE.md](ARCHITECTURE.md)
for how that's structured.

This repository is being built in phases. **Phase 0** (current) is the
project scaffold and design system only — no real feature screens, no real
backend. See [CHANGELOG.md](CHANGELOG.md) for what's shipped so far.

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

Then fill in real values in `.env` as each service is wired up. In Phase 0
every key can stay blank — the app runs entirely on mocked/local data and
does not call any real backend yet. See `.env.example` for the full list
of keys and what each is for.

## Run locally

```bash
flutter run
```

This launches the mock role picker (Phase 0 has no real sign-in yet —
see [ARCHITECTURE.md](ARCHITECTURE.md)). Choose Student, Rider, or Admin
to see that role's shell.

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
