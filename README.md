# Forma

A native iOS companion for training, nutrition, body weight, daily steps and small supporting routines — built with SwiftUI, SwiftData, Swift Charts, HealthKit, ActivityKit and UserNotifications.

The idea: **make daily tracking effortless, then turn it into progress you can actually read.** Every screen tries to answer one of three questions: *What should I do today? What have I logged? Am I making progress?*

- No account, no server, no analytics. Data lives on the device.
- Fully usable without Apple Health. Health makes steps and scale weigh-ins automatic.
- Wording is descriptive and non-judgemental: missing days are "not logged", never "missed", and there are no streaks.

---

## Requirements

| | |
|---|---|
| Xcode | 16 or later (the project uses folder-synchronised groups, `objectVersion 77`) |
| iOS deployment target | 17.0 |
| Devices | iPhone (portrait) |
| Swift language mode | 5 |

## Getting it running

1. Open `Forma.xcodeproj`.
2. Select the **Forma** target → *Signing & Capabilities* → choose your team. Do the same for **FormaWidgetsExtension** and **FormaTests**.
3. Change the bundle identifiers to your own prefix. They must stay nested:
   - app: `dev.forma.app` → e.g. `com.yourname.forma`
   - widget extension: `dev.forma.app.Widgets` → `com.yourname.forma.Widgets`
   - tests: `dev.forma.app.Tests`
4. Confirm the **HealthKit** capability is present on the app target (it comes from `Config/Forma.entitlements`). With automatic signing Xcode registers it for your App ID.
5. Build and run the **Forma** scheme on a device or simulator.

Everything except HealthKit data and Live Activities can be exercised in the Simulator. HealthKit works in the Simulator with data you add in its Health app; Live Activities and the Dynamic Island need an iPhone 14 Pro or later (or the matching simulator) for the island layouts.

### Sideloading without Xcode

Every push builds an IPA in the **Sideload IPA** workflow (Actions tab → latest run → *Artifacts* → `Forma-ipa`; you need to be signed in to GitHub to download it). It's compiled for iPhone and ad-hoc signed with the app's entitlements, but it is **not** signed with an Apple certificate, so it has to be installed with a tool that re-signs it with your Apple ID:

