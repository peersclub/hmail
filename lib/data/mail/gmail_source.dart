import 'dart:convert';

import 'package:googleapis/gmail/v1.dart';
import 'package:http/http.dart' as http;

import '../../domain/models.dart';
import '../../domain/scan_settings.dart';
import 'mail_source.dart';

/// Gmail-as-a-backend: targeted queries, not inbox paging.
///
/// Instead of pulling the newest N messages and hoping, each insight domain
/// has its own Gmail search — the same queries a power user would type.
class GmailSource implements MailSource {
  final GmailApi api;
  final ScanSettings settings;

  /// Overrides [ScanSettings.maxEmailsPerQuery] as the per-query ceiling when
  /// set, so callers can raise the cap without a settings change. Null keeps
  /// today's default (25).
  final int? _perQueryCap;

  /// Delay before retry N (1-based) of a throttled request. Injectable so
  /// tests can observe the schedule; defaults to 1s / 2s / 4s.
  final Duration Function(int retry) _retryDelay;

  /// How to actually wait. Tests inject a zero-delay recorder.
  final Future<void> Function(Duration delay) _sleep;

  /// Where the last Retry-After header lives, when the caller routed the api
  /// through a [RetryAfterClient]. Null means backoff is purely exponential —
  /// [GmailApi] swallows response headers before throwing, so this is the
  /// only way to see the server's own pacing.
  final RetryAfterClient? _retryAfterSource;

  GmailSource(
    this.api, {
    this.settings = const ScanSettings(),
    int? perQueryCap,
    Duration Function(int retry)? retryDelay,
    Future<void> Function(Duration delay)? sleep,
    RetryAfterClient? retryAfterSource,
  })  : _perQueryCap = perQueryCap,
        _retryDelay = retryDelay ?? _defaultRetryDelay,
        _sleep = sleep ?? _defaultSleep,
        _retryAfterSource = retryAfterSource;

  static Duration _defaultRetryDelay(int retry) =>
      Duration(seconds: 1 << (retry - 1));

  static Future<void> _defaultSleep(Duration delay) =>
      Future<void>.delayed(delay);

  /// Queries for the domains the user left switched on. Bills and deliveries
  /// keep tight windows regardless of [ScanSettings.historyDays] — a bill
  /// from last year is history, not a task — while receipts honour it so
  /// annual renewals surface.
  static List<String> queriesFor(ScanSettings settings) =>
      [for (final planned in plannedQueries(settings)) planned.query];

  /// The same queries, each with the name the user sees while it runs.
  static List<({String label, String query})> plannedQueries(
      ScanSettings settings) {
    final history = settings.historyDays;
    final queries = <String>[
      if (settings.scanMoney) ...[
        'subject:(receipt OR renewal OR subscription OR "payment successful" OR invoice OR refund OR "payment failed" OR declined) newer_than:${history}d',
        'subject:(bill OR due OR statement) newer_than:${_clamp(history, 60)}d',
      ],
      if (settings.scanDeliveries)
        'subject:(shipped OR delivery OR delivered OR dispatched OR "out for delivery" OR "order confirmed" OR return OR warranty) newer_than:${_clamp(history, 30)}d',
      // Braces are Gmail's OR group.
      if (settings.scanEvents)
        '{subject:invitation subject:"updated invitation" subject:"canceled event" subject:meeting filename:ics} newer_than:${_clamp(history, 14)}d',
      if (settings.scanReads)
        '{from:substack.com from:youtube.com from:medium.com from:theken.com subject:newsletter subject:"new post" subject:"new episode" subject:uploaded} newer_than:${_clamp(history, 21)}d',
      if (settings.scanTravel)
        '{from:makemytrip.com from:goindigo.in from:cleartrip.com from:irctc.co.in subject:pnr subject:"e-ticket" subject:itinerary subject:"booking confirmed" subject:"boarding pass"} newer_than:${_clamp(history, 120)}d',
    ];

    // Labels track the same conditions, in the same order, as the queries.
    final labels = <String>[
      if (settings.scanMoney) ...['receipts', 'bills'],
      if (settings.scanDeliveries) 'packages',
      if (settings.scanEvents) 'meetings',
      if (settings.scanReads) 'reads',
      if (settings.scanTravel) 'travel',
    ];

    return [
      for (var i = 0; i < queries.length; i++)
        (label: labels[i], query: queries[i]),
    ];
  }

