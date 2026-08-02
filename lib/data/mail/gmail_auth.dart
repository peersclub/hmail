import 'dart:io' show SocketException;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/gmail/v1.dart';
import 'package:http/http.dart' as http;

/// One connected Gmail account: the signed-in Google identity paired with an
/// authorized read-only [GmailApi] client.
class GmailAccount {
  final GoogleSignInAccount account;
  final GmailApi api;

  GmailAccount(this.account, this.api);

  String get email => account.email;
  String? get name => account.displayName ?? account.email;
  String? get photoUrl => account.photoUrl;
}

/// Google sign-in + Gmail authorization (google_sign_in 7.x), extended to hold
/// several connected accounts at once so insights merge across inboxes.
///
/// Read-only scope by design: NoMail never modifies or sends mail.
///
/// google_sign_in 7.x reality: [GoogleSignIn.instance.authenticate] drives the
/// system's single active account. Presenting a *distinct* second account is up
/// to iOS — it may show a picker, or it may silently return the account already
/// active. This class handles the "same account returned" case gracefully (it
/// dedupes by email and never adds a duplicate) and never crashes, but it does
/// not guarantee the OS will offer a fresh account on demand.
class GmailAuth {
  static const scopes = [GmailApi.gmailReadonlyScope];

  final List<GmailAccount> _accounts = [];
  bool _initialized = false;

  /// Authorized Gmail clients, one per connected account, in add order.
  List<GmailApi> get apis =>
      List.unmodifiable(_accounts.map((a) => a.api));

  /// Lightweight descriptors for the UI, in add order.
  List<({String email, String? name, String? photoUrl})> get accounts =>
      List.unmodifiable(_accounts.map(
        (a) => (email: a.email, name: a.name, photoUrl: a.photoUrl),
      ));

  bool get isConfigured =>
      (dotenv.maybeGet('GOOGLE_CLIENT_ID') ?? '').isNotEmpty;

  bool get hasAccounts => _accounts.isNotEmpty;

