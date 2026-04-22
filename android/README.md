# KGeN Eye — Android

Kotlin shell for the same product rules and backend contracts as the iOS **EgoCapture** app in the repo root.

## Open in Android Studio

1. **File → Open** and select this `android/` directory (not the monorepo root).
2. Let Android Studio create or sync the **Gradle wrapper** if prompted (`gradlew` / `gradle-wrapper.jar`).
3. Run the **app** configuration on a device or emulator.

## IDs

| Field | Value |
|--------|--------|
| **applicationId** | `com.kgeneye.eye` |
| **namespace** | `com.kgeneye.eye` |

The iOS bundle id is `com.kgeneye.com`. You can change `applicationId` in `app/build.gradle.kts` to match Play Console / org policy.

## Alignment with iOS

- Session artifact names, S3 prefix layout, and `serverless/` Lambda behaviour should stay in sync with `EgoCapture/` and `docs/` in the monorepo.
