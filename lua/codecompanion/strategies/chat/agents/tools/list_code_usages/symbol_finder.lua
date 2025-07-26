local Utils = require("codecompanion.strategies.chat.agents.tools.list_code_usages.utils")
local log = require("codecompanion.utils.log")

---@class ListCodeUsages.SymbolFinder
local SymbolFinder = {}

local CONSTANTS = {
  --- Directories to exclude from grep searches to improve performance and relevance
  EXCLUDED_DIRS = { "node_modules", "dist", "vendor", ".git", "venv", ".env", "target", "build" },
}

--- Asynchronously finds symbols using LSP workspace symbol search
---
--- This function queries all available LSP clients that support workspace symbol
--- search to find symbols matching the given name. It filters results by file paths
--- if provided and sorts them by symbol kind to prioritize definitions.
---
---@param symbolName string The name of the symbol to search for
---@param filepaths string[]|nil Optional array of file paths to filter results
---@param callback function Callback function called with array of found symbols
function SymbolFinder.find_with_lsp_async(symbolName, filepaths, callback)
  local clients = vim.lsp.get_clients({
    method = vim.lsp.protocol.Methods.workspace_symbol,
  })

  if #clients == 0 then
    callback({})
    return
  end

  local symbols = {}
  local completed_clients = 0
  local total_clients = #clients

  for _, client in ipairs(clients) do
    local params = { query = symbolName }

    client:request(vim.lsp.protocol.Methods.workspace_symbol, params, function(err, result, _, _)
      if result then
        for _, symbol in ipairs(result) do
          if symbol.name == symbolName then
            local filepath = Utils.uri_to_filepath(symbol.location.uri)

            -- Filter by filepaths if specified
            if filepaths and #filepaths > 0 then
              local match = false
              for _, pattern in ipairs(filepaths) do
                if filepath:find(pattern) then
                  match = true
                  break
                end
              end
              if not match then
                goto continue
              end
            end

            table.insert(symbols, {
              uri = symbol.location.uri,
              range = symbol.location.range,
              name = symbol.name,
              kind = symbol.kind,
              file = filepath,
            })

            ::continue::
          end
        end
      end

      completed_clients = completed_clients + 1
      if completed_clients == total_clients then
        -- Sort symbols by kind to prioritize definitions
        table.sort(symbols, function(a, b)
          return (a.kind or 999) < (b.kind or 999)
        end)

        log:debug("[SymbolFinder:find_with_lsp_async] Found symbols with LSP:\n %s", vim.inspect(symbols))
        callback(symbols)
      end
    end)
  end
end

--- Asynchronously finds symbols using grep-based text search
---
--- This function performs a grep search for the symbol name, with optional filtering
--- by file extension and specific file paths. It uses Neovim's built-in grep functionality
--- and populates the quickfix list with results.
---
---@param symbolName string The name of the symbol to search for
---@param file_extension string|nil Optional file extension to limit search scope
---@param filepaths string[]|nil Optional array of file paths to search within
---@param callback function Callback called with grep result object or nil if no matches
function SymbolFinder.find_with_grep_async(symbolName, file_extension, filepaths, callback)
  vim.schedule(function()
    local search_pattern = vim.fn.escape(symbolName, "\\")
    local cmd = "silent! grep! -w"

    -- Add file extension filter if provided
    if file_extension and file_extension ~= "" then
      cmd = cmd .. " --glob=" .. vim.fn.shellescape("*." .. file_extension) .. " "
    end

    -- Add exclusion patterns for directories
    for _, dir in ipairs(CONSTANTS.EXCLUDED_DIRS) do
      cmd = cmd .. " --glob=!" .. vim.fn.shellescape(dir .. "/**") .. " "
    end

    cmd = cmd .. vim.fn.shellescape(search_pattern)

    -- Add file paths if provided
    if filepaths and type(filepaths) == "table" and #filepaths > 0 then
      cmd = cmd .. " " .. table.concat(filepaths, " ")
    end

    log:debug("[SymbolFinder:find_with_grep_async] Executing grep command: %s", cmd)

    local success, _ = pcall(vim.cmd, cmd)
    if not success then
      callback(nil)
      return
    end

    local qflist = vim.fn.getqflist()
    if #qflist == 0 then
      callback(nil)
      return
    end

    log:debug("[SymbolFinder:find_with_grep_async] Found grep matches: \n %s", vim.inspect(qflist))

    local first_match = qflist[1]
    callback({
      file = vim.fn.bufname(first_match.bufnr),
      line = first_match.lnum,
      col = first_match.col,
      text = first_match.text,
      bufnr = first_match.bufnr,
      qflist = qflist,
    })
  end)
end

return SymbolFinder
