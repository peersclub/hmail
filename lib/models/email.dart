import 'package:googleapis/gmail/v1.dart';

class Email {
  final String id;
  final String? threadId;
  final String from;
  final String to;
  final String subject;
  final String body;
  final String snippet;
  final DateTime date;
  final List<String> labels;
  final bool isRead;
  final bool isStarred;
  final bool isImportant;
  final bool hasAttachments;
  final List<EmailAttachment> attachments;
  final EmailCategory category;
  final double? aiImportanceScore;
  final String? aiSummary;
  final List<String>? aiKeywords;
  final Map<String, dynamic>? metadata;

  Email({
    required this.id,
    this.threadId,
    required this.from,
    required this.to,
    required this.subject,
    required this.body,
    required this.snippet,
    required this.date,
    required this.labels,
    required this.isRead,
    required this.isStarred,
    required this.isImportant,
    required this.hasAttachments,
    required this.attachments,
    required this.category,
    this.aiImportanceScore,
    this.aiSummary,
    this.aiKeywords,
    this.metadata,
  });

  factory Email.fromGmailMessage(Message message, {
    required String body,
    required String from,
    required String to,
    required String subject,
    required DateTime date,
  }) {
    final labels = message.labelIds ?? [];
    return Email(
      id: message.id!,
      threadId: message.threadId,
      from: from,
      to: to,
      subject: subject,
      body: body,
      snippet: message.snippet ?? '',
      date: date,
      labels: labels,
      isRead: !labels.contains('UNREAD'),
      isStarred: labels.contains('STARRED'),
      isImportant: labels.contains('IMPORTANT'),
      hasAttachments: message.payload?.parts?.any((part) => 
        part.filename != null && part.filename!.isNotEmpty) ?? false,
      attachments: _extractAttachments(message),
      category: _categorizeEmail(labels, subject, from),
    );
  }

  static List<EmailAttachment> _extractAttachments(Message message) {
    final attachments = <EmailAttachment>[];
    if (message.payload?.parts != null) {
      for (final part in message.payload!.parts!) {
        if (part.filename != null && part.filename!.isNotEmpty) {
          attachments.add(EmailAttachment(
            filename: part.filename!,
            mimeType: part.mimeType ?? 'application/octet-stream',
            size: part.body?.size ?? 0,
            attachmentId: part.body?.attachmentId,
          ));
        }
      }
    }
    return attachments;
  }

  static EmailCategory _categorizeEmail(List<String> labels, String subject, String from) {
    final lowerSubject = subject.toLowerCase();
    final lowerFrom = from.toLowerCase();

    if (labels.contains('CATEGORY_PROMOTIONS') || 
        lowerSubject.contains('sale') || 
        lowerSubject.contains('discount')) {
      return EmailCategory.promotions;
    }
    if (labels.contains('CATEGORY_SOCIAL')) {
      return EmailCategory.social;
    }
    if (labels.contains('CATEGORY_UPDATES') ||
        lowerFrom.contains('noreply') ||
        lowerFrom.contains('notification')) {
      return EmailCategory.updates;
    }
    if (labels.contains('CATEGORY_FORUMS')) {
      return EmailCategory.forums;
    }
    if (lowerSubject.contains('invoice') ||
        lowerSubject.contains('receipt') ||
        lowerSubject.contains('order') ||
        lowerSubject.contains('payment')) {
      return EmailCategory.finance;
    }
    if (lowerSubject.contains('meeting') ||
        lowerSubject.contains('calendar') ||
        lowerSubject.contains('appointment')) {
      return EmailCategory.calendar;
    }
    return EmailCategory.primary;
  }

  Email copyWith({
    bool? isRead,
    bool? isStarred,
    bool? isImportant,
    String? aiSummary,
    double? aiImportanceScore,
    List<String>? aiKeywords,
  }) {
    return Email(
      id: id,
      threadId: threadId,
      from: from,
      to: to,
      subject: subject,
      body: body,
      snippet: snippet,
      date: date,
      labels: labels,
      isRead: isRead ?? this.isRead,
      isStarred: isStarred ?? this.isStarred,
      isImportant: isImportant ?? this.isImportant,
      hasAttachments: hasAttachments,
      attachments: attachments,
      category: category,
      aiImportanceScore: aiImportanceScore ?? this.aiImportanceScore,
      aiSummary: aiSummary ?? this.aiSummary,
      aiKeywords: aiKeywords ?? this.aiKeywords,
      metadata: metadata,
    );
  }
}

class EmailAttachment {
  final String filename;
  final String mimeType;
  final int size;
  final String? attachmentId;

  EmailAttachment({
    required this.filename,
    required this.mimeType,
    required this.size,
    this.attachmentId,
  });
}

enum EmailCategory {
  primary,
  social,
  promotions,
  updates,
  forums,
  finance,
  calendar,
  travel,
  shopping,
  work,
  personal,
}

class EmailThread {
  final String id;
  final List<Email> messages;
  final String subject;
  final List<String> participants;
  final DateTime lastMessageDate;
  final int messageCount;
  final bool hasUnread;

  EmailThread({
    required this.id,
    required this.messages,
    required this.subject,
    required this.participants,
    required this.lastMessageDate,
    required this.messageCount,
    required this.hasUnread,
  });
}

class EmailFilter {
  final String? query;
  final EmailCategory? category;
  final bool? isUnread;
  final bool? isStarred;
  final bool? isImportant;
  final bool? hasAttachments;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? from;
  final String? to;

  EmailFilter({
    this.query,
    this.category,
    this.isUnread,
    this.isStarred,
    this.isImportant,
    this.hasAttachments,
    this.startDate,
    this.endDate,
    this.from,
    this.to,
  });

  String toGmailQuery() {
    final parts = <String>[];
    
    if (query != null && query!.isNotEmpty) {
      parts.add(query!);
    }
    if (isUnread == true) parts.add('is:unread');
    if (isStarred == true) parts.add('is:starred');
    if (isImportant == true) parts.add('is:important');
    if (hasAttachments == true) parts.add('has:attachment');
    if (from != null) parts.add('from:$from');
    if (to != null) parts.add('to:$to');
    if (startDate != null) {
      parts.add('after:${startDate!.millisecondsSinceEpoch ~/ 1000}');
    }
    if (endDate != null) {
      parts.add('before:${endDate!.millisecondsSinceEpoch ~/ 1000}');
    }
    
    if (category != null) {
      switch (category!) {
        case EmailCategory.primary:
          parts.add('category:primary');
          break;
        case EmailCategory.social:
          parts.add('category:social');
          break;
        case EmailCategory.promotions:
          parts.add('category:promotions');
          break;
        case EmailCategory.updates:
          parts.add('category:updates');
          break;
        case EmailCategory.forums:
          parts.add('category:forums');
          break;
        case EmailCategory.finance:
          parts.add('(invoice OR receipt OR payment OR bill)');
          break;
        case EmailCategory.calendar:
          parts.add('(meeting OR calendar OR appointment)');
          break;
        case EmailCategory.travel:
          parts.add('(flight OR hotel OR booking OR reservation)');
          break;
        case EmailCategory.shopping:
          parts.add('(order OR shipping OR delivery OR package)');
          break;
        default:
          break;
      }
    }
    
    return parts.join(' ');
  }
}