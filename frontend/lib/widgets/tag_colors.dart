import 'package:flutter/material.dart';

/// Well-known tag name → colour mapping.
const _wellKnownColors = <String, Color>{
  'bug': Color(0xFFEF5350),
  'bugfix': Color(0xFFEF5350),
  'feature': Color(0xFFBA68C8),
  'todo': Color(0xFFFFA726),
  'inprogress': Color(0xFF42A5F5),
  'in-progress': Color(0xFF42A5F5),
  'done': Color(0xFF4CAF50),
  'completed': Color(0xFF4CAF50),
  'high-priority': Color(0xFFEF5350),
  'critical': Color(0xFFEF5350),
  'docs': Color(0xFF9E9E9E),
  'documentation': Color(0xFF9E9E9E),
  'test': Color(0xFF4DB6AC),
  'testing': Color(0xFF4DB6AC),
};

/// Palette used for deterministic hash fallback.
const _hashPalette = <Color>[
  Color(0xFFE57373), // red 300
  Color(0xFFF06292), // pink 300
  Color(0xFFBA68C8), // purple 300
  Color(0xFF9575CD), // deep purple 300
  Color(0xFF7986CB), // indigo 300
  Color(0xFF64B5F6), // blue 300
  Color(0xFF4FC3F7), // light blue 300
  Color(0xFF4DD0E1), // cyan 300
  Color(0xFF4DB6AC), // teal 300
  Color(0xFF81C784), // green 300
  Color(0xFFAED581), // light green 300
  Color(0xFFFFD54F), // amber 300
  Color(0xFFFFB74D), // orange 300
  Color(0xFFFF8A65), // deep orange 300
  Color(0xFFA1887F), // brown 300
  Color(0xFF90A4AE), // blue grey 300
];

/// Parse a hex colour string like "#ef5350" or "ef5350" into a [Color].
///
/// Returns `null` if [hex] is not a valid 6-digit hex colour.
Color? _parseHex(String hex) {
  var s = hex.startsWith('#') ? hex.substring(1) : hex;
  if (s.length != 6) return null;
  final value = int.tryParse(s, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

/// Deterministic hash of [name] to a palette index.
int _hashIndex(String name) {
  // djb2 hash
  var hash = 5381;
  for (var i = 0; i < name.length; i++) {
    hash = ((hash << 5) + hash) + name.codeUnitAt(i);
    hash &= 0x7FFFFFFF; // keep positive 31-bit
  }
  return hash % _hashPalette.length;
}

/// Returns the display colour for a tag.
///
/// Resolution order:
/// 1. If [customHex] is non-null and valid, use it.
/// 2. If [tagName] matches a well-known default, use that.
/// 3. Deterministic hash fallback from the Material palette.
Color tagColor(String tagName, {String? customHex}) {
  if (customHex != null) {
    final parsed = _parseHex(customHex);
    if (parsed != null) return parsed;
  }

  final wellKnown = _wellKnownColors[tagName];
  if (wellKnown != null) return wellKnown;

  return _hashPalette[_hashIndex(tagName)];
}
