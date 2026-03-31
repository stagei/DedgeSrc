# Cursor IDE Browser MCP - Complete Guide

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-22  
**Technology:** Cursor IDE / MCP

---

## Overview

The `cursor-ide-browser` is a built-in MCP (Model Context Protocol) server in Cursor that gives the AI agent the ability to control a real browser directly inside the IDE. It can navigate web pages, click buttons, fill forms, take screenshots, read console output, inspect network traffic, and profile performance -- all without you leaving the editor.

This is useful for:
- Visually verifying web apps after deployment
- Testing UI changes, login flows, and form submissions
- Debugging front-end issues by reading console errors and network requests
- Capturing screenshots for documentation or test reports
- Performance profiling JavaScript in the browser

---

## How It Works

The browser opens as a tab inside Cursor's editor area (like a file tab). The AI agent interacts with it through a structured accessibility tree ("snapshot"), not pixel-based vision. Each element in the snapshot gets a `ref` identifier that the agent uses to click, type, scroll, etc.

```
User prompt  -->  AI Agent  -->  MCP browser tools  -->  Built-in Chromium tab
                                                              |
                                                         Snapshot (DOM tree)
                                                         Screenshots (PNG)
                                                         Console logs
                                                         Network requests
```

---

## Critical Workflow: Lock/Unlock

The browser has a lock mechanism to prevent your mouse clicks from interfering while the agent works:

1. **Navigate first** -- `browser_navigate` must be called before `browser_lock` (you need an open tab)
2. **Lock** -- `browser_lock` shows a subtle overlay that blocks your clicks/scrolls
3. **Interact** -- the agent does its work (click, type, scroll, etc.)
4. **Unlock** -- `browser_unlock` releases control back to you

You can always click "Take Control" in the browser overlay to manually unlock.

---

## All 33 Tools by Category

### Navigation (7 tools)

| Tool | Description | Key Parameters |
|------|-------------|---------------|
| `browser_navigate` | Go to a URL | `url` (required), `newTab`, `position` ("side" for split view) |
| `browser_navigate_back` | Browser back button | -- |
| `browser_navigate_forward` | Browser forward button | -- |
| `browser_reload` | Refresh the page | -- |
| `browser_tabs` | List, create, close, or select tabs | `action` ("list", "new", "close", "select"), `index` |
| `browser_wait_for` | Wait for text/time | `text`, `textGone`, `time` (seconds), `timeout` (ms, default 30000) |
| `browser_resize` | Resize browser viewport | width, height |

### Interaction (6 tools)

| Tool | Description | Key Parameters |
|------|-------------|---------------|
| `browser_click` | Click an element | `element` + `ref` (required), `doubleClick`, `button` (left/right/middle), `modifiers` (Ctrl/Shift/Alt) |
| `browser_hover` | Hover over an element | `element` + `ref` (required) |
| `browser_scroll` | Scroll page or element | `direction` (up/down/left/right), `amount` (px, default 300), `ref` + `scrollIntoView` |
| `browser_drag` | Drag and drop | `sourceRef` (required), `targetRef` or `targetX`/`targetY` |
| `browser_press_key` | Press keyboard key | `key` (required) -- e.g. "Enter", "Escape", "Control+s", "Alt+Tab" |
| `browser_handle_dialog` | Handle alert/confirm/prompt | `accept` (required), `promptText` -- call BEFORE triggering the dialog |

### Form Input (4 tools)

| Tool | Description | Key Parameters |
|------|-------------|---------------|
| `browser_type` | Append text to an input | `element` + `ref` + `text` (required), `clear`, `submit` (press Enter), `slowly` (char by char) |
| `browser_fill` | Clear and replace input value | `element` + `ref` + `value` (required) -- atomically replaces content |
| `browser_fill_form` | Fill multiple fields at once | `fields` array of {element, ref, value, clear} |
| `browser_select_option` | Select dropdown option | `element` + `ref` + `values` (array) -- matches value, then label, then partial label |

