local BaseTool = require("codecompanion.tools.base_tool")
local ctcr = require("codecompanion.tools.chunk")
local log = require("codecompanion.utils.log")
local rag = require("codecompanion.utils.rag")

---@class CodeCompanion.RagTool : CodeCompanion.CopilotTool
local RagTool = setmetatable({}, { __index = BaseTool })
RagTool.__index = RagTool

---@param copilot CodeCompanion.Copilot
function RagTool.new(copilot)
  local self = setmetatable(BaseTool.new(copilot), RagTool)
  self.name = "rag"
  return self
end

---@param args string table containing the arguments necessary for execution.
---@param callback fun(response: CodeCompanion.CopilotToolChunkResp)
-- function RagTool:execute(args, callback)
--   local address
--   local cmd = [[curl -X GET -H  "Accept: text/event-stream" ]]
--
--   -- Determine if it's a search or read query
--   if args:sub(1, 5) == "read:" then
--     address = "https://r.jina.ai/"
--     cmd = cmd .. address .. rag.encode(args:sub(6)) -- Remove "read:" from the query
--   else
--     address = "https://s.jina.ai/"
--     cmd = cmd .. address .. rag.encode(args) -- Default to search
--   end
--
--   log:info("Executing RAG command: %s", cmd)
--
--   -- Execute command and capture output
--   local output = io.popen(cmd .. " 2>&1"):read("*a")
--   log:info("Command output: %s", output)
--
--   callback(ctcr.new_final(self.copilot.bufnr, output))
-- end
local Job = require("plenary.job")

function RagTool:execute(args, callback)
  local query, address
  local stdout, stderr = {}, {}

  -- Determine if it's a search or read query
  if args:sub(1, 5) == "read:" then
    -- Remove "read:" from the query
    address = "https://r.jina.ai/"
    query = args:sub(6)
    --- trim whitespace
    query = query:gsub("^%s*(.-)%s*$", "%1")
  else
    -- Default to search
    address = "https://s.jina.ai/"
    query = rag.encode(args)
  end

  if query == "" then
    callback(ctcr.new_error(self.copilot.bufnr, "Invalid query"))
    return
  end

  log:info("query:%s", query)
  log:info("Executing RAG command: %s", address .. query)
  Job:new({
    command = "curl",
    args = { "-N", "-H", "Accept: text/event-stream", address .. query },
    on_exit = function(j, exit_code)
      vim.schedule(function()
        -- Process any remaining data in the buffer
        log:info("rag final result: %s", j:result())
        log:info("rag exited with code: %s", exit_code)
        log:info("rag error: %s", table.concat(stderr, "\n"))

        if #stderr > 0 then
          callback(ctcr.new_error(self.copilot.bufnr, "Command failed with exit code: " .. tostring(exit_code)))
        else
          callback(ctcr.new_final(self.copilot.bufnr))
        end
      end)
    end,
    on_stdout = function(_, chunk)
      vim.schedule(function()
        if not chunk or chunk == "" then
          return
        end

        callback(ctcr.new_progress(self.copilot.bufnr, chunk))
      end)
    end,
    on_stderr = function(_, data)
      table.insert(stderr, data)
    end,
  }):start()
end

function RagTool:description()
  return "Retrieval Augmented Generation tool for executing searches and reads."
end

function RagTool:input_format()
  return "A query to search for or the URL to browse. Use 'query' to search and 'read: query' to read."
end

function RagTool:output_format()
  return "The output of the RAG execution."
end

function RagTool:example()
  return [[
  1. search today in history
(rag)
```
today in history
```
output:==
```

2. read https://jina.ai/
(rag)
```
read: https://jina.ai/
```
output:==
    ]]
end

return RagTool
