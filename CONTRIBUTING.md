# Contributing to SENSE

Thanks for helping improve SENSE.

## Principles

- **Privacy first.** New features must work on device by default. Anything that sends data off the device must be opt-in, clearly explained, and degrade gracefully when unavailable.
- **No hidden sensing.** Never access the camera, microphone, location, contacts or photos outside of an explicit user action.
- **Free to run.** The app must stay usable without paid services or API keys.
- **Honest features.** Don't ship placeholder functionality presented as complete.

## Development setup

```bash
brew install xcodegen
xcodegen generate
open SENSE.xcodeproj
```

The Xcode project is generated from `project.yml`; don't commit `SENSE.xcodeproj`. Put signing settings in `Config/Local.xcconfig` (see `Config/Local.example.xcconfig`).

## Where code goes

- Logic that doesn't need UIKit or Apple-only frameworks (parsing, extraction, ranking, provider logic) belongs in `Packages/SenseCore` and needs unit tests.
- Apple framework integrations (Vision, Speech, CoreLocation, notifications, SwiftData) belong in `App/Perception`, `App/Services` or `App/Persistence`.
- Screens belong in `App/Features/<Feature>`.

## Before opening a pull request

- `swift test --package-path Packages/SenseCore` passes.
- The app builds without new warnings.
- User-facing strings are localizable (`String(localized:)` or `Text` literals).
- New UI supports Dynamic Type, VoiceOver and dark mode.
- No secrets, keys or personal data are included in code, tests or fixtures.

## Reporting issues

Use the bug report template. Please don't attach captures that contain personal information.
