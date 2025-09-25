// lib/ui/screens/group_room_screen.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import '../../core/env.dart'; // exposes Env.livekitHost (from your .env)

/*
  Usage:
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => GroupRoomScreen(
        threadId: '<thread-id>',
        title: 'Team Standup',
        video: true,   // join with camera enabled
        audio: true,   // join with microphone enabled
      ),
    ),
  );
*/

class GroupRoomScreen extends StatefulWidget {
  final String threadId;
  final String title;
  final bool video; // start with local camera ON
  final bool audio; // start with local mic ON

  const GroupRoomScreen({
    super.key,
    required this.threadId,
    required this.title,
    this.video = true,
    this.audio = true,
  });

  @override
  State<GroupRoomScreen> createState() => _GroupRoomScreenState();
}

class _GroupRoomScreenState extends State<GroupRoomScreen> {
  final _sb = Supabase.instance.client;

  Room? _room;
  bool _connecting = true;
  String? _error;

  bool _micEnabled = true;
  bool _camEnabled = true;
  CameraPosition _camPos = CameraPosition.front;

  @override
  void initState() {
    super.initState();
    _join();
  }

  @override
  void dispose() {
    _room?.removeListener(_onRoomChanged);
    _room?.dispose();
    super.dispose();
  }

  // ---------- Join flow ----------
  Future<void> _join() async {
    setState(() {
      _connecting = true;
      _error = null;
    });

    try {
      // 1) Fetch LiveKit access token from your Edge Function
      final resp = await _sb.functions.invoke('lk_token', body: {
        'threadId': widget.threadId,
      });
      final data = resp.data;
      final token = (data is Map && data['token'] is String)
          ? data['token'] as String
          : null;
      if (token == null || token.isEmpty) {
        throw Exception('Token missing from lk_token response');
      }

      // 2) Permissions (mobile)
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await _ensureCallPermissions(needCamera: widget.video);
      }

      // 3) Connect to LiveKit room
      final livekitUrl = Env.livekitHost.trim();
      if (livekitUrl.isEmpty || !livekitUrl.startsWith('wss://')) {
        throw Exception('LIVEKIT_HOST is missing or must be a wss:// URL in .env');
      }

      final room = Room();
      await room.connect(
        livekitUrl,
        token,
        roomOptions: RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultCameraCaptureOptions: const CameraCaptureOptions(
            cameraPosition: CameraPosition.front,
          ),
          // Correct prop name:
          defaultAudioCaptureOptions: const AudioCaptureOptions(),
        ),
        connectOptions: const ConnectOptions(
          autoSubscribe: true, // subscribe to remote tracks automatically
        ),
      );

      // Web browsers often require a user gesture to start audio playback.
      if (kIsWeb) {
        await room.startAudio();
      } else if (Platform.isAndroid || Platform.isIOS) {
        // Route audio to the loud-speaker so you can hear the call
        await rtc.Helper.setSpeakerphoneOn(true);
      }

      // 4) Initial local state (respect widget flags)
      _micEnabled = widget.audio;
      _camEnabled = widget.video;

      await room.localParticipant?.setMicrophoneEnabled(_micEnabled);
      await room.localParticipant?.setCameraEnabled(_camEnabled);

      // 5) Listen for room updates
      room.addListener(_onRoomChanged);

