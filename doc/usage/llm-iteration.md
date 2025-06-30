# LLM 迭代管理

CodeCompanion 提供了智能迭代管理功能，防止无限循环并优化上下文使用。这个功能包括上下文摘要、迭代限制和进度显示。

## 🚀 异步处理和性能优化

### 新的异步功能

为了避免阻塞 Neovim UI，迭代功能现在支持异步处理：

- **异步上下文摘要**：摘要生成不会冻结界面
- **非阻塞用户确认**：使用 `vim.ui.select` 而不是 `vim.fn.confirm`
- **事件驱动进度**：通过 CodeCompanion 事件系统支持进度显示

### 与 Fidget.nvim 集成

迭代功能通过 CodeCompanion 的事件系统工作，这意味着您可以使用现有的 Fidget 集成来显示进度：

#### 监听迭代相关事件

```lua
local group = vim.api.nvim_create_augroup("CodeCompanionIterationProgress", {})

-- 监听所有请求事件来显示进度
vim.api.nvim_create_autocmd({ "User" }, {
  pattern = "CodeCompanionRequest*",
  group = group,
  callback = function(request)
    -- 上下文摘要请求
    if request.match == "CodeCompanionRequestStartedContextSummarization" then
      -- Fidget 会自动显示 "Context Summarization" 进度
    elseif request.match == "CodeCompanionRequestFinishedContextSummarization" then
      -- 摘要完成
    end
    
    -- 常规 LLM 请求（包括迭代请求）
    if request.match == "CodeCompanionRequestStarted" and request.data.strategy == "chat" then
      -- Fidget 会显示正常的聊天请求进度
    end
  end,
})
```

#### 推荐的 Fidget 配置

如果您已经使用 Fidget 来显示 CodeCompanion 进度，迭代功能会自动工作：

```lua
-- 在您现有的 Fidget 配置中
local group = vim.api.nvim_create_augroup("CodeCompanionHooks", {})

vim.api.nvim_create_autocmd({ "User" }, {
  pattern = "CodeCompanionRequest*",
  group = group,
  callback = function(request)
    local fidget = require("fidget")
    
    if request.match == "CodeCompanionRequestStarted" then
      local adapter = request.data.adapter
      local message = string.format("🤖 %s (%s)", adapter.formatted_name, adapter.model)
      
      -- 特殊处理上下文摘要
      if request.data.context and request.data.context.summarization then
        message = "📝 " .. message .. " - Context Summarization"
      end
      
      fidget.notify(message, "info", { group = "codecompanion" })
    elseif request.match == "CodeCompanionRequestFinished" then
      fidget.notify("✅ Request completed", "info", { group = "codecompanion" })
    end
  end,
})
```

## 🛠️ 配置

