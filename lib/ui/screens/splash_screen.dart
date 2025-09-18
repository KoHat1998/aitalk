import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_routes.dart';

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
    // tiny delay so the spinner shows
    await Future.delayed(const Duration(milliseconds: 600));
    final session = Supabase.instance.client.auth.currentSession;

    if (!mounted) return;
    if (session != null) {
      Navigator.pushReplacementNamed(context, AppRoutes.shell);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.signIn);
    }
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
