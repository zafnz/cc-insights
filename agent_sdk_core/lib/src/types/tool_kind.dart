/// Semantic categorization of tool operations.
///
/// Each backend maps its native tool names/types into these kinds.
/// The original tool name is preserved separately for display and
/// backend-specific rendering.
enum ToolKind {
  execute, // Shell/command execution (Bash, ShellTool)
  read, // File reading (Read, ReadFileTool)
  edit, // File modification (Edit, Write, EditTool, WriteFileTool)
  delete, // File deletion
  move, // File rename/move
  search, // Content/file search (Grep, Glob, GrepTool, GlobTool)
  fetch, // Web fetching (WebFetch, WebFetchTool)
  browse, // Web search (WebSearch, WebSearchTool)
  think, // Subagent/delegation (Task)
  ask, // User interaction (AskUserQuestion)
  memory, // State tracking (TodoWrite, MemoryTool)
  mcp, // MCP server tool call
  other; // Unknown/custom tools

  /// Maps a Claude CLI tool name to a [ToolKind].
  ///
  /// Uses the mapping table from the InsightsEvent protocol:
  /// - `Bash` → [execute]
  /// - `Read` → [read]
  /// - `Write`, `Edit`, `NotebookEdit` → [edit]
  /// - `Glob`, `Grep` → [search]
  /// - `WebFetch` → [fetch]
  /// - `WebSearch` → [browse]
  /// - `Task` → [think]
  /// - `AskUserQuestion` → [ask]
  /// - `TodoWrite` → [memory]
  /// - `mcp__*` → [mcp]
  /// - Everything else → [other]
  static ToolKind fromToolName(String toolName) {
    if (toolName.startsWith('mcp__')) return ToolKind.mcp;

    return switch (toolName) {
      'Bash' => ToolKind.execute,
      'Read' => ToolKind.read,
      'Write' || 'Edit' || 'NotebookEdit' => ToolKind.edit,
      'Glob' || 'Grep' => ToolKind.search,
      'WebFetch' => ToolKind.fetch,
      'WebSearch' => ToolKind.browse,
      'Task' => ToolKind.think,
      'AskUserQuestion' => ToolKind.ask,
      'TodoWrite' => ToolKind.memory,
      _ => ToolKind.other,
    };
  }
}
