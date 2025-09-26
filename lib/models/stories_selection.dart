import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// If you add path_provider for managing file paths more robustly
// import 'package:path_provider/path_provider.dart';

final supabase = Supabase.instance.client;

class StoryCreationService {
  final ImagePicker _picker = ImagePicker();

  Future<void> pickAndUploadStory(BuildContext context, {String? caption}) async {
    // Let user choose image or video (can be separate buttons or a dialog)
    // For simplicity, let's start with image only. You can extend for video.
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    // Or allow camera: await _picker.pickImage(source: ImageSource.camera);
    // For video: await _picker.pickVideo(source: ImageSource.gallery);

    if (pickedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No media selected.')));
      return;
    }

    File mediaFile = File(pickedFile.path);
    String mediaType = 'image'; // Assume image for now
    // if (pickedFile.mimeType?.startsWith('video/') ?? false) { // More robust type checking
    //   mediaType = 'video';
    // }

    // Optional: Show a preview and allow adding a caption before uploading
    // This would typically involve navigating to a new screen or showing a dialog.
    // For now, let's assume caption is passed or empty.

    try {
      // Show loading indicator
      showDialog(context: context, barrierDismissible: false, builder: (_) => Center(child: CircularProgressIndicator()));

      final String userId = supabase.auth.currentUser!.id;
      final String fileExtension = mediaFile.path.split('.').last.toLowerCase();
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      // Path within the bucket: user_id/stories/filename.ext
      // Note: 'public/' prefix is not needed if your bucket is public and you're using .upload() directly to the root path.
      // If your bucket is public, the path for getPublicUrl is just the path you uploaded to.
      final String storagePath = '$userId/stories/$fileName';


      // 1. Upload to Supabase Storage
      await supabase.storage
          .from('stories_media') // Your bucket name
          .upload(
        storagePath,
        mediaFile,
        fileOptions: FileOptions(contentType: 'image/$fileExtension'), // Adjust for video
      );

      // 2. Get the public URL
      final String mediaUrl = supabase.storage
          .from('stories_media')
          .getPublicUrl(storagePath);

      // 3. Insert into 'stories' table
      final expiresAt = DateTime.now().add(const Duration(hours: 24));

      await supabase.from('stories').insert({
        'user_id': userId,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'caption': caption, // If you have a caption field
        'expires_at': expiresAt.toIso8601String(),
        // created_at is default in the DB
      });

      Navigator.pop(context); // Dismiss loading indicator
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Story posted!')));
      // TODO: Refresh the stories list in your UI if needed

    } on StorageException catch (e) {
      Navigator.pop(context); // Dismiss loading indicator
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Storage Error: ${e.message}')));
      print("Story Upload Storage Error: ${e.toString()}");
    } catch (e) {
      Navigator.pop(context); // Dismiss loading indicator
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error posting story: $e')));
      print("Story Upload Generic Error: ${e.toString()}");
    }
  }
}
