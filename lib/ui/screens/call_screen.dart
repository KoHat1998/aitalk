import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../core/env.dart';
import '../widgets/round_icon_button.dart';

class CallArgs {
  final String threadId;
  final String title;
  final bool video;
  final String? inviteId; // used to sync end state
  const CallArgs({
    required this.threadId,
    this.title = 'Video Call',
    this.video = true,
    this.inviteId,
  });
}

class CallScreen extends StatefulWidget {
  final CallArgs args;
  const CallScreen({super.key, required this.args});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _sb = Supabase.instance.client;

  Room? _room;
  CancelListenFunc? _cancelEvents;

  bool _connecting = true;
  bool _joining = false;     // ← NEW: track connect in-flight
  bool _micOn = true;
  bool _camOn = true;
  bool _frontCam = true;
  bool _flipping = false;

  // Keep a direct ref to the currently published local camera track & a key for renderer refresh
  LocalVideoTrack? _localCamTrack;
  Key _localRendererKey = const ValueKey('local_init');

  // Invite syncing
  RealtimeChannel? _inviteChan;
  String? get _inviteId => widget.args.inviteId;
  bool _ending = false;
  Timer? _autoEndTimer;

  @override
  void initState() {
    super.initState();
    _subscribeInvite();
    _join();
  }

  @override
  void dispose() {
    _ending = true; // stop UI updates
    _autoEndTimer?.cancel();
    if (_inviteChan != null) _sb.removeChannel(_inviteChan!);
    _cancelEvents?.call();
    _room?.dispose();
    super.dispose();
  }