  /// First connected account, or null. Backs the existing single-account UI.
  GmailAccount? get first => _accounts.isEmpty ? null : _accounts.first;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: dotenv.maybeGet('GOOGLE_CLIENT_ID'),
    );
    _initialized = true;
  }

  /// Silent resume for returning users; no UI. Restores whatever the platform's
  /// lightweight auth hands back (one account is expected). Returns true when a
  /// session was restored and Gmail is authorized.
  Future<bool> resumeSilently() async {
    if (!isConfigured) return false;
    try {
      await _ensureInitialized();
      final account =
          await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (account == null) return false;
      return await _authorizeAndAdd(account, interactive: false);
    } catch (_) {
      return false;
    }
  }

  /// Interactive add of an account. Presents Google sign-in, authorizes the
  /// read-only scope, and appends the account when its email isn't already
  /// connected. Returns true on success (including when the account is new);
  /// false on cancel/failure. If the OS returns an already-connected account,
  /// this is a no-op that still returns true.
  Future<bool> addAccount() async {
    if (!isConfigured) return false;
    try {
      await _ensureInitialized();
      final account =
          await GoogleSignIn.instance.authenticate(scopeHint: scopes);
      return await _authorizeAndAdd(account, interactive: true);
    } on GoogleSignInException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Alias for [addAccount] — connects the first (or an additional) account.
  Future<bool> signIn() => addAccount();

  Future<bool> _authorizeAndAdd(GoogleSignInAccount account,
      {required bool interactive}) async {
    final client = account.authorizationClient;
    var authorization = await client.authorizationForScopes(scopes);
    if (authorization == null && interactive) {
      authorization = await client.authorizeScopes(scopes);
    }
    if (authorization == null) return false;

    // Hand the client a way to *re-ask* for a token rather than a snapshot of
    // one: access tokens last about an hour, which a long-running session
    // outlives.
    final api = GmailApi(_BearerClient(
      ({bool refresh = false}) async {
        try {
          final fresh = await client.authorizationForScopes(scopes);
          return fresh?.accessToken;
        } catch (_) {
          return null;
        }
      },
      initialToken: authorization.accessToken,
    ));
    final existing =
        _accounts.indexWhere((a) => a.email == account.email);
    if (existing >= 0) {
      // Same identity signed in again — refresh its client, don't duplicate.
      _accounts[existing] = GmailAccount(account, api);
    } else {
      _accounts.add(GmailAccount(account, api));
    }
    return true;
  }

  /// Drops the account with [email]. Only when removing the *last* account does
  /// this sign out of the underlying Google session (which is shared across
  /// accounts in google_sign_in 7.x); otherwise a global sign-out would drop
  /// the accounts we're keeping.
  Future<void> removeAccount(String email) async {
    _accounts.removeWhere((a) => a.email == email);
    if (_accounts.isEmpty) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
  }

  /// Returns a [drive.DriveApi] authorized for the app-data Drive scope, or null
  /// if no account is connected or authorization isn't available.
  ///
  /// [interactive] gates the consent prompt: when false (the default) this only
  /// returns an API if the scope was *already* granted — a silent check safe to
  /// call on screen load or for metadata. Only pass true from an explicit user
  /// action (Back Up Now / Restore), which may show the Google consent sheet.
  ///
  /// `appDataFolder` is a hidden per-app folder — invisible in the user's Drive
  /// and unreadable by other apps — so this never touches their real files. The
  /// `drive.appdata` scope must be on the OAuth consent screen to be grantable.
  Future<drive.DriveApi?> driveApi({bool interactive = false}) async {
    final acct = first?.account;
    if (acct == null) return null;
    try {
      await _ensureInitialized();
      final client = acct.authorizationClient;
      const driveScopes = [drive.DriveApi.driveAppdataScope];
      var authorization = await client.authorizationForScopes(driveScopes);
      if (authorization == null) {
        // Not yet granted. Don't prompt unless the caller explicitly asked.
        if (!interactive) return null;
        authorization = await client.authorizeScopes(driveScopes);
      }
      return drive.DriveApi(_BearerClient(
        ({bool refresh = false}) async {
          try {
            final fresh = await client.authorizationForScopes(driveScopes);
            return fresh?.accessToken;
          } catch (_) {
            return null;
          }
        },
        initialToken: authorization.accessToken,
      ));
    } catch (_) {
      return null;
    }
  }

  /// Signs out of every connected account and the underlying Google session.
  Future<void> signOutAll() async {
    _accounts.clear();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}

/// Authorized client that survives a long sync.
///
/// A full scan is hundreds of sequential requests on one connection, which
/// exposes two failure modes the naive client had. Keep-alive sockets get
/// reclaimed underneath us — surfacing as `ClientException: Bad file
/// descriptor` — and a snapshot access token expires after about an hour,
/// so a long-lived session starts 401ing. Both are recoverable, and neither
/// should end a sync: this retries socket errors on a fresh connection and
/// re-fetches the token on a 401.
class _BearerClient extends http.BaseClient {
  /// Asks the platform for a token; [refresh] forces a new one.
  final Future<String?> Function({bool refresh}) _tokenFor;

  http.Client _inner = http.Client();
  String? _token;

  _BearerClient(this._tokenFor, {String? initialToken})
      : _token = initialToken;

  static const _maxAttempts = 3;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    Object? lastError;

    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      _token ??= await _tokenFor(refresh: attempt > 0);
      final attemptRequest = _copy(request);
      attemptRequest.headers['Authorization'] = 'Bearer $_token';

      try {
        final response = await _inner.send(attemptRequest);
        if (response.statusCode != 401 || attempt == _maxAttempts - 1) {
          return response;
        }
        // Token went stale mid-sync; drop it and let the next pass refetch.
        _token = null;
      } on http.ClientException catch (error) {
        lastError = error;
        _resetConnection();
      } on SocketException catch (error) {
        lastError = error;
        _resetConnection();
      }

      // Brief, growing pause — the socket layer needs a moment to settle.
      await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
    }

    throw lastError ??
        http.ClientException('Request failed after $_maxAttempts attempts',
            request.url);
  }

  void _resetConnection() {
    try {
      _inner.close();
    } catch (_) {}
    _inner = http.Client();
  }

  /// A [http.BaseRequest] can only be sent once, so every retry needs its own.
  /// Streamed bodies can't be replayed; the Gmail reads are all GETs, so
  /// this returns the original and simply forgoes the retry in that case.
  http.BaseRequest _copy(http.BaseRequest original) {
    if (original is! http.Request) return original;
    return http.Request(original.method, original.url)
      ..bodyBytes = original.bodyBytes
      ..headers.addAll(original.headers)
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