- [Sideloadly](https://sideloadly.io) (Windows/macOS): connect the iPhone, drop in the `.ipa`, enter your Apple ID.
- [AltStore](https://altstore.io) or SideStore: add the `.ipa` from the Files app.

Requirements and caveats:
- iOS 17 or later. Turn on **Developer Mode** (Settings → Privacy & Security → Developer Mode) and, with Sideloadly, trust your Apple ID under Settings → General → VPN & Device Management.
- With a free Apple ID the app expires after 7 days (re-install or let AltStore refresh it; your data is kept as long as the app isn't deleted) and counts toward the 3-app limit. The Live Activity extension uses one extra App ID.
- Live Activities and notifications don't need special entitlements and work when sideloaded. **Apple Health** needs the HealthKit entitlement; whether your Apple ID and tool grant it varies. If it isn't granted, "Connect Apple Health" shows an error and everything else (manual weight, steps, food, training) still works.
- With a paid developer account, building and running from Xcode (above) is simpler and doesn't expire after 7 days.

### Capabilities & configuration (already in the repo)

| Item | Where |
|---|---|
| HealthKit entitlement | `Config/Forma.entitlements` |
| `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription` | `Config/Forma-Info.plist` |
| `NSSupportsLiveActivities` | `Config/Forma-Info.plist` |
| `forma://` URL scheme (Live Activity taps) | `Config/Forma-Info.plist` |
| Widget extension point (`com.apple.widgetkit-extension`) | `Config/FormaWidgets-Info.plist` |
| Widget extension embedded in app | *Embed Foundation Extensions* build phase |

No App Groups, background modes, push notifications or iCloud are required.

---

## What's in the app

**Today** — an actionable dashboard rather than a wall of numbers: planned or in-progress workout with a one-tap start/resume, calories and protein against the targets in effect today, steps, due routines (check off in place), latest weight with a 30-day trend sparkline, quick actions, and a card linking to last week's review. New users get a short "Get started" checklist instead of zeros. Card order adapts to whether today is a training day.

**Training**
- Templates: name, exercises, warm-up/working sets, rep ranges, per-exercise rest, notes, planned weekdays; reorder, duplicate, delete. Templates never rewrite history.
- Active workout (full-screen, minimisable to a persistent "Workout in progress" bar on every tab): last session's values beside each set and as placeholders, tap "previous" to copy it, big check buttons, warm-up vs working sets, optional RPE, per-exercise notes, add/remove/reorder exercises mid-session, rest timer with ±15 s and skip, elapsed time, finish/discard confirmations, PR badge when a set beats earlier sessions.
- Suggested values are written into a set only when you check it off.
- Crash/termination safe: the session is saved to SwiftData as you go and restored on launch, including a running rest timer.
- History with session detail, in-place editing of finished workouts, "repeat this workout", "save as template".
- Exercise library (53 built-in exercises including bench, squat, deadlift, rows, pulldowns, pullovers, overhead press) plus custom exercises with weighted, bodyweight, assisted, timed and distance tracking.
- Per-exercise progression: estimated 1RM (Epley, labelled as an estimate), top set, comparable volume, best reps, heaviest-weight-by-reps table, PR markers per session.

**Nutrition**
- Day diary grouped by Breakfast/Lunch/Dinner/Snacks, day navigation and date picker, totals vs targets, optional carbs/fat.
- Add sheet with Recent, Favorites, Saved meals and My foods, plus search; Quick Add for estimates; create foods with any serving size/unit and log by servings, grams/ounces or volume.
- Duplicate, "log again today", move between meals, copy a meal from another day, save a meal and log it later (it expands into normal, editable entries).
- Entry time ("eaten at", optional) is separate from when it was logged; logging lunch at night stays lunch.
- Each entry shows its source (My food, Saved meal, Quick estimate, Copied). Entries snapshot their values so editing or deleting a food never changes history.
- There is **no bundled food database or barcode scanner** — see limitations.

**Progress**
- Weight: daily weigh-ins as faint points plus a smoothed trend line, W/M/3M/Y/All, drag to inspect, goal line or maintenance band, change over the period, a plain-language summary, and an explanation sheet. The line breaks across gaps of more than three weeks instead of implying data.
- Strength (most-trained exercises), training consistency (workouts per week vs plan), steps, nutrition trends (logged days only), routines, and weekly reviews.

**Steps** — daily target (dated, so changing it doesn't reinterpret history), today's progress, W/M/3M/Y bar chart with the target line, averages that ignore days without data, days the target was reached. Optional manual entries are labelled and never added on top of Health data.

**Routines** — lightweight habits with daily / specific-days / N-times-a-week schedules, optional reminders, archiving, and links to logged activity ("when I finish a workout", "when I reach my step target", "when I log food/weight") so nothing is ticked twice. Weekly consistency uses symbols, not just colour.

**Weekly review** — workouts vs planned, personal records, days with food logged and averages on those days, weight-trend change when there's enough data, average steps and target days, routine check-ins. Then a small next step: keep the plan or adjust (with shortcuts to training days, targets and routines), plus an optional note.

**Settings** — units, weight goal, nutrition and step targets, training days and per-day templates, rest/RPE preferences, manual steps, reminders, Apple Health, Live Activity, appearance, CSV export, delete-all, privacy.

---

## Integrations

### Apple Health
- Reads **body mass** (anchored query: only changes since last import, including deletions) and **step count** (daily `cumulativeSum` statistics, which HealthKit de-duplicates across iPhone and Watch).
- Optionally writes weigh-ins you enter in Forma and finished strength workouts (`HKWorkoutBuilder`, iOS 17).
- Only the types the current toggles need are requested, and only when the person chooses to connect.
- Duplicate prevention (`FormaKit/HealthImport.swift`): samples from Forma's own bundle, samples carrying a local entry's ID in `HKMetadataKeyExternalUUID`, previously imported UUIDs and implausible values are skipped. Edits rewrite only Forma's own sample; Forma never edits or deletes other apps' data.
- HealthKit doesn't reveal read permission; empty results are shown as "no data found" with a pointer to the Health app, never as "access denied".
- Refreshes when the app becomes active and on pull-to-refresh.

### Live Activity
- Starts with a workout, updates on set completion and rest changes, ends on finish (lingers 5 min with the final state) or discard (immediately). Orphaned activities are cleaned up at launch.
- Lock Screen and Dynamic Island (compact, minimal, expanded) layouts. All clocks are timestamp-driven (`Text(timerInterval:)`, `Text(_:style: .timer)`), with the rest end as the stale date so the view re-renders when rest ends. No background loop.
- **Skip** and **+30s** rest buttons use `LiveActivityIntent` (compiled into both targets so they run in the app's process).
- Settings let people turn it off or hide workout/exercise names on the Lock Screen.

### Notifications
- Permission is requested in context: the first time a reminder is turned on, or the first time a rest timer starts with rest alerts enabled.
- Reminder types: planned workouts, weigh-ins, routines (per routine), weekly review, rest-timer completion.
- Reminders are planned as dated, one-off notifications up to 14 days ahead (`ReminderPlanner`) and re-planned on launch, on foreground and after data changes. That lets Forma skip a reminder for something already done, respect quiet hours and stay under iOS's 64 pending notification limit. Discreet text ("You have a reminder.") is on by default.

---

## Architecture

```
Forma.xcodeproj
Forma/                 App target (folder-synchronised)
  App/                 Entry point, root tabs, router, @_exported FormaKit
  DesignSystem/        Theme tokens, motion, components, formatting, number field
  Models/              SwiftData models, versioned schema, exercise catalog
  Services/            Settings, HealthKit, notifications, Live Activity, workout controller, export
  Features/            Today, Training, Workout, Nutrition, Weight, Steps, Routines, Progress, Settings, Onboarding
  Resources/           Asset catalog (app icon, accent colour)
Shared/                Compiled into the app and the widget: activity attributes, rest-timer intents, palette
FormaWidgets/          Widget extension: workout Live Activity
FormaTests/            App-hosted unit tests (SwiftData in memory, workout controller)
FormaKit/              Swift package with all pure logic + 70 tests
Config/                Info.plists and entitlements
```

- **FormaKit** holds everything that can be pure: units and parsing, `DayKey`, weight-trend smoothing, chart scales, 1RM/PR/progression, nutrition math, dated target timelines, step reconciliation, routine schedules and consistency, weekly review sentences, reminder planning, Health import de-duplication, CSV, and the tolerant settings model. It has no UI or Apple-only dependencies, so it builds and tests on Linux too.
- **Persistence**: SwiftData with a `VersionedSchema` (`FormaSchemaV1`) and a `SchemaMigrationPlan`, so future model changes get explicit migration stages. CloudKit is explicitly disabled so Health-derived data is never synced through iCloud.
- **State**: `@Observable` services injected through the environment (`AppSettings`, `HealthService`, `NotificationService`, `LiveActivityService`, `WorkoutController`, `DayClock`, `AppRouter`), and `@Query` for data in views.

### Data decisions worth knowing
- Masses are stored in kilograms, energy in kcal; units are a display concern, and fields only write back when the typed value changes, so viewing in pounds never alters stored values.
- Diary-style records (food, routine check-ins, manual steps) store a **day key** (`yyyy-MM-dd`) chosen by the person; instants (weigh-ins, workouts) store absolute dates. Travelling across time zones never moves Tuesday's lunch to Wednesday.
- Targets (calories, macros, steps) are stored as dated changes. Past days are judged against the target in effect that day; the first target also applies to earlier history.
- Weight trend: daily means, then an exponentially weighted moving average (α = 0.1 per day, scaled for gaps: `1 − 0.9^days`, ~6.6-day half-life). Weekly rate is a least-squares slope over 28 days that needs ≥4 weigh-ins over ≥10 days. Y-axes have a minimum span (3 kg / 6 lb) so normal fluctuation isn't exaggerated.
- Steps: Health wins for any day it has data; manual entries fill other days; days without data are omitted from averages.

---

## Design

The design system lives in `Forma/DesignSystem`: neutral grouped surfaces, one accent for interaction, and one consistent hue per metric (weight, calories, protein, carbs, fat, steps, training, routines) used across cards, charts and progress. Rounded, tabular numerals for values that change; continuous corners; cards without borders.

Motion (`Motion.swift`): short ease-out for presses (scale to ~0.97), interruptible springs for layout and progress, nothing animates from zero scale, and every animation falls back to a short fade (or nothing) under Reduce Motion. Haptics mark completion, selection and warnings.

Accessibility: Dynamic Type throughout (dense set rows are capped at the first accessibility size), VoiceOver labels/values/hints and combined elements for cards and stats, per-mark chart labels plus written summaries under every chart, status conveyed by text and symbols as well as colour, and 44–52 pt targets for workout controls.

> **Note on the requested "design skills by Emil":** no such skill was installed in this environment (the local skills directory, synced skills, plugin list and skill catalog were all checked). They were not used. The design decisions above are my own, guided by general design-engineering practice.

---

## Tests and verification

```bash
# Pure logic (runs on macOS or Linux)
cd FormaKit && swift test
```
70 tests across 15 suites cover units and parsing, day keys across DST and time zones, trend smoothing and rates, chart scales, 1RM/PRs/progression/suggestions, nutrition math, target timelines, step reconciliation and stats, routine schedules and consistency, reminder planning (quiet hours, completed days, caps, discreet text), Health import de-duplication, CSV escaping, weekly review wording and settings decoding.

In Xcode, **Product → Test** on the Forma scheme runs `FormaTests`: SwiftData persistence (edit/delete, unit storage, nutrition totals after edits, independent duplicates, saved meals, dated targets, routine toggles, idempotent seeding) and workout behaviour (template edits don't rewrite sessions, suggestions only applied on completion, finish drops unchecked sets, restore after relaunch, discard, history edits feed progression, repeat workout). Run the package tests from the FormaKit scheme or the command line.

**Continuous integration.** `.github/workflows/build.yml` runs on every push: FormaKit `swift test`, an `xcodebuild` build of the app and widget extension for the iOS Simulator, and `FormaTests` on a simulator, using the newest stable Xcode on the GitHub macOS runner. The first runs (Xcode 26, iOS 26.5 simulator) passed: 70/70 package tests and 15/15 app tests. `.github/workflows/ipa.yml` produces the sideload IPA.

**Not yet verified:** running on a physical iPhone, and real HealthKit data, Live Activities and notification delivery. These need a device and are worth checking by hand.

---

## Limitations and deferred work

- **No food database, search service or barcode scanner.** Logging works with your own foods, saved meals, recents and quick estimates. `NutritionSource.externalDatabase` is reserved for a future integration.
- Reminders are planned two weeks ahead and re-planned whenever the app opens; if the app isn't opened for two weeks they pause.
- Planned-workout counts in past weekly reviews use the *current* training days.
- Health data is refreshed on app open/foreground and pull-to-refresh; there is no HealthKit background delivery.
- Sleep, dietary energy write-back and workout reading from Health are not implemented.
- iPhone only, portrait. No iPad layout, widgets beyond the Live Activity, Watch app, or iCloud sync.
- Localisation: strings are English and not yet extracted into a String Catalog.
- No App Intents/Shortcuts beyond the Live Activity buttons.
