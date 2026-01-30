# TODO list

## IMPORTANT
Claude only adds to the bigger todos at the bottom

## Small todo list
- [x] When permission times out, remove the permission box.
- [ ] Confirm before quitting claude. Have a setting For ConfirmQuit. Never|WhenActive|Always 
  - Never confirm before quitting
  - Confirm if Claude is thinking (Default)
  - Always confirm
  - The confirmation box should have a dropdown of those 3 options so the user can change it
- [x] The cost tracker in the top should be for the session. The cost tracker on the status bar at the bottom that says "Total" should be across all sessions
- [ ] ability to turn off autocompact
- [ ] An about box
- [ ] option to change context bar and percentage to be relative to free space (taking into account context buffer) or total space (as is now)
- [ ] When exiting plan mode show the user the plan before accept/denying it.
- [ ] When hitting deny (anywhere) you can usually add text explaining what to do instead
- [ ] Stop scroll bounce in scroll views inside tool widgets
- [ ] Sub agents should be reverse order for better scrolling UX.
- [ ] Uparrow conversation history
- [ ] Allow pasting images
- [ ] Overflows EVERYWHERE (but mainly on ever growing user input boxes)
- [ ] The circle indicator in the session list that shows claude's status should be a unread/activity/prompt marker.
      When Claude is thinking it should be a spinner. When claude has stopped but there is text that the user hasn't 
      seen (eg scrolled down to the bottom of) it should be green, and when there's an outstanding question it should be
      purple. if claude is stopped and all messages have been seen, then its a hollow. 
- [ ] When the user is typing a lot into the initial session setup request, put up a hint saying to click then icon to
      go into full screen editor, which opens a better editor for defining the task. 
      - The icon should be the standard fullscreen icon.
      - The full screen editor Enter does NOT submit.
      - The toolbar is: `Model: [Dropdown] Permissions: [Dropdown] [ ]Fixed width font   ...    [Cancel] [Submit]`
      - 
- [ ] Syntax highlighting for markdown and code viewer.
- [ ] Optional spellcheck/autocorrect in input box. Some kind of icon on far right of box (inside box) that when tapped turns on macs spellcheck/autocorrect/whatever.
- [ ] Optional fixed width font button in input box ( ) [ User input box.          <icon> ]. The icon when tapped is enabled and changes the text in the input to monospaced. Icon should be google's "Format Letter Spacing 2"
- [ ] Pending messages
- [ ] Start session screen should have a Submit button to click. Also in small text under the input box have "Enter to submit, Cmd+Enter for newline" (and change that to whatever Windows and Linux uses)
- [ ] Add an Agents icon on the navrail under sessions. Tapping that turns it off/on. Right clicking the agents icon brings up the popup menu to display the agents stacked, panel, or toolbar (as is currently offered)
- [ ] Add nicer mcp display, but we would have to connect to the mcps directly to get the tool descriptions
- [ ] Claude is working... should have a time counter. It should be the time since last stop (not since last tool used)

## Todo bigger tasks

### Name of the task

**Problem**: What the problem is

**Solutions**: 
- One or more possible solutions