      setState(() {
        _room = room;
        _connecting = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _connecting = false;
      });
    }
  }

  void _onRoomChanged() {
    if (mounted) setState(() {});
  }

  // ---------- Actions ----------
  Future<void> _toggleMic() async {
    final room = _room;
    if (room == null) return;
    final next = !_micEnabled;
    try {
      await room.localParticipant?.setMicrophoneEnabled(next);
      setState(() => _micEnabled = next);
    } catch (_) {}
  }

  Future<void> _toggleCam() async {
    final room = _room;
    if (room == null) return;
    final next = !_camEnabled;
    try {
      await room.localParticipant?.setCameraEnabled(next);
      setState(() => _camEnabled = next);
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    final room = _room;
    if (room == null) return;

    try {
      final lp = room.localParticipant;
      if (lp == null) return;

      LocalVideoTrack? localCam;
      for (final pub in lp.videoTrackPublications) {
        final t = pub.track;
        if (t is LocalVideoTrack) {
          localCam = t;
          break;
        }
      }

      if (localCam != null) {
        final next = _camPos == CameraPosition.front
            ? CameraPosition.back
            : CameraPosition.front;
        await localCam.setCameraPosition(next);
        setState(() => _camPos = next);
      }
    } catch (_) {}
  }

  Future<void> _leave() async {
    try {
      await _room?.disconnect();
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  // ---------- Permissions ----------
  Future<void> _ensureCallPermissions({required bool needCamera}) async {
    if (kIsWeb) return; // browser prompts as needed
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    final req = <Permission>[
      Permission.microphone,
      if (needCamera) Permission.camera,
    ];

    final results = await req.request();

    bool denied(Permission p) {
      final s = results[p];
      return s == null ||
          s.isDenied ||
          s.isPermanentlyDenied ||
          s.isRestricted ||
          s.isLimited;
    }

    if (denied(Permission.microphone) ||
        (needCamera && denied(Permission.camera))) {
      throw Exception('Camera/Microphone permission not granted');
    }
  }

  // ---------- Helpers ----------
  List<Participant> _allParticipants() {
    final room = _room;
    if (room == null) return const [];

    final list = <Participant>[];

    final lp = room.localParticipant;
    if (lp != null) list.add(lp);

    list.addAll(room.remoteParticipants.values);
    return list;
  }

  String _labelFor(Participant p) {
    // LiveKit sets 'name' from the token's 'name' claim. Fallback to identity.
    final name = (p.name.isNotEmpty ? p.name : p.identity).trim();
    return name.isNotEmpty ? name : 'User';
  }

  VideoTrack? _firstVideoTrack(Participant p) {
    for (final pub in p.videoTrackPublications) {
      final t = pub.track;
      if (t is VideoTrack) return t;
    }
    return null;
  }

  int _gridCrossAxisCount(int count) {
    if (count <= 1) return 1;
    if (count <= 4) return 2;
    if (count <= 9) return 3;
    return 4;
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final participants = _allParticipants();
    final count = participants.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.title} ($count)'),
        actions: [
          IconButton(
            tooltip: 'Participants',
            icon: const Icon(Icons.group),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                showDragHandle: true,
                builder: (_) => SafeArea(
                  child: _ParticipantsSheet(
                    participants: participants,
                    labelFor: _labelFor,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: _connecting
          ? const Center(child: CircularProgressIndicator())
          : (_error != null
          ? _ErrorView(error: _error!, onRetry: _join)
          : Stack(
        children: [
          // Video grid
          Positioned.fill(
            child: count == 0
                ? const Center(
              child: Text(
                'Waiting for others…',
                style: TextStyle(color: Colors.white70),
              ),
            )
                : GridView.builder(
              padding:
              const EdgeInsets.fromLTRB(12, 12, 12, 120),
              gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _gridCrossAxisCount(count),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 9 / 16,
              ),
              itemCount: count,
              itemBuilder: (_, i) {
                final p = participants[i];
                final vTrack = _firstVideoTrack(p);
                final isLocal =
                identical(p, _room?.localParticipant);
                return _ParticipantTile(
                  participant: p,
                  track: vTrack,
                  label: _labelFor(p),
                  isLocal: isLocal,
                );
              },
            ),
          ),
          // Bottom controls
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding:
                const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _ControlsBar(
                  micOn: _micEnabled,
                  camOn: _camEnabled,
                  onToggleMic: _toggleMic,
                  onToggleCam: _toggleCam,
                  onFlipCam: _switchCamera,
                  onLeave: _leave,
                ),
              ),
            ),
          ),
        ],
      )),
    );
  }
}

// ---------- UI pieces ----------

class _ParticipantTile extends StatelessWidget {
  final Participant participant;
  final VideoTrack? track;
  final String label;
  final bool isLocal;

  const _ParticipantTile({
    required this.participant,
    required this.track,
    required this.label,
    required this.isLocal,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
    participant.isSpeaking ? Colors.greenAccent : Colors.white24;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video or placeholder
          if (track != null)
            VideoTrackRenderer(
              track!, // positional arg in livekit_client
              fit: VideoViewFit.cover,
            )
          else
            Container(
              color: Colors.blueGrey.shade900,
              child: Center(
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.blueGrey.shade700,
                  child: Text(
                    label.isNotEmpty ? label[0].toUpperCase() : 'U',
                    style: const TextStyle(fontSize: 22, color: Colors.white),
                  ),
                ),
              ),
            ),

          // Name & "you" badge
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor, width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isLocal)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Text(
                        'you',
                        style:
                        TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlsBar extends StatelessWidget {
  final bool micOn;
  final bool camOn;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCam;
  final VoidCallback onFlipCam;
  final VoidCallback onLeave;

  const _ControlsBar({
    required this.micOn,
    required this.camOn,
    required this.onToggleMic,
    required this.onToggleCam,
    required this.onFlipCam,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surface;
    return Material(
      elevation: 8,
      color: color.withOpacity(0.98),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _roundBtn(
              icon: micOn ? Icons.mic : Icons.mic_off,
              onTap: onToggleMic,
              tooltip: micOn ? 'Mute mic' : 'Unmute mic',
            ),
            const SizedBox(width: 8),
            _roundBtn(
              icon: camOn ? Icons.videocam : Icons.videocam_off,
              onTap: onToggleCam,
              tooltip: camOn ? 'Turn camera off' : 'Turn camera on',
            ),
            const SizedBox(width: 8),
            _roundBtn(
              icon: Icons.cameraswitch,
              onTap: onFlipCam,
              tooltip: 'Switch camera',
            ),
            const Spacer(),
            _roundBtn(
              icon: Icons.call_end,
              onTap: onLeave,
              tooltip: 'Leave',
              bg: Colors.red,
              fg: Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundBtn({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    Color? bg,
    Color? fg,
  }) {
    return Tooltip(
      message: tooltip,
      child: Ink(
        decoration: ShapeDecoration(
          color: bg ?? Colors.black12,
          shape: const CircleBorder(),
        ),
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, color: fg ?? Colors.black87),
        ),
      ),
    );
  }
}

class _ParticipantsSheet extends StatelessWidget {
  final List<Participant> participants;
  final String Function(Participant) labelFor;

  const _ParticipantsSheet({
    required this.participants,
    required this.labelFor,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: participants.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final p = participants[i];
        final isLocal = p is LocalParticipant;
        final speaking = p.isSpeaking;
        final label = labelFor(p);
        return ListTile(
          leading: CircleAvatar(
            child:
            Text((label.isNotEmpty ? label[0] : 'U').toUpperCase()),
          ),
          title:
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(isLocal ? 'You' : (speaking ? 'Speaking' : '')),
          trailing:
          speaking ? const Icon(Icons.volume_up, size: 18) : null,
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded,
                size: 42, color: Colors.amber),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
