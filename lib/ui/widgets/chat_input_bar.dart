import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSendText,
    required this.onSendFiles,
    required this.onSendLocation,
    this.hintText = 'Type your message…', required bool enabled,
  });

  final void Function(String text) onSendText;
  final void Function(List<File> files) onSendFiles;

  /// Awaitable so UI can disable while sending location.
  final Future<void> Function({
  required double lat,
  required double lng,
  double? accuracyM,
  }) onSendLocation;

  final String hintText;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  bool _sendingText = false;
  bool _busyAttachOrLocation = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _openAttachMenu() async {
    if (_busyAttachOrLocation) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Media (photo/video)'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickFiles(type: FileType.media);
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('File'),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickFiles(type: FileType.any);
              },
            ),
            ListTile(
              leading: const Icon(Icons.my_location_outlined),
              title: const Text('Share location'),
              onTap: () async {
                Navigator.pop(ctx);
                await _shareLocation();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFiles({required FileType type}) async {
    if (!mounted || _busyAttachOrLocation) return;
    setState(() => _busyAttachOrLocation = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: type,
        withData: true, // <-- critical for content:// URIs
      );
      if (result == null || result.files.isEmpty) return;

      final tempDir = await getTemporaryDirectory();
      final List<File> localFiles = [];

      for (final pf in result.files) {
        if (pf.path != null) {
          // Picker returned a real filesystem path
          localFiles.add(File(pf.path!));
        } else if (pf.bytes != null) {
          // No path (common on Android) -> write bytes to a temp file
          final safeName = pf.name.isNotEmpty ? pf.name : 'file';
          final f = File(
            '${tempDir.path}/${DateTime.now().microsecondsSinceEpoch}_$safeName',
          );
          await f.writeAsBytes(pf.bytes!, flush: true);
          localFiles.add(f);
        }
      }

      if (localFiles.isNotEmpty) {
        widget.onSendFiles(localFiles);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read selected files.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File pick failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyAttachOrLocation = false);
    }
  }


  Future<void> _shareLocation() async {
    if (!mounted || _busyAttachOrLocation) return;
    setState(() => _busyAttachOrLocation = true);

    try {
      final status = await Permission.location.request();
      if (status.isPermanentlyDenied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission permanently denied. Open settings to enable.')),
        );
        await openAppSettings();
        return;
      }
      if (!status.isGranted) return;

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turn on Location Services to share your location.')),
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);

      await widget.onSendLocation(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracyM: pos.accuracy,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share location: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyAttachOrLocation = false);
    }
  }

  Future<void> _sendText() async {
    if (_sendingText) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _sendingText = true);
    try {
      widget.onSendText(text);
      _ctrl.clear();
      _focus.requestFocus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _sendingText = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        color: theme.colorScheme.surface,
        child: Row(
          children: [
            IconButton(
              onPressed: _busyAttachOrLocation ? null : _openAttachMenu,
              icon: _busyAttachOrLocation
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add),
              tooltip: 'Attach',
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 5,
                  decoration: InputDecoration(hintText: widget.hintText, border: InputBorder.none),
                  onSubmitted: (_) => _sendText(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _sendingText ? null : _sendText, icon: const Icon(Icons.send_rounded)),
          ],
        ),
      ),
    );
  }
}
