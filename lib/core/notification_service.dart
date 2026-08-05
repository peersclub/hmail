/// Local notifications — the 8am brief and actionable insight pushes.
///
/// The daily brief notification is the habit loop: one push every morning
/// with the same content the Today screen shows, so opening NoMail is the
/// natural next tap. Insight notifications carry action buttons that mirror
/// the in-app [ActionKind] vocabulary (Pay/Remind on bills, Track on
/// deliveries, Join on events).
///
/// Routing contract: every tap reaches the `onTap` callback passed to
/// [NotificationService.init] as a single opaque string.
///  * Body tap        → the `payload` given when the notification was shown.
///  * Action button   → `'action:<actionId>|<payload>'`, where `<actionId>`
///    is one of 'pay', 'remind', 'track', 'join'.
/// The UI layer owns decoding; this service never interprets payloads.
///
/// Everything degrades gracefully: if permission is denied (or the platform
/// has no notification support), every method quietly no-ops — the brief
/// still exists in-app.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/models.dart';
import 'upcoming_alerts.dart';

/// Stable id for the daily brief so re-scheduling after each sync replaces
/// the pending notification instead of stacking a new one per sync.
const _briefNotificationId = 1001;

/// iOS categories exposing action buttons. Every action uses the
/// `foreground` option: the tap opens the app, so routing stays in the
/// normal response callback (no background isolate needed).
final _darwinCategories = <DarwinNotificationCategory>[
  DarwinNotificationCategory(
    'bill',
    actions: [
      DarwinNotificationAction.plain(
        'pay',
        'Pay',
        options: {DarwinNotificationActionOption.foreground},
      ),
      DarwinNotificationAction.plain(
        'remind',
        'Remind',
        options: {DarwinNotificationActionOption.foreground},
      ),
    ],
  ),
  DarwinNotificationCategory(
    'delivery',
    actions: [
      DarwinNotificationAction.plain(
        'track',
        'Track',
        options: {DarwinNotificationActionOption.foreground},
      ),
    ],
  ),
  DarwinNotificationCategory(
    'event',
    actions: [
      DarwinNotificationAction.plain(
        'join',
        'Join',
        options: {DarwinNotificationActionOption.foreground},
      ),
    ],
  ),
];

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin;

  /// False until [init] succeeds AND permission is granted; while false
  /// every public method is a silent no-op.
  bool _enabled = false;

  void Function(String payload)? _onTap;

  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Initializes the plugin, requests permission and sets the local
  /// timezone. Returns whether notifications are usable; callers may ignore
  /// the result because later methods no-op when they aren't.
  ///
  /// [onTap] receives every notification response — see the library doc for
  /// the payload/action encoding.
  Future<bool> init({void Function(String payload)? onTap}) async {
    _onTap = onTap;
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        // Unknown/unmapped zone: tz falls back to UTC, which only shifts the
        // brief's hour — scheduling still works.
      }

      final initialized = await _plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            // Requested explicitly below so init order can't double-prompt.
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
            notificationCategories: _darwinCategories,
          ),
        ),
        onDidReceiveNotificationResponse: _handleResponse,
      );
      if (initialized != true) return false;

      _enabled = await _requestPermission();
    } catch (_) {
      _enabled = false;
    }
    return _enabled;
  }

  Future<bool> _requestPermission() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      // Pre-Android 13 has no runtime prompt; the plugin returns true there.
      return await android.requestNotificationsPermission() ?? false;
    }
    return false;
  }

  void _handleResponse(NotificationResponse response) {
    final payload = response.payload ?? '';
    final actionId = response.actionId;
    _onTap?.call(
      (actionId == null || actionId.isEmpty)
          ? payload
          : 'action:$actionId|$payload',
    );
  }

  /// Schedules (or replaces) the repeating daily brief at [hour] local time.
  /// Call after every sync so tomorrow's push carries today's content.
  Future<void> scheduleDailyBrief(DailyBrief brief, {int hour = 8}) async {
    if (!_enabled) return;
    final body = brief.bullets.join('\n');
    try {
      // zonedSchedule with the same id already replaces, but cancelling
      // first also clears a stale pending brief if details ever change shape.
      await _plugin.cancel(id: _briefNotificationId);
      await _plugin.zonedSchedule(
        id: _briefNotificationId,
        title: brief.headline,
        body: body,
        scheduledDate: _nextInstanceOf(hour),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_brief',
            'Daily brief',
            channelDescription: 'Your 8am morning brief',
            styleInformation: BigTextStyleInformation(body),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        // Inexact: the brief doesn't need alarm precision, and exact alarms
        // require an extra Android permission users must grant in settings.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'brief',
      );
    } catch (_) {
      // Scheduling is best-effort; the brief still renders in-app.
    }
  }

  tz.TZDateTime _nextInstanceOf(int hour) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Shows an insight notification immediately. [payload] is opaque to this
  /// service and comes back verbatim through `onTap` (or wrapped in the
  /// action encoding when a button is tapped). [category] selects the iOS
  /// action buttons: 'bill', 'delivery' or 'event'; null means tap-only.
  Future<void> showInsightNotification({
    required String title,
    required String body,
    required String payload,
    String? category,
  }) async {
    if (!_enabled) return;
    try {
      await _plugin.show(
        // Same insight re-notified updates in place; distinct insights stack.
        id: payload.hashCode & 0x7fffffff,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: const AndroidNotificationDetails(
            'insights',
            'Insights',
            channelDescription: 'Actionable insights from your email',
          ),
          iOS: DarwinNotificationDetails(categoryIdentifier: category),
        ),
        payload: payload,
      );
    } catch (_) {
      // Best-effort, same rationale as scheduleDailyBrief.
    }
  }

  /// Replaces every scheduled upcoming alert with [alerts] (built by
  /// `buildUpcomingAlerts`). Cancels only pending notifications inside the
  /// [upcomingAlertIdFloor]..[upcomingAlertIdCeiling] namespace — the daily
  /// brief and already-shown insight notifications are untouched — so no
  /// extra bookkeeping store is needed.
  ///
  /// Each alert's [UpcomingAlert.fireAt] is a local wall-clock target from
  /// the pure builder; a target that has already passed (e.g. a renewal only
  /// 1.5 days out, whose "two days before at 9am" moment is behind us) is
  /// bumped to fire five minutes from now instead of being dropped.
  ///
  /// Best-effort like [scheduleDailyBrief]: never throws, and everything
  /// still renders in-app if scheduling fails.
  Future<void> syncUpcomingAlerts(List<UpcomingAlert> alerts) async {
    if (!_enabled) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final request in pending) {
        if (request.id >= upcomingAlertIdFloor &&
            request.id <= upcomingAlertIdCeiling) {
          await _plugin.cancel(id: request.id);
        }
      }

      final now = tz.TZDateTime.now(tz.local);
      for (final alert in alerts) {
        var fireAt = tz.TZDateTime(
          tz.local,
          alert.fireAt.year,
          alert.fireAt.month,
          alert.fireAt.day,
          alert.fireAt.hour,
          alert.fireAt.minute,
        );
        if (!fireAt.isAfter(now)) {
          fireAt = now.add(const Duration(minutes: 5));
        }
        await _plugin.zonedSchedule(
          id: alert.id,
          title: alert.title,
          body: alert.body,
          scheduledDate: fireAt,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              'upcoming_alerts',
              'Upcoming alerts',
              channelDescription:
                  'Renewals, bills and return windows about to hit',
              styleInformation: BigTextStyleInformation(alert.body),
            ),
            iOS: const DarwinNotificationDetails(),
          ),
          // One-shot (no matchDateTimeComponents): each alert is about a
          // specific date, and the next sync rebuilds the whole set anyway.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: alert.payload,
        );
      }
    } catch (_) {
      // Best-effort, same rationale as scheduleDailyBrief.
    }
  }

  Future<void> cancelAll() async {
    if (!_enabled) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