**When to use `type` vs `fill`:**
- `browser_type` **appends** text (like typing on keyboard). Use when the input has autocomplete or key-by-key handlers.
- `browser_fill` **clears first, then sets** the value atomically. Use when you want to replace the entire field content.

### Inspection (11 tools)

| Tool | Description | Key Parameters |
|------|-------------|---------------|
| `browser_snapshot` | Get page accessibility tree | `interactive` (only interactive elements), `selector` (CSS scope), `compact`, `maxDepth` (default 20), `includeDiff` |
| `browser_search` | Ctrl+F search on page | `query`, `caseSensitive`, `navigateToMatch` (0-based index), `clearHighlights` |
| `browser_take_screenshot` | Save page as PNG/JPEG | `filename`, `type` (png/jpeg), `fullPage`, `element` + `ref` (element screenshot) |
| `browser_get_attribute` | Read element attribute | `element` + `ref` + `name` (attribute name) |
| `browser_get_bounding_box` | Get element position/size | `element` + `ref` |
| `browser_get_input_value` | Read input field value | `element` + `ref` |
| `browser_is_checked` | Check if checkbox/radio is checked | `element` + `ref` |
| `browser_is_enabled` | Check if element is enabled | `element` + `ref` |
| `browser_is_visible` | Check if element is visible | `element` + `ref` |
| `browser_console_messages` | Get all console output | -- |
| `browser_network_requests` | Get all network requests | -- |

### Visual Debugging (1 tool)

| Tool | Description | Key Parameters |
|------|-------------|---------------|
| `browser_highlight` | Temporarily highlight an element | `element` + `ref`, `durationMs` (default 2000) |

### Utility / Profiling (4 tools)

| Tool | Description | Key Parameters |
|------|-------------|---------------|
| `browser_lock` | Lock browser (block user input) | -- |
| `browser_unlock` | Unlock browser (return control) | -- |
| `browser_profile_start` | Start CPU profiling | -- |
| `browser_profile_stop` | Stop profiling, get results | -- |

---

## How to Guide the Agent: Prompt Examples

### Basic Navigation and Verification

```
Open http://localhost/DedgeAuth/ in the browser and take a screenshot.
```

```
Navigate to http://dedge-server/DocView/ and check if the page loads correctly.
Tell me if there are any console errors.
```

```
Open the ServerMonitorDashboard at http://localhost/ServerMonitorDashboard/ 
in a side panel next to my code.
```

### Testing Login Flows

```
Go to http://localhost/DedgeAuth/login.html, fill in username "testuser" 
and password "testpass", then click the Login button. 
Show me what happens after login.
```

```
Navigate to http://localhost/DocView/, check if it redirects to DedgeAuth 
for authentication, and verify the auth flow completes.
```

### Form Testing

```
Open the admin page and fill in the registration form with:
- Name: Test User
- Email: test@example.com
- Role: select "Administrator" from the dropdown
Then submit the form and show me the result.
```

### Debugging and Inspection

```
Open http://localhost/GenericLogHandler/ and show me all network requests 
that were made. Are there any failed requests?
```

```
Navigate to the dashboard and check the browser console for any 
JavaScript errors or warnings.
```

```
Go to the ServerMonitorDashboard and search for the text "CPU Usage" 
on the page. Is it visible?
```

### Screenshots and Reports

```
Open each of our web apps one by one and take full-page screenshots 
of each. Save them with descriptive filenames.
```

```
Navigate to http://localhost/DedgeAuth/ and take a screenshot, 
then check if dark mode is available and capture that too.
```

### Performance Profiling

```
Open http://localhost/ServerMonitorDashboard/ and start CPU profiling. 
Wait 10 seconds for the dashboard to do its updates, then stop profiling 
and show me what JavaScript functions are taking the most time.
```

