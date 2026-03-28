package = "codecompanion.nvim"
version = "dev-1"
source = {
	url = "git+ssh://git@github.com/olimorris/codecompanion.nvim.git"
}
description = {
	detailed = [[CodeCompanion is a Neovim plugin which enables you to code with AI, using LLMs and agents, in Neovim.]],
	homepage = "https://codecompanion.olimorris.dev",
	license = "Apache License 2.0"
}
dependencies = {
	"plenary.nvim"
}
build = {
	type = "builtin",
	modules = {
		["codecompanion._extensions.init"] = "lua/codecompanion/_extensions/init.lua",
		["codecompanion.acp.init"] = "lua/codecompanion/acp/init.lua",
		["codecompanion.acp.methods"] = "lua/codecompanion/acp/methods.lua",
		["codecompanion.acp.prompt_builder"] = "lua/codecompanion/acp/prompt_builder.lua",
		["codecompanion.actions.builtins.commit"] = "lua/codecompanion/actions/builtins/commit.lua",
		["codecompanion.actions.builtins.lsp"] = "lua/codecompanion/actions/builtins/lsp.lua",
		["codecompanion.actions.init"] = "lua/codecompanion/actions/init.lua",
		["codecompanion.actions.markdown"] = "lua/codecompanion/actions/markdown.lua",
		["codecompanion.actions.prompt_library"] = "lua/codecompanion/actions/prompt_library.lua",
		["codecompanion.actions.static"] = "lua/codecompanion/actions/static.lua",
		["codecompanion.adapters.acp.auggie_cli"] = "lua/codecompanion/adapters/acp/auggie_cli.lua",
		["codecompanion.adapters.acp.cagent"] = "lua/codecompanion/adapters/acp/cagent.lua",
		["codecompanion.adapters.acp.claude_code"] = "lua/codecompanion/adapters/acp/claude_code.lua",
		["codecompanion.adapters.acp.codex"] = "lua/codecompanion/adapters/acp/codex.lua",
		["codecompanion.adapters.acp.gemini_cli"] = "lua/codecompanion/adapters/acp/gemini_cli.lua",
		["codecompanion.adapters.acp.goose"] = "lua/codecompanion/adapters/acp/goose.lua",
		["codecompanion.adapters.acp.helpers"] = "lua/codecompanion/adapters/acp/helpers.lua",
		["codecompanion.adapters.acp.init"] = "lua/codecompanion/adapters/acp/init.lua",
		["codecompanion.adapters.acp.kimi_cli"] = "lua/codecompanion/adapters/acp/kimi_cli.lua",
		["codecompanion.adapters.acp.opencode"] = "lua/codecompanion/adapters/acp/opencode.lua",
		["codecompanion.adapters.http.anthropic"] = "lua/codecompanion/adapters/http/anthropic.lua",
		["codecompanion.adapters.http.azure_openai"] = "lua/codecompanion/adapters/http/azure_openai.lua",
		["codecompanion.adapters.http.copilot.get_models"] = "lua/codecompanion/adapters/http/copilot/get_models.lua",
		["codecompanion.adapters.http.copilot.init"] = "lua/codecompanion/adapters/http/copilot/init.lua",
		["codecompanion.adapters.http.copilot.stats"] = "lua/codecompanion/adapters/http/copilot/stats.lua",
		["codecompanion.adapters.http.copilot.token"] = "lua/codecompanion/adapters/http/copilot/token.lua",
		["codecompanion.adapters.http.deepseek"] = "lua/codecompanion/adapters/http/deepseek.lua",
		["codecompanion.adapters.http.gemini"] = "lua/codecompanion/adapters/http/gemini.lua",
		["codecompanion.adapters.http.githubmodels"] = "lua/codecompanion/adapters/http/githubmodels.lua",
		["codecompanion.adapters.http.huggingface"] = "lua/codecompanion/adapters/http/huggingface.lua",
		["codecompanion.adapters.http.init"] = "lua/codecompanion/adapters/http/init.lua",
		["codecompanion.adapters.http.jina"] = "lua/codecompanion/adapters/http/jina.lua",
		["codecompanion.adapters.http.mistral"] = "lua/codecompanion/adapters/http/mistral.lua",
		["codecompanion.adapters.http.novita"] = "lua/codecompanion/adapters/http/novita.lua",
		["codecompanion.adapters.http.ollama.get_models"] = "lua/codecompanion/adapters/http/ollama/get_models.lua",
		["codecompanion.adapters.http.ollama.init"] = "lua/codecompanion/adapters/http/ollama/init.lua",
		["codecompanion.adapters.http.openai"] = "lua/codecompanion/adapters/http/openai.lua",
		["codecompanion.adapters.http.openai_compatible"] = "lua/codecompanion/adapters/http/openai_compatible.lua",
		["codecompanion.adapters.http.openai_responses"] = "lua/codecompanion/adapters/http/openai_responses.lua",
		["codecompanion.adapters.http.tavily"] = "lua/codecompanion/adapters/http/tavily.lua",
		["codecompanion.adapters.http.xai"] = "lua/codecompanion/adapters/http/xai.lua",
		["codecompanion.adapters.init"] = "lua/codecompanion/adapters/init.lua",
		["codecompanion.adapters.shared"] = "lua/codecompanion/adapters/shared.lua",
		["codecompanion.commands"] = "lua/codecompanion/commands.lua",
		["codecompanion.config"] = "lua/codecompanion/config.lua",
		["codecompanion.health"] = "lua/codecompanion/health.lua",
		["codecompanion.helpers"] = "lua/codecompanion/helpers.lua",
		["codecompanion.helpers.actions"] = "lua/codecompanion/helpers/actions.lua",
		["codecompanion.http"] = "lua/codecompanion/http.lua",
		["codecompanion.init"] = "lua/codecompanion/init.lua",
		["codecompanion.interactions.background.builtin.chat_make_title"] =
		"lua/codecompanion/interactions/background/builtin/chat_make_title.lua",
		["codecompanion.interactions.background.callbacks"] = "lua/codecompanion/interactions/background/callbacks.lua",
		["codecompanion.interactions.background.init"] = "lua/codecompanion/interactions/background/init.lua",
		["codecompanion.interactions.chat.acp.commands"] = "lua/codecompanion/interactions/chat/acp/commands.lua",
		["codecompanion.interactions.chat.acp.formatters"] = "lua/codecompanion/interactions/chat/acp/formatters.lua",
		["codecompanion.interactions.chat.acp.fs"] = "lua/codecompanion/interactions/chat/acp/fs.lua",
		["codecompanion.interactions.chat.acp.handler"] = "lua/codecompanion/interactions/chat/acp/handler.lua",
		["codecompanion.interactions.chat.acp.request_permission"] =
		"lua/codecompanion/interactions/chat/acp/request_permission.lua",
		["codecompanion.interactions.chat.buffer_diffs"] = "lua/codecompanion/interactions/chat/buffer_diffs.lua",
		["codecompanion.interactions.chat.context"] = "lua/codecompanion/interactions/chat/context.lua",
		["codecompanion.interactions.chat.debug"] = "lua/codecompanion/interactions/chat/debug.lua",
		["codecompanion.interactions.chat.edit_tracker"] = "lua/codecompanion/interactions/chat/edit_tracker.lua",
		["codecompanion.interactions.chat.helpers.diff"] = "lua/codecompanion/interactions/chat/helpers/diff.lua",
		["codecompanion.interactions.chat.helpers.filter"] = "lua/codecompanion/interactions/chat/helpers/filter.lua",
		["codecompanion.interactions.chat.helpers.init"] = "lua/codecompanion/interactions/chat/helpers/init.lua",
		["codecompanion.interactions.chat.helpers.wait"] = "lua/codecompanion/interactions/chat/helpers/wait.lua",
		["codecompanion.interactions.chat.init"] = "lua/codecompanion/interactions/chat/init.lua",
		["codecompanion.interactions.chat.keymaps.change_adapter"] =
		"lua/codecompanion/interactions/chat/keymaps/change_adapter.lua",
		["codecompanion.interactions.chat.keymaps.init"] = "lua/codecompanion/interactions/chat/keymaps/init.lua",
		["codecompanion.interactions.chat.parser"] = "lua/codecompanion/interactions/chat/parser.lua",
		["codecompanion.interactions.chat.rules.helpers"] = "lua/codecompanion/interactions/chat/rules/helpers.lua",
		["codecompanion.interactions.chat.rules.init"] = "lua/codecompanion/interactions/chat/rules/init.lua",
		["codecompanion.interactions.chat.rules.parsers.claude"] =
		"lua/codecompanion/interactions/chat/rules/parsers/claude.lua",
		["codecompanion.interactions.chat.rules.parsers.codecompanion"] =
		"lua/codecompanion/interactions/chat/rules/parsers/codecompanion.lua",
		["codecompanion.interactions.chat.rules.parsers.init"] = "lua/codecompanion/interactions/chat/rules/parsers/init.lua",
		["codecompanion.interactions.chat.rules.parsers.none"] = "lua/codecompanion/interactions/chat/rules/parsers/none.lua",
		["codecompanion.interactions.chat.slash_commands.builtin.buffer"] =
		"lua/codecompanion/interactions/chat/slash_commands/builtin/buffer.lua",
		["codecompanion.interactions.chat.slash_commands.builtin.compact"] =
		"lua/codecompanion/interactions/chat/slash_commands/builtin/compact.lua",
		["codecompanion.interactions.chat.slash_commands.builtin.fetch"] =
		"lua/codecompanion/interactions/chat/slash_commands/builtin/fetch.lua",
		["codecompanion.interactions.chat.slash_commands.builtin.file"] =
		"lua/codecompanion/interactions/chat/slash_commands/builtin/file.lua",
		["codecompanion.interactions.chat.slash_commands.builtin.help"] =
		"lua/codecompanion/interactions/chat/slash_commands/builtin/help.lua",
		["codecompanion.interactions.chat.slash_commands.builtin.image"] =
		"lua/codecompanion/interactions/chat/slash_commands/builtin/image.lua",
		["codecompanion.interactions.chat.slash_commands.builtin.mode"] =
		"lua/codecompanion/interactions/chat/slash_commands/builtin/mode.lua",
		["codecompanion.interactions.chat.slash_commands.builtin.now"] =
		"lua/codecompanion/interactions/chat/slash_commands/builtin/now.lua",
		["codecompanion.interactions.chat.slash_commands.builtin.quickfix"] =
		"lua/codecompanion/interactions/chat/slash_commands/builtin/quickfix.lua",
		["codecompanion.interactions.chat.slash_commands.builtin.rules"] =
		"lua/codecompanion/interactions/chat/slash_commands/builtin/rules.lua",
		["codecompanion.interactions.chat.slash_commands.builtin.symbols"] =
		"lua/codecompanion/interactions/chat/slash_commands/builtin/symbols.lua",
		["codecompanion.interactions.chat.slash_commands.builtin.terminal"] =
		"lua/codecompanion/interactions/chat/slash_commands/builtin/terminal.lua",
		["codecompanion.interactions.chat.slash_commands.filter"] =
		"lua/codecompanion/interactions/chat/slash_commands/filter.lua",
		["codecompanion.interactions.chat.slash_commands.helpers"] =
		"lua/codecompanion/interactions/chat/slash_commands/helpers.lua",
		["codecompanion.interactions.chat.slash_commands.init"] =
		"lua/codecompanion/interactions/chat/slash_commands/init.lua",
		["codecompanion.interactions.chat.slash_commands.keymaps"] =
		"lua/codecompanion/interactions/chat/slash_commands/keymaps.lua",
		["codecompanion.interactions.chat.subscribers"] = "lua/codecompanion/interactions/chat/subscribers.lua",
		["codecompanion.interactions.chat.super_diff"] = "lua/codecompanion/interactions/chat/super_diff.lua",
		["codecompanion.interactions.chat.tool_registry"] = "lua/codecompanion/interactions/chat/tool_registry.lua",
		["codecompanion.interactions.chat.tools.approvals"] = "lua/codecompanion/interactions/chat/tools/approvals.lua",
		["codecompanion.interactions.chat.tools.builtin.cmd_runner"] =
		"lua/codecompanion/interactions/chat/tools/builtin/cmd_runner.lua",
		["codecompanion.interactions.chat.tools.builtin.create_file"] =
		"lua/codecompanion/interactions/chat/tools/builtin/create_file.lua",
		["codecompanion.interactions.chat.tools.builtin.delete_file"] =
		"lua/codecompanion/interactions/chat/tools/builtin/delete_file.lua",
		["codecompanion.interactions.chat.tools.builtin.fetch_webpage"] =
		"lua/codecompanion/interactions/chat/tools/builtin/fetch_webpage.lua",
		["codecompanion.interactions.chat.tools.builtin.file_search"] =
		"lua/codecompanion/interactions/chat/tools/builtin/file_search.lua",
		["codecompanion.interactions.chat.tools.builtin.get_changed_files"] =
		"lua/codecompanion/interactions/chat/tools/builtin/get_changed_files.lua",
		["codecompanion.interactions.chat.tools.builtin.grep_search"] =
		"lua/codecompanion/interactions/chat/tools/builtin/grep_search.lua",
		["codecompanion.interactions.chat.tools.builtin.helpers.init"] =
		"lua/codecompanion/interactions/chat/tools/builtin/helpers/init.lua",
		["codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.constants"] =
		"lua/codecompanion/interactions/chat/tools/builtin/insert_edit_into_file/constants.lua",
		["codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.init"] =
		"lua/codecompanion/interactions/chat/tools/builtin/insert_edit_into_file/init.lua",
		["codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.match_selector"] =
		"lua/codecompanion/interactions/chat/tools/builtin/insert_edit_into_file/match_selector.lua",
		["codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.strategies"] =
		"lua/codecompanion/interactions/chat/tools/builtin/insert_edit_into_file/strategies.lua",
		["codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.text_utils"] =
		"lua/codecompanion/interactions/chat/tools/builtin/insert_edit_into_file/text_utils.lua",
		["codecompanion.interactions.chat.tools.builtin.list_code_usages.code_extractor"] =
		"lua/codecompanion/interactions/chat/tools/builtin/list_code_usages/code_extractor.lua",
		["codecompanion.interactions.chat.tools.builtin.list_code_usages.init"] =
		"lua/codecompanion/interactions/chat/tools/builtin/list_code_usages/init.lua",
		["codecompanion.interactions.chat.tools.builtin.list_code_usages.lsp_handler"] =
		"lua/codecompanion/interactions/chat/tools/builtin/list_code_usages/lsp_handler.lua",
		["codecompanion.interactions.chat.tools.builtin.list_code_usages.result_processor"] =
		"lua/codecompanion/interactions/chat/tools/builtin/list_code_usages/result_processor.lua",
		["codecompanion.interactions.chat.tools.builtin.list_code_usages.symbol_finder"] =
		"lua/codecompanion/interactions/chat/tools/builtin/list_code_usages/symbol_finder.lua",
		["codecompanion.interactions.chat.tools.builtin.list_code_usages.utils"] =
		"lua/codecompanion/interactions/chat/tools/builtin/list_code_usages/utils.lua",
		["codecompanion.interactions.chat.tools.builtin.memory"] =
		"lua/codecompanion/interactions/chat/tools/builtin/memory.lua",
		["codecompanion.interactions.chat.tools.builtin.next_edit_suggestion"] =
		"lua/codecompanion/interactions/chat/tools/builtin/next_edit_suggestion.lua",
		["codecompanion.interactions.chat.tools.builtin.read_file"] =
		"lua/codecompanion/interactions/chat/tools/builtin/read_file.lua",
		["codecompanion.interactions.chat.tools.builtin.web_search"] =
		"lua/codecompanion/interactions/chat/tools/builtin/web_search.lua",
		["codecompanion.interactions.chat.tools.filter"] = "lua/codecompanion/interactions/chat/tools/filter.lua",
		["codecompanion.interactions.chat.tools.init"] = "lua/codecompanion/interactions/chat/tools/init.lua",
		["codecompanion.interactions.chat.tools.orchestrator"] = "lua/codecompanion/interactions/chat/tools/orchestrator.lua",
		["codecompanion.interactions.chat.tools.runtime.queue"] =
		"lua/codecompanion/interactions/chat/tools/runtime/queue.lua",
		["codecompanion.interactions.chat.tools.runtime.runner"] =
		"lua/codecompanion/interactions/chat/tools/runtime/runner.lua",
		["codecompanion.interactions.chat.ui.builder"] = "lua/codecompanion/interactions/chat/ui/builder.lua",
		["codecompanion.interactions.chat.ui.folds"] = "lua/codecompanion/interactions/chat/ui/folds.lua",
		["codecompanion.interactions.chat.ui.formatters.base"] = "lua/codecompanion/interactions/chat/ui/formatters/base.lua",
		["codecompanion.interactions.chat.ui.formatters.reasoning"] =
		"lua/codecompanion/interactions/chat/ui/formatters/reasoning.lua",
		["codecompanion.interactions.chat.ui.formatters.standard"] =
		"lua/codecompanion/interactions/chat/ui/formatters/standard.lua",
		["codecompanion.interactions.chat.ui.formatters.tools"] =
		"lua/codecompanion/interactions/chat/ui/formatters/tools.lua",
		["codecompanion.interactions.chat.ui.icons"] = "lua/codecompanion/interactions/chat/ui/icons.lua",
		["codecompanion.interactions.chat.ui.init"] = "lua/codecompanion/interactions/chat/ui/init.lua",
		["codecompanion.interactions.chat.variables.buffer"] = "lua/codecompanion/interactions/chat/variables/buffer.lua",
		["codecompanion.interactions.chat.variables.init"] = "lua/codecompanion/interactions/chat/variables/init.lua",
		["codecompanion.interactions.chat.variables.lsp"] = "lua/codecompanion/interactions/chat/variables/lsp.lua",
		["codecompanion.interactions.chat.variables.user"] = "lua/codecompanion/interactions/chat/variables/user.lua",
		["codecompanion.interactions.chat.variables.viewport"] = "lua/codecompanion/interactions/chat/variables/viewport.lua",
		["codecompanion.interactions.cmd"] = "lua/codecompanion/interactions/cmd.lua",
		["codecompanion.interactions.init"] = "lua/codecompanion/interactions/init.lua",
		["codecompanion.interactions.inline.completion"] = "lua/codecompanion/interactions/inline/completion.lua",
		["codecompanion.interactions.inline.init"] = "lua/codecompanion/interactions/inline/init.lua",
		["codecompanion.interactions.inline.keymaps"] = "lua/codecompanion/interactions/inline/keymaps.lua",
		["codecompanion.interactions.inline.variables.buffer"] = "lua/codecompanion/interactions/inline/variables/buffer.lua",
		["codecompanion.interactions.inline.variables.chat"] = "lua/codecompanion/interactions/inline/variables/chat.lua",
		["codecompanion.interactions.inline.variables.clipboard"] =
		"lua/codecompanion/interactions/inline/variables/clipboard.lua",
		["codecompanion.interactions.inline.variables.init"] = "lua/codecompanion/interactions/inline/variables/init.lua",
		["codecompanion.providers.actions.default"] = "lua/codecompanion/providers/actions/default.lua",
		["codecompanion.providers.actions.fzf_lua"] = "lua/codecompanion/providers/actions/fzf_lua.lua",
		["codecompanion.providers.actions.mini_pick"] = "lua/codecompanion/providers/actions/mini_pick.lua",
		["codecompanion.providers.actions.shared"] = "lua/codecompanion/providers/actions/shared.lua",
		["codecompanion.providers.actions.snacks"] = "lua/codecompanion/providers/actions/snacks.lua",
		["codecompanion.providers.actions.telescope"] = "lua/codecompanion/providers/actions/telescope.lua",
		["codecompanion.providers.completion.blink.init"] = "lua/codecompanion/providers/completion/blink/init.lua",
		["codecompanion.providers.completion.blink.setup"] = "lua/codecompanion/providers/completion/blink/setup.lua",
		["codecompanion.providers.completion.cmp.acp_commands"] =
		"lua/codecompanion/providers/completion/cmp/acp_commands.lua",
		["codecompanion.providers.completion.cmp.models"] = "lua/codecompanion/providers/completion/cmp/models.lua",
		["codecompanion.providers.completion.cmp.setup"] = "lua/codecompanion/providers/completion/cmp/setup.lua",
		["codecompanion.providers.completion.cmp.slash_commands"] =
		"lua/codecompanion/providers/completion/cmp/slash_commands.lua",
		["codecompanion.providers.completion.cmp.tools"] = "lua/codecompanion/providers/completion/cmp/tools.lua",
		["codecompanion.providers.completion.cmp.variables"] = "lua/codecompanion/providers/completion/cmp/variables.lua",
		["codecompanion.providers.completion.coc.init"] = "lua/codecompanion/providers/completion/coc/init.lua",
		["codecompanion.providers.completion.coc.setup"] = "lua/codecompanion/providers/completion/coc/setup.lua",
		["codecompanion.providers.completion.default.omnifunc"] =
		"lua/codecompanion/providers/completion/default/omnifunc.lua",
		["codecompanion.providers.completion.default.setup"] = "lua/codecompanion/providers/completion/default/setup.lua",
		["codecompanion.providers.completion.init"] = "lua/codecompanion/providers/completion/init.lua",
		["codecompanion.providers.diff.inline"] = "lua/codecompanion/providers/diff/inline.lua",
		["codecompanion.providers.diff.mini_diff"] = "lua/codecompanion/providers/diff/mini_diff.lua",
		["codecompanion.providers.diff.split"] = "lua/codecompanion/providers/diff/split.lua",
		["codecompanion.providers.diff.utils"] = "lua/codecompanion/providers/diff/utils.lua",
		["codecompanion.providers.init"] = "lua/codecompanion/providers/init.lua",
		["codecompanion.providers.slash_commands.default"] = "lua/codecompanion/providers/slash_commands/default.lua",
		["codecompanion.providers.slash_commands.fzf_lua"] = "lua/codecompanion/providers/slash_commands/fzf_lua.lua",
		["codecompanion.providers.slash_commands.mini_pick"] = "lua/codecompanion/providers/slash_commands/mini_pick.lua",
		["codecompanion.providers.slash_commands.snacks"] = "lua/codecompanion/providers/slash_commands/snacks.lua",
		["codecompanion.providers.slash_commands.telescope"] = "lua/codecompanion/providers/slash_commands/telescope.lua",
		["codecompanion.schema"] = "lua/codecompanion/schema.lua",
		["codecompanion.types"] = "lua/codecompanion/types.lua",
		["codecompanion.utils.adapters"] = "lua/codecompanion/utils/adapters.lua",
		["codecompanion.utils.async"] = "lua/codecompanion/utils/async.lua",
		["codecompanion.utils.buffers"] = "lua/codecompanion/utils/buffers.lua",
		["codecompanion.utils.context"] = "lua/codecompanion/utils/context.lua",
		["codecompanion.utils.deprecate"] = "lua/codecompanion/utils/deprecate.lua",
		["codecompanion.utils.files"] = "lua/codecompanion/utils/files.lua",
		["codecompanion.utils.hash"] = "lua/codecompanion/utils/hash.lua",
		["codecompanion.utils.images"] = "lua/codecompanion/utils/images.lua",
		["codecompanion.utils.init"] = "lua/codecompanion/utils/init.lua",
		["codecompanion.utils.keymaps"] = "lua/codecompanion/utils/keymaps.lua",
		["codecompanion.utils.log"] = "lua/codecompanion/utils/log.lua",
		["codecompanion.utils.native_bit"] = "lua/codecompanion/utils/native_bit.lua",
		["codecompanion.utils.os"] = "lua/codecompanion/utils/os.lua",
		["codecompanion.utils.regex"] = "lua/codecompanion/utils/regex.lua",
		["codecompanion.utils.tokens"] = "lua/codecompanion/utils/tokens.lua",
		["codecompanion.utils.tool_transformers"] = "lua/codecompanion/utils/tool_transformers.lua",
		["codecompanion.utils.treesitter"] = "lua/codecompanion/utils/treesitter.lua",
		["codecompanion.utils.ui"] = "lua/codecompanion/utils/ui.lua",
		["codecompanion.utils.yaml"] = "lua/codecompanion/utils/yaml.lua",
		["legendary.extensions.codecompanion"] = "lua/legendary/extensions/codecompanion.lua",
		["telescope._extensions.codecompanion"] = "lua/telescope/_extensions/codecompanion.lua"
	},
	copy_directories = {
		"doc",
		"tests"
	}
}
