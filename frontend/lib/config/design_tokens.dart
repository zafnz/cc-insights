/// Centralized design tokens for consistent spacing, sizing, and timing.
///
/// These constants replace hardcoded numeric literals scattered throughout
/// widget files, ensuring visual consistency and easy theme-wide adjustments.
library;

import 'package:flutter/widgets.dart';

// =============================================================================
// Spacing
// =============================================================================

/// Spacing constants following a 4px base grid.
abstract final class Spacing {
  /// 4px — tight spacing between closely related elements.
  static const double xs = 4;

  /// 6px — small spacing for compact layouts.
  static const double sm = 6;

  /// 8px — standard spacing between elements.
  static const double md = 8;

  /// 12px — content padding for inputs and containers.
  static const double lg = 12;

  /// 16px — section-level padding.
  static const double xl = 16;

  /// Standard horizontal+vertical padding for content areas.
  static const EdgeInsets contentPadding = EdgeInsets.all(md);

  /// Standard padding for input fields and compact containers.
  static const EdgeInsets inputPadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );
}

// =============================================================================
// Border Radii
// =============================================================================

/// Border radius constants for consistent rounding.
abstract final class Radii {
  /// 4px — small rounding for chips, badges, inline code.
  static const double sm = 4;

  /// 6px — medium rounding for cards and inputs.
  static const double md = 6;

  /// 8px — larger rounding for buttons and containers.
  static const double lg = 8;

  static const BorderRadius smallBorderRadius =
      BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mediumBorderRadius =
      BorderRadius.all(Radius.circular(md));
  static const BorderRadius largeBorderRadius =
      BorderRadius.all(Radius.circular(lg));
}

// =============================================================================
// Icon Sizes
// =============================================================================

/// Icon size constants.
abstract final class IconSizes {
  /// 14px — extra-small inline icons.
  static const double xs = 14;

  /// 16px — standard info/status icons.
  static const double sm = 16;

  /// 18px — medium action icons.
  static const double md = 18;

  /// 20px — standard action button icons.
  static const double lg = 20;

  /// 22px — large prominent icons.
  static const double xl = 22;
}

// =============================================================================
// Font Sizes
// =============================================================================

/// Font size constants for non-theme text.
///
/// Prefer [Theme.of(context).textTheme] for standard text styles.
/// Use these for specialized text that doesn't map to Material text roles
/// (e.g., code blocks, tool output, status labels).
abstract final class FontSizes {
  /// 11px — small code/monospace text.
  static const double code = 11;

  /// 12px — compact body text.
  static const double bodySmall = 12;

  /// 13px — standard body text in panels.
  static const double body = 13;

  /// 14px — slightly larger body or section headers.
  static const double bodyLarge = 14;
}

// =============================================================================
// Animation Durations
// =============================================================================

/// Standard animation durations.
abstract final class AnimDurations {
  /// 100ms — quick micro-interactions (scroll snap, fade).
  static const Duration fast = Duration(milliseconds: 100);

  /// 200ms — standard transitions (expand, slide).
  static const Duration standard = Duration(milliseconds: 200);

  /// 300ms — slower emphasis animations.
  static const Duration slow = Duration(milliseconds: 300);
}

// =============================================================================
// Component Sizes
// =============================================================================

/// Fixed sizes for common UI components.
abstract final class ComponentSizes {
  /// Standard square button size (40x40).
  static const double buttonSize = 40;

  /// Image preview thumbnail size (80x80).
  static const double thumbnailSize = 80;

  /// Maximum height for scrollable result containers.
  static const double maxResultHeight = 300;
}
