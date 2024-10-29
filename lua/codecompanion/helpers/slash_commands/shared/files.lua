local log = require("codecompanion.utils.log")

return {
  ---The default provider. Requires a git enabled repository
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@param output function
  ---@return nil
  default = function(SlashCommand, output)
    local check_git = vim.fn.system("git rev-parse --is-inside-work-tree")
    if check_git == 1 then
      return log:error(
        "The default provider requires the repository to be git enabled. Please select an alternative provider."
      )
    end

    local tracked_files = vim.fn.system(string.format("git -C %s ls-files", vim.fn.getcwd()))
    local untracked_files =
      vim.fn.system(string.format("git -C %s ls-files --others --exclude-standard", vim.fn.getcwd()))
    local files = tracked_files .. "\n" .. untracked_files

    files = vim
      .iter(vim.split(files, "\n"))
      :map(function(f)
        return { relative_path = f, path = vim.fn.getcwd() .. "/" .. f }
      end)
      :totable()

    vim.ui.select(files, {
      prompt = "Select a file",
      format_item = function(item)
        return item.relative_path
      end,
    }, function(selected)
      if not selected then
        return
      end

      return output(SlashCommand, selected)
    end)
  end,

  ---The Telescope provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@param output function
  ---@return nil
  telescope = function(SlashCommand, output)
    local ok, telescope = pcall(require, "telescope.builtin")
    if not ok then
      return log:error("Telescope is not installed")
    end

    telescope.find_files({
      prompt_title = CONSTANTS.PROMPT,
      attach_mappings = function(prompt_bufnr, map)
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")

        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            selection = { relative_path = selection[1], path = selection.path }
            output(SlashCommand, selection)
          end
        end)

        return true
      end,
    })
  end,

  ---The mini.pick provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@param output function
  ---@return nil
  mini_pick = function(SlashCommand, output)
    local ok, mini_pick = pcall(require, "mini.pick")
    if not ok then
      return log:error("mini.pick is not installed")
    end
    mini_pick.builtin.files({}, {
      source = {
        name = CONSTANTS.PROMPT,
        choose = function(path)
          local success, _ = pcall(function()
            output(SlashCommand, { path = path })
          end)
          if success then
            return nil
          end
        end,
      },
    })
  end,

  ---The fzf-lua provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@param output function
  ---@return nil
  fzf_lua = function(SlashCommand, output)
    local ok, fzf_lua = pcall(require, "fzf-lua")
    if not ok then
      return log:error("fzf-lua is not installed")
    end

    fzf_lua.files({
      prompt = CONSTANTS.PROMPT,
      actions = {
        ["default"] = function(selected, o)
          if not selected or #selected == 0 then
            return
          end
          local file = fzf_lua.path.entry_to_file(selected[1], o)
          local selection = { relative_path = file.stripped, path = file.path }
          output(SlashCommand, selection)
        end,
      },
    })
  end,
}