  void _subscribeInvite() {
    if (_inviteId == null) return;
    _inviteChan = _sb
        .channel('realtime:call_invites:${_inviteId!}')
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'call_invites',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: _inviteId!,
      ),
      callback: (payload) {
        final status = payload.newRecord?['status'] as String?;
        if (status == null) return;
        if (status == 'ended' || status == 'canceled' || status == 'declined' || status == 'timeout') {
          _remoteEnded();
        }
      },
    )
        .subscribe();
  }

  Future<void> _setInviteStatus(String status) async {
    if (_inviteId == null) return;
    try {
      await _sb.from('call_invites').update({'status': status}).eq('id', _inviteId!);
    } catch (_) {}
  }

  Future<void> _join() async {
    if (_ending) return;
    setState(() {
      _connecting = true;
      _joining = true;
    });
    try {
      // Permissions
      final req = <Permission>[Permission.microphone];
      if (widget.args.video) req.add(Permission.camera);
      final statuses = await req.request();
      if (statuses.values.any((s) => s != PermissionStatus.granted)) {
        throw Exception('Required permissions denied');
      }
      if (_ending) return; // user hung up during permission dialog

      // Edge function for LiveKit token
      final resp = await _sb.functions.invoke(
        'lk_token',
        body: {'threadId': widget.args.threadId, 'video': widget.args.video},
      );
      final data = resp.data;
      final token = (data is Map && data['token'] is String)
          ? (data['token'] as String)
          : (data is String ? data : null);
      if (token == null || token.isEmpty) {
        throw Exception('No token from lk_token');
      }
      if (_ending) return; // user hung up while fetching token

      final room = Room();

      _cancelEvents = room.events.listen((event) {
        if (!mounted || _ending) return;
        setState(() {}); // refresh UI on any event
        _syncLocalCamRef();
        // If remotes disappear, end shortly after
        _autoEndTimer?.cancel();
        _autoEndTimer = Timer(const Duration(seconds: 2), () {
          if (!mounted || _ending) return;
          if (room.remoteParticipants.isEmpty) {
            _remoteEnded();
          }
        });
      });

      await room.connect(
        Env.livekitHost,
        token,
        connectOptions: const ConnectOptions(autoSubscribe: true),
      );
      if (_ending) {
        try { await room.disconnect(); } catch (_) {}
        return; // we’ll pop in hangup path
      }

      await room.localParticipant?.setMicrophoneEnabled(true);
      if (widget.args.video) {
        await room.localParticipant?.setCameraEnabled(
          true,
          cameraCaptureOptions: const CameraCaptureOptions(
            cameraPosition: CameraPosition.front,
          ),
        );
        _frontCam = true;
      } else {
        _camOn = false;
      }

      _room = room;
      _syncLocalCamRef();

      if (!mounted || _ending) return;
      setState(() => _connecting = false);
    } catch (e) {
      if (!mounted || _ending) return;
      setState(() => _connecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to join: $e')),
      );
      _popSafe(); // ensure we don’t get stuck
    } finally {
      _joining = false;
    }
  }

  void _syncLocalCamRef() {
    final lp = _room?.localParticipant;
    if (lp == null) {
      _localCamTrack = null;
      return;
    }
    for (final pub in lp.videoTrackPublications) {
      if (pub.source == TrackSource.camera && pub.track is LocalVideoTrack) {
        _localCamTrack = pub.track as LocalVideoTrack;
        return;
      }
    }
    _localCamTrack = null;
  }

  Future<void> _remoteEnded() async {
    if (_ending) return;
    _ending = true;
    await _teardown();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Call ended')));
    _popSafe();
  }

  Future<void> _toggleMic() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    final next = !_micOn;
    await lp.setMicrophoneEnabled(next);
    if (mounted && !_ending) setState(() => _micOn = next);
  }

  Future<void> _toggleCam() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    final next = !_camOn;
    await lp.setCameraEnabled(
      next,
      cameraCaptureOptions: CameraCaptureOptions(
        cameraPosition: _frontCam ? CameraPosition.front : CameraPosition.back,
      ),
    );
    _syncLocalCamRef();
    if (mounted && !_ending) setState(() => _camOn = next);
  }

  // Preferred flip: restart existing track; fallback to unpublish/publish.
  Future<void> _flipCam() async {
    final lp = _room?.localParticipant;
    if (lp == null || _flipping || !_camOn || _ending) return;

    _flipping = true;
    final desired = _frontCam ? CameraPosition.back : CameraPosition.front;

    try {
      _syncLocalCamRef();
      if (_localCamTrack != null) {
        await Future.delayed(const Duration(milliseconds: 60));
        await _localCamTrack!.restartTrack(
          CameraCaptureOptions(cameraPosition: desired),
        );
        _frontCam = !_frontCam;
        _localRendererKey = ValueKey('local_${DateTime.now().microsecondsSinceEpoch}');
        if (mounted && !_ending) setState(() {});
        return;
      }
    } catch (_) {
      // continue to hard switch
    } finally {
      _flipping = false;
    }

    // Hard switch fallback
    _flipping = true;
    try {
      LocalVideoTrack? oldTrack;
      TrackPublication? oldPub;
      for (final pub in lp.videoTrackPublications) {
        if (pub.source == TrackSource.camera && pub.track is LocalVideoTrack) {
          oldTrack = pub.track as LocalVideoTrack;
          oldPub = pub;
          break;
        }
      }

      if (oldTrack != null) {
        final dynLp = lp as dynamic;
        try {
          await dynLp.unpublishTrack(oldPub, stopOnUnpublish: true);
        } catch (_) {
          try { await dynLp.unpublishTrack(oldTrack, stopOnUnpublish: true); } catch (_) {
            try { await dynLp.unpublishTrack(oldTrack); } catch (_) {}
            try { await (oldTrack as dynamic).stop?.call(); } catch (_) {}
          }
        }
      } else {
        try { await lp.setCameraEnabled(false); } catch (_) {}
      }

      await Future.delayed(const Duration(milliseconds: 100));
      final newTrack = await LocalVideoTrack.createCameraTrack(
        CameraCaptureOptions(cameraPosition: desired),
      );

      try {
        await lp.publishVideoTrack(newTrack);
      } catch (_) {
        try {
          await lp.setCameraEnabled(
            true,
            cameraCaptureOptions: CameraCaptureOptions(cameraPosition: desired),
          );
        } finally {
          try { await (newTrack as dynamic).stop?.call(); } catch (_) {}
        }
      }

      _frontCam = !_frontCam;
      _camOn = true;
      _syncLocalCamRef();
      _localRendererKey = ValueKey('local_${DateTime.now().microsecondsSinceEpoch}');
      if (mounted && !_ending) setState(() {});
    } catch (e) {
      if (mounted && !_ending) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Flip failed: $e')));
      }
    } finally {
      _flipping = false;
    }
  }

  Future<void> _hangup() async {
    if (_ending) return;
    _ending = true;
    await _setInviteStatus('ended');    // notify other side
    await _teardown();                  // fully release resources first
    _popSafe();                         // then navigate away
  }

  Future<void> _teardown() async {
    // Stop listeners first to prevent setState after dispose/pop
    _autoEndTimer?.cancel(); _autoEndTimer = null;
    _cancelEvents?.call(); _cancelEvents = null;
    if (_inviteChan != null) { _sb.removeChannel(_inviteChan!); _inviteChan = null; }

    // If join is in-flight, try to stop camera early to avoid HAL locks
    if (_joining) {
      try { await _room?.localParticipant?.setCameraEnabled(false); } catch (_) {}
    }

    try { await _room?.disconnect(); } catch (_) {}
    _room?.dispose(); _room = null;
  }

  Future<void> _popSafe() async {
    if (!mounted) return;
    // Delay pop to get out of frame callbacks from LiveKit
    await Future.delayed(const Duration(milliseconds: 10));
    final popped = await Navigator.maybePop(context);
    if (!popped && mounted) {
      // Fall back to your home/shell if nothing to pop
      Navigator.pushNamedAndRemoveUntil(context, '/shell', (r) => false);
    }
  }

  List<Participant> _remotes() => (_room?.remoteParticipants.values.toList() ?? const []);

  lk.VideoTrack? _firstCameraTrack(Participant p) {
    for (final pub in p.videoTrackPublications) {
      if (pub.source == TrackSource.camera) {
        final t = pub.track;
        if (t is lk.VideoTrack && (p is LocalParticipant || pub.subscribed == true)) {
          return t;
        }
      }
    }
    for (final pub in p.videoTrackPublications) {
      final t = pub.track;
      if (t is lk.VideoTrack && (p is LocalParticipant || pub.subscribed == true)) {
        return t;
      }
    }
    return null;
  }

  (Participant? p, lk.VideoTrack?) _primaryTrackRemoteOnly() {
    final rs = _remotes();
    for (final r in rs) {
      final t = _firstCameraTrack(r);
      if (t != null) return (r, t);
    }
    return (null, null);
  }

  @override
  Widget build(BuildContext context) {
    final (primaryP, primaryT) = _primaryTrackRemoteOnly();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.args.title),
        leading: IconButton(icon: const Icon(Icons.chevron_left), onPressed: _hangup),
      ),
      body: Stack(
        children: [
          // Full-screen remote (black until joined)
          Positioned.fill(
            child: _connecting
                ? const Center(child: CircularProgressIndicator())
                : (primaryT != null
                ? FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: 1280,
                height: 720,
                child: ClipRect(child: lk.VideoTrackRenderer(primaryT)),
              ),
            )
                : const ColoredBox(color: Colors.black)),
          ),

          // Local PIP
          if (!_connecting && _camOn && _localCamTrack != null)
            Positioned(
              right: 12,
              bottom: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 120,
                  height: 180,
                  color: Colors.black,
                  child: lk.VideoTrackRenderer(
                    _localCamTrack!,
                    key: _localRendererKey, // refresh on flip/new track
                  ),
                ),
              ),
            ),

          // Controls
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    RoundIconButton(icon: _micOn ? Icons.mic : Icons.mic_off, onTap: _toggleMic),
                    const SizedBox(width: 16),
                    RoundIconButton(icon: _camOn ? Icons.videocam : Icons.videocam_off, onTap: _toggleCam),
                    const SizedBox(width: 16),
                    RoundIconButton(icon: Icons.switch_camera, onTap: _flipCam),
                    const SizedBox(width: 16),
                    RoundIconButton(icon: Icons.call_end, bg: Colors.red, fg: Colors.white, onTap: _hangup),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
