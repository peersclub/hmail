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
        'subject:(receipt OR renewal OR subscription OR "payment successful" OR invoice) newer_than:${history}d',
        'subject:(bill OR due OR statement) newer_than:${_clamp(history, 60)}d',
      ],
      if (settings.scanDeliveries)
        'subject:(shipped OR delivery OR delivered OR dispatched OR "out for delivery" OR "order confirmed") newer_than:${_clamp(history, 30)}d',
      // Braces are Gmail's OR group.
      if (settings.scanEvents)
        '{subject:invitation subject:"updated invitation" subject:"canceled event" subject:meeting filename:ics} newer_than:${_clamp(history, 14)}d',
      if (settings.scanReads)
        '{from:substack.com from:youtube.com from:medium.com from:theken.com subject:newsletter subject:"new post" subject:"new episode" subject:uploaded} newer_than:${_clamp(history, 21)}d',
    ];
  }

  static int _clamp(int history, int cap) => history < cap ? history : cap;

  /// Fetches candidate emails across all insight queries, deduped by id.
  @override
  Future<List<EmailMeta>> fetchCandidates({int? maxPerQuery}) async {
    final seen = <String>{};
    final results = <EmailMeta>[];
    final perQuery = maxPerQuery ?? settings.maxEmailsPerQuery;

    for (final query in queriesFor(settings)) {
      final list = await api.users.messages.list(
        'me',
        q: query,
        maxResults: perQuery,
      );
      for (final ref in list.messages ?? const <Message>[]) {
        final id = ref.id;
        if (id == null || !seen.add(id)) continue;
        final message = await api.users.messages.get('me', id, format: 'full');
        final meta = _toMeta(message);
        if (meta != null) results.add(meta);
      }
    }
    return results;
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
