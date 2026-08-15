import SwiftUI
import WidgetKit

struct GreenlightEntry: TimelineEntry {
  let date: Date
  let lightName: String?
  let todayCount: Int
}

struct GreenlightProvider: TimelineProvider {
  func placeholder(in context: Context) -> GreenlightEntry {
    GreenlightEntry(date: Date(), lightName: "Crossing at bakery", todayCount: 3)
  }

  func getSnapshot(in context: Context,
                   completion: @escaping (GreenlightEntry) -> Void) {
    completion(load())
  }

  func getTimeline(in context: Context,
                   completion: @escaping (Timeline<GreenlightEntry>) -> Void) {
    let now = load()
    // A second entry at next local midnight resets the displayed day count.
    let midnight = Calendar.current
      .startOfDay(for: Date()).addingTimeInterval(86400)
    let reset = GreenlightEntry(date: midnight, lightName: now.lightName,
                                todayCount: 0)
    completion(Timeline(entries: [now, reset], policy: .atEnd))
  }

  private func load() -> GreenlightEntry {
    let prefs = UserDefaults(suiteName: GreenlightShared.suiteName)
    let name = prefs?.string(forKey: "active_light_name")
    var count = 0
    if prefs?.string(forKey: "count_date") == GreenlightShared.ymd(Date()) {
      count = prefs?.integer(forKey: "today_count") ?? 0
    }
    return GreenlightEntry(date: Date(), lightName: name, todayCount: count)
  }
}

private let panelColor = Color(red: 0.12, green: 0.16, blue: 0.14)
private let greenColor = Color(red: 0.0, green: 0.65, blue: 0.32)

struct GreenlightWidgetView: View {
  var entry: GreenlightEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(entry.lightName ?? "Greenlight")
        .font(.headline)
        .foregroundColor(.white)
        .lineLimit(1)
      Text(entry.lightName == nil
           ? "Open the app and pick a light"
           : "\(entry.todayCount) green\(entry.todayCount == 1 ? "" : "s") today")
        .font(.caption)
        .foregroundColor(.white.opacity(0.7))
      Spacer(minLength: 4)
      recordArea
    }
  }

  @ViewBuilder private var recordArea: some View {
    if #available(iOSApplicationExtension 17.0, *) {
      Button(intent: RecordGreenIntent()) { buttonLabel }
        .buttonStyle(.plain)
    } else {
      // Pre-17 widgets cannot run code in place; tapping opens the app on the
      // record screen. The homeWidget query item is home_widget's marker.
      buttonLabel
        .widgetURL(URL(string: "greenlight://record?homeWidget"))
    }
  }

  private var buttonLabel: some View {
    Text("GREEN NOW")
      .font(.system(size: 16, weight: .heavy))
      .foregroundColor(.white)
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(RoundedRectangle(cornerRadius: 12).fill(greenColor))
  }
}

struct GreenlightWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "GreenlightWidget",
                        provider: GreenlightProvider()) { entry in
      if #available(iOSApplicationExtension 17.0, *) {
        GreenlightWidgetView(entry: entry)
          .containerBackground(for: .widget) { panelColor }
      } else {
        ZStack {
          panelColor
          GreenlightWidgetView(entry: entry).padding(12)
        }
      }
    }
    .configurationDisplayName("Greenlight")
    .description("One tap records the moment your light turns green.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
