import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:googleapis/gmail/v1.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../models/email.dart';

class EnhancedGmailService {
  static const List<String> _scopes = [
    GmailApi.gmailModifyScope,
    GmailApi.gmailComposeScope,
    GmailApi.gmailSendScope,
  ];

  GoogleSignInAccount? _currentUser;
  GmailApi? _gmailApi;
  bool _initialized = false;

  GoogleSignInAccount? get currentUser => _currentUser;
  bool get isConfigured => (dotenv.maybeGet('GOOGLE_CLIENT_ID') ?? '').isNotEmpty;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: dotenv.maybeGet('GOOGLE_CLIENT_ID'),
    );
    _initialized = true;
  }

  /// Signs in with Google and authorizes Gmail scopes.
  ///
  /// Returns false when OAuth is not configured (no GOOGLE_CLIENT_ID) or the
  /// user cancels — callers fall back to demo mode.
  Future<bool> signIn() async {
    if (!isConfigured) return false;

    try {
      await _ensureInitialized();
      final signIn = GoogleSignIn.instance;

      // Silent re-auth for returning users; interactive prompt otherwise.
      GoogleSignInAccount? account =
          await signIn.attemptLightweightAuthentication();
      account ??= await signIn.authenticate(scopeHint: _scopes);
      _currentUser = account;

      final authorization =
          await account.authorizationClient.authorizationForScopes(_scopes) ??
              await account.authorizationClient.authorizeScopes(_scopes);

      _gmailApi = GmailApi(GoogleAuthClient(authorization.accessToken));
      return true;
    } on GoogleSignInException catch (e) {
      print('Google Sign-In failed: ${e.code} ${e.description}');
      _currentUser = null;
      _gmailApi = null;
      return false;
    } catch (e) {
      print('Error signing in: $e');
      _currentUser = null;
      _gmailApi = null;
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    _currentUser = null;
    _gmailApi = null;
  }

  Future<List<Email>> fetchEmails({
    EmailFilter? filter,
    int maxResults = 50,
    String? pageToken,
  }) async {
    if (_gmailApi == null) throw Exception('Not signed in');

    try {
      final query = filter?.toGmailQuery();
      final response = await _gmailApi!.users.messages.list(
        'me',
        q: query,
        maxResults: maxResults,
        pageToken: pageToken,
      );

      if (response.messages == null) return [];

      final emails = <Email>[];
      for (final messageRef in response.messages!) {
        if (messageRef.id != null) {
          final message = await _gmailApi!.users.messages.get(
            'me',
            messageRef.id!,
            format: 'full',
          );
          
          final email = _parseEmail(message);
          if (email != null) {
            emails.add(email);
          }
        }
      }

      return emails;
    } catch (e) {
      print('Error fetching emails: $e');
      return [];
    }
  }

  Future<EmailThread> fetchThread(String threadId) async {
    if (_gmailApi == null) throw Exception('Not signed in');

    try {
      final thread = await _gmailApi!.users.threads.get('me', threadId);
      final messages = <Email>[];
      final participants = <String>{};

      if (thread.messages != null) {
        for (final message in thread.messages!) {
          final email = _parseEmail(message);
          if (email != null) {
            messages.add(email);
            participants.add(email.from);
            participants.add(email.to);
          }
        }
      }

      return EmailThread(
        id: threadId,
        messages: messages,
        subject: messages.isNotEmpty ? messages.first.subject : '',
        participants: participants.toList(),
        lastMessageDate: messages.isNotEmpty ? messages.last.date : DateTime.now(),
        messageCount: messages.length,
        hasUnread: messages.any((m) => !m.isRead),
      );
    } catch (e) {
      print('Error fetching thread: $e');
      throw e;
    }
  }

  Future<void> markAsRead(String messageId) async {
    if (_gmailApi == null) throw Exception('Not signed in');

    final request = ModifyMessageRequest()
      ..removeLabelIds = ['UNREAD'];

    await _gmailApi!.users.messages.modify(request, 'me', messageId);
  }

  Future<void> markAsUnread(String messageId) async {
    if (_gmailApi == null) throw Exception('Not signed in');

    final request = ModifyMessageRequest()
      ..addLabelIds = ['UNREAD'];

    await _gmailApi!.users.messages.modify(request, 'me', messageId);
  }

  Future<void> toggleStar(String messageId, bool starred) async {
    if (_gmailApi == null) throw Exception('Not signed in');

    final request = ModifyMessageRequest();
    if (starred) {
      request.addLabelIds = ['STARRED'];
    } else {
      request.removeLabelIds = ['STARRED'];
    }

    await _gmailApi!.users.messages.modify(request, 'me', messageId);
  }

  Future<void> markAsImportant(String messageId, bool important) async {
    if (_gmailApi == null) throw Exception('Not signed in');

    final request = ModifyMessageRequest();
    if (important) {
      request.addLabelIds = ['IMPORTANT'];
    } else {
      request.removeLabelIds = ['IMPORTANT'];
    }

    await _gmailApi!.users.messages.modify(request, 'me', messageId);
  }

  Future<void> moveToTrash(String messageId) async {
    if (_gmailApi == null) throw Exception('Not signed in');
    await _gmailApi!.users.messages.trash('me', messageId);
  }

  Future<void> deleteForever(String messageId) async {
    if (_gmailApi == null) throw Exception('Not signed in');
    await _gmailApi!.users.messages.delete('me', messageId);
  }

  Future<void> archiveEmail(String messageId) async {
    if (_gmailApi == null) throw Exception('Not signed in');

    final request = ModifyMessageRequest()
      ..removeLabelIds = ['INBOX'];

    await _gmailApi!.users.messages.modify(request, 'me', messageId);
  }

  Future<void> sendEmail({
    required String to,
    required String subject,
    required String body,
    String? cc,
    String? bcc,
    List<String>? attachmentPaths,
    String? replyToMessageId,
  }) async {
    if (_gmailApi == null) throw Exception('Not signed in');
    
    final from = _currentUser!.email;
    
    String emailContent = 'From: $from\r\n'
        'To: $to\r\n';
    
    if (cc != null) emailContent += 'Cc: $cc\r\n';
    if (bcc != null) emailContent += 'Bcc: $bcc\r\n';
    
    emailContent += 'Subject: $subject\r\n'
        'Content-Type: text/html; charset=utf-8\r\n'
        '\r\n'
        '$body';

    final bytes = utf8.encode(emailContent);
    final base64Email = base64.encode(bytes)
        .replaceAll('+', '-')
        .replaceAll('/', '_')
        .replaceAll('=', '');

    final message = Message()
      ..raw = base64Email;

    if (replyToMessageId != null) {
      final originalMessage = await _gmailApi!.users.messages.get('me', replyToMessageId);
      message.threadId = originalMessage.threadId;
    }

    await _gmailApi!.users.messages.send(message, 'me');
  }

  Future<List<String>> fetchLabels() async {
    if (_gmailApi == null) throw Exception('Not signed in');

    try {
      final response = await _gmailApi!.users.labels.list('me');
      return response.labels?.map((l) => l.name ?? '').toList() ?? [];
    } catch (e) {
      print('Error fetching labels: $e');
      return [];
    }
  }

  Future<void> createLabel(String name) async {
    if (_gmailApi == null) throw Exception('Not signed in');

    final label = Label()
      ..name = name
      ..labelListVisibility = 'labelShow'
      ..messageListVisibility = 'show';

    await _gmailApi!.users.labels.create(label, 'me');
  }

  Future<void> applyLabel(String messageId, String labelName) async {
    if (_gmailApi == null) throw Exception('Not signed in');

    final labels = await _gmailApi!.users.labels.list('me');
    final label = labels.labels?.firstWhere((l) => l.name == labelName);
    
    if (label?.id != null) {
      final request = ModifyMessageRequest()
        ..addLabelIds = [label!.id!];
      
      await _gmailApi!.users.messages.modify(request, 'me', messageId);
    }
  }

  Email? _parseEmail(Message message) {
    try {
      final headers = message.payload?.headers ?? [];
      String from = '';
      String to = '';
      String subject = '';
      DateTime? date;

      for (final header in headers) {
        switch (header.name?.toLowerCase()) {
          case 'from':
            from = header.value ?? '';
            break;
          case 'to':
            to = header.value ?? '';
            break;
          case 'subject':
            subject = header.value ?? '';
            break;
          case 'date':
            try {
              date = DateTime.parse(header.value!);
            } catch (_) {}
            break;
        }
      }

      final body = _extractBody(message) ?? '';

      return Email.fromGmailMessage(
        message,
        body: body,
        from: from,
        to: to,
        subject: subject,
        date: date ?? DateTime.now(),
      );
    } catch (e) {
      print('Error parsing email: $e');
      return null;
    }
  }

  String? _extractBody(Message message) {
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