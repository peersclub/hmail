import 'package:flutter/material.dart';
import '../models/email.dart';
import 'package:intl/intl.dart';

class EmailListItem extends StatelessWidget {
  final Email email;
  final VoidCallback onTap;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;
  final VoidCallback? onStarToggle;

  const EmailListItem({
    super.key,
    required this.email,
    required this.onTap,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.onStarToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(email.id),
      background: Container(
        color: Colors.green,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.archive, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) {
        if (direction == DismissDirection.startToEnd) {
          onSwipeLeft?.call();
        } else {
          onSwipeRight?.call();
        }
      },
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: email.isRead ? null : Theme.of(context).colorScheme.primaryContainer.withOpacity(0.1),
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.2),
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _getCategoryColor(email.category),
                child: Text(
                  email.from.isNotEmpty ? email.from[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _extractSenderName(email.from),
                            style: TextStyle(
                              fontWeight: email.isRead ? FontWeight.normal : FontWeight.bold,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (email.aiImportanceScore != null && email.aiImportanceScore! > 0.7)
                          Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Important',
                              style: TextStyle(fontSize: 10, color: Colors.white),
                            ),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(email.date),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email.subject,
                      style: TextStyle(
                        fontWeight: email.isRead ? FontWeight.normal : FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email.aiSummary ?? email.snippet,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (email.aiKeywords != null && email.aiKeywords!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 4,
                          children: email.aiKeywords!.take(3).map((keyword) => 
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                keyword,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ).toList(),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    icon: Icon(
                      email.isStarred ? Icons.star : Icons.star_border,
                      color: email.isStarred ? Colors.amber : null,
                      size: 20,
                    ),
                    onPressed: onStarToggle,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  if (email.hasAttachments)
                    const Icon(Icons.attach_file, size: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getCategoryColor(EmailCategory category) {
    switch (category) {
      case EmailCategory.primary:
        return Colors.blue;
      case EmailCategory.social:
        return Colors.lightBlue;
      case EmailCategory.promotions:
        return Colors.green;
      case EmailCategory.updates:
        return Colors.orange;
      case EmailCategory.forums:
        return Colors.purple;
      case EmailCategory.finance:
        return Colors.teal;
      case EmailCategory.calendar:
        return Colors.red;
      case EmailCategory.travel:
        return Colors.indigo;
      case EmailCategory.shopping:
        return Colors.amber;
      case EmailCategory.work:
        return Colors.blueGrey;
      case EmailCategory.personal:
        return Colors.pink;
    }
  }

  String _extractSenderName(String from) {
    if (from.contains('<')) {
      return from.substring(0, from.indexOf('<')).trim();
    }
    if (from.contains('@')) {
      return from.substring(0, from.indexOf('@'));
    }
    return from;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return DateFormat('HH:mm').format(date);
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return DateFormat('EEE').format(date);
    } else if (date.year == now.year) {
      return DateFormat('MMM d').format(date);
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }
}