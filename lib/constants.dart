/// Identifiers shared with the native widget code on both platforms.
/// The Swift AppIntent and Kotlin BroadcastReceiver hardcode the same values —
/// keep them in sync when changing anything here.
const appGroupId = 'group.com.robberthofman.greenlight';
const iosWidgetName = 'GreenlightWidget';
const androidWidgetName = 'GreenlightWidgetProvider';

/// Keys in the shared key-value store (App Group UserDefaults on iOS,
/// HomeWidgetPreferences SharedPreferences file on Android).
/// Values must stay String/int/bool: home_widget encodes Dart doubles on
/// Android as raw long bits plus a companion flag key, which native code
/// cannot round-trip safely.
const kActiveLightId = 'active_light_id';
const kActiveLightName = 'active_light_name';
const kPendingEvents = 'pending_events';
const kTodayCount = 'today_count';
const kCountDate = 'count_date';
const kLastRecordedMs = 'last_recorded_ms';

const kRecordRoute = '/record';
