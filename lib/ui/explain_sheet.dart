/// Press and hold a row to ask what it actually is.
///
/// A row is terse by design, and the moment it is confusing there was nowhere to
/// go but "Open email" — which hands the user back the raw message they were
/// trying to avoid reading. This reads it for them.
///
/// Long-press rather than another button: the gesture costs no pixels, it is the
/// iOS idiom for "tell me more about this" (Quick Look, context menus), and it
/// cannot be hit by accident while scrolling a list.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../core/palette.dart';
import '../data/ai/insight_explainer.dart';
import 'glass/glass.dart';

/// Whether a long-press should be offered at all.
///
/// False in demo mode and before sign-in, and false with no AI key — offering a
/// gesture that can only apologise is worse than not offering it, because the
/// user learns the gesture does nothing and stops trying.
bool canExplain() => insightExplainer.isAvailable;

/// Opens the explanation sheet for one insight.
Future<void> showExplanation(
  BuildContext context, {
  required String sourceEmailId,
  required String label,
  String? context_,
}) async {
  // The press is the commitment, so it gets the feedback — the sheet itself
  // arrives a beat later, after the fetch.
  HapticFeedback.mediumImpact();

  await showSheet<void>(
    context: context,
    builder: (sheetContext) => _ExplainSheet(
      sourceEmailId: sourceEmailId,
      label: label,
      context_: context_,
    ),
  );
}

class _ExplainSheet extends StatefulWidget {
  final String sourceEmailId;
  final String label;
  final String? context_;

  const _ExplainSheet({
    required this.sourceEmailId,
    required this.label,
    this.context_,
  });

  @override
  State<_ExplainSheet> createState() => _ExplainSheetState();
}

class _ExplainSheetState extends State<_ExplainSheet> {
  InsightExplanation? _result;

  @override
  void initState() {
    super.initState();
    // A cached summary renders on the first frame, so re-opening a row the user
    // already asked about feels instant rather than like a second request.
    final hit = insightExplainer.cached(widget.sourceEmailId);
    if (hit != null) {
      _result = InsightExplanation.ok(hit);
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final result = await insightExplainer.explain(
      sourceEmailId: widget.sourceEmailId,
      label: widget.label,
      context: widget.context_,
    );
    if (!mounted) return;
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return CupertinoActionSheet(
      title: Text(widget.label),
      message: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: switch (result) {
          null => const _Thinking(),
          final r when r.ok => Text(
              r.text!,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 15,
                height: 1.42,
                color: Palette.label(context),
              ),
            ),
          final r => Text(
              r.error!,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 15,
                height: 1.42,
                color: Palette.secondaryLabel(context),
              ),
            ),
        },
      ),
      actions: [
        if (result != null && !result.ok)
          CupertinoActionSheetAction(
            onPressed: () {
              setState(() => _result = null);
              _load();
            },
            child: const Text('Try again'),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    );
  }
}

/// Says what is happening rather than just spinning: this waits on a network
/// fetch plus a model call, which is long enough that a bare spinner reads as a
/// hang.
class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CupertinoActivityIndicator(radius: 8),
        const SizedBox(width: 10),
        Text(
          'Reading the email…',
          style: TextStyle(
            fontSize: 15,
            color: Palette.secondaryLabel(context),
          ),
        ),
      ],
    );
  }
}
