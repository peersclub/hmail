import 'package:googleapis/gmail/v1.dart';

import '../../domain/models.dart';
import '../../domain/scan_settings.dart';
import 'gmail_source.dart';
import 'mail_source.dart';

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

  MultiGmailSource(this.apis, {this.settings = const ScanSettings()});

  @override
  Future<List<EmailMeta>> fetchCandidates() async {
    final merged = <EmailMeta>[];
    final seen = <String>{};

    for (var index = 0; index < apis.length; index++) {
      final prefix = 'a$index:';
      try {
        final candidates =
            await GmailSource(apis[index], settings: settings).fetchCandidates();
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
      } catch (_) {
        // Skip this account; a single bad inbox must not fail the sync.
        continue;
      }
    }
    return merged;
  }
}
