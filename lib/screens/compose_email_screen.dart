import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/enhanced_email_provider.dart';
import '../models/email.dart';

class ComposeEmailScreen extends StatefulWidget {
  final Email? replyTo;
  final bool isReplyAll;

  const ComposeEmailScreen({
    super.key,
    this.replyTo,
    this.isReplyAll = false,
  });

  @override
  State<ComposeEmailScreen> createState() => _ComposeEmailScreenState();
}

class _ComposeEmailScreenState extends State<ComposeEmailScreen> {
  final _toController = TextEditingController();
  final _ccController = TextEditingController();
  final _bccController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  
  bool _showCc = false;
  bool _showBcc = false;
  bool _isSending = false;
  
  final List<String> _quickReplies = [
    "Thanks for your email. I'll get back to you soon.",
    "I've received your message and will review it.",
    "Thank you for reaching out. Let me look into this.",
    "I appreciate your patience. I'll respond shortly.",
    "Got it! I'll take care of this right away.",
  ];

  final List<EmailTemplate> _templates = [
    EmailTemplate(
      name: 'Meeting Request',
      subject: 'Meeting Request - [Topic]',
      body: '''Hi [Name],

I hope this email finds you well. I'd like to schedule a meeting to discuss [topic].

Would you be available [date/time]? Please let me know what works best for your schedule.

Best regards,
[Your name]''',
    ),
    EmailTemplate(
      name: 'Follow Up',
      subject: 'Following up on [Topic]',
      body: '''Hi [Name],

I wanted to follow up on our previous conversation about [topic].

[Add details here]

Please let me know if you need any additional information.

Best regards,
[Your name]''',
    ),
    EmailTemplate(
      name: 'Thank You',
      subject: 'Thank You',
      body: '''Hi [Name],

Thank you for [reason]. I really appreciate [specific detail].

[Add more context]

Best regards,
[Your name]''',
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.replyTo != null) {
      _setupReply();
    }
  }

  void _setupReply() {
    final email = widget.replyTo!;
    _toController.text = email.from;
    
    if (widget.isReplyAll) {
      // Add other recipients
    }
    
    _subjectController.text = email.subject.startsWith('Re:') 
      ? email.subject 
      : 'Re: ${email.subject}';
    
    _bodyController.text = '''


On ${email.date}, ${email.from} wrote:
> ${email.body.split('\n').join('\n> ')}
''';
  }

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _bccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.replyTo != null ? 'Reply' : 'Compose'),
        actions: [
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: _attachFile,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showMoreOptions,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _isSending
              ? const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendEmail,
                ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _toController,
                    decoration: InputDecoration(
                      labelText: 'To',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!_showCc)
                            TextButton(
                              onPressed: () => setState(() => _showCc = true),
                              child: const Text('Cc'),
                            ),
                          if (!_showBcc)
                            TextButton(
                              onPressed: () => setState(() => _showBcc = true),
                              child: const Text('Bcc'),
                            ),
                        ],
                      ),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  if (_showCc)
                    TextField(
                      controller: _ccController,
                      decoration: const InputDecoration(labelText: 'Cc'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                  if (_showBcc)
                    TextField(
                      controller: _bccController,
                      decoration: const InputDecoration(labelText: 'Bcc'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                  TextField(
                    controller: _subjectController,
                    decoration: const InputDecoration(labelText: 'Subject'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _bodyController,
                    decoration: const InputDecoration(
                      hintText: 'Compose email',
                      border: InputBorder.none,
                    ),
                    maxLines: null,
                    minLines: 10,
                    keyboardType: TextInputType.multiline,
                  ),
                ],
              ),
            ),
          ),
          Container(
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
            child: Column(
              children: [
                if (_quickReplies.isNotEmpty)
                  Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _quickReplies.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          child: ActionChip(
                            label: Text(
                              _quickReplies[index].length > 30
                                ? '${_quickReplies[index].substring(0, 30)}...'
                                : _quickReplies[index],
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () {
                              _bodyController.text = _quickReplies[index];
                            },
                          ),
                        );
                      },
                    ),
                  ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.format_bold),
                      onPressed: () => _formatText('bold'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.format_italic),
                      onPressed: () => _formatText('italic'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.format_underlined),
                      onPressed: () => _formatText('underline'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.link),
                      onPressed: _insertLink,
                    ),
                    IconButton(
                      icon: const Icon(Icons.emoji_emotions_outlined),
                      onPressed: _insertEmoji,
                    ),
                    const Spacer(),
                    PopupMenuButton<EmailTemplate>(
                      icon: const Icon(Icons.description),
                      tooltip: 'Templates',
                      onSelected: _useTemplate,
                      itemBuilder: (context) => _templates.map((template) =>
                        PopupMenuItem(
                          value: template,
                          child: Text(template.name),
                        ),
                      ).toList(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _sendEmail() async {
    if (_toController.text.isEmpty || _subjectController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in To and Subject fields')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      await context.read<EnhancedEmailProvider>().sendEmail(
        to: _toController.text,
        subject: _subjectController.text,
        body: _bodyController.text,
        replyToMessageId: widget.replyTo?.id,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email sent successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send email: $e')),
        );
      }
    }
  }

  void _attachFile() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('Attach Photo'),
              onTap: () {
                Navigator.pop(context);
                // Implement photo attachment
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_present),
              title: const Text('Attach File'),
              onTap: () {
                Navigator.pop(context);
                // Implement file attachment
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_eta),
              title: const Text('From Google Drive'),
              onTap: () {
                Navigator.pop(context);
                // Implement Drive attachment
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.schedule_send),
              title: const Text('Schedule Send'),
              onTap: () {
                Navigator.pop(context);
                _scheduleSend();
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock),
              title: const Text('Confidential Mode'),
              onTap: () {
                Navigator.pop(context);
                // Implement confidential mode
              },
            ),
            ListTile(
              leading: const Icon(Icons.save),
              title: const Text('Save as Draft'),
              onTap: () {
                Navigator.pop(context);
                // Save as draft
              },
            ),
          ],
        ),
      ),
    );
  }

  void _scheduleSend() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );

      if (time != null) {
        // Schedule the email
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Email scheduled for ${date.toString().split(' ')[0]} at ${time.format(context)}'),
          ),
        );
      }
    }
  }

  void _formatText(String format) {
    // Implement text formatting
  }

  void _insertLink() {
    // Implement link insertion
  }

  void _insertEmoji() {
    // Implement emoji picker
  }

  void _useTemplate(EmailTemplate template) {
    _subjectController.text = template.subject;
    _bodyController.text = template.body;
  }
}

class EmailTemplate {
  final String name;
  final String subject;
  final String body;

  EmailTemplate({
    required this.name,
    required this.subject,
    required this.body,
  });
}