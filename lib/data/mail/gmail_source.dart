import 'dart:convert';

import 'package:googleapis/gmail/v1.dart';

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

  GmailSource(this.api, {this.settings = const ScanSettings()});

  /// Queries for the domains the user left switched on. Bills and deliveries
  /// keep tight windows regardless of [ScanSettings.historyDays] — a bill
  /// from last year is history, not a task — while receipts honour it so
  /// annual renewals surface.
  static List<String> queriesFor(ScanSettings settings) {
    final history = settings.historyDays;
    return [
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
  Future<List<EmailMeta>> fetchCandidates({int? maxPerQuery}) async {
    final seen = <String>{};
    final results = <EmailMeta>[];
    final perQuery = maxPerQuery ?? settings.maxEmailsPerQuery;
    failures = 0;

    for (final query in queriesFor(settings)) {
      final List<Message> refs;
      try {
        final list = await api.users.messages.list(
          'me',
          q: query,
          maxResults: perQuery,
        );
        refs = list.messages ?? const <Message>[];
      } catch (_) {
        failures++;
        continue;
      }

      for (final ref in refs) {
        final id = ref.id;
        if (id == null || !seen.add(id)) continue;
        try {
          final message =
              await api.users.messages.get('me', id, format: 'full');
          final meta = _toMeta(message);
          if (meta != null) results.add(meta);
        } catch (_) {
          failures++;
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
