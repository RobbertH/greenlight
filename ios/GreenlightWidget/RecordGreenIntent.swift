import AppIntents
import Foundation

/// Runs in the widget-extension process when the widget button is tapped on
/// iOS 17+ — no app launch, no Flutter engine. Appends the tap to the
/// pending-events queue the Flutter app merges into SQLite on next open.
/// Keys and JSON shape mirror lib/constants.dart and the Android receiver.
@available(iOSApplicationExtension 16.0, *)
struct RecordGreenIntent: AppIntent {
  static var title: LocalizedStringResource = "Record green light"
  static var description =
    IntentDescription("Records the moment your traffic light turns green.")

  func perform() async throws -> some IntentResult {
    // Capture the timestamp before anything else runs.
    let tsMs = Int(Date().timeIntervalSince1970 * 1000)

    guard let prefs = UserDefaults(suiteName: GreenlightShared.suiteName),
          let lightId = prefs.string(forKey: "active_light_id")
    else { return .result() }

    var events: [[String: Any]] = []
    if let raw = prefs.string(forKey: "pending_events"),
       let data = raw.data(using: .utf8),
       let parsed = try? JSONSerialization.jsonObject(with: data)
         as? [[String: Any]] {
      events = parsed
    }
    events.append(["lightId": lightId, "ts": tsMs])
    if let data = try? JSONSerialization.data(withJSONObject: events),
       let json = String(data: data, encoding: .utf8) {
      prefs.set(json, forKey: "pending_events")
    }

    prefs.set(tsMs, forKey: "last_recorded_ms")
    let today = GreenlightShared.ymd(Date(timeIntervalSince1970: Double(tsMs) / 1000))
    if prefs.string(forKey: "count_date") == today {
      prefs.set(prefs.integer(forKey: "today_count") + 1, forKey: "today_count")
    } else {
      prefs.set(today, forKey: "count_date")
      prefs.set(1, forKey: "today_count")
    }

    // All writes above are synchronous; WidgetKit reloads the timeline as
    // soon as perform() returns, which is the on-widget confirmation.
    return .result()
  }
}

enum GreenlightShared {
  static let suiteName = "group.com.robberthofman.greenlight"

  static func ymd(_ date: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.dateFormat = "yyyy-MM-dd"
    return df.string(from: date)
  }
}
