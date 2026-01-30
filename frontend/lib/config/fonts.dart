import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized font configuration for the app.
///
/// To change the monospace font across the entire app, modify the
/// [monoTextStyle] method to use a different Google Font.
class AppFonts {
  AppFonts._();

  /// The monospace font family used throughout the app.
  /// This is used for code, commands, file paths, and technical content.
  ///
  /// To switch to a different font, change this to use a different
  /// GoogleFonts method (e.g., GoogleFonts.firaCode, GoogleFonts.sourceCodePro).
  static TextStyle monoTextStyle({
    double fontSize = 12.0,
    Color? color,
    FontWeight fontWeight = FontWeight.normal,
    FontStyle fontStyle = FontStyle.normal,
    double? height,
    TextDecoration? decoration,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      height: height,
      decoration: decoration,
    );
  }

  /// Create a monospace TextSpan for use in RichText widgets.
  static TextSpan monoTextSpan({
    required String text,
    double fontSize = 12.0,
    Color? color,
    FontWeight fontWeight = FontWeight.normal,
    FontStyle fontStyle = FontStyle.normal,
  }) {
    return TextSpan(
      text: text,
      style: monoTextStyle(
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
      ),
    );
  }
}
