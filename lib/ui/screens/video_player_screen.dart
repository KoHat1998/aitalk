// lib/ui/screens/video_player_screen.dart
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String url;
  final String? title;
  const VideoPlayerScreen({super.key, required this.url, this.title});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _controller;
  bool _showControls = true;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.url)..setLooping(true);
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      setState(() {});
      await _controller.play();
    } catch (_) {
      if (!mounted) return;
      setState(() {});
    }
    _controller.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  String _fmt(Duration? d) {
    if (d == null) return '--:--';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final v = _controller.value;
    final initialized = v.isInitialized;
    final aspect = initialized ? (v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio) : 16 / 9;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'Video')),
      body: Center(
        child: initialized
            ? Stack(
          alignment: Alignment.bottomCenter,
          children: [
            GestureDetector(
              onTap: () => setState(() => _showControls = !_showControls),
              child: AspectRatio(
                aspectRatio: aspect,
                child: VideoPlayer(_controller),
              ),
            ),
            if (_showControls)
              _Controls(
                controller: _controller,
                fmt: _fmt,
                muted: _muted,
                onToggleMute: () {
                  setState(() {
                    _muted = !_muted;
                    _controller.setVolume(_muted ? 0.0 : 1.0);
                  });
                },
              ),
          ],
        )
            : v.hasError
            ? Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'Video error:\n${v.errorDescription ?? 'Unknown error'}',
            textAlign: TextAlign.center,
          ),
        )
            : const SizedBox(
          height: 220,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final VideoPlayerController controller;
  final String Function(Duration?) fmt;
  final bool muted;
  final VoidCallback onToggleMute;

  const _Controls({
    required this.controller,
    required this.fmt,
    required this.muted,
    required this.onToggleMute,
  });

  @override
  Widget build(BuildContext context) {
    final v = controller.value;
    final pos = v.position;
    final dur = v.duration;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      color: Colors.black54,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: v.isPlaying ? 'Pause' : 'Play',
                icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                onPressed: () => v.isPlaying ? controller.pause() : controller.play(),
              ),
              IconButton(
                tooltip: muted ? 'Unmute' : 'Mute',
                icon: Icon(muted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                onPressed: onToggleMute,
              ),
              const SizedBox(width: 6),
              Text(fmt(pos), style: const TextStyle(color: Colors.white)),
              const Spacer(),
              Text(fmt(dur), style: const TextStyle(color: Colors.white)),
              const SizedBox(width: 8),
              PopupMenuButton<double>(
                tooltip: 'Speed',
                icon: const Icon(Icons.speed, color: Colors.white),
                onSelected: (s) => controller.setPlaybackSpeed(s),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 0.5, child: Text('0.5x')),
                  PopupMenuItem(value: 1.0, child: Text('1.0x')),
                  PopupMenuItem(value: 1.25, child: Text('1.25x')),
                  PopupMenuItem(value: 1.5, child: Text('1.5x')),
                  PopupMenuItem(value: 2.0, child: Text('2.0x')),
                ],
              ),
            ],
          ),
          VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            colors: VideoProgressColors(
              playedColor: Theme.of(context).colorScheme.primary,
              bufferedColor: Colors.white70,
              backgroundColor: Colors.white24,
            ),
          ),
        ],
      ),
    );
  }
}
