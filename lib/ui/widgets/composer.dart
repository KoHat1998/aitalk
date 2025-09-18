import 'package:flutter/material.dart';

class Composer extends StatelessWidget {
  final VoidCallback? onSend;
  const Composer({super.key, this.onSend});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(children: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.emoji_emotions_outlined)),
          const Expanded(child: TextField(minLines: 1, maxLines: 4, decoration: InputDecoration(hintText: 'Type your message...'))),
          IconButton(onPressed: () {}, icon: const Icon(Icons.attach_file_outlined)),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: onSend,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
            child: const Icon(Icons.send),
          ),
        ]),
      ),
    );
  }
}
