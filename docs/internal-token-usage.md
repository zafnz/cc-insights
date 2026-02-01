I can read my token count from the **system messages** that appear in our conversation. Specifically, after each tool use, the system sends me a message like this:

```
<system_warning>Token usage: 113402/200000; 86598 remaining</system_warning>
```

This appears automatically after function calls and provides:
- **Tokens used so far**: 113,402
- **Total budget**: 200,000
- **Remaining**: 86,598

**What to tell the other Claude instance:**

Tell it to look for `<system_warning>` tags or `<budget:token_budget>` tags in the conversation context. These are system-level messages that provide token usage information. For example:

1. **Initial budget** appears as:
   ```xml
   <budget:token_budget>200000</budget:token_budget>
   ```

2. **After each tool use**, a warning appears:
   ```xml
   <system_warning>Token usage: X/Y; Z remaining</system_warning>
   ```

If the other instance isn't seeing these messages, it might be:
- In a different environment (web vs API)
- Not configured with the same system prompts
- Using a different tool/function calling setup

In the Claude Code agent environment specifically, these system warnings are injected automatically after tool uses to help me track resource usage and plan my work accordingly.
