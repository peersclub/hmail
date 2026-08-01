/// Calendar/meeting extraction.
///
/// Invite emails are the most machine-shaped mail there is — Google Calendar
/// puts the whole event in the subject line ("Invitation: Design sync @ Mon
/// Aug 3, 2026 3pm - 3:30pm (IST)"), and Zoom/Teams invites carry a join link
/// plus a "When:"/"Time:" line. No AI needed to read them.
library;

import '../../domain/models.dart';
import 'extractors.dart' show extractDate;
import 'links.dart';

final _amPmTime = RegExp(
  r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
  caseSensitive: false,
);
// Bare 24h times ("15:00") only count when they look like clock times.
final _time24 = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b');

({int hour, int minute})? _extractTime(String text, {int from = 0}) {
  final slice = text.substring(from.clamp(0, text.length));
  final amPm = _amPmTime.firstMatch(slice);
  if (amPm != null) {
    var hour = int.parse(amPm.group(1)!) % 12;
    if (amPm.group(3)!.toLowerCase() == 'pm') hour += 12;
    return (hour: hour, minute: int.tryParse(amPm.group(2) ?? '') ?? 0);
  }
  final t24 = _time24.firstMatch(slice);
  if (t24 != null) {
    return (hour: int.parse(t24.group(1)!), minute: int.parse(t24.group(2)!));
  }
  return null;
}

/// Date + first clock time in [text]; date-only (midnight) when no time
/// appears, so the event still lands on the right day.
DateTime? extractEventStart(String text, {required DateTime anchor}) {
  final date = extractDate(text, anchor: anchor);
  if (date == null) return null;
  final time = _extractTime(text);
  if (time == null) return date;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// End time from a "3pm - 4pm" style range: the second clock time on the
/// same day as [start], if it comes after it.
DateTime? _extractEventEnd(String text, DateTime start) {
  final first = _amPmTime.firstMatch(text) ?? _time24.firstMatch(text);
  if (first == null) return null;
  final second = _extractTime(text, from: first.end);
  if (second == null) return null;
  final end = DateTime(
      start.year, start.month, start.day, second.hour, second.minute);
  return end.isAfter(start) ? end : null;
}

const _invitePrefixes = [
  'updated invitation:',
  'invitation:',
  'canceled event:',
  'cancelled event:',
  'declined:',
  'accepted:',
  'tentatively accepted:',
  'reminder:',
];

const _inviteBodySignals = [
  'invites you to',
  'has invited you',
  'is inviting you to a scheduled',
  'meeting invitation',
  'scheduled a meeting',
  'when:',
  'joining info',
  'join zoom meeting',
];

bool _looksLikeInvite(EmailMeta email) {
  final subject = email.subject.toLowerCase().trim();
  if (_invitePrefixes.any(subject.startsWith)) return true;
  final hay = email.haystack;
  if (_inviteBodySignals.any(hay.contains)) return true;
  // A bare meeting link only counts alongside join-language — newsletters
  // embed webinar links all the time.
  return extractMeetingLink(email.rawText) != null &&
      (hay.contains('join') || hay.contains('starts at'));
}

bool _isCancelled(EmailMeta email) {
  final subject = email.subject.toLowerCase();
  return subject.contains('canceled event') ||
      subject.contains('cancelled event') ||
      email.haystack.contains('this event has been canceled') ||
      email.haystack.contains('this event has been cancelled') ||
      email.haystack.contains('meeting has been cancelled') ||
      email.haystack.contains('meeting has been canceled');
}

String _cleanTitle(String subject) {
  var title = subject.trim();
  final lower = title.toLowerCase();
  for (final prefix in _invitePrefixes) {
    if (lower.startsWith(prefix)) {
      title = title.substring(prefix.length).trim();
      break;
    }
  }
  // Google puts the schedule after " @ " — that's data, not title.
  final at = title.indexOf(' @ ');
  if (at > 0) title = title.substring(0, at).trim();
  return title.isEmpty ? 'Meeting' : title;
}

String? _organizer(EmailMeta email) {
  // Display name half of `Name <addr>`; fall back to the bare address.
  final match = RegExp(r'^"?([^"<]+?)"?\s*<').firstMatch(email.from);
  final name = match?.group(1)?.trim();
  if (name != null && name.isNotEmpty) return name;
  final addr = RegExp(r'[\w.+-]+@[\w.-]+').firstMatch(email.from)?.group(0);
  return addr;
}

String? _location(EmailMeta email) {
  final match = RegExp(r'where:\s*([^\n]+)', caseSensitive: false)
      .firstMatch(email.body);
  final where = match?.group(1)?.trim();
  if (where == null || where.isEmpty) return null;
  // "Where:" lines for video calls just repeat the join link — skip those.
  return where.startsWith('http') ? null : where;
}

EventItem? extractEvent(EmailMeta email) {
  if (!_looksLikeInvite(email)) return null;

  // Prefer the subject's " @ ..." tail (precise), then a When:/Time: line,
  // then the whole text.
  final atIndex = email.subject.indexOf(' @ ');
  final subjectTail =
      atIndex > 0 ? email.subject.substring(atIndex + 3) : null;
  final whenLine = RegExp(r'(?:when|time|date):\s*([^\n]+)',
          caseSensitive: false)
      .firstMatch(email.body)
      ?.group(1);

  DateTime? start;
  String? scheduleText;
  for (final candidate in [subjectTail, whenLine, email.rawText]) {
    if (candidate == null) continue;
    start = extractEventStart(candidate, anchor: email.date);
    if (start != null) {
      scheduleText = candidate;
      break;
    }
  }
  if (start == null) return null;

  final meeting = extractMeetingLink(email.rawText);

  return EventItem(
    title: _cleanTitle(email.subject),
    organizer: _organizer(email),
    start: start,
    end: _extractEventEnd(scheduleText!, start),
    meetingUrl: meeting?.url,
    provider: meeting?.provider ?? MeetingProvider.other,
    location: _location(email),
    isCancelled: _isCancelled(email),
    lastSeen: email.date,
    sourceEmailId: email.id,
  );
}
