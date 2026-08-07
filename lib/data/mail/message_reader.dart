/// On-demand fetch of one message's full body, for the in-app reader.
///
/// WHY THIS IS SEPARATE FROM THE SYNC PATH
/// A scan reads hundreds of messages and keeps a 4000-character text
/// projection of each ([EmailMeta.body]) — enough for extraction, useless for
/// reading. The store is `shared_preferences`, so keeping real bodies there
/// was never an option. The reader therefore refetches exactly the one message
/// the user tapped, which costs a single API call at tap time and keeps the
/// snapshot as small as it is today.
///
/// WHY THE READER EXISTS AT ALL
/// On iOS there is no way to hand a message to the Gmail app reliably:
/// `mail.google.com` publishes no `apple-app-site-association` naming Gmail,
/// so the https URL only ever reaches Safari — where the user is often signed
/// out, because a fresh browser session is not the app's session. Rendering
/// the body ourselves is the only path that always works, and it works offline
/// once fetched.
///
/// WHY IT IS SAFE TO RENDER
/// The screen builds the document with a restrictive Content-Security-Policy
/// and loads it via `loadHtmlString`, so there is no navigation and no origin
/// — the WebView's cookie jar is never involved, and nothing in the message
/// can reach the network unless the user asks for images.
library;

/// A message body, ready to be composed into a document by the UI.
class MessageBody {
  final String from;
  final String subject;
  final DateTime date;

  /// The conversation this message belongs to.
  ///
  /// Worth carrying because Gmail's web URL addresses a *conversation*: the
  /// fragment after `#all/` is a thread id, and passing a message id only
  /// works when the thread holds one message. Most transactional mail does,
  /// which is exactly why the difference stayed invisible. A refetch is the
  /// one place this is known for free, so the reader's "open on the web"
  /// button is the one link in the app that can be right on a reply chain.
  final String threadId;

  /// Which mailbox this came out of, when the caller knew.
  ///
  /// The `a<N>:` prefix on an insight is a position in NoMail's OAuth list,
  /// and Gmail's own `/u/<N>/` slot is the browser's sign-in order — unrelated
  /// orderings, so with several accounts connected a positional link opens
  /// somebody else's inbox. The address is the only identifier both sides
  /// agree on, and a refetch is where it is known.
  final String accountEmail;

  /// The message's own `text/html`, or its `text/plain` escaped and wrapped —
  /// either way, a fragment to place inside a document, never a whole one.
  final String html;

  /// False when the source was plain text. The reader uses it to pick
  /// typography, since a plain-text body carries its own line breaks.
  final bool isRichText;

  const MessageBody({
    required this.from,
    required this.subject,
    required this.date,
    required this.html,
    required this.isRichText,
    this.threadId = '',
    this.accountEmail = '',
  });
}

/// Fetches [sourceEmailId] — the id as insights carry it, `a<N>:` prefix and
/// all. Returns null when the message is gone or the account can't be reached.
typedef MessageBodyFetcher = Future<MessageBody?> Function(String sourceEmailId);

/// Where the reader finds its backend.
///
/// The same shape as [installedApps] and [hostRouting]: a library-level
/// singleton the state layer binds once, so a leaf screen doesn't need a
/// controller threaded through every call site that might open it.
class MessageReader {
  MessageBodyFetcher? _fetcher;

  /// Most-recently-read bodies. Re-opening the same email is the common case —
  /// read it, act on it, come back — and a second network round trip for a
  /// body we already have is a second chance to fail.
  final _cache = <String, MessageBody>{};

  /// Small on purpose: this holds whole email bodies, and the point of the
  /// refetch design was to keep them out of long-lived storage.
  static const _cacheSize = 12;

  /// Binds the backend. Null unbinds — sign-out must not leave a closure
  /// holding a signed-in API client.
  void bind(MessageBodyFetcher? fetcher) {
    _fetcher = fetcher;
    _cache.clear();
  }

  /// True when a body can be fetched at all. False before sign-in, and the
  /// reason the reader is not offered rather than offered and broken.
  bool get isAvailable => _fetcher != null;

  Future<MessageBody?> fetch(String sourceEmailId) async {
    final cached = _cache[sourceEmailId];
    if (cached != null) return cached;

    final fetcher = _fetcher;
    if (fetcher == null) return null;

    final body = await fetcher(sourceEmailId);
    if (body == null) return null;

    if (_cache.length >= _cacheSize) _cache.remove(_cache.keys.first);
    _cache[sourceEmailId] = body;
    return body;
  }

  /// Test seam — drops everything held.
  void clear() => _cache.clear();
}

final MessageReader messageReader = MessageReader();

/// Escapes text for placement inside an HTML document.
///
/// Ampersand first: any other order re-escapes the escapes and the user sees
/// `&amp;lt;` where the message said `<`.
String escapeHtml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
