import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/enhanced_email_provider.dart';
import '../models/email.dart';
import 'compose_email_screen.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

class EmailDetailScreen extends StatefulWidget {
  final Email email;

  const EmailDetailScreen({super.key, required this.email});

  @override
  State<EmailDetailScreen> createState() => _EmailDetailScreenState();
}

class _EmailDetailScreenState extends State<EmailDetailScreen> {
  bool _showFullHeaders = false;
  EmailThread? _thread;

  @override
  void initState() {
    super.initState();
    _loadThread();
    _markAsRead();
  }

  void _loadThread() async {
    if (widget.email.threadId != null) {
      final thread = await context.read<EnhancedEmailProvider>()
          .fetchThread(widget.email.threadId!);
      setState(() {
        _thread = thread;
      });
    }
  }

  void _markAsRead() {
    if (!widget.email.isRead) {
      context.read<EnhancedEmailProvider>().markAsRead(widget.email.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.email.subject),
        actions: [
          IconButton(
            icon: Icon(
              widget.email.isStarred ? Icons.star : Icons.star_border,
              color: widget.email.isStarred ? Colors.amber : null,
            ),
            onPressed: () {
              context.read<EnhancedEmailProvider>()
                  .toggleStar(widget.email.id, !widget.email.isStarred);
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'unread':
                  context.read<EnhancedEmailProvider>()
                      .markAsUnread(widget.email.id);
                  break;
                case 'label':
                  _addLabel();
                  break;
                case 'archive':
                  context.read<EnhancedEmailProvider>()
                      .archiveEmail(widget.email.id);
                  Navigator.pop(context);
                  break;
                case 'delete':
                  context.read<EnhancedEmailProvider>()
                      .deleteEmail(widget.email.id);
                  Navigator.pop(context);
                  break;
                case 'spam':
                  // Report spam
                  break;
                case 'print':
                  // Print email
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'unread',
                child: ListTile(
                  leading: Icon(Icons.markunread),
                  title: Text('Mark as unread'),
                ),
              ),
              const PopupMenuItem(
                value: 'label',
                child: ListTile(
                  leading: Icon(Icons.label),
                  title: Text('Add label'),
                ),
              ),
              const PopupMenuItem(
                value: 'archive',
                child: ListTile(
                  leading: Icon(Icons.archive),
                  title: Text('Archive'),
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete),
                  title: Text('Delete'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'spam',
                child: ListTile(
                  leading: Icon(Icons.report),
                  title: Text('Report spam'),
                ),
              ),
              const PopupMenuItem(
                value: 'print',
                child: ListTile(
                  leading: Icon(Icons.print),
                  title: Text('Print'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildEmailHeader(),
                  if (widget.email.aiSummary != null) _buildAISummary(),
                  const SizedBox(height: 16),
                  _buildEmailBody(),
                  if (widget.email.hasAttachments) _buildAttachments(),
                  if (_thread != null && _thread!.messages.length > 1)
                    _buildThreadMessages(),
                ],
              ),
            ),
          ),
          _buildActionBar(),
        ],
      ),
    );
  }

  Widget _buildEmailHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    widget.email.from.isNotEmpty 
                        ? widget.email.from[0].toUpperCase() 
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _extractSenderName(widget.email.from),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.email.from,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  DateFormat('MMM d, yyyy HH:mm').format(widget.email.date),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => setState(() => _showFullHeaders = !_showFullHeaders),
              child: Row(
                children: [
                  Text(
                    'to ${widget.email.to}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _showFullHeaders 
                        ? Icons.keyboard_arrow_up 
                        : Icons.keyboard_arrow_down,
                    size: 16,
                  ),
                ],
              ),
            ),
            if (_showFullHeaders)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('From: ${widget.email.from}'),
                    Text('To: ${widget.email.to}'),
                    Text('Date: ${widget.email.date}'),
                    if (widget.email.labels.isNotEmpty)
                      Text('Labels: ${widget.email.labels.join(', ')}'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAISummary() {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Text(
                  'AI Summary',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(widget.email.aiSummary!),
            if (widget.email.aiKeywords != null && 
                widget.email.aiKeywords!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: widget.email.aiKeywords!.map((keyword) =>
                  Chip(
                    label: Text(keyword),
                    visualDensity: VisualDensity.compact,
                  ),
                ).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmailBody() {
    return SelectableText(
      widget.email.body,
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }

  Widget _buildAttachments() {
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Attachments (${widget.email.attachments.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...widget.email.attachments.map((attachment) =>
              ListTile(
                leading: Icon(_getAttachmentIcon(attachment.mimeType)),
                title: Text(attachment.filename),
                subtitle: Text(_formatFileSize(attachment.size)),
                trailing: IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: () {
                    // Download attachment
                  },
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThreadMessages() {
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thread (${_thread!.messages.length} messages)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ..._thread!.messages.where((m) => m.id != widget.email.id).map((message) =>
              ListTile(
                leading: CircleAvatar(
                  radius: 16,
                  child: Text(
                    message.from.isNotEmpty 
                        ? message.from[0].toUpperCase() 
                        : '?',
                  ),
                ),
                title: Text(_extractSenderName(message.from)),
                subtitle: Text(
                  message.snippet,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  DateFormat('MMM d').format(message.date),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                onTap: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EmailDetailScreen(email: message),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.reply),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ComposeEmailScreen(replyTo: widget.email),
                ),
              );
            },
            tooltip: 'Reply',
          ),
          IconButton(
            icon: const Icon(Icons.reply_all),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ComposeEmailScreen(
                    replyTo: widget.email,
                    isReplyAll: true,
                  ),
                ),
              );
            },
            tooltip: 'Reply All',
          ),
          IconButton(
            icon: const Icon(Icons.forward),
            onPressed: () {
              // Forward email
            },
            tooltip: 'Forward',
          ),
          IconButton(
            icon: const Icon(Icons.archive),
            onPressed: () {
              context.read<EnhancedEmailProvider>()
                  .archiveEmail(widget.email.id);
              Navigator.pop(context);
            },
            tooltip: 'Archive',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              context.read<EnhancedEmailProvider>()
                  .deleteEmail(widget.email.id);
              Navigator.pop(context);
            },
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }

  void _addLabel() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Label'),
          content: Consumer<EnhancedEmailProvider>(
            builder: (context, provider, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: provider.labels.map((label) =>
                  ListTile(
                    title: Text(label),
                    onTap: () {
                      provider.applyLabel(widget.email.id, label);
                      Navigator.pop(context);
                    },
                  ),
                ).toList(),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: _createNewLabel,
              child: const Text('Create New'),
            ),
          ],
        );
      },
    );
  }

  void _createNewLabel() {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Create New Label'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Label Name',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  context.read<EnhancedEmailProvider>()
                      .createLabel(controller.text);
                  Navigator.pop(context);
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
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

  IconData _getAttachmentIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.videocam;
    if (mimeType.startsWith('audio/')) return Icons.audiotrack;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return Icons.description;
    }
    if (mimeType.contains('sheet') || mimeType.contains('excel')) {
      return Icons.table_chart;
    }
    return Icons.attach_file;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}