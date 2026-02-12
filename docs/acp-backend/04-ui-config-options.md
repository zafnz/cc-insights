**ACP Config Options and Toolbar UX**

**Toolbar Placement**
- Show ACP session config options on the conversation toolbar.
- Prioritize `category: model` and `category: mode`.
- Render other categories in a compact overflow menu.

**Config Options Behavior**
- When `ConfigOptionsEvent` arrives, rebuild the toolbar state directly from the event payload.
- When the user changes a value, call `session/set_config_option` with `configId` and `value`.
- After the response, emit a new `ConfigOptionsEvent` and update the UI.

**Modes Fallback**
- If ACP provides `modes` but no `configOptions`, show a mode selector.
- On mode change, call `session/set_mode`.
- Use `SessionModeEvent` to update the toolbar.

**Available Commands**
- If `AvailableCommandsEvent` is emitted, optionally show a slash-command picker.
- If not shown, keep the data for future UI work and debugging.

**Display Rules**
- Always use ACP-provided `name` and `description` as display text.
- Preserve ordering from the ACP payload.
- Hide selectors when there is only one option value.
