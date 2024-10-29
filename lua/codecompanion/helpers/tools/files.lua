local Path = require("plenary.path")
local config = require("codecompanion.config")

local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils.util")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local accepted = {}
local rejected = {}

---Create a file and it's surrounding folders
---@param action table The action object
---@return nil
local function create(action)
  local p = Path:new(action.path)
  p.filename = p:expand()
  p:touch({ parents = true })
  p:write(action.contents or "", "w")
end

---Edit the contents of a file
---@param action table The action object
--@return nil
local function edit(action)
  local p = Path:new(action.path)
  p.filename = p:expand()
  p:write(action.contents, "w")
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
  edit = edit,
  delete = delete,
  rename = rename,
  copy = copy,
  move = move,
}

---Ask the user to approve the action
---@param action table The action object
local function approve(action)
  log:info("[Files Tool] Prompting for %s", action._attr.type)

  local msg = string.upper(action._attr.type) .. " the file at " .. action.path
  if action.new_path then
    msg = msg .. " to " .. action.new_path
  end
  msg = msg .. "?"

  local ok, choice = pcall(vim.fn.confirm, msg, "No\nYes")
  if not ok or choice ~= 2 then
    log:info("[Files Tool] Rejected the %s action", action._attr.type)
    table.insert(rejected, {
      type = action._attr.type,
      path = action.path,
      new_path = action.new_path,
    })
    return
  end

  log:info("[Files Tool] Approved the %s action", action._attr.type)
  table.insert(accepted, {
    type = action._attr.type,
    path = action.path,
    new_path = action.new_path,
  })
  return actions[action._attr.type](action)
end

---@class CodeCompanion.Tool
return {
  name = "files",
  actions = actions,
  cmds = {
    ---Execute the file commands
    ---@param self CodeCompanion.Tools The Tools object
    ---@param input any The output from the previous function call
    ---@return table { status: string, output: string }
    function(self, input)
      accepted = {}
      rejected = {}

      local has_opts = config.strategies.agent.tools.files.opts

      -- Run the action
      local function run(action)
        if has_opts and has_opts.user_approval then
          approve(action)
        else
          actions[action._attr.type](action)
          log:info("[Files Tool] Auto-approved the %s action", action._attr.type)
        end
      end

      -- Loop through the actions
      local action = self.tool.request.action
      if util.is_array(action) then
        for _, v in ipairs(action) do
          run(v)
        end
      else
        run(action)
      end

      local function update_llm(tbl, str)
        vim.iter(tbl):each(function(v)
          local content = str .. string.upper(v.type) .. " the file at " .. v.path
          if v.new_path then
            content = content .. " to " .. v.new_path
          end
          self.chat:append_to_buf({
            content = content .. "\n",
          })
        end)
      end

      if #accepted > 0 or #rejected > 0 then
        self.chat:append_to_buf({
          content = "Below is a list of all the file system actions that I accepted or rejected:\n\n",
        })
      end

      if #accepted > 0 then
        update_llm(accepted, "[x] ")
      end
      if #rejected > 0 then
        update_llm(rejected, "[ ] ")
      end

      return { status = "success", output = nil }
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
          _attr = { type = "edit" },
          path = "/Users/Oli/Code/new_app/hello_world.py",
          contents = "<![CDATA[    print('Hello CodeCompanion')]]>",
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
    return string.format(
      [[### Files Tool

1. **Purpose**: Create/Edit/Delete/Rename/Copy files on the file system.

2. **Usage**: Return an XML markdown code block for create, edit or delete operations.

3. **Key Points**:
  - **Only use when you deem it necessary**. The user has the final control on these operations through an approval mechanism.
  - Ensure XML is **valid and follows the schema**
  - **Include indentation** in the file's content
  - **Don't escape** special characters
  - **Wrap contents in a CDATA block**, the contents could contain characters reserved by XML
  - **Don't duplicate code** in the response. Consider writing code directly into the contents tag of the XML

4. **Actions**:

a) Create:

```xml
%s
```
- This will ensure a file is created at the specified path with the given content.

b) Edit:

```xml
%s
```
- This will ensure a file is edited at the specified path and its contents replaced with the given content.

c) Delete:

```xml
%s
```
- This will ensure a file is deleted at the specified path.

d) Rename:

```xml
%s
```
- Ensure `new_path` contains the filename

e) Copy:

```xml
%s
```
- Ensure `new_path` contains the filename
- Any folders that don't exist in the path will be created

f) Move:

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
- If the user types `~` in their response, do not replace or expand it.]],
      xml2lua.toXml({ tools = { schema[1] } }),
      xml2lua.toXml({ tools = { schema[2] } }),
      xml2lua.toXml({ tools = { schema[3] } }),
      xml2lua.toXml({ tools = { schema[4] } }),
      xml2lua.toXml({ tools = { schema[5] } }),
      xml2lua.toXml({ tools = { schema[6] } }),
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
}