  static int _clamp(int history, int cap) => history < cap ? history : cap;

  /// Fetches candidate emails across all insight queries, deduped by id.
  ///
  /// A scan is one request per query plus one per message — hundreds of calls
  /// over a phone's network. Individual failures are expected at that volume,
  /// so neither a dead query nor a dead message aborts the run: a scan that
  /// returns most of the mail is worth far more than one that returns an
  /// error. [failures] counts what was lost.
  @override
  Future<List<EmailMeta>> fetchCandidates({
    int? maxPerQuery,
    void Function(String detail)? onProgress,
  }) async {
    final seen = <String>{};
    final results = <EmailMeta>[];
    final perQuery = maxPerQuery ?? _perQueryCap ?? settings.maxEmailsPerQuery;
    failures = 0;

    final planned = plannedQueries(settings);
    for (var q = 0; q < planned.length; q++) {
      final label = planned[q].label;
      onProgress?.call('Searching $label (${q + 1} of ${planned.length})');

      final List<Message> refs;
      try {
        refs = await _listPages(planned[q].query, perQuery);
      } catch (_) {
        failures++;
        onProgress?.call('Search for $label failed — carrying on');
        continue;
      }

      var read = 0;
      for (final ref in refs) {
        final id = ref.id;
        if (id == null || !seen.add(id)) continue;
        try {
          final message = await _withRetry(
              () => api.users.messages.get('me', id, format: 'full'));
          final meta = _toMeta(message);
          if (meta != null) results.add(meta);
        } catch (_) {
          failures++;
        }
        read++;
        // Every message would be a rebuild per request; every fifth keeps
        // the number moving without thrashing the UI.
        if (read % 5 == 0 || read == refs.length) {
          onProgress?.call('Reading $label · $read of ${refs.length}');
        }
      }
    }

    // Everything failed: that's not a partial result, it's a broken sync.
    if (results.isEmpty && failures > 0) {
      throw StateError(
          'Gmail unreachable — $failures request${failures == 1 ? '' : 's'} failed');
    }
    return results;
  }

  /// Requests dropped during the last [fetchCandidates].
  int failures = 0;

  /// Lists message refs for [query], following `nextPageToken` until [cap]
  /// refs are in hand or Gmail runs out of pages.
  ///
  /// The first page is the same request the pre-pagination code sent
  /// (`maxResults: cap`, no page token), so default traffic is unchanged —
  /// extra pages only happen when Gmail returns short pages with more to
  /// give. A page that dies after retries ends the walk: with nothing in
  /// hand that rethrows (the query is dead), with earlier pages banked it
  /// returns the partial haul, because a short list beats no list.
  Future<List<Message>> _listPages(String query, int cap) async {
    final refs = <Message>[];
    String? pageToken;
    while (true) {
      final ListMessagesResponse list;
      try {
        list = await _withRetry(() => api.users.messages.list(
              'me',
              q: query,
              maxResults: cap - refs.length,
              pageToken: pageToken,
            ));
      } catch (_) {
        if (refs.isEmpty) rethrow;
        failures++;
        return refs;
      }
      refs.addAll(list.messages ?? const <Message>[]);
      pageToken = list.nextPageToken;
      if (pageToken == null || refs.length >= cap) {
        return refs.length > cap ? refs.sublist(0, cap) : refs;
      }
    }
  }

  /// Retries after the initial attempt — 3 means at most 4 tries total.
  static const _maxRetries = 3;

