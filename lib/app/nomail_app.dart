import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../state/app_controller.dart';
import '../ui/screens/shell_screen.dart';
import '../ui/screens/sign_in_screen.dart';

class NoMailApp extends StatelessWidget {
  const NoMailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: 'NoMail',
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        // Brightness left null: follows the system, like a native app.
        primaryColor: CupertinoColors.activeBlue,
      ),
      home: Consumer<AppController>(
        builder: (context, app, _) {
          switch (app.phase) {
            case AppPhase.booting:
              return const CupertinoPageScaffold(
                backgroundColor: CupertinoColors.systemGroupedBackground,
                child: Center(child: CupertinoActivityIndicator()),
              );
            case AppPhase.signedOut:
              return const SignInScreen();
            case AppPhase.syncing:
            case AppPhase.ready:
              return const ShellScreen();
          }
        },
      ),
    );
  }
}
