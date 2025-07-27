local Utils = require("codecompanion.strategies.chat.tools.catalog.list_code_usages.utils")
local log = require("codecompanion.utils.log")

---@class ListCodeUsages.LspHandler
local LspHandler = {}

local CONSTANTS = {
  LSP_METHODS = {
    references = vim.lsp.protocol.Methods.textDocument_references,
    documentation = vim.lsp.protocol.Methods.textDocument_hover,
  },
}

--- Filters LSP references to only include files within the current project
---
--- This function removes references from external dependencies, system files,
--- or other locations outside the current project directory to keep results
--- focused and relevant.
---
---@param references table[] Array of LSP reference objects with uri fields
---@return table[] Filtered array containing only project-local references
function LspHandler.filter_project_references(references)
  local filtered_results = {}

  for _, reference in ipairs(references) do
    local uri = reference.uri
    if uri then
      local filepath = Utils.uri_to_filepath(uri)
      if Utils.is_in_project(filepath) then
        table.insert(filtered_results, reference)
      end
    end
  end

  log:debug(
    "[LspHandler:filter_project_references] References filtered. Original: %d, Filtered: %d",
    #references,
    #filtered_results
  )

  return filtered_results
end

--- Asynchronously executes an LSP request across all capable clients
---
--- This function handles the complex process of:
--- 1. Finding all LSP clients that support the requested method
--- 2. Ensuring clients are attached to the target buffer
--- 3. Executing the request with proper position parameters
--- 4. Collecting and processing results from all clients
--- 5. Handling special cases like hover documentation and references
---
---@param bufnr number The buffer number to execute the request on
---@param method string The LSP method to execute (e.g., textDocument_references)
---@param callback function Callback called with collected results from all clients
function LspHandler.execute_request_async(bufnr, method, callback)
  local clients = vim.lsp.get_clients({ method = method })
  local lsp_results = {}
  local completed_clients = 0
  local total_clients = #clients

  if total_clients == 0 then
    callback({})
    return
  end

  for _, client in ipairs(clients) do
    if not vim.lsp.buf_is_attached(bufnr, client.id) then
      log:debug(
        "[LspHandler:execute_request_async] Attaching client %s to buffer %d for method %s",
        client.name,
        bufnr,
        method
      )
      vim.lsp.buf_attach_client(bufnr, client.id)
    end

    local position_params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    position_params.context = { includeDeclaration = false }

    client:request(method, position_params, function(_, result, _, _)
      if result then
        -- Handle hover documentation specially
        if method == CONSTANTS.LSP_METHODS.documentation and result.contents then
          result = {
            range = result.range,
            contents = result.contents.value or result.contents,
          }
        end

        -- For references, filter to just project references
        if method == CONSTANTS.LSP_METHODS.references and type(result) == "table" then
          lsp_results[client.name] = LspHandler.filter_project_references(result)
        else
          lsp_results[client.name] = result
        end
      end

      completed_clients = completed_clients + 1
      if completed_clients == total_clients then
        callback(lsp_results)
      end
    end, bufnr)
  end
end

return LspHandler
