import 'dart:core';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

String? extractPathFromUrl(String url) {
  try {
    final uri = Uri.parse(url);
    // Example path in URL: /storage/v1/object/public/post_images/public/user_id_folder/image.jpg
    // We want to extract: public/user_id_folder/image.jpg
    List<String> segments = uri.pathSegments;
    int bucketNameIndex = segments.indexOf('post_images'); // Your bucket name

    if (bucketNameIndex != -1 && bucketNameIndex < segments.length -1) {
      // The path inside the bucket starts after the bucket name segment
      return segments.sublist(bucketNameIndex + 1).join('/');
    }
  } catch (e) {
    print("Error parsing URL for storage path: $e");
  }
  return null;
}

Future<String?> uploadImageToSupabase(
    BuildContext context, // To show SnackBars
    XFile imageFile,
    String bucketName, // e.g., 'post_images'
        {SupabaseClient? client} // Optional: pass Supabase client if not using instance
    ) async {
  final supabase = client ?? Supabase.instance.client;
  final String? currentAuthUserId = supabase.auth.currentUser?.id;

  if (currentAuthUserId == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: User not authenticated for image upload.')),
      );
    }
    print('Image Upload Error: User not authenticated.');
    return null;
  }

  try {
    final String fileName = '${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';
    final String storagePath = 'public/$currentAuthUserId/$fileName'; // Uses current authenticated user

    await supabase.storage
        .from(bucketName)
        .upload(
      storagePath,
      File(imageFile.path),
      fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
    );

    final String publicUrl = supabase.storage
        .from(bucketName)
        .getPublicUrl(storagePath);

    return publicUrl;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading image: $e')),
      );
    }
    print('Image Upload Error: $e');
    return null;
  }
}
