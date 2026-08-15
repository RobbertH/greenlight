# Greenlight 🚦

Record the exact moment a traffic light turns from red to green. With enough
datapoints per light, Greenlight detects the light's fixed cycle and predicts
— with a live countdown — when it will turn green next.

All data stays on the device (SQLite). Flutter app for iOS + Android with
native home-screen widgets.

## The loop

1. **Add a light**: long-press its location on the map, name it.
2. **Select it**: tap its pin — the app (and the widget) remember the last
   selected light.
3. **Record**: while waiting at red, open the record screen (or just look at
   the home-screen widget) and tap the big green button at the exact moment
   the light turns green.
4. **Predict**: after ≥5 records spanning a few cycles, the record screen and
   detail screen show the estimated cycle length and a countdown to the next
   green, gated by a statistical confidence test.

## Home-screen widget

One tap on the widget records instantly **without opening the app**:

- **iOS 17+**: interactive widget button backed by an `AppIntent` that runs in
  the widget-extension process. iOS 14–16: tapping the widget opens the app on
  the record screen.
- **Android**: widget button fires a `BroadcastReceiver` in the app process.

Both capture the timestamp as their first statement (reaction timing is the
whole point), append `{lightId, ts}` to a `pending_events` JSON queue in the
shared key-value store (App Group `UserDefaults` / `HomeWidgetPreferences`),
and the Flutter app merges the queue into SQLite on next launch/resume.
`UNIQUE(light_id, ts_ms)` makes merges idempotent. The widget never touches
SQLite directly.

## Prediction math (lib/prediction/cycle_estimator.dart)

Green onsets folded at the true cycle length C cluster at one phase. The
estimator scans candidate frequencies f = 1/C ∈ [1/200 s, 1/30 s], scoring
each with the mean resultant length R(f) = |Σ e^(i·2π·s_j·f)|/n (epoch
folding). Details: uniform-in-frequency grid (Δf = 1/(8·span)), two-stage
refinement + parabolic interpolation, largest-C tie-break against C/2, C/3…
divisors, Rayleigh test with Bonferroni correction for the confidence gate,
σ from circular variance. Mean reaction delay (~0.5 s) biases predictions
slightly late — the safe side. Adaptive/actuated lights never reach the
confidence gate, which is itself signal.

## Dev

```sh
flutter test          # 14 unit tests: repository (sqflite_ffi) + estimator
flutter run           # iOS simulator or Android
flutter build ios --simulator --debug
flutter build apk --debug
```

- Plugins are managed by Swift Package Manager on iOS (no CocoaPods).
- The widget extension target (`ios/GreenlightWidget`) was added
  programmatically; "Embed Foundation Extensions" is ordered before Flutter's
  "Thin Binary" phase on purpose (build-cycle pitfall).
- **Device deploys**: set your Apple team on both the Runner and
  GreenlightWidget targets in Xcode once; the App Group
  `group.com.robberthofman.greenlight` is declared in both entitlements files.
- Debug builds have a **seed** menu item on the light detail screen that
  injects a synthetic 90 s cycle for end-to-end validation, and CSV/JSON
  export lives in the same menu.

## Shared key-value contract

Mirrored in `lib/constants.dart`, `ios/GreenlightWidget/RecordGreenIntent.swift`
and `android/.../RecordGreenReceiver.kt` — change all three together:

| key | type | meaning |
|---|---|---|
| `active_light_id` | String | last selected light (also the app's own memory) |
| `active_light_name` | String | shown on the widget |
| `pending_events` | String | JSON `[{"lightId":"1","ts":1755212345678}]` |
| `today_count` / `count_date` | int / String | widget display, local-midnight rollover |
| `last_recorded_ms` | long | last tap, any source |

Values stay String/Int/Bool/Long — home_widget stores Dart doubles on Android
as raw long bits + a flag key, which native code can't round-trip.
