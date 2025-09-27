import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/env.dart';
import 'core/app_theme.dart';
import 'core/app_routes.dart';
import 'core/push_service.dart';

// A global navigator so PushService.onOpenRoute can push named routes from anywhere.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  Env.assertConfigured();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  // ✅ Initialize push once, with deep-link handler
  await PushService.init(
    onOpenRoute: (route) {
      // Expecting routes like: /incoming_call?callId=...&thread=...
      navigatorKey.currentState?.pushNamed(route);
    },
    onForegroundMessage: (_) {
      // no banner for messages in-foreground; refresh UI/badge if you want
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
      navigatorKey: navigatorKey, // ✅ allow PushService to navigate
    );
  }
}
