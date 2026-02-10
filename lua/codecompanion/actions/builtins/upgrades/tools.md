---
name: Upgrade Tools
interaction: chat
description: Upgrade Tools from v19 to v20
opts:
  is_slash_cmd: false
  stop_context_insertion: true
---

## user

I need you to update my custom CodeCompanion.nvim tool to the new tools API. The signatures have changed as follows:

### `cmds` functions

**Synchronous tools** (return a result table):
````lua
-- OLD:
function(self, args, input)
-- NEW (unchanged for sync):
function(self, args, opts)
-- `opts` contains: { input = any, output_cb = fun(msg: table) }
-- For sync tools that don't use input or output_cb, the signature change is cosmetic.
-- Return: { status = "success"|"error", data = string }
````

**Asynchronous tools** (use a callback):
````lua
-- OLD:
function(self, args, _, cb)
  cb({ status = "success", data = result })
end
-- NEW:
function(self, args, opts)
  local cb = opts.output_cb
  cb({ status = "success", data = result })
end
````

**Consecutive cmds** (chained functions that pass data forward):
````lua
-- OLD: second function received previous output as 3rd positional arg
function(self, args, input)
-- NEW: previous output is in opts.input
function(self, args, opts)
  local input = opts.input
end
````

### `output` callbacks

**`success`:**
````lua
-- OLD:
success = function(self, tools, cmd, stdout)
  local chat = tools.chat
-- NEW:
success = function(self, stdout, meta)
  local chat = meta.tools.chat
  -- meta.cmd is also available if needed
````

**`error`:**
````lua
-- OLD:
error = function(self, tools, cmd, stderr)
  local chat = tools.chat
-- NEW:
error = function(self, stderr, meta)
  local chat = meta.tools.chat
````

**`rejected`:**
````lua
-- OLD:
rejected = function(self, tools, cmd, opts)
  helpers.rejected(self, { tools = tools, message = "..." })
-- NEW:
rejected = function(self, meta)
  -- meta already contains { tools, cmd, opts }
  local message = "The user rejected ..."
  meta = vim.tbl_extend("force", { message = message }, meta or {})
  helpers.rejected(self, meta)
````

**`prompt`:**
````lua
-- OLD:
prompt = function(self, tools)
-- NEW:
prompt = function(self, meta)
  -- meta contains { tools }
````

**`cmd_string`:**
````lua
-- OLD:
cmd_string = function(self, tools)
-- NEW:
cmd_string = function(self, meta)
  -- meta contains { tools }
````

**`cancelled`:**
````lua
-- OLD:
cancelled = function(self, tools, cmd)
  local chat = tools.chat
-- NEW:
cancelled = function(self, meta)
  local chat = meta.tools.chat
  -- meta.cmd is also available
````

### `handlers` callbacks

**`setup`:**
````lua
-- OLD:
setup = function(self, tools)
-- NEW:
setup = function(self, meta)
  -- meta contains { tools }
````

**`on_exit`:**
````lua
-- OLD:
on_exit = function(self, tools)
-- NEW:
on_exit = function(self, meta)
  -- meta contains { tools }
````

**`prompt_condition`:**
````lua
-- OLD:
prompt_condition = function(self, tools)
-- NEW:
prompt_condition = function(self, meta)
  -- meta contains { tools }
````

### Summary of the pattern

The core change is: **positional arguments have been replaced with structured tables**.

- `cmds` functions: `(self, args, opts)` where `opts = { input, output_cb }`
- `output.*` callbacks: `(self, stdout_or_stderr, meta)` where `meta = { tools, cmd }`
- `output.rejected`: `(self, meta)` where `meta = { tools, cmd, opts }`
- `output.prompt` / `output.cmd_string`: `(self, meta)` where `meta = { tools }`
- `handlers.*`: `(self, meta)` where `meta = { tools }`
- `helpers.rejected`: `(self, opts)` where `opts = { tools, message, reason }`

Anywhere you previously accessed `tools.chat`, you now access `meta.tools.chat`.

### Instructions

Please update my tool below to use the new API signatures. Only change the function signatures and how arguments are accessed — do not alter any business logic.

My tool can be found in #{buffer}.

