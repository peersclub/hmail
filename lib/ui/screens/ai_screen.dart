/// AI settings — the trust surface.
///
/// A user handing an app their mailbox deserves to see exactly what the AI
/// is: whether it is on, which model, that it genuinely connects, what it
/// costs, and what leaves the device. Everything here is live, not copy.
library;

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../core/ai_key.dart';
import '../../core/palette.dart';
import '../../data/ai/ai_status.dart';
import '../../state/app_controller.dart';
import '../glass/glass.dart';

class AiScreen extends StatefulWidget {
  const AiScreen({super.key});

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  AiKeyUsage? _usage;
  AiConnectionResult? _test;
  bool _loadingUsage = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    final usage = await context.read<AppController>().aiStatus.fetchUsage();
    if (!mounted) return;
    setState(() {
      _usage = usage;
      _loadingUsage = false;
    });
  }

  /// Add / replace / remove the OpenRouter key, in-app. The old copy told
  /// users to edit .env — an instruction no phone user can follow.
  Future<void> _keyOptions(BuildContext context) async {
    final userProvided = AiKey.isUserProvided;
    final hasKey = AiKey.value != null;

    if (!hasKey) {
      await _enterKey(context);
      return;
    }
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('OpenRouter key'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, 'replace'),
            child: const Text('Replace key…'),
          ),
          // Only offer to remove a key this app actually stores — the .env
          // fallback isn't removable from here.
          if (userProvided)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(sheetContext, 'remove'),
              child: const Text('Remove key'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'replace') {
      await _enterKey(context);
    } else if (action == 'remove') {
      await AiKey.clear();
      if (mounted) setState(() => _test = null);
      _loadUsage();
    }
  }

  Future<void> _enterKey(BuildContext context) async {
    final controller = TextEditingController();
    final saved = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('OpenRouter key'),
        content: Column(
          children: [
            const SizedBox(height: 8),
            const Text(
              'Create a key at openrouter.ai → Keys, set a spending cap, '
              'and paste it here. Stored only on this device.',
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: controller,
              placeholder: 'sk-or-…',
              autocorrect: false,
              enableSuggestions: false,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final key = controller.text.trim();
    if (saved == true && key.isNotEmpty) {
      await AiKey.save(key);
      if (mounted) setState(() => _test = null);
      // The saved key changes what usage/status report — refresh both.
      _loadUsage();
    }
  }

  Future<void> _runTest() async {
    setState(() => _testing = true);
    final result = await context.read<AppController>().aiStatus.testConnection();
    if (!mounted) return;
    setState(() {
      _test = result;
      _testing = false;
    });
    // A successful call moves the spend needle; refresh so the number is real.
    _loadUsage();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final status = app.aiStatus;
    final settings = app.settings;
    final configured = status.isConfigured;

    return GlassBackground(
      child: CupertinoPageScaffold(
        backgroundColor: const Color(0x00000000),
        navigationBar: const CupertinoNavigationBar(
          middle: Text('AI'),
          backgroundColor: Color(0x00000000),
          border: null,
        ),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              GlassSection(
                label: 'Connection',
                children: [
                  GlassRow(
                    icon: configured
                        ? CupertinoIcons.checkmark_seal_fill
                        : CupertinoIcons.lock_circle,
                    iconTint: configured ? null : Palette.accent(context),
                    title: configured ? 'Key configured' : 'Add your key',
                    subtitle: status.maskedKey ??
                        'Paste an OpenRouter API key to turn on AI '
                            '(openrouter.ai → Keys)',
                    subtitleMaxLines: 2,
                    trailingCaption: configured ? 'Change' : 'Add',
                    trailingCaptionColor: Palette.accent(context),
                    onTap: () => _keyOptions(context),
                  ),
                  GlassRow(
                    icon: CupertinoIcons.cube,
                    title: 'Model',
                    subtitle: _modelLabel(settings.aiModel),
                    trailingCaption: 'Change',
                    trailingCaptionColor: Palette.accent(context),
                    onTap: configured ? () => _pickModel(context, app) : null,
                  ),
                  if (configured)
                    GlassRow(
                      icon: CupertinoIcons.bolt_horizontal,
                      title: _testing ? 'Testing…' : 'Test connection',
                      subtitle: _test?.summary ??
                          'Send one tiny request and time the round trip',
                      trailingCaption: _test == null
                          ? null
                          : (_test!.ok ? 'OK' : 'Failed'),
                      trailingCaptionColor: _test == null
                          ? null
                          : (_test!.ok
                              ? Palette.accent(context)
                              : Palette.destructive(context)),
                      onTap: _testing ? null : _runTest,
                    ),
                ],
              ),
              if (configured)
                GlassSection(
                  label: 'Spend',
                  children: [
                    GlassRow(
                      icon: CupertinoIcons.chart_bar,
                      title: 'Usage',
                      subtitle: _loadingUsage
                          ? 'Checking…'
                          : (_usage?.spendSummary ?? 'Unavailable'),
                      trailingCaption: 'Refresh',
                      trailingCaptionColor: Palette.accent(context),
                      onTap: () {
                        setState(() => _loadingUsage = true);
                        _loadUsage();
                      },
                    ),
                    if (_usage?.warning != null)
                      GlassRow(
                        icon: CupertinoIcons.exclamationmark_shield,
                        iconTint: Palette.destructive(context),
                        title: _usage!.warning!,
                        titleMaxLines: 2,
                        subtitle:
                            'Set a monthly cap at openrouter.ai/settings/keys',
                        subtitleMaxLines: 2,
                      ),
                  ],
                ),
              GlassSection(
                label: 'Privacy',
                children: [
                  _toggleRow(
                    context,
                    icon: CupertinoIcons.sparkles,
                    title: 'Use AI',
                    subtitle: 'Off means rules only — nothing leaves the device',
                    value: settings.aiEnabled,
                    onChanged: (on) => app.updateSettings(
                      settings.copyWith(aiEnabled: on),
                    ),
                  ),
                ],
              ),
              const Footnote(
                'With AI on, NoMail sends the extracted summary — amounts, '
                'dates, merchant names and email subjects — to OpenRouter to '
                'write the brief and check its own results. Full email bodies '
                'are never sent, and insights are stored only on this device.',
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  String _modelLabel(String slug) {
    for (final option in AiStatusService.modelOptions) {
      if (option.slug == slug) return option.label;
    }
    return slug;
  }

  Future<void> _pickModel(BuildContext context, AppController app) async {
    final chosen = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Model'),
        message: const Text('All handle the brief; they differ in cost.'),
        actions: [
          for (final option in AiStatusService.modelOptions)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(sheetContext, option.slug),
              child: Column(
                children: [
                  Text(option.label),
                  const SizedBox(height: 2),
                  Text(
                    option.note,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Palette.secondaryLabel(sheetContext),
                    ),
                  ),
                ],
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (chosen != null) {
      await app.updateSettings(app.settings.copyWith(aiModel: chosen));
    }
  }
}

/// GlassRow with a trailing switch — GlassRow only takes string trailings.
Widget _toggleRow(
  BuildContext context, {
  required IconData icon,
  required String title,
  String? subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    child: Row(
      children: [
        IconBadge(icon),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  letterSpacing: -0.4,
                  color: Palette.label(context),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 13,
                    color: Palette.secondaryLabel(context),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        CupertinoSwitch(value: value, onChanged: onChanged),
      ],
    ),
  );
}
