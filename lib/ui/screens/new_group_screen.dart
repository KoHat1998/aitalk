import 'package:flutter/material.dart';

class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final nameCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final canCreate = nameCtrl.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Group'),
        leading: IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => Navigator.pop(context)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(controller: nameCtrl, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Group Name')),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: canCreate ? () => Navigator.pop(context) : null,
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Create Group')),
          ),
        ),
      ),
    );
  }
}
