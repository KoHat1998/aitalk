import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// You might want a loading overlay package or create a simple one
// e.g., using a Stack and CircularProgressIndicator

class CreateStoryScreen extends StatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  State<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen> {
  final _supabase = Supabase.instance.client;
  final _captionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  XFile? _selectedImageFile;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        setState(() {
          _selectedImageFile = pickedFile;
          _errorMessage = null; // Clear previous error if any
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Error picking image: $e";
        });
      }
    }
  }

  Future<void> _postStory() async {
    if (_selectedImageFile == null) {
      setState(() {
        _errorMessage = "Please select an image for your story.";
      });
      return;
    }
    if (_supabase.auth.currentUser == null) {
      setState(() {
        _errorMessage = "You need to be logged in to post a story.";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final File imageFile = File(_selectedImageFile!.path);
      final String userId = _supabase.auth.currentUser!.id;
      final String fileExtension = imageFile.path.split('.').last.toLowerCase();
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final String storagePath = '$userId/stories/$fileName'; // Path within the bucket

      // 1. Upload to Supabase Storage
      await _supabase.storage
          .from('stories_media') // Your bucket name
          .upload(
        storagePath,
        imageFile,
        fileOptions: FileOptions(contentType: 'image/$fileExtension'), // Be specific with content type
      );

      // 2. Get the public URL
      final String mediaUrl = _supabase.storage
          .from('stories_media')
          .getPublicUrl(storagePath);

      // 3. Insert into 'stories' table
      final String? caption = _captionController.text.trim().isNotEmpty
          ? _captionController.text.trim()
          : null;
      final expiresAt = DateTime.now().add(const Duration(hours: 24));

      await _supabase.from('stories').insert({
        'user_id': userId,
        'media_url': mediaUrl,
        'media_type': 'image', // For now, only image
        'caption': caption,
        'expires_at': expiresAt.toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Story posted successfully!')),
        );
        Navigator.pop(context, true); // Pop with true to indicate success
      }
    } on StorageException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Storage Error: ${e.message}";
          _isLoading = false;
        });
      }
      print("Story Upload Storage Error: ${e.toString()}");
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "An unexpected error occurred: $e";
          _isLoading = false;
        });
      }
      print("Story Upload Generic Error: ${e.toString()}");
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Story'),
        actions: [
          if (_selectedImageFile != null && !_isLoading)
            IconButton(
              icon: const Icon(Icons.check_circle_outline),
              tooltip: 'Post Story',
              onPressed: _postStory,
            ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                  width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (_selectedImageFile == null)
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[400]!),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined, size: 50, color: Colors.grey[600]),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.image_search),
                      label: const Text('Pick from Gallery'),
                      onPressed: () => _pickImage(ImageSource.gallery),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Take a Photo'),
                      onPressed: () => _pickImage(ImageSource.camera),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12.0),
                    child: Image.file(
                      File(_selectedImageFile!.path),
                      fit: BoxFit.contain, // Or BoxFit.cover, adjust as needed
                      height: MediaQuery.of(context).size.height * 0.4, // Adjust height
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Change Image'),
                    onPressed: () => setState(() => _selectedImageFile = null), // Allow re-picking
                  ),
                ],
              ),
            const SizedBox(height: 20),
            TextField(
              controller: _captionController,
              decoration: InputDecoration(
                labelText: 'Add a caption (optional)',
                hintText: 'What\'s on your mind?',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              maxLines: 3,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 20),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            if (_selectedImageFile != null && !_isLoading) // Show post button at bottom too
              ElevatedButton.icon(
                icon: const Icon(Icons.publish_outlined),
                label: const Text('Post Story'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                ),
                onPressed: _postStory,
              ),
            if (_isLoading)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