  /// Runs [send], retrying quota and server hiccups so a moment of
  /// throttling doesn't kill the account's whole scan.
  ///
  /// Only Gmail's own transient verdicts are retried — 429, 403 rate limits,
  /// 5xx. Network-level exceptions (socket death, bad descriptors) still
  /// fail immediately: when the phone is offline, sleeping between retries
  /// would turn a fast failure into a hung scan. The wait honours the
  /// server's Retry-After when a [RetryAfterClient] captured one, else falls
  /// back to the exponential schedule.
  Future<T> _withRetry<T>(Future<T> Function() send) async {
    for (var retry = 0; ; retry++) {
      try {
        return await send();
      } on DetailedApiRequestError catch (error) {
        if (retry >= _maxRetries || !_isTransient(error)) rethrow;
        await _sleep(
            _retryAfterSource?.lastRetryAfter ?? _retryDelay(retry + 1));
      }
    }
  }

  /// Worth retrying: quota (429, or 403 with a rate-limit reason) and
  /// server-side errors (5xx). A plain 403 is a permissions problem and a
  /// retry would just burn quota on the same answer.
  static bool _isTransient(DetailedApiRequestError error) {
    final status = error.status;
    if (status == null) return false;
    if (status == 429 || status >= 500) return true;
    if (status != 403) return false;
    const throttled = {'rateLimitExceeded', 'userRateLimitExceeded'};
    return error.errors.any((detail) => throttled.contains(detail.reason)) ||
        throttled.any((reason) => error.message?.contains(reason) ?? false);
  }

  EmailMeta? _toMeta(Message message) {
    final id = message.id;
    if (id == null) return null;

    String from = '', subject = '';
    for (final header in message.payload?.headers ?? const <MessagePartHeader>[]) {
      switch (header.name?.toLowerCase()) {
        case 'from':
          from = header.value ?? '';
        case 'subject':
          subject = header.value ?? '';
      }
    }

    final internalMs = int.tryParse(message.internalDate ?? '');
    final date = internalMs != null
        ? DateTime.fromMillisecondsSinceEpoch(internalMs)
        : DateTime.now();

    return EmailMeta(
      id: id,
      from: from,
      subject: subject,
      snippet: message.snippet ?? '',
      body: _extractBody(message.payload),
      date: date,
    );
  }

  String _extractBody(MessagePart? payload) {
    if (payload == null) return '';
    // Prefer text/plain; fall back to first decodable part; cap length so
    // giant HTML bodies don't bloat extraction or AI prompts.
    final plain = _findPart(payload, 'text/plain') ?? payload;
    final data = plain.body?.data;
    if (data == null) return '';
    try {
      final decoded = utf8.decode(
        base64Url.decode(base64Url.normalize(data)),
        allowMalformed: true,
      );
      return decoded.length > 4000 ? decoded.substring(0, 4000) : decoded;
    } catch (_) {
      return '';
    }
  }

  MessagePart? _findPart(MessagePart part, String mimeType) {
    if (part.mimeType == mimeType && part.body?.data != null) return part;
    for (final child in part.parts ?? const <MessagePart>[]) {
      final found = _findPart(child, mimeType);
      if (found != null) return found;
    }
    return null;
  }
}

/// An http client that remembers the Retry-After header of the last response.
///
/// [GmailApi] discards response headers before throwing, so backoff code
/// downstream can never see how long the server asked us to wait. Wrap the
/// authenticated client in one of these, hand it to both [GmailApi] and
/// [GmailSource] (`retryAfterSource:`), and throttled retries pace themselves
/// to the server instead of guessing. Without it, [GmailSource] simply falls
/// back to exponential backoff.
class RetryAfterClient extends http.BaseClient {
  final http.Client _inner;

  /// Retry-After from the most recent response; null when the response had
  /// none — every send overwrites it, so a stale header never outlives the
  /// response it arrived on.
  Duration? lastRetryAfter;

  RetryAfterClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    lastRetryAfter = _parseRetryAfter(
        response.headers['retry-after'] ?? response.headers['Retry-After']);
    return response;
  }

  @override
  void close() => _inner.close();

  /// Delta-seconds only (Gmail's form); the HTTP-date form falls back to
  /// exponential backoff. Clamped to 30s so a hostile or broken header can't
  /// hang a scan.
  static Duration? _parseRetryAfter(String? header) {
    if (header == null) return null;
    final seconds = int.tryParse(header.trim());
    if (seconds == null || seconds < 0) return null;
    return Duration(seconds: seconds > 30 ? 30 : seconds);
  }
}
