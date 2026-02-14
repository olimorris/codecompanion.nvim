local M = {}

---Test cases for diff visualization
M.test_cases = {
  {
    name = "Zed Example - Multiple small changes",
    filetype = "rust",
    before = [[
async fn run_cargo_build_json() -> io::Result<Option<String>> {
    let mut child = Command::new("cargo")
        .args(["build", "--message-format=json"])
        .stdout(Stdio::piped())
}
]],
    after = [[
async fn rn_crgo_build_jsons() -> io::Result<Option<String>> {
    let mut childddd = Command::new("cargo")
        .ars(["build", "--message-format=json"])
        .stddddouttt(Stdio::piped())
}
]],
  },
  {
    name = "Line additions",
    filetype = "lua",
    before = [[
return {
  "CodeCompanion is amazing - Oli Morris"
}
]],
    after = [[
return {
  "CodeCompanion is amazing - Oli Morris"
  "Lua and Neovim are amazing too - Oli Morris"
  "Happy coding!"
  "Hello world"
}
]],
  },
  {
    name = "Line deletions",
    filetype = "python",
    before = [[
def process():
    step1()
    step2()
    step3()
    step4()
]],
    after = [[
def process():
    step1()
    step4()
]],
  },
  {
    name = "Long file - Variable rename and deletion",
    filetype = "lua",
    before = [[
local M = {}

---@class ConfigManager
---@field options table
---@field defaults table
---@field callbacks table
local ConfigManager = {}
ConfigManager.__index = ConfigManager

---Create a new config manager instance
---@param opts? table
---@return ConfigManager
function ConfigManager.new(opts)
  local self = setmetatable({}, ConfigManager)
  self.defaults = {
    enable_logging = true,
    log_level = "info",
    cache_enabled = true,
    max_cache_size = 1000,
    timeout = 5000,
  }
  self.options = vim.tbl_deep_extend("force", self.defaults, opts or {})
  self.callbacks = {}
  return self
end

---Get a configuration value
---@param key string
---@return any
function ConfigManager:get(key)
  return self.options[key]
end

---Set a configuration value
---@param key string
---@param value any
function ConfigManager:set(key, value)
  local old_value = self.options[key]
  self.options[key] = value
  self:_notify_changed(key, old_value, value)
end

---Register a callback for config changes
---@param callback function
function ConfigManager:on_change(callback)
  table.insert(self.callbacks, callback)
end

---Notify callbacks of changes
---@param key string
---@param old_value any
---@param new_value any
function ConfigManager:_notify_changed(key, old_value, new_value)
  for _, callback in ipairs(self.callbacks) do
    callback(key, old_value, new_value)
  end
end

---Reset to defaults
function ConfigManager:reset()
  self.options = vim.deepcopy(self.defaults)
end

M.ConfigManager = ConfigManager
return M
]],
    after = [[
local M = {}

---@class ConfigManager
---@field settings table
---@field defaults table
---@field callbacks table
local ConfigManager = {}
ConfigManager.__index = ConfigManager

---Create a new config manager instance
---@param opts? table
---@return ConfigManager
function ConfigManager.new(opts)
  local self = setmetatable({}, ConfigManager)
  self.defaults = {
    enable_logging = true,
    log_level = "info",
    cache_enabled = true,
    max_cache_size = 1000,
    timeout = 5000,
  }
  self.settings = vim.tbl_deep_extend("force", self.defaults, opts or {})
  self.callbacks = {}
  return self
end

---Get a configuration value
---@param key string
---@return any
function ConfigManager:get(key)
  return self.settings[key]
end

---Set a configuration value
---@param key string
---@param value any
function ConfigManager:set(key, value)
  local old_value = self.settings[key]
  self.settings[key] = value
  self:_notify_changed(key, old_value, value)
end

---Register a callback for config changes
---@param callback function
function ConfigManager:on_change(callback)
  table.insert(self.callbacks, callback)
end

---Notify callbacks of changes
---@param key string
---@param old_value any
---@param new_value any
function ConfigManager:_notify_changed(key, old_value, new_value)
  for _, callback in ipairs(self.callbacks) do
    callback(key, old_value, new_value)
  end
end

M.ConfigManager = ConfigManager
return M
]],
  },
  {
    name = "TypeScript - Import and logger changes",
    filetype = "typescript",
    before = [[
import { ApiClient } from './api/client';
import { Logger } from './utils/logger';
import type { User, UserPreferences, ApiResponse } from './types';

const apiClient = new ApiClient();
const logger = new Logger('useUserManager');

/**
 * Fetch user preferences from the API
 */
const fetchPreferences = async (userId: string) => {
  try {
    const response: ApiResponse<UserPreferences> = await apiClient.get(
      `/users/${userId}/preferences`
    );

    if (response.success) {
      setPreferences(response.data);
      logger.info('Preferences fetched successfully', { userId });
    }
  } catch (err) {
    logger.error('Failed to fetch preferences', { userId, error: err });
  }

  return { user: currentUser, timeout: 500 };
};

const updatePreferences = useCallback(
  debounce(async (newPreferences: Partial<UserPreferences>) => {
    try {
      const response = await apiClient.patch(
        `/users/${userId}/preferences`,
        newPreferences
      );

      if (response.success) {
        setPreferences(prev => ({ ...prev, ...newPreferences } as UserPreferences));
        logger.info('Preferences updated successfully', { userId });
      }
    } catch (err) {
      logger.error('Failed to update preferences', { error: err });
    }
  }),
  []
);
]],
    after = [[
import { ApiClient } from './api/client';
import type { UserPreferences, ApiResponse } from './types';

const apiClient = new ApiClient();

/**
 * Fetch user preferences
 * Retrieves preferences for the given user ID
 */
const fetchPreferences = async (userId: string) => {
  try {
    const response: ApiResponse<UserPreferences> = await apiClient.get(
      `/users/${userId}/preferences`
    );

    if (response.success) {
      setPreferences(response.data);
    }
  } catch (err) {
    console.error('Failed to fetch preferences', { userId, error: err });
  }

  return { timeout: 500 };
};

const updatePreferences = useCallback(
  debounce(async (newPreferences: Partial<UserPreferences>) => {
    try {
      const response = await apiClient.patch(
        `/users/${userId}/preferences`,
        newPreferences
      );

      if (response.success) {
        setPreferences(prev => ({ ...prev, ...newPreferences } as UserPreferences));
      }
    } catch (err) {
      console.error('Failed to update preferences', { userId, error: err });
    }
  }, 500),
  [userId]
);
]],
  },
  {
    name = "Large addition - Scroll issue demo",
    filetype = "lua",
    before = [[
-- A simple module
local M = {}

return M
]],
    after = [[
-- A comprehensive module with many functions
local M = {}

---@class User
---@field id number
---@field name string
---@field email string
---@field created_at number
---@field updated_at number

---@class UserManager
---@field users table<number, User>
---@field next_id number
local UserManager = {}
UserManager.__index = UserManager

---Create a new UserManager instance
---@return UserManager
function UserManager.new()
  local self = setmetatable({}, UserManager)
  self.users = {}
  self.next_id = 1
  return self
end

---Create a new user
---@param name string
---@param email string
---@return User
function UserManager:create(name, email)
  local user = {
    id = self.next_id,
    name = name,
    email = email,
    created_at = os.time(),
    updated_at = os.time(),
  }
  self.users[user.id] = user
  self.next_id = self.next_id + 1
  return user
end

---Get a user by ID
---@param id number
---@return User?
function UserManager:get(id)
  return self.users[id]
end

---Update a user
---@param id number
---@param updates table
---@return User?
function UserManager:update(id, updates)
  local user = self.users[id]
  if not user then
    return nil
  end
  for key, value in pairs(updates) do
    if key ~= "id" and key ~= "created_at" then
      user[key] = value
    end
  end
  user.updated_at = os.time()
  return user
end

---Delete a user
---@param id number
---@return boolean
function UserManager:delete(id)
  if self.users[id] then
    self.users[id] = nil
    return true
  end
  return false
end

---List all users
---@return User[]
function UserManager:list()
  local result = {}
  for _, user in pairs(self.users) do
    table.insert(result, user)
  end
  return result
end

---Find users by name pattern
---@param pattern string
---@return User[]
function UserManager:find_by_name(pattern)
  local result = {}
  for _, user in pairs(self.users) do
    if user.name:match(pattern) then
      table.insert(result, user)
    end
  end
  return result
end

---Find user by email
---@param email string
---@return User?
function UserManager:find_by_email(email)
  for _, user in pairs(self.users) do
    if user.email == email then
      return user
    end
  end
  return nil
end

---Count total users
---@return number
function UserManager:count()
  local count = 0
  for _ in pairs(self.users) do
    count = count + 1
  end
  return count
end

---Export users to JSON-like table
---@return table
function UserManager:export()
  return {
    users = self:list(),
    total = self:count(),
    exported_at = os.time(),
  }
end

M.UserManager = UserManager

return M
]],
  },
}

