// lib/ui/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_routes.dart';
import '../../core/push_route_handler.dart'; // markPushRoutingReady()

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    // tiny delay so the spinner shows (optional)
    await Future.delayed(const Duration(milliseconds: 300));

    // ⬅️ IMPORTANT: await the Future<bool>
    final consumed = await markPushRoutingReady();
    if (consumed) return; // deep link (thread/call) already navigated

    // No deep link handled — proceed to your normal start destination
    final session = Supabase.instance.client.auth.currentSession;
    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      session != null ? AppRoutes.shell : AppRoutes.signIn,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('AI Talk', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
            SizedBox(height: 16),
            SizedBox(width: 100, height: 100, child: CircularProgressIndicator(strokeWidth: 3)),
          ],
        ),
      ),
    );
  }
}
