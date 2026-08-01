import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'app/nomail_app.dart';
import 'state/app_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // No .env bundled — sign-in and AI stay unconfigured; demo still works.
    dotenv.testLoad(fileInput: '');
  }

  final controller = AppController();
  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const NoMailApp(),
    ),
  );
  controller.init();
}
