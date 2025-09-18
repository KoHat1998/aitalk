import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String get supabaseUrl    => dotenv.get('SUPABASE_URL');
  static String get supabaseAnonKey=> dotenv.get('SUPABASE_ANON_KEY');
  static String get livekitHost    => dotenv.get('LIVEKIT_HOST'); // e.g. wss://xxx.livekit.cloud

  static void assertConfigured() {
    for (final k in ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'LIVEKIT_HOST']) {
      assert(dotenv.env[k]?.isNotEmpty == true, 'Missing $k in .env');
    }
  }
}
