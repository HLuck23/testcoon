# Chat

## Changes Made

### 1. Removed script print logs from chat
File: `cl_chat.lua`
- The `__cfx_internal:serverPrint` handler now only prints to the F8 console.
- Script `print()` statements will no longer appear in the chat box.

### 2. Removed command fallback messages from chat
File: `sv_chat.lua`
- The `__cfx_internal:commandFallback` handler is disabled.
- Commands triggered by keybinds (e.g. `/e "sunbathe"`) will no longer appear in chat.

### 3. Optional: Disable join/leave messages
Add these lines to your `server.cfg`:
```cfg
set chat_showJoins 0
set chat_showQuits 0
```
