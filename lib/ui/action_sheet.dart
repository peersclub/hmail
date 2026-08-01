/// Insight → action bridge for the UI.
///
/// Tapping any insight row opens a native action sheet listing what can be
/// done with it (Track package, Pay via UPI, Join on Meet, Open email...).
/// A single action skips the sheet and launches straight away — no ceremony
/// when there's no choice to make.
library;

import 'package:flutter/cupertino.dart';

import '../core/action_launcher.dart';
import '../domain/actions.dart';

Future<void> showInsightActions(
  BuildContext context, {
  required String title,
  String? message,
  required List<InsightAction> actions,
}) async {
  if (actions.isEmpty) return;
  if (actions.length == 1) {
    await openAction(actions.single);
    return;
  }

  await showCupertinoModalPopup<void>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: Text(title),
      message: message == null ? null : Text(message),
      actions: [
        for (final action in actions)
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheetContext);
              openAction(action);
            },
            child: Text(action.label),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.pop(sheetContext),
        child: const Text('Cancel'),
      ),
    ),
  );
}
