// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/app_theme.dart';
import 'core/app_routes.dart';
import 'core/push_service.dart';
import 'core/push_route_handler.dart'; // pushNavKey + handlePushRoute

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  Env.assertConfigured();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  // Initialize FCM/local notifications and wire deep links
  await PushService.init(
    onOpenRoute: handlePushRoute, // parses "/call" and "/thread/<id>"
    onForegroundMessage: (_) {
      // No system banner for foreground messages; update badges/UI if desired.
    },
  );

  // Light icons on a dark UI
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light, // Android
    statusBarBrightness: Brightness.dark,      // iOS
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const AiTalkApp());
}

class AiTalkApp extends StatelessWidget {
  const AiTalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI TALK',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      onGenerateRoute: AppRoutes.onGenerateRoute,
      initialRoute: AppRoutes.splash,
      navigatorKey: pushNavKey, // global key used by push route handler
    );
  }
}
