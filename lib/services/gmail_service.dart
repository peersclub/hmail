import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

class GmailService {
  static const List<String> _scopes = [
    GmailApi.gmailReadonlyScope,
    GmailApi.gmailMetadataScope,
  ];

  GoogleSignInAccount? _currentUser;
  GmailApi? _gmailApi;

  Future<bool> signIn() async {
    try {
      // For now, return false as Google Sign-In needs proper configuration
      // This will be implemented when Google OAuth is properly set up
      return false;
      if (_currentUser == null) return false;

      final auth = await _currentUser!.authentication;
      final accessToken = auth.idToken ?? '';
      final client = GoogleAuthClient(accessToken);
      _gmailApi = GmailApi(client);
      
      return true;
    } catch (e) {
      print('Error signing in: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    // await GoogleSignIn.instance.signOut();
    _currentUser = null;
    _gmailApi = null;
  }

  bool get isSignedIn => _currentUser != null;
  String? get userEmail => _currentUser?.email;
  String? get userName => _currentUser?.displayName;
  String? get userPhoto => _currentUser?.photoUrl;

  Future<List<Message>> fetchEmails({
    String? query,
    int maxResults = 100,
  }) async {
    if (_gmailApi == null) throw Exception('Not signed in');

    try {
      final response = await _gmailApi!.users.messages.list(
        'me',
        q: query,
        maxResults: maxResults,
      );

      if (response.messages == null) return [];

      final messages = <Message>[];
      for (final messageRef in response.messages!) {
        if (messageRef.id != null) {
          final message = await _gmailApi!.users.messages.get(
            'me',
            messageRef.id!,
            format: 'full',
          );
          messages.add(message);
        }
      }

      return messages;
    } catch (e) {
      print('Error fetching emails: $e');
      return [];
    }
  }

  Future<List<Message>> fetchAmazonOrders() async {
    return fetchEmails(
      query: 'from:amazon.com OR from:amazon.in subject:(order OR shipped OR delivered)',
      maxResults: 50,
    );
  }

  Future<List<Message>> fetchSubscriptions() async {
    return fetchEmails(
      query: 'subject:(subscription OR renewal OR recurring) OR from:(netflix OR spotify OR apple OR google OR microsoft OR adobe)',
      maxResults: 50,
    );
  }

  Future<List<Message>> fetchBills() async {
    return fetchEmails(
      query: 'subject:(bill OR invoice OR statement OR payment due) -from:amazon',
      maxResults: 50,
    );
  }

  String? extractEmailBody(Message message) {
    if (message.payload?.parts != null) {
      for (final part in message.payload!.parts!) {
        if (part.mimeType == 'text/plain' && part.body?.data != null) {
          return _decodeBase64(part.body!.data!);
        }
      }
      for (final part in message.payload!.parts!) {
        if (part.mimeType == 'text/html' && part.body?.data != null) {
          return _decodeBase64(part.body!.data!);
        }
      }
    } else if (message.payload?.body?.data != null) {
      return _decodeBase64(message.payload!.body!.data!);
    }
    return null;
  }

  String? extractEmailSubject(Message message) {
    final headers = message.payload?.headers;
    if (headers != null) {
      for (final header in headers) {
        if (header.name?.toLowerCase() == 'subject') {
          return header.value;
        }
      }
    }
    return null;
  }

  DateTime? extractEmailDate(Message message) {
    final headers = message.payload?.headers;
    if (headers != null) {
      for (final header in headers) {
        if (header.name?.toLowerCase() == 'date') {
          try {
            return DateTime.parse(header.value!);
          } catch (e) {
            return null;
          }
        }
      }
    }
    return null;
  }

  String _decodeBase64(String encoded) {
    final normalized = encoded.replaceAll('-', '+').replaceAll('_', '/');
    final padding = '=' * ((4 - normalized.length % 4) % 4);
    final padded = normalized + padding;
    return Uri.decodeFull(String.fromCharCodes(base64.decode(padded)));
  }
}

class GoogleAuthClient extends http.BaseClient {
  final String _accessToken;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._accessToken);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _client.send(request);
  }
}