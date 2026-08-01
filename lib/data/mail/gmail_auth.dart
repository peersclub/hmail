import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart';
import 'package:http/http.dart' as http;

/// Google sign-in + Gmail authorization (google_sign_in 7.x).
///
/// Read-only scope by design: NoMail never modifies or sends mail.
class GmailAuth {
  static const scopes = [GmailApi.gmailReadonlyScope];

  GoogleSignInAccount? _account;
  GmailApi? _api;
  bool _initialized = false;

  GoogleSignInAccount? get account => _account;
  GmailApi? get api => _api;
  bool get isConfigured =>
      (dotenv.maybeGet('GOOGLE_CLIENT_ID') ?? '').isNotEmpty;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: dotenv.maybeGet('GOOGLE_CLIENT_ID'),
    );
    _initialized = true;
  }

  /// Silent resume for returning users; no UI. Returns true when a session
  /// was restored and Gmail is authorized.
  Future<bool> resumeSilently() async {
    if (!isConfigured) return false;
    try {
      await _ensureInitialized();
      final account =
          await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (account == null) return false;
      return await _authorize(account, interactive: false);
    } catch (_) {
      return false;
    }
  }

  /// Interactive sign-in. Returns false on cancel/failure.
  Future<bool> signIn() async {
    if (!isConfigured) return false;
    try {
      await _ensureInitialized();
      final account =
          await GoogleSignIn.instance.authenticate(scopeHint: scopes);
      return await _authorize(account, interactive: true);
    } on GoogleSignInException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _authorize(GoogleSignInAccount account,
      {required bool interactive}) async {
    final client = account.authorizationClient;
    var authorization = await client.authorizationForScopes(scopes);
    if (authorization == null && interactive) {
      authorization = await client.authorizeScopes(scopes);
    }
    if (authorization == null) return false;
    _account = account;
    _api = GmailApi(_BearerClient(authorization.accessToken));
    return true;
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    _account = null;
    _api = null;
  }
}

class _BearerClient extends http.BaseClient {
  final String _token;
  final http.Client _inner = http.Client();

  _BearerClient(this._token);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }
}
