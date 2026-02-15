import 'dart:io';

import 'package:path/path.dart' as p;

/// Manages Python helper scripts used by git rebase operations.
///
/// The scripts are embedded as string constants and written to
/// `~/.ccinsights/scripts/` on first use. Each script is only
/// rewritten when its content has changed.
class RebaseScripts {
  RebaseScripts._();

  static String? _cachedDir;

  /// Returns the directory where scripts are stored, creating it if needed.
  static Future<String> _scriptsDir() async {
    if (_cachedDir != null) return _cachedDir!;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final dir = p.join(home, '.ccinsights', 'scripts');
    await Directory(dir).create(recursive: true);
    _cachedDir = dir;
    return dir;
  }

  /// Ensures a script file exists with the expected content and is executable.
  ///
  /// Only writes if the file is missing or its content differs.
  static Future<String> _ensureScript(
    String filename,
    String content,
  ) async {
    final dir = await _scriptsDir();
    final path = p.join(dir, filename);
    final file = File(path);

    bool needsWrite = true;
    if (file.existsSync()) {
      final existing = await file.readAsString();
      if (existing == content) needsWrite = false;
    }

    if (needsWrite) {
      await file.writeAsString(content);
      // Make executable on Unix-like systems.
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', path]);
      }
    }

    return path;
  }

  /// Returns the path to the sequence editor script, writing it if needed.
  static Future<String> ensureSequenceEditor() async {
    // Always write the .py script (used directly on Unix, via .cmd on Windows).
    await _ensureScript('rebase_sequence_editor.py', _sequenceEditorPy);
    if (Platform.isWindows) {
      return _ensureScript(
        'rebase_sequence_editor.cmd',
        _sequenceEditorCmd,
      );
    }
    final dir = await _scriptsDir();
    return p.join(dir, 'rebase_sequence_editor.py');
  }

  /// Returns the path to the message editor script, writing it if needed.
  static Future<String> ensureMessageEditor() async {
    // Always write the .py script (used directly on Unix, via .cmd on Windows).
    await _ensureScript('rebase_message_editor.py', _messageEditorPy);
    if (Platform.isWindows) {
      return _ensureScript(
        'rebase_message_editor.cmd',
        _messageEditorCmd,
      );
    }
    final dir = await _scriptsDir();
    return p.join(dir, 'rebase_message_editor.py');
  }

  // ---------------------------------------------------------------------------
  // Embedded scripts
  // ---------------------------------------------------------------------------

  static const _sequenceEditorPy = r'''#!/usr/bin/env python3
"""GIT_SEQUENCE_EDITOR for selective squash rebase.

Environment variables:
  FIRST_PICK   – SHA prefix of the commit to keep as "pick"
  SQUASH_SHAS  – space-separated SHA prefixes to mark as "squash"
"""
import os, re, sys

def main():
    if len(sys.argv) != 2:
        sys.exit("Expected path to git-rebase-todo")

    todo_path = sys.argv[1]
    first_pick = os.environ["FIRST_PICK"].lower()
    squash_set = set(
        sha.lower()
        for sha in os.environ.get("SQUASH_SHAS", "").split()
        if sha.strip()
    )

    output_lines = []
    with open(todo_path, "r", encoding="utf-8") as f:
        for line in f:
            m = re.match(r'^(pick)\s+([0-9a-fA-F]+)\b(.*)', line)
            if m:
                sha = m.group(2).lower()
                if sha == first_pick:
                    output_lines.append(f"pick {m.group(2)}{m.group(3)}\n")
                    continue
                if sha in squash_set:
                    output_lines.append(f"squash {m.group(2)}{m.group(3)}\n")
                    continue
            output_lines.append(line)

    with open(todo_path, "w", encoding="utf-8") as f:
        f.writelines(output_lines)

if __name__ == "__main__":
    main()
''';

  static const _messageEditorPy = r'''#!/usr/bin/env python3
"""GIT_EDITOR for setting the final squash commit message.

Environment variables:
  FINAL_MSG – the commit message to write
"""
import os, sys

def main():
    if len(sys.argv) != 2:
        sys.exit("Expected path to commit message file")

    msg_path = sys.argv[1]
    final_msg = os.environ.get("FINAL_MSG", "")
    with open(msg_path, "w", encoding="utf-8") as f:
        f.write(final_msg)

if __name__ == "__main__":
    main()
''';

  static const _sequenceEditorCmd = r'''@echo off
python3 "%~dp0rebase_sequence_editor.py" %*
''';

  static const _messageEditorCmd = r'''@echo off
python3 "%~dp0rebase_message_editor.py" %*
''';
}
