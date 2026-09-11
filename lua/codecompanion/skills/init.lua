local chat_helpers = require("codecompanion.interactions.chat.helpers")
local config = require("codecompanion.config")
local files = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")
local tags = require("codecompanion.interactions.shared.tags")
local yaml = require("codecompanion.utils.yaml")

local fmt = string.format

local SKILL_FILE = "SKILL.md"
local RESERVED_KEYS = { dirs = true, opts = true }

---@class CodeCompanion.Skill
---@field name string
---@field description string
---@field path string Absolute path to the skill's SKILL.md

---@class CodeCompanion.Skills.Group
---@field name string
---@field description? string
---@field skills string[] Names of the skills in the group

local M = {}

---@return boolean
local function has_yaml_parser()
  return pcall(vim.treesitter.language.add, "yaml")
end

---@param path string
---@return CodeCompanion.Skill|nil
local function parse_skill(path)
  local content = files.read(path)
  if not content then
    return log:warn("[Skills] Could not read `%s`", path)
  end

  local frontmatter = files.normalize_content(content):match("^%-%-%-\n(.-)\n%-%-%-")
  if not frontmatter then
    return log:warn("[Skills] `%s` has no frontmatter", path)
  end

  local ok, parsed = pcall(yaml.decode, frontmatter)
  if not ok or type(parsed) ~= "table" then
    return log:warn("[Skills] Could not parse the frontmatter in `%s`", path)
  end
  if not parsed.name or not parsed.description then
    return log:warn("[Skills] `%s` needs both a `name` and a `description` in its frontmatter", path)
  end

  return { name = parsed.name, description = parsed.description, path = path }
end

---Scan the configured dirs for skills, sorted by name
---@return CodeCompanion.Skill[]
function M.list()
  if not has_yaml_parser() then
    log:warn("[Skills] Install the yaml parser with `:TSInstall yaml` and try again")
    return {}
  end

  -- Later dirs take precedence, so a project skill overrides a personal one of the same name
  local by_name = {}
  for _, configured_dir in ipairs(config.skills.dirs or {}) do
    local dir = vim.fs.abspath(vim.fs.normalize(configured_dir))
    if files.is_dir(dir) then
      for entry in vim.fs.dir(dir) do
        local skill_file = vim.fs.joinpath(dir, entry, SKILL_FILE)
        if files.exists(skill_file) then
          local skill = parse_skill(skill_file)
          if skill then
            by_name[skill.name] = skill
          end
        end
      end
    end
  end

  local skills = vim.tbl_values(by_name)
  table.sort(skills, function(a, b)
    return a.name < b.name
  end)

  return skills
end

---The skill groups defined in the config, sorted by name
---@return CodeCompanion.Skills.Group[]
function M.groups()
  local groups = {}
  for name, group in pairs(config.skills or {}) do
    if not RESERVED_KEYS[name] and type(group) == "table" then
      table.insert(groups, { name = name, description = group.description, skills = group.skills or {} })
    end
  end

  table.sort(groups, function(a, b)
    return a.name < b.name
  end)

  return groups
end

---Resolve group names and skill names into the skills they refer to
---@param names string[]
---@return CodeCompanion.Skill[]
function M.resolve(names)
  local discovered = {}
  for _, skill in ipairs(M.list()) do
    discovered[skill.name] = skill
  end

  local groups = {}
  for _, group in ipairs(M.groups()) do
    groups[group.name] = group
  end

  local resolved = {}
  local seen = {}

  local function add(name)
    local skill = discovered[name]
    if not skill then
      return log:warn("[Skills] Could not find a skill named `%s`", name)
    end
    if not seen[name] then
      seen[name] = true
      table.insert(resolved, skill)
    end
  end

  for _, name in ipairs(names) do
    local group = groups[name]
    if group then
      vim.iter(group.skills):each(add)
    else
      add(name)
    end
  end

  return resolved
end

---@param opts { adapter: CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter }
---@return boolean
function M.available_for(opts)
  if config.skills.opts.chat.enabled == false then
    return false
  end

  local adapter = opts.adapter
  return adapter ~= nil and adapter.type == "http" and adapter.opts.tools ~= false
end

---@param skill CodeCompanion.Skill
---@return string
local function get_skill_id(skill)
  return "<skill>" .. skill.name .. "</skill>"
end

---Tell the chat a skill exists and give it the tools to load it on demand
---@param chat CodeCompanion.Chat
---@param skill CodeCompanion.Skill
---@return nil
local function add_skill(chat, skill)
  local id = get_skill_id(skill)
  if chat_helpers.has_context(id, chat.messages) then
    return
  end

  chat.tool_registry:add_single_tool("read_file")
  chat.tool_registry:add_single_tool("run_command")

  local content = fmt(
    "The `%s` skill is available: %s\nRead `%s` when the skill applies and follow its instructions.",
    skill.name,
    skill.description,
    skill.path
  )

  chat:add_context({ role = config.constants.SYSTEM_ROLE, content = content }, "skills", id, {
    path = skill.path,
    tag = tags.SKILLS,
  })
end

---@param chat CodeCompanion.Chat
---@param skills CodeCompanion.Skill[]
---@return nil
function M.add_to_chat(chat, skills)
  if not M.available_for(chat) then
    return
  end

  vim.iter(skills):each(function(skill)
    add_skill(chat, skill)
  end)
end

---Add the skills a new chat asked for, falling back to the configured autoload
---@param chat CodeCompanion.Chat
---@param names? string[]|fun(): string[] Group or skill names
---@return nil
function M.autoload(chat, names)
  names = names or config.skills.opts.chat.autoload
  if type(names) == "function" then
    names = names()
  end
  if not names or vim.tbl_isempty(names) then
    return
  end

  M.add_to_chat(chat, M.resolve(names))
end

return M
