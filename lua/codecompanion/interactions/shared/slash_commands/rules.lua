local helpers = require("codecompanion.interactions.shared.rules.helpers")
local rules = require("codecompanion.interactions.shared.rules")

---A picker for rules
---@param chat? CodeCompanion.Chat
---@param callback fun(selected: table)
local function picker(chat, callback)
  vim.ui.select(helpers.list(chat), {
    prompt = "Select a rule",
    format_item = function(item)
      return item.name
    end,
  }, function(selected)
    if selected then
      callback(selected)
    end
  end)
end

---@class CodeCompanion.SlashCommand.Rules: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommand
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommand })

  return self
end

function SlashCommand:execute()
  picker(self.Chat, function(selected)
    self:output(selected)
  end)
end

---Execute the slash command
---@param selected table
---@return nil
function SlashCommand:output(selected)
  return rules
    .new({
      name = selected.name,
      files = selected.files,
      opts = selected.opts,
      parser = selected.parser,
    })
    :make({ chat = self.Chat, force = true })
end

---Render the slash command for the CLI interaction
---@param _ table
---@param callback fun(paths: string[]) Called with a table of relative file paths
---@return nil
function SlashCommand.cli_render(_, callback)
  picker(nil, function(selected)
    local rule = rules.new({
      files = selected.files,
      name = selected.name,
      opts = selected.opts,
      parser = "cli",
    })

    -- Strip file-level parsers so the group-level cli parser handles all files
    local files = rule:read_files(rule:resolve_paths())
    vim.iter(files):each(function(f)
      f.parser = nil
    end)
    rule.processed = rule:parse_files(files)

    local added = {}
    local paths = {}

    for _, file in ipairs(files) do
      local path = file.path
      if not added[path] then
        added[path] = true
        table.insert(paths, path)
      end
    end

    for _, f in ipairs(rule.processed) do
      if f.meta and f.meta.included_files then
        for _, included in ipairs(f.meta.included_files) do
          if not added[included] then
            added[included] = true
            table.insert(paths, included)
          end
        end
      end
    end

    callback(paths)
  end)
end

return SlashCommand