---Create a test command for visual diff testing
function M.setup()
  vim.api.nvim_create_user_command("CodeCompanionDiffTest", function(opts)
    local test_num = tonumber(opts.args) or 1
    M.run_visual_test(test_num)
  end, {
    desc = "Test CodeCompanion diff provider (optional: test case number 1-" .. #M.test_cases .. ")",
    nargs = "?",
  })

  vim.api.nvim_create_user_command("CodeCompanionDiffInlineTest", function(opts)
    local test_num = tonumber(opts.args) or 1
    M.run_inline_test(test_num)
  end, {
    desc = "Test CodeCompanion inline diff provider (optional: test case number 1-" .. #M.test_cases .. ")",
    nargs = "?",
  })
end

---Run the visual diff test
---@param test_num? number Test case number (1-based)
function M.run_visual_test(test_num)
  test_num = test_num or 1

  if test_num < 1 or test_num > #M.test_cases then
    vim.notify(string.format("Invalid test case %d. Available: 1-%d", test_num, #M.test_cases), vim.log.levels.ERROR)
    return
  end

  local test_case = M.test_cases[test_num]
  local before_lines = vim.split(test_case.before, "\n", { plain = true })
  local after_lines = vim.split(test_case.after, "\n", { plain = true })

  local helpers = require("codecompanion.helpers")
  local diff_id = math.random(10000000)

  local diff_ui = helpers.show_diff({
    from_lines = before_lines,
    to_lines = after_lines,
    ft = test_case.filetype,
    title = string.format("%s (Test %d/%d)", test_case.name, test_num, #M.test_cases),
    diff_id = diff_id,
    keymaps = {
      on_accept = function()
        vim.notify(
          string.format("Test %d/%d: Changes ACCEPTED", test_num, #M.test_cases),
          vim.log.levels.INFO,
          { title = "CodeCompanion Diff Test" }
        )
      end,
      on_reject = function()
        vim.notify(
          string.format("Test %d/%d: Changes REJECTED", test_num, #M.test_cases),
          vim.log.levels.WARN,
          { title = "CodeCompanion Diff Test" }
        )
      end,
    },
  })

  return diff_ui
end

---Run the inline diff test
---@param test_num? number Test case number (1-based)
function M.run_inline_test(test_num)
  test_num = test_num or 1

  if test_num < 1 or test_num > #M.test_cases then
    vim.notify(string.format("Invalid test case %d. Available: 1-%d", test_num, #M.test_cases), vim.log.levels.ERROR)
    return
  end

  local test_case = M.test_cases[test_num]
  local before_lines = vim.split(test_case.before, "\n", { plain = true })
  local after_lines = vim.split(test_case.after, "\n", { plain = true })
  local bufnr = vim.api.nvim_create_buf(true, false)

  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, before_lines)
  vim.api.nvim_set_option_value("filetype", test_case.filetype, { buf = bufnr })

  local helpers = require("codecompanion.helpers")
  local diff_id = math.random(10000000)

  local diff_ui = helpers.show_diff({
    from_lines = before_lines,
    to_lines = after_lines,
    ft = test_case.filetype,
    title = string.format("%s (Inline Test %d/%d)", test_case.name, test_num, #M.test_cases),
    diff_id = diff_id,
    bufnr = bufnr,
    inline = true,
    keymaps = {
      on_accept = function()
        vim.notify(
          string.format("Inline Test %d/%d: Changes ACCEPTED", test_num, #M.test_cases),
          vim.log.levels.INFO,
          { title = "CodeCompanion Diff Inline Test" }
        )
      end,
      on_reject = function()
        vim.notify(
          string.format("Inline Test %d/%d: Changes REJECTED", test_num, #M.test_cases),
          vim.log.levels.WARN,
          { title = "CodeCompanion Diff Inline Test" }
        )
      end,
    },
  })

  return diff_ui
end

return M
