---@class CodeCompanion.Command
---@field cmd string
---@field callback fun(args:table)
---@field opts CodeCompanion.Command.Opts

---@class CodeCompanion.Command.Opts:table
---@field desc string

local codecompanion = require("codecompanion")
local config = require("codecompanion.config")

local _cached_adapters = nil

---Get the available adapters from the config
---@return string[]
local function get_adapters()
  if not _cached_adapters then
    local config_adapters = vim.tbl_deep_extend("force", {}, config.adapters.acp, config.adapters.http)
    _cached_adapters = vim
      .iter(config_adapters)
      :filter(function(k, _)
        return k ~= "acp" and k ~= "http" and k ~= "opts"
      end)
      :map(function(k, _)
        return k
      end)
      :totable()
  end
  return _cached_adapters
end

---@type CodeCompanion.Command[]
return {
  {
    cmd = "CodeCompanion",
    callback = function(opts)
      -- Detect the user calling a prompt from the prompt library
      if opts.fargs[1] and string.sub(opts.fargs[1], 1, 1) == "/" then
        -- Get the prompt minus the slash
        local prompt = string.sub(opts.fargs[1], 2)

        if #opts.fargs > 1 then
          opts.user_prompt = table.concat(opts.fargs, " ", 2)
        end
        return codecompanion.prompt(prompt, opts)
      end

      -- If the user calls the command with no prompt, then ask for their input
      if #vim.trim(opts.args or "") == 0 then
        vim.ui.input({ prompt = config.display.action_palette.prompt }, function(input)
          if #vim.trim(input or "") == 0 then
            return
          end
          opts.args = input
          return codecompanion.inline(opts)
        end)
      else
        codecompanion.inline(opts)
      end
    end,
    opts = {
      desc = "Use the CodeCompanion Inline Assistant",
      range = true,
      nargs = "*",
      -- Reference:
      -- https://github.com/nvim-neorocks/nvim-best-practices?tab=readme-ov-file#speaking_head-user-commands
      complete = function(arg_lead, cmdline, cursor_pos)
        local param_key = arg_lead:match("^(%w+)=$")
        if param_key == "adapter" then
          local adapters = get_adapters()
          return vim
            .iter(adapters)
            :map(function(adapter)
              return adapter
            end)
            :totable()
        end

        local args = vim.split(cmdline, "%s+")
        local current_arg_index = #args

        -- If we're typing in the middle of an argument, adjust the index
        if cmdline:sub(cursor_pos, cursor_pos) ~= " " and arg_lead ~= "" then
          current_arg_index = current_arg_index
        else
          current_arg_index = current_arg_index + 1
        end

        -- Always provide completions for adapters, prompt library, and variables
        local completions = {}
        local adapters = get_adapters()
        local short_name_prompts = require("codecompanion.helpers").get_short_name_prompts()

        -- Add adapters
        for _, adapter in ipairs(adapters) do
          table.insert(completions, "adapter=" .. adapter)
        end

        -- Add prompt library items
        vim.iter(short_name_prompts):each(function(k)
          table.insert(completions, "/" .. k)
        end)

        -- Add inline variables
        for key, _ in pairs(config.strategies.inline.variables) do
          if key ~= "opts" then
            table.insert(completions, "#{" .. key .. "}")
          end
        end

        -- Filter based on what the user is typing
        return vim
          .iter(completions)
          :filter(function(completion)
            return completion:find(vim.pesc(arg_lead), 1, true) == 1
          end)
          :totable()
      end,
    },
  },
  {
    cmd = "CodeCompanionChat",
    callback = function(opts)
      local params = {}
      local prompt = {}
      local subcommand = nil

      for _, arg in ipairs(opts.fargs) do
        local key, value = arg:match("^(%w+)=(.+)$")
        if key and value then
          params[key] = value
        elseif arg:lower() == "toggle" or arg:lower() == "add" or arg:lower() == "refreshcache" then
          subcommand = arg:lower()
        else
          -- Anything else is a prompt
          table.insert(prompt, arg)
        end
      end

      opts.params = params
      opts.subcommand = subcommand

      if #prompt > 0 then
        opts.user_prompt = table.concat(prompt, " ")
        opts.args = opts.user_prompt
      end

      codecompanion.chat(opts)
    end,
    opts = {
      desc = "Work with a CodeCompanion chat buffer",
      range = true,
      nargs = "*",
      -- Reference:
      -- https://github.com/nvim-neorocks/nvim-best-practices?tab=readme-ov-file#speaking_head-user-commands
      complete = function(arg_lead, cmdline, _cursor_pos)
        -- Check if we're completing a parameter value (e.g., "adapter=" or "model=")
        local param_key = arg_lead:match("^(%w+)=$")
        if param_key == "adapter" then
          return get_adapters()
        elseif param_key == "model" then
          -- Extract the adapter from the command line
          local adapter_name = cmdline:match("adapter=(%S+)")
          if adapter_name then
            local config_adapters = vim.tbl_deep_extend("force", {}, config.adapters.acp, config.adapters.http)
            local adapter_config = config_adapters[adapter_name]
            if adapter_config then
              -- Resolve the adapter to get the full schema
              local ok, adapter = pcall(require("codecompanion.adapters").resolve, adapter_config)
              if ok and adapter and adapter.schema and adapter.schema.model and adapter.schema.model.choices then
                local choices = adapter.schema.model.choices

                -- Handle function choices
                if type(choices) == "function" then
                  local ok_fn, result = pcall(choices, adapter, { async = false })
                  if ok_fn and result then
                    choices = result
                  else
                    -- If the function call fails or returns nil, return empty
                    return {}
                  end
                end

                -- Extract model names from choices (if choices is not nil)
                if type(choices) == "table" then
                  if vim.islist(choices) then
                    return choices
                  else
                    return vim.tbl_keys(choices)
                  end
                end
              end
            end
          end
          return {}
        end

        -- Only show general completions when at the start (no partial param typed)
        if cmdline:match("^['<,'>]*CodeCompanionChat[!]*%s+$") or arg_lead == "" then
          local completions = {
            "adapter=",
            "model=",
            "Toggle",
            "Add",
            "RefreshCache",
          }

          return vim
            .iter(completions)
            :filter(function(key)
              return key:find(vim.pesc(arg_lead), 1, true) == 1
            end)
            :totable()
        end

        return {}
      end,
    },
  },
  {
    cmd = "CodeCompanionCmd",
    callback = function(opts)
      codecompanion.cmd(opts)
    end,
    opts = {
      desc = "Prompt the LLM to write a command for the command-line",
      range = false,
      nargs = "*",
    },
  },
  {
    cmd = "CodeCompanionActions",
    callback = function(opts)
      if opts.fargs[1] and opts.fargs[1]:lower() == "refresh" then
        local context = require("codecompanion.utils.context").get(vim.api.nvim_get_current_buf())
        require("codecompanion.actions").refresh_cache(context)
      end
      codecompanion.actions(opts)
    end,
    opts = {
      desc = "Open the CodeCompanion actions palette",
      range = true,
      nargs = "*",
      complete = function(arg_lead, cmdline, _cursor_pos)
        return { "refresh" }
      end,
    },
  },
}
