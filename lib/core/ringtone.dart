import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class Ringtone {
  static final AudioPlayer _p = AudioPlayer();

  static Future<void> start() async {
    try {
      await _p.stop();
      await _p.setReleaseMode(ReleaseMode.loop);

      // Android-only audio context; keeps speaker on and grabs audio focus
      await _p.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.alarm, // good for ring/alert
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ),
      );

      // Some devices/emulators are picky about the source call—try both forms.
      try {
        await _p.play(AssetSource('assets/ringtone.mp3'), volume: 2.0);
      } catch (_) {
        // Fallback: set source then resume
        await _p.setSource(AssetSource('assets/ringtone.mp3'));
        await _p.setVolume(1.0);
        await _p.resume();
      }
    } catch (e) {
      debugPrint('Ringtone.start error: $e');
    }
  }

  static Future<void> stop() async {
    try {
      await _p.stop();
    } catch (_) {}
  }
}
