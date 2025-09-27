// lib/main.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/app_theme.dart';
import 'core/app_routes.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/env.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// Push
import 'core/push_service.dart';
import 'core/push_token.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();

  await dotenv.load(fileName: '.env');
  Env.assertConfigured();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  // Initialize push (channels, permissions, handlers)
  await PushService.init(
    onOpenRoute: (route) {
      final ctx = navigatorKey.currentState?.context;
      if (ctx != null && route.isNotEmpty) {
        Navigator.of(ctx).pushNamed(route);
      }
    },
  );

  // If already logged in, store this device's token
  final user = Supabase.instance.client.auth.currentUser;
  if (user != null) {
    try {
      await PushToken.registerForCurrentUser(
        platform: Platform.isAndroid
            ? 'android'
            : Platform.isIOS
            ? 'ios'
            : 'other',
      );
    } catch (_) {}
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
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
      navigatorKey: navigatorKey,
    );
  }
}
