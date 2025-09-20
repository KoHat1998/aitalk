
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/storage_utils.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _contentController = TextEditingController();
  bool _isLoading = false;
  XFile? _selectedImageFile;
  final ImagePicker _picker = ImagePicker();

  String? get currentLoggedInUserId {
    // This gets the ID of the user authenticated via Supabase Auth
    return _supabase.auth.currentUser?.id;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1000, // Optional: resize image to save space and upload time
        imageQuality: 85, // Optional: compress image
      );
      if (pickedFile != null) {
        setState(() {
          _selectedImageFile = pickedFile;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Photo Library'),
                  onTap: () {
                    _pickImage(ImageSource.gallery);
                    Navigator.of(context).pop();
                  }),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Camera'),
                onTap: () {
                  _pickImage(ImageSource.camera);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }


  Future<void> _submitPost() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Check for authenticated user (important before calling utility function if it doesn't do its own check)
    // The utility function `uploadImageToSupabase` already checks for an authenticated user.
    // However, for the database insert of the post itself, we still need the user ID.
    final String? currentAuthUserId = _supabase.auth.currentUser?.id;
    if (currentAuthUserId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be logged in to create a post.'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    setState(() { _isLoading = true; });

    String? uploadedImageUrl;

    // 1. Upload image if selected
    if (_selectedImageFile != null) {
      //                                 Pass context VVVVVVV
      uploadedImageUrl = await uploadImageToSupabase(context, _selectedImageFile!, 'post_images');
      if (uploadedImageUrl == null && mounted) {
        // Error message is already shown by uploadImageToSupabase if context was mounted
        // You might just want to stop loading and return
        setState(() { _isLoading = false; });
        return;
      }
    }

    // 2. Insert post data
    try {
      await _supabase.from('posts').insert({
        'user_id': currentAuthUserId, // Use the authenticated user's ID
        'content': _contentController.text.isEmpty && uploadedImageUrl != null ? null : _contentController.text,
        'image_url': uploadedImageUrl,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post created successfully!')),
        );
        Navigator.pop(context, true); // Signal success to refresh feed
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create post: ${e.message}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An unexpected error occurred: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }


  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Post'),
      ),
      body: SingleChildScrollView( // Added SingleChildScrollView
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _contentController,
                decoration: const InputDecoration(
                  labelText: 'What\'s on your mind?',
                  border: OutlineInputBorder(),
                  hintText: 'Write something or just post an image...',
                ),
                maxLines: 5,
                validator: (value) {
                  // Content is optional if an image is selected
                  if (_selectedImageFile == null && (value == null || value.trim().isEmpty)) {
                    return 'Please enter some content or select an image.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 15),

              // --- Image Picker and Preview ---
              if (_selectedImageFile != null)
                Column(
                  children: [
                    Text("Selected Image:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Image.file(
                      File(_selectedImageFile!.path),
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.clear, color: Colors.red),
                      label: const Text('Remove Image', style: TextStyle(color: Colors.red)),
                      onPressed: () {
                        setState(() {
                          _selectedImageFile = null;
                        });
                      },
                    ),
                    const SizedBox(height: 15),
                  ],
                ),

              OutlinedButton.icon(
                icon: const Icon(Icons.image_search),
                label: Text(_selectedImageFile == null ? 'Add Image' : 'Change Image'),
                onPressed: () => _showImageSourceActionSheet(context),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    textStyle: const TextStyle(fontSize: 16)
                ),
              ),
              // --- End Image Picker and Preview ---

              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitPost,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  // backgroundColor: Theme.of(context).primaryColor, // Optional: for theming
                  // foregroundColor: Colors.white, // Optional: for theming
                ),
                child: _isLoading
                    ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ))
                    : const Text('Post', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