### 基本配置

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      iteration = {
        enabled = true,
        max_iterations_per_task = 20,
        iteration_increase_amount = 10,
        show_iteration_progress = true,
        
        context_summarization = {
          enabled = true,
          threshold_ratio = 0.75,
          keep_recent_messages = 3,
          max_summary_tokens = 1000,
        },
      },
    },
  },
})
```

### 高级上下文限制配置

```lua
context_limits = {
  -- 适配器级别的默认限制
  anthropic = 200000,
  openai = 128000,
  copilot = 128000,
  ollama = 4096,
  
  -- 特定模型的精确限制
  models = {
    -- OpenAI 模型
    ["openai:gpt-4o"] = 128000,
    ["openai:gpt-4o-mini"] = 128000,
    ["openai:gpt-4-turbo"] = 128000,
    
    -- Anthropic 模型
    ["anthropic:claude-3-5-sonnet-20241022"] = 200000,
    ["anthropic:claude-3-5-haiku-20241022"] = 200000,
    ["anthropic:claude-3-opus-20240229"] = 200000,
    
    -- GitHub Copilot 模型（用户特别要求）
    ["copilot:gpt-4.1"] = 128000,
    
    -- Gemini 模型
    ["gemini:gemini-1.5-pro"] = 2000000,
    ["gemini:gemini-1.5-flash"] = 1000000,
    
    -- 本地 Ollama 模型
    ["ollama:llama3.1:70b"] = 8192,
    ["ollama:codestral:22b"] = 32768,
  },
  
  -- 架构级别的检测（自动检测）
  detect_by_architecture = true,
  
  -- 默认回退值
  default_limit = 4096,
}
```

### 自定义进度通知

您可以自定义迭代进度通知：

```lua
-- 监听迭代通知事件
vim.api.nvim_create_autocmd({ "User" }, {
  pattern = "vim.notify",
  callback = function(event)
    local message = event.data
    
    -- 检测迭代进度消息
    if message and string.match(message, "🔄 Iteration %d+/%d+") then
      -- 可以集成到您的状态栏或自定义 UI
      print("Iteration progress: " .. message)
    elseif message and string.match(message, "📝.*summarization") then
      -- 上下文摘要进度
      print("Summarization: " .. message)
    end
  end,
})
```

## 🎯 工作原理

### 事件系统集成

迭代功能通过以下方式与现有事件系统集成：

1. **上下文摘要请求**：
   - 触发 `CodeCompanionRequestStartedContextSummarization`
   - 触发 `CodeCompanionRequestFinishedContextSummarization`
   - 包含 `context.summarization = true` 标识

2. **迭代计数**：
   - 通过标准通知显示进度
   - 每 5 次迭代显示一次避免刷屏
   - 用户确认时显示详细信息

3. **LLM 请求**：
   - 使用标准的 `CodeCompanionRequestStarted/Finished` 事件
   - 现有 Fidget 集成自动工作

### 非阻塞操作

- **异步摘要**：使用异步 LLM 调用生成摘要
- **用户友好确认**：使用 `vim.ui.select` 进行非阻塞确认
- **事件驱动反馈**：通过事件系统让用户了解当前状态

## 🎯 使用示例

### 启用详细进度显示

```lua
-- 在您的 CodeCompanion 配置中
require("codecompanion").setup({
  strategies = {
    chat = {
      iteration = {
        enabled = true,
        show_iteration_progress = true,
        
        context_summarization = {
          enabled = true,
          threshold_ratio = 0.8,  -- 80% 时触发摘要
        },
      },
    },
  },
})
```

### 为特定适配器自定义限制

```lua
context_limits = {
  -- 您的 Ollama 本地模型可能有较小的上下文窗口
  ollama = 2048,
  
  -- 但特定模型可能支持更大的上下文
  models = {
    ["ollama:llama3.1:70b"] = 8192,
    ["ollama:codestral:22b"] = 32768,
  },
}
```

## 🔧 故障排除

### 如果迭代功能不工作

1. **检查配置**：确保 `iteration.enabled = true`
2. **查看日志**：检查 `:CodeCompanionLog` 中的错误
3. **验证适配器**：确保您的适配器支持 `chat_output` 处理

### 如果进度显示不工作

1. **检查事件监听**：确保您的 Fidget 配置监听了正确的事件
2. **验证通知**：检查是否收到标准的 `vim.notify` 消息
3. **查看事件数据**：使用 `:autocmd User` 来调试事件触发

### 与现有 Fidget 配置集成

如果您已经有 Fidget 配置显示 CodeCompanion 进度，迭代功能会自动工作：

```lua
-- 现有配置会自动处理迭代请求
vim.api.nvim_create_autocmd({ "User" }, {
  pattern = "CodeCompanionRequest*",
  group = group,
  callback = function(request)
    -- 您现有的 Fidget 逻辑
    -- 迭代请求会自动通过这里显示
  end,
})
```

## 🏆 最佳实践

### 上下文管理

- 使用较高的 `threshold_ratio` (0.75-0.85) 来最大化上下文使用
- 保留至少 3-5 条最近消息以维持对话连贯性
- 调整 `max_summary_tokens` 来控制摘要长度

### 迭代控制

- 根据您的使用情况调整 `max_iterations_per_task`
- 启用 `show_iteration_progress` 来获得可视化反馈
- 使用 `iteration_increase_amount` 来控制扩展增量

### 事件监听

- 使用现有的 Fidget 配置来显示迭代进度
- 监听 `ContextSummarization` 事件来跟踪摘要进度
- 自定义通知处理来集成到您的工作流

### 性能优化

1. **调整摘要阈值**：较低的 `threshold_ratio` 意味着更早摘要
2. **保留消息数量**：增加 `keep_recent_messages` 以保留更多上下文
3. **摘要 token 限制**：调整 `max_summary_tokens` 来控制摘要长度
4. **事件优化**：合理配置事件监听避免性能影响 