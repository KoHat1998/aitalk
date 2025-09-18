import 'package:flutter/material.dart';

class AppTheme {
  // Brand palette
  static const Color _bg        = Color(0xFF0B0F14); // app background
  static const Color _surface   = Color(0xFF121821); // cards, sheets
  static const Color _surface2  = Color(0xFF0E141C); // darker surface
  static const Color _outline   = Color(0xFF243140); // strokes
  static const Color _primary   = Color(0xFF3B82F6); // blue-500
  static const Color _primaryHi = Color(0xFF60A5FA); // blue-400
  static const Color _danger    = Color(0xFFEF4444); // red-500

  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: _bg,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
    );

    const scheme = ColorScheme.dark(
      primary: _primary,
      onPrimary: Colors.white,
      secondary: _primaryHi,
      onSecondary: Colors.white,
      surface: _surface,
      onSurface: Color(0xFFE5E7EB),
      background: _bg,
      onBackground: Color(0xFFE5E7EB),
      error: _danger,
      onError: Colors.white,
      outline: _outline,
    );

    return base.copyWith(
      colorScheme: scheme,

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),

      // Cards  ✅ CardThemeData (not CardTheme)
      cardTheme: CardThemeData(
        color: _surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: EdgeInsets.zero,
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _surface,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _primaryHi,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: const Color(0xFF0E141A), // _surface2
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surface,
        hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _danger),
        ),
      ),

      // List tiles (contacts, settings rows)
      listTileTheme: const ListTileThemeData(
        iconColor: Colors.white,
        textColor: Colors.white,
        tileColor: _surface,
      ),

      // Switch / Toggle (MaterialStateProperty for best compat)
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return Colors.white;
          return const Color(0xFF9CA3AF);
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return _primary;
          return _outline;
        }),
      ),

      // Chip (e.g., “Online”)
      chipTheme: const ChipThemeData(
        backgroundColor: _surface,
        selectedColor: _primary,
        labelStyle: TextStyle(color: Colors.white),
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: StadiumBorder(),
      ),

      // Divider / outline
      dividerTheme: const DividerThemeData(
        color: _outline,
        thickness: 1,
        space: 1,
      ),

      // SnackBar
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: _surface2,
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),

      // Text styles
      textTheme: base.textTheme.copyWith(
        titleLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
        titleMedium: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
        bodyLarge: const TextStyle(fontSize: 16, color: Color(0xFFE5E7EB)),
        bodyMedium: const TextStyle(fontSize: 14, color: Color(0xFFC7CED6)),
        labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}
