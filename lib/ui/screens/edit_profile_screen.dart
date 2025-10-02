import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _aiTalkIdController = TextEditingController();
  final _phoneNumberController = TextEditingController();

  String? _currentAiTalkId;
  String? _currentPhoneNumber;

  bool _loading = true;
  bool _saving = false;
  final _sb = Supabase.instance.client;

  // availability check
  bool _isCheckingAiTalkId = false;
  String? _aiTalkIdAvailabilityMessage;
  Timer? _aiTalkIdDebounce;
  bool _aiTalkIdIsSetInDB = false;


  @override
  void initState() {
    super.initState();
    _bootstrap();
    _aiTalkIdController.addListener(_onAiTalkIdChanged);
  }

  @override
  void dispose() {
    _name.dispose();
    _aiTalkIdController.removeListener(_onAiTalkIdChanged);
    _aiTalkIdController.dispose();
    _aiTalkIdDebounce?.cancel();
    _phoneNumberController.dispose();
    super.dispose();
  }

  void _onAiTalkIdChanged() {
    if (_aiTalkIdIsSetInDB) return; // Don't check if already set

    if (_aiTalkIdDebounce?.isActive ?? false) _aiTalkIdDebounce!.cancel();
    _aiTalkIdDebounce = Timer(const Duration(milliseconds: 700), () {
      final newId = _aiTalkIdController.text.trim().toLowerCase();
      if (newId.isNotEmpty) {
        _checkAiTalkIdAvailability(newId);
      } else {
        if (mounted) {
          setState(() {
            _aiTalkIdAvailabilityMessage = null; // Clear message if field is empty
          });
        }
      }
    });
  }

  Future<void> _checkAiTalkIdAvailability(String id) async {
    if (!mounted || _aiTalkIdIsSetInDB) return;
    setState(() {
      _isCheckingAiTalkId = true;
      _aiTalkIdAvailabilityMessage = 'Checking...';
    });

    try {
      final bool isAvailable = await _sb.rpc(
        'check_username_availability', // Your RPC function name
        params: {'p_check_username': id},
      );
      if (!mounted) return;
      setState(() {
        if (isAvailable) {
          _aiTalkIdAvailabilityMessage = '$id is available!';
        } else {
          _aiTalkIdAvailabilityMessage = '$id is already in use.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiTalkIdAvailabilityMessage = 'Error checking availability.';
      });
      print("Error checking AI Talk ID availability: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingAiTalkId = false;
        });
      }
    }
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    final u = _sb.auth.currentUser;
    if (u == null) {
      _snack('Not signed in');
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final row = await _sb
          .from('users')
          .select('display_name, email, username, phone_number')
          .eq('id', u.id)
          .maybeSingle();

      if( row == null && mounted) {
        _snack('User profile not found. Please try again.');
        setState(() => _loading = false);
        return;
      }

      final dn = (row?['display_name'] as String?)?.trim();
      _name.text = (dn != null && dn.isNotEmpty)
          ? dn
          : (u.email?.split('@').first.replaceAll(RegExp(r'[._]+'), ' ') ?? '');
      _currentAiTalkId = row?['username'] as String?;
      if (_currentAiTalkId != null && _currentAiTalkId!.isNotEmpty) {
        _aiTalkIdController.text = _currentAiTalkId!;
        _aiTalkIdIsSetInDB = true; // Mark that it's already set
      } else {
        _aiTalkIdIsSetInDB = false;
      }

      // Load Phone Number
      _currentPhoneNumber = row?['phone_number'] as String?;
      if (_currentPhoneNumber != null) {
        _phoneNumberController.text = _currentPhoneNumber!;
      }
    } catch (e) {
      _snack('Failed to load profile: ${e.toString()}');
      _name.text =
          _sb.auth.currentUser?.email?.split('@').first.replaceAll(RegExp(r'[._]+'), ' ') ?? '';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final u = _sb.auth.currentUser;
    if (u == null) {
      _snack('Not signed in');
      return;
    }

    setState(() => _saving = true);
    final displayName = _name.text.trim();
    final String newAiTalkId = _aiTalkIdController.text.trim();
    final String newPhoneNumber = _phoneNumberController.text.trim();

    bool profileUpdateSuccess = false;
    bool aiTalkIdUpdateAttempted = false;

    // --- 1. Update AI Talk ID (Username) if it's new and not already set ---
    if (!_aiTalkIdIsSetInDB && newAiTalkId.isNotEmpty) {
      aiTalkIdUpdateAttempted = true;
      try {
        final response = await _sb.rpc(
          'update_user_username', // Your RPC for updating username
          params: {'p_new_username': newAiTalkId},
        ) as String;

        if (response.startsWith('Success')) {
          _snack(response); // Show success from RPC
          setState(() {
            _currentAiTalkId = newAiTalkId.toLowerCase(); // Update local state
            _aiTalkIdIsSetInDB = true; // Mark as set
            _aiTalkIdAvailabilityMessage = null; // Clear availability message
          });
          // No need to set profileUpdateSuccess = true yet, other fields might fail
        } else {
          // Error from RPC (e.g., "already taken", "invalid format")
          _snack(response); // Show the error from RPC
          setState(() => _saving = false);
          return; // Stop saving process if AI Talk ID fails
        }
      } catch (e) {
        _snack('Error setting AI Talk ID: ${e.toString()}');
        setState(() => _saving = false);
        return; // Stop saving
      }
    }

    // --- 2. Update Display Name and Phone Number in public.users ---
    try {
      Map<String, dynamic> updates = {
        'display_name': displayName,
        // Store null if phone number is empty, otherwise store the trimmed value
        'phone_number': newPhoneNumber.isNotEmpty ? newPhoneNumber : null,
        // We don't update 'username' here directly as it's handled by the RPC
        // If AI Talk ID was already set, _currentAiTalkId should be correct.
        // If it was just set by RPC, _currentAiTalkId was updated.
      };

      // If the user *cleared* their phone number, and you want to also clear phone_verified_at:
      if (newPhoneNumber.isNotEmpty && newPhoneNumber.trim() != _currentPhoneNumber) {
        updates['phone_verified_at'] = null;
      } else if (newPhoneNumber.isEmpty && _currentPhoneNumber != null) {
        // If phone number was cleared, also clear verification status
        updates['phone_verified_at'] = null;
      }


      final updatedRow = await _sb
          .from('users')
          .update(updates)
          .eq('id', u.id)
          .select('id') // Just to confirm update happened
          .maybeSingle();

      if (updatedRow == null && !_aiTalkIdIsSetInDB && !aiTalkIdUpdateAttempted) {
        // This case means the user row didn't exist AND we didn't attempt to set an AI Talk ID
        // (which might have created the row if your RPC did an upsert, but ours doesn't).
        // This implies an issue, as the user should exist if authenticated.
        // For simplicity, we'll assume the row usually exists if _bootstrap worked.
        // If you need to handle user row creation here if it's missing, you'd insert.
        _snack('User profile not found for update. Please try logging out and in.');
        setState(() => _saving = false);
        return;
      }

      profileUpdateSuccess = true;

      // --- 3. Optional: Mirror display_name to auth metadata ---
      if (displayName != (u.userMetadata?['display_name'] as String?)) {
        try {
          await _sb.auth.updateUser(
            UserAttributes(data: {'display_name': displayName}),
          );
        } catch (_) {/* non-fatal, auth metadata update failed */}
      }

      if (!mounted) return;

      if (profileUpdateSuccess || (aiTalkIdUpdateAttempted && _aiTalkIdIsSetInDB) ) {
        _snack('Profile saved successfully!'); // General success if either part relevant succeeded
        Navigator.pop(context, true); // Pop screen indicating success
      } else if (!aiTalkIdUpdateAttempted && !profileUpdateSuccess) {
        // This case means nothing was attempted or nothing succeeded.
        _snack('No changes were made or save failed.');
      }

    } on PostgrestException catch (e) {
      _snack('Database Error: ${e.message}');
    } catch (e) {
      _snack('Failed to save profile: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView( // Changed to ListView for scrollability if content grows
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Display Name', // Changed from hintText to labelText
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Enter your display name (min 2 chars)'
                    : null,
              ),
              const SizedBox(height: 16),

              // --- AI Talk ID (Username) Field ---
              TextFormField(
                controller: _aiTalkIdController,
                readOnly: _aiTalkIdIsSetInDB, // Make read-only if already set
                decoration: InputDecoration(
                  labelText: 'AI Talk ID',
                  prefixIcon: const Icon(Icons.alternate_email),
                  helperText: _aiTalkIdIsSetInDB
                      ? 'Your AI Talk ID cannot be changed.'
                      : _aiTalkIdAvailabilityMessage,
                  helperMaxLines: 2,
                  suffixIcon: _isCheckingAiTalkId
                      ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ))
                      : null,
                ),
                validator: (v) {
                  if (_aiTalkIdIsSetInDB) return null; // No validation if already set and read-only
                  if (v == null || v.trim().isEmpty) {
                    // return 'AI Talk ID cannot be empty.'; // Or make it optional by not returning error
                    return null; // Assuming AI Talk ID is optional until saved
                  }
                  if (v.trim().length < 3 || v.trim().length > 20) {
                    return 'Must be 3-20 characters.';
                  }
                  // You might add a regex validator here for allowed characters
                  // if (!RegExp(r'^[a-z0-9_]+$').hasMatch(v.trim())) {
                  //   return 'Use only lowercase letters, numbers, and underscores.';
                  // }
                  if (_aiTalkIdAvailabilityMessage != null &&
                      _aiTalkIdAvailabilityMessage!.contains('in use')) {
                    return 'This ID is already taken.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // --- Phone Number Field ---
              TextFormField(
                controller: _phoneNumberController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number (Optional)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
                // No validator here, making it purely optional.
                // You could add validation for phone format if desired.
              ),
              const SizedBox(height: 32), // More space before button

              FilledButton(
                onPressed: _saving ? null : _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _saving
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                      : const Text('Save Profile'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
