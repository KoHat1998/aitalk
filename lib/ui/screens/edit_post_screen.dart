// lib/ui/screens/edit_post_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user_post.dart';
import '../../utils/storage_utils.dart'; // Adjust path

class EditPostScreen extends StatefulWidget {
  final UserPost postToEdit;
  const EditPostScreen({super.key, required this.postToEdit});

  @override
  State<EditPostScreen> createState() => _EditPostScreenState();
}

class _EditPostScreenState extends State<EditPostScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _contentController;
  bool _isLoading = false;

  XFile? _selectedImageFile; // For new image selection
  String? _existingImageUrl; // To keep track of current image
  bool _removeCurrentImage = false; // Flag to indicate if existing image should be removed

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.postToEdit.content);
    _existingImageUrl = widget.postToEdit.imageUrl;
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

  Future<void> _deleteStoredImage(String? imageUrl) async {
    if (imageUrl == null || imageUrl.isEmpty) return;
    // Call the utility function for path extraction
    final imagePath = extractPathFromUrl(imageUrl); // <--- Make sure this is from storage_utils.dart
    if (imagePath != null) {
      try {
        await _supabase.storage.from('post_images').remove([imagePath]);
      } catch (e) {
        print("Error deleting previous image from storage: $e");
      }
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    // The utility function `uploadImageToSupabase` checks for an authenticated user.
    // The RLS policy on the 'posts' table update also relies on auth.uid().
    if (_supabase.auth.currentUser == null) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You must be logged in.')));
      return;
    }

    setState(() { _isLoading = true; });

    String? finalImageUrl = _existingImageUrl;
    bool newImageUploadedSuccessfully = false; // Keep track of successful new upload for potential rollback

    try {
      // 1. Handle new image upload
      if (_selectedImageFile != null) {
        //                                      Pass context VVVVVVV
        String? uploadedUrl = await uploadImageToSupabase(context, _selectedImageFile!, 'post_images');

        if (uploadedUrl != null) {
          // If a new image was uploaded successfully, delete the old one (if it exists)
          if (_existingImageUrl != null && _existingImageUrl!.isNotEmpty) {
            await _deleteStoredImage(_existingImageUrl);
          }
          finalImageUrl = uploadedUrl;
          newImageUploadedSuccessfully = true;
        } else {
          // New image selected, but upload failed. Message shown by utility.
          if (mounted) setState(() { _isLoading = false; });
          return; // Don't proceed if critical image upload fails
        }
      } else if (_removeCurrentImage) {
        // User explicitly removed the existing image without selecting a new one
        if (_existingImageUrl != null && _existingImageUrl!.isNotEmpty) {
          await _deleteStoredImage(_existingImageUrl);
        }
        finalImageUrl = null;
      }

      // 2. Update post data in the database
      await _supabase.from('posts').update({
        'content': _contentController.text.isEmpty && finalImageUrl != null ? null : _contentController.text,
        'image_url': finalImageUrl,
      }).eq('id', widget.postToEdit.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post updated successfully!')),
        );
        Navigator.pop(context, true);
      }
    } on PostgrestException catch (e) {
      // If a new image was uploaded successfully but DB update failed,
      // consider deleting the newly uploaded image.
      if (newImageUploadedSuccessfully && finalImageUrl != null && finalImageUrl != _existingImageUrl) {
        print("DB update failed after new image upload. Attempting to delete newly uploaded image: $finalImageUrl");
        await _deleteStoredImage(finalImageUrl); // Try to clean up
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update post: ${e.message}'), backgroundColor: Colors.red),
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
        title: const Text('Edit Post'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _isLoading ? null : _saveChanges,
            tooltip: 'Save Changes',
          )
        ],
      ),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                TextFormField(
                controller: _contentController,
                decoration: const InputDecoration(
                  labelText: 'Your content',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
                validator: (value) {
                  if (_selectedImageFile == null && (_existingImageUrl == null || _existingImageUrl!.isEmpty || _removeCurrentImage) && (value == null || value.trim().isEmpty)) {
                    return 'Please enter content or select an image.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 15),

              // --- Image Display and Picker ---
              if (_selectedImageFile != null) // Display newly selected image
                Column(
                  children: [
                      const Text("New Image:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Image.file(File(_selectedImageFile!.path), height: 200, width: double.infinity, fit: BoxFit.contain),
                      TextButton.icon(
                          icon: const Icon(Icons.clear),
                          label: const Text('Cancel New Image'),
                          onPressed: () => setState(() => _selectedImageFile = null)),
                      const SizedBox(height: 10),
                      ],
                    )
              else if (_existingImageUrl != null && _existingImageUrl!.isNotEmpty && !_removeCurrentImage) // Display existing image
                Column(
                  children: [
                    const Text("Current Image:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Image.network(_existingImageUrl!, height: 200, width: double.infinity, fit: BoxFit.contain),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text('Remove Current Image', style: TextStyle(color: Colors.red)),
                      onPressed: () => setState(() {
                      _removeCurrentImage = true;
                      _selectedImageFile = null; // Clear any newly selected if removing current
                      })),
                    const SizedBox(height: 10),
                  ],
                )
              else if (_removeCurrentImage)
                  const Text("Image will be removed.", style: TextStyle(fontStyle: FontStyle.italic)),


              OutlinedButton.icon(
                icon: const Icon(Icons.image_search),
                label: Text(_selectedImageFile != null
                    ? 'Change Selected Image'
                    : (_existingImageUrl != null && _existingImageUrl!.isNotEmpty && !_removeCurrentImage)
                        ? 'Change Current Image'
                        : 'Add Image'),
                onPressed: () => _showImageSourceActionSheet(context),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: _isLoading ? Container() : const Icon(Icons.save_alt_outlined),
                  label: _isLoading
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white))
                      : const Text('Save Changes', style: TextStyle(fontSize: 16)),
                  onPressed: _isLoading ? null : _saveChanges,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ],
            ),
          ),
      ),
    );
  }
}