### Multi-Tab Testing

```
Open DedgeAuth in one tab and DocView in a second tab. 
Verify both load correctly and list all open tabs.
```

### Waiting for Dynamic Content

```
Navigate to the dashboard and wait for "Data loaded" to appear 
on the page before taking a screenshot.
```

```
Click the refresh button and wait for the loading spinner 
text to disappear before checking the results.
```

### Element State Inspection

```
Go to the settings page and check which checkboxes are currently checked. 
Also verify that the "Save" button is enabled.
```

### Handling Dialogs

```
On the admin page, I need to click "Delete All" which shows a 
confirmation dialog. Configure the dialog to click Cancel, 
then click the button and verify nothing was deleted.
```

---

## Key Concepts for Users

### The Snapshot is Everything

Before the agent can click, type, or inspect anything, it needs to take a **snapshot** of the page. The snapshot is an accessibility tree -- a structured representation of all visible elements with their `ref` identifiers. The agent uses these refs to target elements.

You don't need to mention snapshots in your prompts -- the agent takes them automatically. But if you want to be explicit:

```
Take a snapshot of the page and tell me what interactive elements are available.
```

### Side-by-Side Browsing

Use the word "side" or "beside" in your prompt to open the browser next to your code:

```
Open the app in a side panel so I can see both the code and the result.
```

### Element Targeting

The agent finds elements by their accessibility role and text content from the snapshot. If you need to be specific about which element to interact with, describe it clearly:

```
Click the "Submit" button in the login form (not the one in the footer).
```

### Scrolling and Visibility

For long pages or nested scroll containers, the agent can scroll elements into view:

```
Scroll down to the footer and take a screenshot of the copyright notice.
```

For nested containers (like a scrollable sidebar inside a page), mention that explicitly:

```
Scroll down inside the log viewer panel to see the latest entries.
```

### Native Dialogs (alert/confirm/prompt)

Native browser dialogs are **non-blocking** in this environment. They return immediately. The agent must configure dialog handling **before** triggering the action that shows the dialog.

---

## Limitations

| Limitation | Workaround |
|------------|-----------|
| **Iframe content is not accessible** | Only elements outside iframes can be interacted with |
| **No file uploads via dialog** | Use `browser_fill` on file input elements if possible |
| **No authentication persistence** | The browser session is ephemeral; cookies don't persist between Cursor restarts |
| **Localhost only from dev machine** | Remote server URLs must be accessible from your network |
| **Binary content not readable** | PDFs, images, videos are displayed but content can't be extracted as text |

---

## Profiling Output

CPU profiles are saved to `~/.cursor/browser-logs/`:
- `cpu-profile-{timestamp}.json` -- raw Chrome DevTools format
- `cpu-profile-{timestamp}-summary.md` -- human-readable summary

The raw JSON contains `profile.samples`, `profile.nodes[].hitCount`, and `profile.nodes[].callFrame.functionName`. Always cross-reference the summary with the raw data for accuracy.

---

## Quick Reference Card

| What you want | What to say |
|---------------|-------------|
| Open a URL | "Open http://... in the browser" |
| Open side-by-side | "Open http://... in a side panel" |
| Take a screenshot | "Take a screenshot of the page" |
| Full-page screenshot | "Take a full-page screenshot" |
| Check for errors | "Show me the console errors" |
| Check network | "Show me the network requests" |
| Fill a form | "Fill in the form with..." |
| Click a button | "Click the Submit button" |
| Wait for content | "Wait for 'Loading complete' to appear" |
| Search on page | "Search for 'error' on the page" |
| Test dark mode | "Activate dark mode and take a screenshot" |
| Profile performance | "Start CPU profiling, wait 10 seconds, then show results" |
| Multiple tabs | "Open X in one tab and Y in another" |
| Check element state | "Is the Save button enabled?" |
| Handle a dialog | "Click Delete but cancel the confirmation dialog" |
