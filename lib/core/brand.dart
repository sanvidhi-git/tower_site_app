import 'package:flutter/material.dart';

/// Sanvidhi Site brand constants (Sanvidhi logo colours + site orange accent).
class Brand {
  Brand._();

  static const appName = 'Sanvidhi Site';
  static const tagline = 'Site reporting for ERPNext';
  static const company = 'Sanvidhi Tech Pvt. Ltd.';
  static const logo = 'assets/branding/logo.png';

  static const magenta = Color(0xFF9C2492);
  static const purple = Color(0xFF5B2D9E);
  static const indigo = Color(0xFF2B368F);
  static const orange = Color(0xFFF28C28);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [magenta, purple, indigo],
  );
}
