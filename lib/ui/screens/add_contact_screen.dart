import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_routes.dart';
import 'dart:async';
import '../widgets/avatar.dart';

enum AddContactMethod { byCode, byAiTalkId, byPhoneNumber }

class AddContactScreen extends StatefulWidget {
  final String? initialContactCode;

  const AddContactScreen({
    super.key,
    this.initialContactCode,
  });

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _sb = Supabase.instance.client;

  final _codeController = TextEditingController();
  final _globalSearchController = TextEditingController();
  late final VoidCallback _globalSearchListener;

  AddContactMethod _currentAddMethod = AddContactMethod.byCode;

  Map<String, dynamic>? _codeSearchResult;
  bool _isSearchingByCode = false;
  bool _isAddingFromCode = false;

  List<Map<String, dynamic>> _globalSearchResults = [];
  bool _isSearchingGlobally = false;
  Timer? _globalSearchDebounce;

  @override
  void initState() {
    super.initState();

    // Listener for global search input
    _globalSearchListener = () {
      _onGlobalSearchQueryChanged();
    };
    _globalSearchController.addListener(_globalSearchListener);

    // Handle initial contact code if passed
    if (widget.initialContactCode != null && widget.initialContactCode!.isNotEmpty) {
      _codeController.text = widget.initialContactCode!;
      _currentAddMethod = AddContactMethod.byCode; // Ensure correct method is selected
      // Auto-trigger find by code after the first frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _findByCode();
        }
      });
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _globalSearchController.removeListener(_globalSearchListener);
    _globalSearchController.dispose();
    _globalSearchDebounce?.cancel();
    super.dispose();
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _findByCode() async {
    final code = _codeController.text.trim().toLowerCase();
    if (code.isEmpty) return;
    setState(() {
      _isSearchingByCode = true;
      _codeSearchResult = null;
    });
    try {
      final res = await _sb.rpc('lookup_user_by_code', params: {'p_code': code});
      Map<String, dynamic>? row;
      if (res is List && res.isNotEmpty) {
        row = Map<String, dynamic>.from(res.first as Map);
      } else if (res is Map) {
        row = Map<String, dynamic>.from(res);
      }

      if (row == null) {
        _snack('No user found for that code', isError: true);
      } else {
        _codeSearchResult = row;
      }
    } on PostgrestException catch (e) {
      _snack('Error finding user: ${e.message}', isError: true);
    } catch (e) {
      _snack('An unexpected error occurred: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isSearchingByCode = false);
    }
  }

  Future<void> _scanQrCode() async {
    final scannedCode = await Navigator.pushNamed(context, AppRoutes.scanQr) as String?;
    if (scannedCode != null && scannedCode.isNotEmpty) {
      _codeController.text = scannedCode;
      await _findByCode();
    }
  }

  Future<void> _addContactFromCodeResult() async {
    final me = _sb.auth.currentUser?.id;
    final targetId = _codeSearchResult?['id'] as String?; // Assuming 'id' is the user_id from lookup_user_by_code

    if (me == null || targetId == null) {
      _snack('Could not identify users.', isError: true);
      return;
    }
    if (me == targetId) {
      _snack("You can't add yourself.", isError: true);
      return;
    }

    setState(() => _isAddingFromCode = true);
    try {
      await _sb.rpc('add_contact_mutual', params: {'p_contact': targetId});
      _snack('${_codeSearchResult?['display_name'] ?? 'User'} added to contacts!');
      if (mounted) Navigator.pop(context, true); // Success, pop and refresh previous screen
    } on PostgrestException catch (e) {
      _handleMutualAddError(e, _codeSearchResult?['display_name'] ?? 'User');
    } catch (e) {
      _snack('Add failed: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isAddingFromCode = false);
    }
  }

  // --- Logic for "Search by AI Talk ID / Phone" ---
  void _onGlobalSearchQueryChanged() {
    if (_globalSearchDebounce?.isActive ?? false) _globalSearchDebounce!.cancel();
    _globalSearchDebounce = Timer(const Duration(milliseconds: 600), () {
      final query = _globalSearchController.text.trim();
      if (query.isNotEmpty) {
        _performGlobalSearch(query);
      } else {
        if (mounted) setState(() => _globalSearchResults.clear());
      }
    });
  }

  Future<void> _performGlobalSearch(String query) async {
    if (!mounted || (_currentAddMethod != AddContactMethod.byAiTalkId && _currentAddMethod != AddContactMethod.byPhoneNumber)) {
      return;
    }
    setState(() {
      _isSearchingGlobally = true;
      _globalSearchResults.clear();
    });

    final currentUserId = _sb.auth.currentUser?.id;
    if (currentUserId == null) {
      _snack("You must be logged in to search.", isError: true);
      if (mounted) setState(() => _isSearchingGlobally = false);
      return;
    }

    final searchTypeString = _currentAddMethod == AddContactMethod.byAiTalkId ? 'username' : 'phone';

    try {
      final List<dynamic> results = await _sb.rpc(
        'search_users_by_identifier',
        params: {
          'p_search_term': query,
          'p_search_type': searchTypeString,
          'p_requesting_user_id': currentUserId,
        },
      );
      if (mounted) {
        setState(() {
          _globalSearchResults = results.map((item) => item as Map<String, dynamic>).toList();
        });
      }
    } catch (e) {
      _snack('Error searching users: ${e.toString()}', isError: true);
      if (mounted) _globalSearchResults.clear();
    } finally {
      if (mounted) setState(() => _isSearchingGlobally = false);
    }
  }

  // Generic function to add a contact, used by global search results
  Future<void> _addContactFromGlobalSearchResult(Map<String, dynamic> userData) async {
    final targetUserId = userData['user_id'] as String?;
    final displayName = userData['display_name'] as String? ?? 'this user';

    if (targetUserId == null) {
      _snack("Cannot add user: Missing user ID.", isError: true);
      return;
    }
    final me = _sb.auth.currentUser?.id;
    if (me == null) {
      _snack("You're not logged in.", isError: true);
      return;
    }
    if (me == targetUserId) {
      _snack("You can't add yourself.", isError: true);
      return;
    }

    // Optional: Add a loading state specific to this item in the list
    // For now, a general snackbar will indicate progress.
    _snack('Adding $displayName...');

    try {
      await _sb.rpc('add_contact_mutual', params: {'p_contact': targetUserId});
      _snack("$displayName has been added to your contacts!");
      // No need to pop here, user is still on AddContactScreen.
      // Refreshing the search or clearing it might be good UX.
      _globalSearchController.clear(); // Clear search after adding
      if(mounted) setState(() => _globalSearchResults.clear()); // Clear results
      // Potentially navigate back or show a prominent success message.
      // For now, just clear.
    } on PostgrestException catch (e) {
      _handleMutualAddError(e, displayName);
    } catch (e) {
      _snack('Add failed: ${e.toString()}', isError: true);
    } finally {
      // Clear item-specific loading state if you implement one
    }
  }

  void _handleMutualAddError(PostgrestException e, String displayName) {
    if (e.message.toLowerCase().contains('duplicate key value violates unique constraint') || e.code == '23505') {
      _snack('$displayName is already in your contacts or the request was duplicated.');
    } else {
      _snack('Error adding $displayName: ${e.message}', isError: true);
    }
    print('PostgrestException adding contact: ${e.toString()}');
  }


  // --- Build Method & UI Components ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add New Contact')),
      body: ListView( // Using ListView to prevent overflow if content gets long
        padding: const EdgeInsets.all(16),
        children: [
          _buildMethodSelector(),
          const SizedBox(height: 20),
          if (_currentAddMethod == AddContactMethod.byCode)
            _buildFindByCodeUI(),
          if (_currentAddMethod == AddContactMethod.byAiTalkId || _currentAddMethod == AddContactMethod.byPhoneNumber)
            _buildGlobalSearchUI(),
        ],
      ),
    );
  }

  Widget _buildMethodSelector() {
    return SegmentedButton<AddContactMethod>(
      segments: const <ButtonSegment<AddContactMethod>>[
        ButtonSegment<AddContactMethod>(
            value: AddContactMethod.byCode,
            label: Text('Code'),
            icon: Icon(Icons.qr_code_2_outlined)),
        ButtonSegment<AddContactMethod>(
            value: AddContactMethod.byAiTalkId,
            label: Text('AI Talk ID'), // Or "Username"
            icon: Icon(Icons.alternate_email)),
        ButtonSegment<AddContactMethod>(
            value: AddContactMethod.byPhoneNumber,
            label: Text('Phone'),
            icon: Icon(Icons.phone_outlined)),
      ],
      selected: <AddContactMethod>{_currentAddMethod},
      onSelectionChanged: (Set<AddContactMethod> newSelection) {
        setState(() {
          _currentAddMethod = newSelection.first;
          // Clear previous search results and inputs when changing method
          _codeSearchResult = null;
          _globalSearchResults.clear();
          _codeController.clear();
          _globalSearchController.clear();
        });
      },
    );
  }

  Widget _buildFindByCodeUI() {
    final userFoundByCode = _codeSearchResult != null;
    final name = (userFoundByCode ? (_codeSearchResult!['display_name'] as String?) : null) ?? '';
    final email = (userFoundByCode ? (_codeSearchResult!['email'] as String?) : null) ?? ''; // Or other identifier

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _codeController,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Enter friend code',
            prefixIcon: Icon(Icons.qr_code_2),
          ),
          onSubmitted: (_) => _findByCode(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: _isSearchingByCode ? null : _findByCode,
                child: _isSearchingByCode
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Find by Code'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _scanQrCode,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan QR'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (userFoundByCode)
          Card(
            child: ListTile(
              leading: Avatar(name: name, imageUrl: _codeSearchResult!['avatar_url']), // Use Avatar widget
              title: Text(name.isNotEmpty ? name : 'User (No Name)'),
              subtitle: Text(email.isNotEmpty ? email : (_codeSearchResult!['username'] ?? 'No identifier')),
              trailing: SizedBox(
                width: 90,
                child: FilledButton(
                  onPressed: _isAddingFromCode ? null : _addContactFromCodeResult,
                  child: _isAddingFromCode
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Add'),
                ),
              ),
            ),
          ),
        if (!userFoundByCode && !_isSearchingByCode && _codeController.text.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Text(
              'Enter a friend code or scan a QR to find a user.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
      ],
    );
  }

  Widget _buildGlobalSearchUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _globalSearchController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: _currentAddMethod == AddContactMethod.byAiTalkId
                ? 'Search by AI Talk ID...'
                : 'Search by Phone Number...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _globalSearchController.text.isNotEmpty
                ? IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _globalSearchController.clear();
                setState(() => _globalSearchResults.clear());
              },
            )
                : null,
          ),
          // onSubmitted is handled by debouncer via listener
        ),
        const SizedBox(height: 12),
        // No explicit search button, search happens on type (debounced)

        if (_isSearchingGlobally && _globalSearchResults.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20.0),
            child: Center(child: CircularProgressIndicator()),
          ),

        if (!_isSearchingGlobally && _globalSearchResults.isEmpty && _globalSearchController.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            child: Center(child: Text("No users found for '${_globalSearchController.text}'.")),
          ),

        if (_globalSearchResults.isNotEmpty)
          _buildGlobalSearchResultsListWidget(), // Extracted to a separate method

        if (!_isSearchingGlobally && _globalSearchResults.isEmpty && _globalSearchController.text.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Text(
              _currentAddMethod == AddContactMethod.byAiTalkId
                  ? 'Enter an AI Talk ID to find users.'
                  : 'Enter a phone number to find users.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
      ],
    );
  }

  Widget _buildGlobalSearchResultsListWidget() {
    return ListView.builder(
      shrinkWrap: true, // Important when ListView is inside another scrollable (like the parent ListView)
      physics: const NeverScrollableScrollPhysics(), // Also important for nested scrolling
      itemCount: _globalSearchResults.length,
      itemBuilder: (context, index) {
        final userData = _globalSearchResults[index];
        return _buildGlobalSearchUserTile(userData); // Reusing your tile structure
      },
    );
  }

  Widget _buildGlobalSearchUserTile(Map<String, dynamic> userData) {
    final displayName = (userData['display_name'] as String?)?.trim() ?? 'N/A';
    final aiTalkId = (userData['username'] as String?)?.trim();
    final userId = userData['user_id'] as String;
    final avatarUrl = userData['avatar_url'] as String?;

    // You might want to check if this user is already a contact to disable "Add"
    // This requires having access to the contacts list or a quick check.
    // For simplicity, this example doesn't include that check here but it's good UX.
    // bool isAlreadyContact = _checkIfAlreadyContact(userId);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Avatar(name: displayName, imageUrl: avatarUrl),
        title: Text(displayName, overflow: TextOverflow.ellipsis),
        subtitle: aiTalkId != null && aiTalkId.isNotEmpty
            ? Text('@$aiTalkId', overflow: TextOverflow.ellipsis)
            : Text(userData['phone_number'] ?? 'User', overflow: TextOverflow.ellipsis), // Show phone if it was search criteria and no username
        trailing: SizedBox(
          width: 90, // Adjust as needed
          child: ElevatedButton(
            onPressed: () => _addContactFromGlobalSearchResult(userData),
            child: const Text('Add'),
          ),
        ),
      ),
    );
  }
}