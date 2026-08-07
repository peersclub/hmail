import 'package:googleapis/gmail/v1.dart';

import '../../domain/models.dart';
import '../../domain/scan_settings.dart';
import 'gmail_source.dart';
import 'mail_source.dart';
import 'message_reader.dart';

/// A [MailSource] that fans a [GmailSource] out across every connected Gmail
/// account and merges the results into one candidate list, so downstream
/// extraction sees the user's whole life across inboxes.
///
/// Gmail message ids are only unique *within* one account, so a naive
/// concatenation could collide (and later dedupe away real emails from a second
/// account that happens to share an id). Every candidate's id is therefore
/// prefixed with the account's index — `a0:<id>`, `a1:<id>`, … — keeping ids
/// globally unique and stable across syncs while dedupe still works within an
/// account.
///
/// One account failing (expired token, quota, network) must not sink the whole
/// sync: a throwing api is skipped and the rest still contribute.
class MultiGmailSource implements MailSource {
  final List<GmailApi> apis;
  final ScanSettings settings;

  /// Email addresses aligned with [apis] by index, used to label failures.
  /// Optional so single-account and test call sites stay unchanged.
  final List<String> accountEmails;

  /// Accounts that failed during the most recent [fetchCandidates] run, with
  /// a short human reason. A failing inbox is skipped so the sync survives —
  /// but skipped silently is how an account's insights quietly go stale, so
  /// the controller surfaces these on the account rows after every sync.
  final List<({String account, String message})> lastFailures = [];

  MultiGmailSource(
    this.apis, {
    this.settings = const ScanSettings(),
    this.accountEmails = const [],
  });

  String _label(int index) => index < accountEmails.length
      ? accountEmails[index]
      : 'Account ${index + 1}';

  @override
  Future<List<EmailMeta>> fetchCandidates({
    void Function(String detail)? onProgress,
  }) async {
    final merged = <EmailMeta>[];
    final seen = <String>{};
    lastFailures.clear();

    for (var index = 0; index < apis.length; index++) {
      final prefix = 'a$index:';
      // With several inboxes, say which one — otherwise the progress line
      // appears to restart for no reason.
      final scope = apis.length > 1 ? ' (account ${index + 1})' : '';
      try {
        final candidates = await GmailSource(apis[index], settings: settings)
            .fetchCandidates(
          onProgress: onProgress == null
              ? null
              : (detail) => onProgress('$detail$scope'),
        );
        for (final email in candidates) {
          final id = '$prefix${email.id}';
          if (!seen.add(id)) continue;
          merged.add(
            EmailMeta(
              id: id,
              from: email.from,
              subject: email.subject,
              snippet: email.snippet,
              body: email.body,
              date: email.date,
            ),
          );
        }
      } catch (e) {
        // Skip this account — a single bad inbox must not fail the sync —
        // but remember who failed and why, so the UI can say so.
        lastFailures.add((
          account: _label(index),
          message: e is DetailedApiRequestError && e.status == 401
              ? 'Session expired — remove and reconnect this account'
              : 'Couldn\'t read this inbox on the last sync',
        ));
        continue;
      }
    }
    return merged;
  }

  /// `a<N>:<gmailId>` — the prefix [fetchCandidates] stamps on, read back.
  static final _prefixed = RegExp(r'^a(\d+):(.+)$');

  /// The full body of one message, routed to the account it came from.
  ///
  /// The prefix is not decoration: Gmail message ids are unique only within an
  /// account, so asking the wrong inbox for one either 404s or — worse, if the
  /// id happens to exist there too — returns a different person's email.
  /// Anything that doesn't carry a prefix is assumed to be account 0, which is
  /// what single-account ids look like.
  Future<MessageBody?> fetchMessageBody(String sourceEmailId) async {
    var index = 0;
    var id = sourceEmailId;
    final match = _prefixed.firstMatch(sourceEmailId);
    if (match != null) {
      index = int.parse(match.group(1)!);
      id = match.group(2)!;
    }
    // An account removed since the last sync leaves its insights behind, so
    // the index can outlive the api it named. No lower bound is needed: the
    // pattern's `\d+` cannot match a sign, so anything shaped like `a-1:` is
    // simply not a prefix and was already treated as account 0 above.
    if (index >= apis.length) return null;

    final body =
        await GmailSource(apis[index], settings: settings).fetchMessageBody(id);
    if (body == null) return null;

    // Stamp the address here, where the index still means something. Past this
    // point only the body travels, and a link built from a position would open
    // whichever mailbox Gmail happens to have in that slot.
    return index < accountEmails.length
        ? MessageBody(
            from: body.from,
            subject: body.subject,
            date: body.date,
            html: body.html,
            isRichText: body.isRichText,
            threadId: body.threadId,
            accountEmail: accountEmails[index],
          )
        : body;
  }
}
