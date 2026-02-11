
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized font configuration for the app.
///
/// To change the monospace font across the entire app, modify the
/// [monoTextStyle] method to use a different Google Font.
class AppFonts {
  AppFonts._();

  /// Default font features for monospace text.
  /// Ligatures are disabled by default to ensure characters like === display
  /// as separate characters rather than combined glyphs.
  static const _defaultFontFeatures = [
    FontFeature.disable('liga'),
    FontFeature.disable('clig'),
    FontFeature.disable('dlig'),
    FontFeature.disable('hlig'),
  ];

  /// The monospace font family used throughout the app.
  /// This is used for code, commands, file paths, and technical content.
  ///
  /// To switch to a different font, change this to use a different
  /// GoogleFonts method (e.g., GoogleFonts.firaCode, GoogleFonts.sourceCodePro).
  ///
  /// Ligatures are disabled by default. Pass an empty list to [fontFeatures]
  /// to enable them, or pass custom font features to override.
  static TextStyle monoTextStyle({
    double fontSize = 12.0,
    Color? color,
    FontWeight fontWeight = FontWeight.normal,
    FontStyle fontStyle = FontStyle.normal,
    double? height,
    TextDecoration? decoration,
    List<FontFeature>? fontFeatures,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      height: height,
      decoration: decoration,
      fontFeatures: fontFeatures ?? _defaultFontFeatures,
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
