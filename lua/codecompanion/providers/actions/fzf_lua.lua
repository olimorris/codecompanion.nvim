local config = require("codecompanion.config")
local fzf = require("fzf-lua")

---A custom fzf-lua previewer for the Action Palette
---@class CodeCompanion.Actions.FzfLua.ActionPreviewer: fzf-lua.previewer.Builtin
---@field name_to_item table<string, CodeCompanion.ActionItem>
local ActionPreviewer = require("fzf-lua.previewer.builtin").base:extend()

---Initialize the previewer instance
---@param o table? `previewer` table passed to `fzf_exec`
---@param opts fzf-lua.config.Base
function ActionPreviewer:new(o, opts)
  ActionPreviewer.super.new(self, o, opts)
  self.name_to_item = o.name_to_item
end

function ActionPreviewer:gen_winopts()
  local enforced_win_opts = {
    wrap = true,
    number = false,
    relativenumber = false,
    cursorcolumn = false,
    spell = false,
    list = false,
    signcolumn = "no",
    foldcolumn = "0",
    colorcolumn = "",
  }
  return vim.tbl_extend("force", self.winopts, enforced_win_opts)
end

function ActionPreviewer:should_clear_preview(_)
  return false
end

function ActionPreviewer:parse_entry(entry_str)
  if not entry_str or entry_str == "" then
    return {}
  end
  return self.name_to_item[entry_str] or {}
end

function ActionPreviewer:populate_preview_buf(entry_str)
  if not self.win or not self.win:validate_preview() then
    return
  end

  local item = self:parse_entry(entry_str)
  if not item or vim.tbl_isempty(item) then
    return
  end

  -- Update preview title to the action's name if available
  if item.name and type(item.name) == "string" and #item.name > 0 then
    self.win:update_preview_title(" " .. item.name .. " ")
  end

  if item.description == "[No messages]" and item.bufnr and vim.api.nvim_buf_is_valid(item.bufnr) then
    -- Attach the provided buffer directly
    -- Protect user buffer from being deleted when the previewer closes
    self.listed_buffers[tostring(item.bufnr)] = true
    self:set_preview_buf(item.bufnr)
    self:update_render_markdown()
  else
    local tmpbuf = self:get_tmp_buffer()
    local description = item.description and vim.split(item.description, "\n", { plain = true }) or { "No description" }
    vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, description)
    self:set_preview_buf(tmpbuf)
  end

  self.win:update_preview_scrollbar()
end

---@class CodeCompanion.Actions.Provider.FZF: CodeCompanion.SlashCommand.Provider
---@field context table
---@field resolve function
local FZF = {}

---@param args CodeCompanion.SlashCommand.ProviderArgs
function FZF.new(args)
  return setmetatable(args, { __index = FZF })
end

---@param items table The items to display in the picker
---@param opts? table The options for the picker
---@return nil
function FZF:picker(items, opts)
  opts = opts or {}
  opts.prompt = opts.prompt or config.display.action_palette.opts.title or "CodeCompanion actions"

  local names = vim.tbl_map(function(item)
    return item.name
  end, items)

  local name_to_item = {}
  for _, item in ipairs(items) do
    name_to_item[item.name] = item
  end

  fzf.fzf_exec(names, {
    winopts = { title = " " .. opts.prompt .. " " },
    previewer = {
      _ctor = function()
        return ActionPreviewer
      end,
      name_to_item = name_to_item,
    },
    actions = {
      ["default"] = function(selected)
        if not selected or #selected == 0 then
          return
        end
        for _, selection in ipairs(selected) do
          local item = name_to_item[selection]
          if item then
            return require("codecompanion.providers.actions.shared").select(self, item)
          end
        end
      end,
    },
  })
end

return FZF
