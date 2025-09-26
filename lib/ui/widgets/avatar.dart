import 'package:flutter/material.dart';

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  final bool online;
  const Avatar({super.key, this.name = 'User', this.size = 40, this.online = false, String? imageUrl});

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? 'U'
        : name.trim().split(RegExp(r'\\s+')).map((e) => e[0]).take(2).join().toUpperCase();
    return Stack(
      children: [
        CircleAvatar(
          radius: size / 2,
          backgroundColor: const Color(0xFF94A3B8),
          child: Text(initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: size / 3)),
        ),
        if (online)
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              width: size / 4.2,
              height: size / 4.2,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}
