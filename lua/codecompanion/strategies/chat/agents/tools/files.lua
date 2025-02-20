--[[
*Files Tool*
This tool can be used make edits to files on disk. It can handle multiple actions
in the same XML block. All actions must be approved by you.
--]]

local Path = require("plenary.path")
local config = require("codecompanion.config")

local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local fmt = string.format
local file = nil

---Create a file and it's surrounding folders
---@param action table The action object
---@return nil
local function create(action)
  local p = Path:new(action.path)
  p.filename = p:expand()
  p:touch({ parents = true })
  p:write(action.contents or "", "w")
end

---Read the contents of af ile
---@param action table The action object
---@return table<string, string>
local function read(action)
  local p = Path:new(action.path)
  p.filename = p:expand()
  file = {
    content = p:read(),
    filetype = vim.fn.fnamemodify(p.filename, ":e"),
  }
  return file
end

---Read the contents of a file between specific lines
---@param action table The action object
---@return nil
local function read_lines(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  -- Read requested lines
  local extracted = {}
  local current_line = 0

  local lines = p:iter()

  -- Parse line numbers
  local start_line = tonumber(action.start_line) or 1
  local end_line = tonumber(action.end_line) or #lines

  for line in lines do
    current_line = current_line + 1
    if current_line >= start_line and current_line <= end_line then
      table.insert(extracted, current_line .. ":  " .. line)
    end
    if current_line > end_line then
      break
    end
  end

  file = {
    content = table.concat(extracted, "\n"),
    filetype = vim.fn.fnamemodify(p.filename, ":e"),
  }
  return file
end

---Edit the contents of a file
---@param action table The action object
---@return nil
local function edit(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  local content = p:read()
  if not content then
    return util.notify(fmt("No data found in %s", action.path))
  end

  if not content:find(vim.pesc(action.search)) then
    return util.notify(fmt("Could not find the search string in %s", action.path))
  end

  p:write(content:gsub(vim.pesc(action.search), vim.pesc(action.replace)))
end

---Delete a file
---@param action table The action object
---@return nil
local function delete(action)
  local p = Path:new(action.path)
  p.filename = p:expand()
  p:rm()
end

---Rename a file
---@param action table The action object
---@return nil
local function rename(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  local new_p = Path:new(action.new_path)
  new_p.filename = new_p:expand()

  p:rename({ new_name = new_p.filename })
end

---Copy a file
---@param action table The action object
---@return nil
local function copy(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  local new_p = Path:new(action.new_path)
  new_p.filename = new_p:expand()

  p:copy({ destination = new_p.filename, parents = true })
end

---Move a file
---@param action table The action object
---@return nil
local function move(action)
  local p = Path:new(action.path)
  p.filename = p:expand()

  local new_p = Path:new(action.new_path)
  new_p.filename = new_p:expand()

  p:copy({ destination = new_p.filename, parents = true })
  p:rm()
end

local actions = {
  create = create,
  read = read,
  read_lines = read_lines,
  edit = edit,
  delete = delete,
  rename = rename,
  copy = copy,
  move = move,
}

---@class CodeCompanion.Tool
return {
  name = "files",
  actions = actions,
  cmds = {
    ---Execute the file commands
    ---@param self CodeCompanion.Agent.Tool The Tools object
    ---@param action table The action object
    ---@param input any The output from the previous function call
    ---@return { status: string, msg: string }
    function(self, action, input)
      local ok, data = pcall(actions[action._attr.type], action)
      if not ok then
        return { status = "error", msg = data }
      end
      return { status = "success", msg = nil }
    end,
  },
  schema = {
    {
      tool = {
        _attr = { name = "files" },
        action = {
          _attr = { type = "create" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
          contents = "<![CDATA[    print('Hello World')]]>",
        },
      },
    },
    {
      tool = {
        _attr = { name = "files" },
        action = {
          _attr = { type = "read" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
        },
      },
    },
    {
      tool = {
        _attr = { name = "files" },
        action = {
          _attr = { type = "read_lines" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
          start_line = "1",
          end_line = "10",
        },
      },
    },
    {
      tool = {
        _attr = { name = "files" },
        action = {
          _attr = { type = "edit" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
          search = "<![CDATA[    print('Hello World')]]>",
          replace = "<![CDATA[    print('Hello CodeCompanion')]]>",
        },
      },
    },
    {
      tool = {
        _attr = { name = "files" },
        action = {
          _attr = { type = "delete" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
        },
      },
    },
    {
      tool = {
        _attr = { name = "files" },
        action = {
          _attr = { type = "rename" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
          new_path = "/Users/Oli/Code/new_app/new_hello_world.py",
        },
      },
    },
    {
      tool = {
        _attr = { name = "files" },
        action = {
          _attr = { type = "copy" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
          new_path = "/Users/Oli/Code/old_app/hello_world.py",
        },
      },
    },
    {
      tool = {
        _attr = { name = "files" },
        action = {
          _attr = { type = "move" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
          new_path = "/Users/Oli/Code/new_app/new_folder/hello_world.py",
        },
      },
    },
    {
      tool = { name = "files" },
      action = {
        {
          _attr = { type = "create" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
          contents = "<![CDATA[    print('Hello World')]]>",
        },
        {
          _attr = { type = "edit" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
          contents = "<![CDATA[    print('Hello CodeCompanion')]]>",
        },
      },
    },
  },
  system_prompt = function(schema)
    return fmt(
      [[### Files Tool (`files`)

1. **Purpose**: Create/Edit/Delete/Rename/Copy files on the file system.

2. **Usage**: Return an XML markdown code block for create, edit or delete operations.

3. **Key Points**:
  - **Only use when you deem it necessary**. The user has the final control on these operations through an approval mechanism.
  - Ensure XML is **valid and follows the schema**
  - **Include indentation** in the file's content
  - **Don't escape** special characters
  - **Wrap contents in a CDATA block**, the contents could contain characters reserved by XML
  - **Don't duplicate code** in the response. Consider writing code directly into the contents tag of the XML
  - The user's current working directory in Neovim is `%s`. They may refer to this in their message to you
  - Make sure the tools xml block is **surrounded by ```xml**
  - Do not hallucinate. If you can't read a file's contents, say so

4. **Actions**:

a) Create:

```xml
%s
```
- This will ensure a file is created at the specified path with the given content.
- It will also ensure that any folders that don't exist in the path are created.

b) Read:

```xml
%s
```
- This will output the contents of a file at the specified path.

c) Read Lines (inclusively):

```xml
%s
```
- This will read specific line numbers (between the start and end lines, inclusively) in the file at the specified path
- This can be useful if you have been given the symbolic outline of a file and need to see more of the file's content

d) Edit:

```xml
%s
```

- This will ensure a file is edited at the specified path
- Ensure that you are terse with which text to search for and replace
- Be specific about what text to search for and what to replace it with
- If the text is not found, the file will not be edited

e) Delete:

```xml
%s
```
- This will ensure a file is deleted at the specified path.

f) Rename:

```xml
%s
```
- Ensure `new_path` contains the filename

i) Copy:

```xml
%s
```
- Ensure `new_path` contains the filename
- Any folders that don't exist in the path will be created

j) Move:

```xml
%s
```
- Ensure `new_path` contains the filename
- Any folders that don't exist in the path will be created

5. **Multiple Actions**: Combine actions in one response if needed:

```xml
%s
```

Remember:
- Minimize explanations unless prompted. Focus on generating correct XML.
- If the user types `~` in their response, do not replace or expand it.
- Wait for the user to share the outputs with you before responding.]],
      vim.fn.getcwd(),
      xml2lua.toXml({ tools = { schema[1] } }), -- Create
      xml2lua.toXml({ tools = { schema[2] } }), -- Read
      xml2lua.toXml({ tools = { schema[3] } }), -- Extract
      xml2lua.toXml({ tools = { schema[4] } }),
      xml2lua.toXml({ tools = { schema[5] } }),
      xml2lua.toXml({ tools = { schema[6] } }),
      xml2lua.toXml({ tools = { schema[7] } }),
      xml2lua.toXml({ tools = { schema[8] } }),
      xml2lua.toXml({
        tools = {
          tool = {
            _attr = { name = "files" },
            action = {
              schema[#schema].action[1],
              schema[#schema].action[2],
            },
          },
        },
      })
    )
  end,
  handlers = {
    ---Approve the command to be run
    ---@param self CodeCompanion.Agent The tool object
    ---@param action table
    ---@return boolean
    approved = function(self, action)
      if vim.g.codecompanion_auto_tool_mode then
        log:info("[Files Tool] Auto-approved running the command")
        return true
      end

      log:info("[Files Tool] Prompting for: %s", string.upper(action._attr.type))

      local prompts = {
        base = function(a)
          return fmt("%s the file at `%s`?", string.upper(a._attr.type), vim.fn.fnamemodify(a.path, ":."))
        end,
        move = function(a)
          return fmt(
            "%s file from `%s` to `%s`?",
            string.upper(a._attr.type),
            vim.fn.fnamemodify(a.path, ":."),
            vim.fn.fnamemodify(a.new_path, ":.")
          )
        end,
      }

      local prompt = prompts.base(action)
      if action.new_path then
        prompt = prompts.move(action)
      end

      local ok, choice = pcall(vim.fn.confirm, prompt, "No\nYes")
      if not ok or choice ~= 2 then
        log:info("[Files Tool] Rejected the %s action", string.upper(action._attr.type))
        return false
      end

      log:info("[Files Tool] Approved the %s action", string.upper(action._attr.type))
      return true
    end,
    on_exit = function(self)
      log:debug("[Files Tool] on_exit handler executed")
      file = nil
    end,
  },
  output = {
    success = function(self, action, output)
      local type = action._attr.type
      local path = action.path
      log:debug("[Files Tool] success callback executed")
      util.notify(fmt("The files tool executed successfully for the `%s` file", vim.fn.fnamemodify(path, ":t")))

      if file then
        self.chat:add_message({
          role = config.constants.USER_ROLE,
          content = fmt(
            [[The output from the %s action for file `%s` is:

```%s
%s
```]],
            string.upper(type),
            path,
            file.filetype,
            file.content
          ),
        }, { visible = false })
      end
    end,

    error = function(self, action, err)
      log:debug("[Files Tool] error callback executed")
      return self.chat:add_buf_message({
        role = config.constants.USER_ROLE,
        content = fmt(
          [[There was an error running the %s action:

```txt
%s
```]],
          string.upper(action._attr.type),
          err
        ),
      })
    end,

    rejected = function(self, action)
      return self.chat:add_buf_message({
        role = config.constants.USER_ROLE,
        content = fmt("I rejected the %s action.\n\n", string.upper(action._attr.type)),
      })
    end,
  },
}
