/// Knowledge — everything NoMail has taught itself.
///
/// The app writes its own handling rules, so those rules have to be visible
/// and reversible. Each row is one learned recipe: what it recognises, what
/// it pulls out, where it can take you, and where it came from. Switch one
/// off and it stops applying without being relearned; delete it and the app
/// may learn it again next time it meets that shape.
library;

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../domain/knowledge.dart';
import '../../state/app_controller.dart';
import '../format.dart';
import '../glass/glass.dart';

class KnowledgeScreen extends StatelessWidget {
  const KnowledgeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final all = [...app.playbook.types]
      ..sort((a, b) => b.learnedAt.compareTo(a.learnedAt));

    // A recipe whose links the user has reported as wrong is the one thing on
    // this screen that needs a decision, so it gets pulled out of the list
    // rather than sitting in it wearing a badge.
    final suspect = [for (final t in all) if (app.isKnowledgeSuspect(t.id)) t];
    final types = [for (final t in all) if (!app.isKnowledgeSuspect(t.id)) t];

    return GlassBackground(
      child: CupertinoPageScaffold(
        backgroundColor: const Color(0x00000000),
        navigationBar: const CupertinoNavigationBar(
          middle: Text('Knowledge'),
          backgroundColor: Color(0x00000000),
          border: null,
        ),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (all.isEmpty)
                const GlassEmptyState(
                  icon: CupertinoIcons.lightbulb,
                  title: 'Nothing Learned Yet',
                  caption:
                      'When NoMail meets a kind of email it does not recognise, '
                      'it writes itself a recipe for handling it. Those recipes '
                      'appear here.',
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          '${all.length}',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            color: Palette.label(context),
                          ),
                        ),
                        Text(
                          all.length == 1
                              ? 'thing NoMail taught itself'
                              : 'things NoMail taught itself',
                          style: TextStyle(
                            fontSize: 14,
                            color: Palette.secondaryLabel(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Each one is applied without the AI, so it costs '
                          'nothing and works offline.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: Palette.secondaryLabel(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (suspect.isNotEmpty)
                  GlassSection(
                    label: 'Needs review',
                    children: [
                      for (final type in suspect)
                        GlassRow(
                          icon: CupertinoIcons.exclamationmark_triangle_fill,
                          iconTint: Palette.destructive(context),
                          title: type.label,
                          titleMaxLines: 2,
                          subtitle: _suspectReason(app, type),
                          subtitleMaxLines: 2,
                          trailingCaption: 'Review',
                          trailingCaptionColor: Palette.destructive(context),
                          onTap: () => _showType(context, app, type),
                        ),
                    ],
                  ),
                if (suspect.isNotEmpty)
                  const Footnote(
                    'These recipes built links you told us went to the wrong '
                    'page, and none that worked. Turning one off keeps the '
                    'emails it recognises — they just stop carrying its link.',
                  ),
                if (types.isNotEmpty)
                  GlassSection(
                    label: 'Learned types',
                    children: [
                      for (final type in types)
                        GlassRow(
                          icon: type.enabled
                              ? CupertinoIcons.lightbulb_fill
                              : CupertinoIcons.lightbulb_slash,
                          iconTint:
                              type.enabled ? Palette.accent(context) : null,
                          title: type.label,
                          titleMaxLines: 2,
                          subtitle: _describe(type),
                          subtitleMaxLines: 2,
                          onTap: () => _showType(context, app, type),
                        ),
                    ],
                  ),
              ],
              const Footnote(
                'Recipes are stored on this device only. Nothing about what '
                'NoMail has learned is shared.',
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  static String _describe(ContentType type) {
    final parts = [
      if (type.match.senderDomains.isNotEmpty) type.match.senderDomains.first,
      '${type.actions.length} action${type.actions.length == 1 ? '' : 's'}',
      if (!type.enabled) 'off',
    ];
    return parts.join(' · ');
  }

  /// The evidence, in the user's own terms — they reported these, so the row
  /// should read back what they said rather than an internal verdict.
  static String _suspectReason(AppController app, ContentType type) {
    final failures = app.linkFailuresFor(type.id);
    return '$failures link${failures == 1 ? '' : 's'} went to the wrong page'
        '${type.enabled ? '' : ' · already off'}';
  }

  Future<void> _showType(
    BuildContext context,
    AppController app,
    ContentType type,
  ) async {
    final suspect = app.isKnowledgeSuspect(type.id);
    final failures = app.linkFailuresFor(type.id);
    final reports = app.linkReportsFor(type.id);

    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(type.label),
        message: Text(
          [
            'Recognises mail from ${type.match.senderDomains.join(', ')}.',
            'Pulls out: ${type.fields.map((f) => f.name).join(', ')}.',
            'Offers: ${type.actions.map((a) => a.label).join(', ')}.',
            '',
            'Learned ${formatDay(type.learnedAt)}'
                '${type.learnedByModel != null ? ' by ${type.learnedByModel}' : ''}.',
            // Only stated when there is something to state: "0 of 0 reported"
            // on a recipe nobody has tested reads like a fault.
            if (reports > 0)
              '$failures of $reports opened link'
                  '${reports == 1 ? '' : 's'} went somewhere wrong.',
          ].join('\n'),
        ),
        actions: [
          CupertinoActionSheetAction(
            // A suspect recipe's likeliest right answer is "stop using it",
            // so the destructive framing goes on the switch, not just delete.
            isDestructiveAction: suspect && type.enabled,
            onPressed: () => Navigator.pop(sheetContext, 'toggle'),
            child: Text(type.enabled ? 'Turn off' : 'Turn on'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(sheetContext, 'delete'),
            child: const Text('Forget this'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ),
    );

    switch (action) {
      case 'toggle':
        await app.setKnowledgeEnabled(type.id, !type.enabled);
      case 'delete':
        await app.forgetKnowledge(type.id);
    }
  }
}
