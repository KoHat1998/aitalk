// lib/ui/screens/image_viewer_screen.dart
import 'package:flutter/material.dart';

class ImageViewerScreen extends StatelessWidget {
  final String url;
  final String? title;
  final String? heroTag;

  const ImageViewerScreen({
    super.key,
    required this.url,
    this.title,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title ?? 'Image'),
      ),
      body: Center(
        child: Hero(
          tag: heroTag ?? url,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, event) {
                if (event == null) return child;
                final total = event.expectedTotalBytes;
                final loaded = event.cumulativeBytesLoaded;
                final value = total != null ? loaded / total : null;
                return SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator(value: value)),
                );
              },
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image,
                color: Colors.white70,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}