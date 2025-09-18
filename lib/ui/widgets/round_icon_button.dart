import 'package:flutter/material.dart';

class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? bg;
  final Color? fg;
  const RoundIconButton({super.key, required this.icon, required this.onTap, this.bg, this.fg});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 36,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: bg ?? Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))],
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Icon(icon, color: fg ?? const Color(0xFF0F172A)),
      ),
    );
  }
}
