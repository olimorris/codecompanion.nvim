# Changelog

## [17.9.0](https://github.com/olimorris/codecompanion.nvim/compare/v17.8.0...v17.9.0) (2025-07-18)


### Features

* **adapters:** Ollama adapter has support for `think` and more hyperparameters ([#1829](https://github.com/olimorris/codecompanion.nvim/issues/1829)) ([408b402](https://github.com/olimorris/codecompanion.nvim/commit/408b402da023ae41f13b4a071e4c79d3b0b78693))
* **ui:** chat buffer can be sticky when navigating tabs ([#1842](https://github.com/olimorris/codecompanion.nvim/issues/1842)) ([71fb6a8](https://github.com/olimorris/codecompanion.nvim/commit/71fb6a80894c584d23ea55d4e8d3448cbb04eeaf))


### Bug Fixes

* **chat:** toggling when chat buffer is not in the current tab ([#1725](https://github.com/olimorris/codecompanion.nvim/issues/1725)) ([4f91b4b](https://github.com/olimorris/codecompanion.nvim/commit/4f91b4b6b400b97b923537cb75721b8452cd54dc))
* **prompt_library:** custom prompts containing URLs ([#1849](https://github.com/olimorris/codecompanion.nvim/issues/1849)) ([164e95c](https://github.com/olimorris/codecompanion.nvim/commit/164e95c6ff0becd6d152e06be56ccd98f53bc5a8))
* **tools:** `read_files` tool can read entire file if `end_line` is greater than total lines ([#1824](https://github.com/olimorris/codecompanion.nvim/issues/1824)) ([562950d](https://github.com/olimorris/codecompanion.nvim/commit/562950d1584a1ff603921ec7ce48638e2d7f9e1d))
* **tools:** failed/cancelled/rejected tool calls no longer block the execution queue ([#1852](https://github.com/olimorris/codecompanion.nvim/issues/1852)) ([48d7e8f](https://github.com/olimorris/codecompanion.nvim/commit/48d7e8f6b2fb894afd68e1475bf63d81c934239a)), closes [#1850](https://github.com/olimorris/codecompanion.nvim/issues/1850)

## [17.8.0](https://github.com/olimorris/codecompanion.nvim/compare/v17.7.1...v17.8.0) (2025-07-11)


### Features

* **chat:** add restore function to ensure a chat buffer can be made visible ([#1816](https://github.com/olimorris/codecompanion.nvim/issues/1816)) ([f37b8b9](https://github.com/olimorris/codecompanion.nvim/commit/f37b8b91d77745b5e5fc816272f50b9826ada6d9))
* **tools:** `insert_edit_into_file` tool now saves the buffer ([#1813](https://github.com/olimorris/codecompanion.nvim/issues/1813)) ([f7c89b4](https://github.com/olimorris/codecompanion.nvim/commit/f7c89b4a17d040ba4288f60b08c138b8b94bde4a))
* **tools:** add `get_changed_files` tool ([#1777](https://github.com/olimorris/codecompanion.nvim/issues/1777)) ([ed5c493](https://github.com/olimorris/codecompanion.nvim/commit/ed5c493eaf54b10b56f1489fdeac3689cd583807))


### Bug Fixes

* **chat:** start_in_insert_mode with telescope ([#1815](https://github.com/olimorris/codecompanion.nvim/issues/1815)) ([dc5eca1](https://github.com/olimorris/codecompanion.nvim/commit/dc5eca177248f5d77e7d01fdd98e18f90ecfcc56))
* **inline:** prompting using telescope and dressing in the UI ([#1702](https://github.com/olimorris/codecompanion.nvim/issues/1702)) ([50dde48](https://github.com/olimorris/codecompanion.nvim/commit/50dde48a6a078283c30ec177f7ab3c4eaa350341))

## [17.7.1](https://github.com/olimorris/codecompanion.nvim/compare/v17.7.0...v17.7.1) (2025-07-10)


### Bug Fixes

* **chat:** tool folding ([#1811](https://github.com/olimorris/codecompanion.nvim/issues/1811)) ([b506225](https://github.com/olimorris/codecompanion.nvim/commit/b5062255224cb72ee35e374ac764ac53f6fe9fa1))
* **chat:** unwatch buffers when they're unlisted ([#1809](https://github.com/olimorris/codecompanion.nvim/issues/1809)) ([ea29e11](https://github.com/olimorris/codecompanion.nvim/commit/ea29e112916bad53e52f514bff1bc2e54e2287c2))

## [17.7.0](https://github.com/olimorris/codecompanion.nvim/compare/v17.6.0...v17.7.0) (2025-07-09)


### Features

* add chat ID to chat opened/hidden events ([17f7cbb](https://github.com/olimorris/codecompanion.nvim/commit/17f7cbb6cabdc12195f164acf4c59c7c7c205b64))


### Bug Fixes

* **adapter:** copilot unauthorized token expired ([#1789](https://github.com/olimorris/codecompanion.nvim/issues/1789)) ([d455d71](https://github.com/olimorris/codecompanion.nvim/commit/d455d71f5887063b08da3fc3cd60548460f1c875))
* **adapters:** reasoning output and tool calls in anthropic ([#1807](https://github.com/olimorris/codecompanion.nvim/issues/1807)) ([5717527](https://github.com/olimorris/codecompanion.nvim/commit/5717527ba6b1086ed748dd3b1390d0f431ec46cb)), closes [#1752](https://github.com/olimorris/codecompanion.nvim/issues/1752)
* **prompts:** reword vectorcode tool in workspace prompt ([#1775](https://github.com/olimorris/codecompanion.nvim/issues/1775)) ([3527a9c](https://github.com/olimorris/codecompanion.nvim/commit/3527a9c85b58a8db2fee6d7dcde72077ba790a4a))

## [17.6.0](https://github.com/olimorris/codecompanion.nvim/compare/v17.5.0...v17.6.0) (2025-07-03)


### Features

* **adapters:** add gemini-2.5-flash and set as new default ([#1686](https://github.com/olimorris/codecompanion.nvim/issues/1686)) ([fb98d6c](https://github.com/olimorris/codecompanion.nvim/commit/fb98d6c03f6039939e676f1257c76d8480a3da4f))
* **chat:** handle buffer deletion of chat buffers ([#1745](https://github.com/olimorris/codecompanion.nvim/issues/1745)) ([dbc7957](https://github.com/olimorris/codecompanion.nvim/commit/dbc7957ee92ddce403405c5c6d91ba7dccb278c7))
* **chat:** tool output can be folded ([#1665](https://github.com/olimorris/codecompanion.nvim/issues/1665)) ([a87ebc7](https://github.com/olimorris/codecompanion.nvim/commit/a87ebc73ffc796bb5020cb083e2a5ef3c2c7e9bf))
* **tools:** `web_search` tool can search specific sites ([#1741](https://github.com/olimorris/codecompanion.nvim/issues/1741)) ([6ef907f](https://github.com/olimorris/codecompanion.nvim/commit/6ef907fca6480dd11dc8f7a3048fec23f8a39b29))


### Bug Fixes

* **chat:** don't remove custom system prompts when using `gs` ([#1770](https://github.com/olimorris/codecompanion.nvim/issues/1770)) ([4e75c62](https://github.com/olimorris/codecompanion.nvim/commit/4e75c629d1c1658c9330a75fd2ffec9cad59ed50)), closes [#1749](https://github.com/olimorris/codecompanion.nvim/issues/1749)
* **chat:** tools can now be dynamically added ([#1693](https://github.com/olimorris/codecompanion.nvim/issues/1693)) ([3a5f895](https://github.com/olimorris/codecompanion.nvim/commit/3a5f8958197b2e134e7d299673bff76c785dbc99))
* **prompts:** agentic workflow in the config ([#1764](https://github.com/olimorris/codecompanion.nvim/issues/1764)) ([0b3831d](https://github.com/olimorris/codecompanion.nvim/commit/0b3831ddee88a389aa663fb05e35f2724f6df7da))

## [17.5.0](https://github.com/olimorris/codecompanion.nvim/compare/v17.4.0...v17.5.0) (2025-06-28)


### Features

* **adapters:** add tool support to Azure OpenAI ([#1737](https://github.com/olimorris/codecompanion.nvim/issues/1737)) ([2c7e9b1](https://github.com/olimorris/codecompanion.nvim/commit/2c7e9b1aa9fa1f5a2b4d82f3f4e065cb0c8bc2b7))


### Bug Fixes

* **adapters:** reduce copilot premium request consumption ([#1738](https://github.com/olimorris/codecompanion.nvim/issues/1738)) ([ed96fe3](https://github.com/olimorris/codecompanion.nvim/commit/ed96fe33c17b41957f2334b1cae29c24d35f8ef2))
* **tools:** patching for empty and small files with insufficient context ([#1734](https://github.com/olimorris/codecompanion.nvim/issues/1734)) ([cb55ef0](https://github.com/olimorris/codecompanion.nvim/commit/cb55ef006be3e75015c84fbd9adef14b3546a08f))


### Code Refactoring

* **chat:** tools and variables now use `@{tool}` and `#{variable}` syntax ([#1740](https://github.com/olimorris/codecompanion.nvim/issues/1740)) ([f89eca2](https://github.com/olimorris/codecompanion.nvim/commit/f89eca26368b29bc8259921d459c1b4e5bfaeebb))

## [17.4.0](https://github.com/olimorris/codecompanion.nvim/compare/v17.3.0...v17.4.0) (2025-06-27)


### Features

* **adapters:** :boom: add tool support to Ollama ([#1585](https://github.com/olimorris/codecompanion.nvim/issues/1585)) ([e325370](https://github.com/olimorris/codecompanion.nvim/commit/e325370b8325697cb2f6becd13f267e6a12a0393))


### Bug Fixes

* **workspace:** add description to buffer content ([#1713](https://github.com/olimorris/codecompanion.nvim/issues/1713)) ([ff939d1](https://github.com/olimorris/codecompanion.nvim/commit/ff939d18d8d64b0bef985aeb9be26f57e4ee8837))

## [17.3.0](https://github.com/olimorris/codecompanion.nvim/compare/v17.2.0...v17.3.0) (2025-06-24)


### Features

* **chat:** add copilot usage statistics with `gS` keymap ([#1677](https://github.com/olimorris/codecompanion.nvim/issues/1677)) ([8602a50](https://github.com/olimorris/codecompanion.nvim/commit/8602a50cacf111c69f35e305d1556afd9fa1f1a1))

## [17.2.0](https://github.com/olimorris/codecompanion.nvim/compare/v17.1.1...v17.2.0) (2025-06-24)


### Features

* **workspaces:** files can be opened as buffers ([#1708](https://github.com/olimorris/codecompanion.nvim/issues/1708)) ([2ea49ff](https://github.com/olimorris/codecompanion.nvim/commit/2ea49ff2063100757e71b0e327b7a32a1d566a9d))


### Bug Fixes

* require tool module path correctly ([#1670](https://github.com/olimorris/codecompanion.nvim/issues/1670)) ([dbefc41](https://github.com/olimorris/codecompanion.nvim/commit/dbefc41dba2f46720ecb6ecec34c0c5f80022f2b))
* **tools:** patching algorithm can start with an empty line ([#1663](https://github.com/olimorris/codecompanion.nvim/issues/1663)) ([370ec56](https://github.com/olimorris/codecompanion.nvim/commit/370ec56f388fd317fd324d68709e9441d3461896))
* **tools:** patching algorithm now supports lines starting with `-` ([#1654](https://github.com/olimorris/codecompanion.nvim/issues/1654)) ([9011839](https://github.com/olimorris/codecompanion.nvim/commit/9011839a6827b264d632822d9ce17cb66fe95e61))

## [17.1.1](https://github.com/olimorris/codecompanion.nvim/compare/v17.1.0...v17.1.1) (2025-06-16)


### Bug Fixes

* **chat:** watchers use the same diff format as in patch ([#1655](https://github.com/olimorris/codecompanion.nvim/issues/1655)) ([86b1ff1](https://github.com/olimorris/codecompanion.nvim/commit/86b1ff13d140d3b63f49f1cbfd69873b2cbbe40d))
* **tools:** make `insert_edit_into_file` more robust for patch markers ([#1653](https://github.com/olimorris/codecompanion.nvim/issues/1653)) ([a6e226c](https://github.com/olimorris/codecompanion.nvim/commit/a6e226ced63d9bb5e601213e63f5cd07ad09f7cd))

## [17.1.0](https://github.com/olimorris/codecompanion.nvim/compare/v17.0.0...v17.1.0) (2025-06-16)


### Features

* **tools:** add `grep_search` tool ([#1651](https://github.com/olimorris/codecompanion.nvim/issues/1651)) ([98eb86c](https://github.com/olimorris/codecompanion.nvim/commit/98eb86cd5e66aa0f2bc3c47eb699ea81c99b74db))
* **tools:** can be conditionally loaded ([#1647](https://github.com/olimorris/codecompanion.nvim/issues/1647)) ([40ba4fc](https://github.com/olimorris/codecompanion.nvim/commit/40ba4fc7e7749a089f23123593d9a6c85140fcfc))


### Bug Fixes

* **tools:** `insert_edit_info_file` tool can insert at EOF ([#1650](https://github.com/olimorris/codecompanion.nvim/issues/1650)) ([d54a41a](https://github.com/olimorris/codecompanion.nvim/commit/d54a41a86a510e9c728f6e460801afdf581d69da))

## [17.0.0](https://github.com/olimorris/codecompanion.nvim/compare/v16.3.0...v17.0.0) (2025-06-15)


### ⚠ BREAKING CHANGES

* remove support for nvim-0.10 ([#1639](https://github.com/olimorris/codecompanion.nvim/issues/1639))

### Features

* **slash_command:** new `/quickfix` command ([#1600](https://github.com/olimorris/codecompanion.nvim/issues/1600)) ([6384dc0](https://github.com/olimorris/codecompanion.nvim/commit/6384dc0d5b150394403e5ab3bc89bfad301634ea))
* **tools:** add `file_search` tool ([#1613](https://github.com/olimorris/codecompanion.nvim/issues/1613)) ([3582a2c](https://github.com/olimorris/codecompanion.nvim/commit/3582a2c465fe8900ad70e24877d48247abd608c9))


### Code Refactoring

* remove support for nvim-0.10 ([#1639](https://github.com/olimorris/codecompanion.nvim/issues/1639)) ([5d0ef43](https://github.com/olimorris/codecompanion.nvim/commit/5d0ef43ed822ea3341ed0989e45f2d10d57ba359))

## [16.3.0](https://github.com/olimorris/codecompanion.nvim/compare/v16.2.2...v16.3.0) (2025-06-14)


### Features

* **chat:** add `collapse_tools` setting for tool groups ([#1614](https://github.com/olimorris/codecompanion.nvim/issues/1614)) ([f1442c7](https://github.com/olimorris/codecompanion.nvim/commit/f1442c743f0f40132d07b42ccf99e450b648fcf6))
* **chat:** can preload with `default_tools` ([#1610](https://github.com/olimorris/codecompanion.nvim/issues/1610)) ([68c12a0](https://github.com/olimorris/codecompanion.nvim/commit/68c12a03a738aaeffe429c45b9f0c14ce00b0132))


### Bug Fixes

* **chat:** don't cache blink completions ([#1618](https://github.com/olimorris/codecompanion.nvim/issues/1618)) ([8a958a4](https://github.com/olimorris/codecompanion.nvim/commit/8a958a4a1a11e58f1eb30d378c4c88c611d388d4))
* **chat:** paths are always relative and wrap context in &lt;attachment&gt; ([#1633](https://github.com/olimorris/codecompanion.nvim/issues/1633)) ([2185ccc](https://github.com/olimorris/codecompanion.nvim/commit/2185ccc81eeb9080f6c856a408ed3cba3f2bb7ef)), closes [#1630](https://github.com/olimorris/codecompanion.nvim/issues/1630) [#1631](https://github.com/olimorris/codecompanion.nvim/issues/1631)
* **inline:** chat placements with claude-sonnet-4 ([#1636](https://github.com/olimorris/codecompanion.nvim/issues/1636)) ([0f82355](https://github.com/olimorris/codecompanion.nvim/commit/0f8235523ee555daa6acc6a5e5b5c4472ed60b43)), closes [#1626](https://github.com/olimorris/codecompanion.nvim/issues/1626)

## [16.2.2](https://github.com/olimorris/codecompanion.nvim/compare/v16.2.1...v16.2.2) (2025-06-13)


### Bug Fixes

* **inline:** revert keymap changes ([#1622](https://github.com/olimorris/codecompanion.nvim/issues/1622)) ([6f89961](https://github.com/olimorris/codecompanion.nvim/commit/6f89961632defce5a591195851569758a1e15a0e)), closes [#1621](https://github.com/olimorris/codecompanion.nvim/issues/1621)

## [16.2.1](https://github.com/olimorris/codecompanion.nvim/compare/v16.2.0...v16.2.1) (2025-06-12)


### Bug Fixes

* **utils:** fallback to vim.highlight ([#1611](https://github.com/olimorris/codecompanion.nvim/issues/1611)) ([6d62e18](https://github.com/olimorris/codecompanion.nvim/commit/6d62e1843cbee7a181a5b86de9e4ec554650d8d9))

## [16.2.0](https://github.com/olimorris/codecompanion.nvim/compare/v16.1.0...v16.2.0) (2025-06-11)


### Features

* **adapters:** add gemini-2.5-pro-preview-06-05 ([#1605](https://github.com/olimorris/codecompanion.nvim/issues/1605)) ([fa8af3b](https://github.com/olimorris/codecompanion.nvim/commit/fa8af3bbaa70773a5d104ad8fdc567d30be260b4))
* **chat:** simplify watchers to use unified diffs ([#1583](https://github.com/olimorris/codecompanion.nvim/issues/1583)) ([81b817b](https://github.com/olimorris/codecompanion.nvim/commit/81b817b4186f85d4b2880516054b0e34bb27e60d))
* **slash_commands:** for `/fetch` only show cache option if cached files exist ([#1582](https://github.com/olimorris/codecompanion.nvim/issues/1582)) ([f022807](https://github.com/olimorris/codecompanion.nvim/commit/f0228073aeb2b577425ace676c34654b2e1a308d))
* **tools:** `editor` tool merges with `insert_edit_into_file` ([#1586](https://github.com/olimorris/codecompanion.nvim/issues/1586)) ([bec6cd1](https://github.com/olimorris/codecompanion.nvim/commit/bec6cd124da650dc25472e03f4416cbe27574ef8))
* **tools:** add `next_edit_suggestion` tool ([#1570](https://github.com/olimorris/codecompanion.nvim/issues/1570)) ([600e7b2](https://github.com/olimorris/codecompanion.nvim/commit/600e7b2d55816fa3b8103ef898aaaa31a224224f))


### Bug Fixes

* **chat:** word boundary matching for tools and variables ([#1503](https://github.com/olimorris/codecompanion.nvim/issues/1503)) ([f572601](https://github.com/olimorris/codecompanion.nvim/commit/f57260190a40bb4f071d27c5386eeff1440c111b))

## [16.1.0](https://github.com/olimorris/codecompanion.nvim/compare/v16.0.0...v16.1.0) (2025-06-06)


### Features

* **tools:** auto_tool_mode now auto submits ([#1580](https://github.com/olimorris/codecompanion.nvim/issues/1580)) ([1b2ab64](https://github.com/olimorris/codecompanion.nvim/commit/1b2ab6445dac16908b2136bd7c071e4dcb7f38d6))

## [16.0.0](https://github.com/olimorris/codecompanion.nvim/compare/v15.12.0...v16.0.0) (2025-06-06)


### ⚠ BREAKING CHANGES

* **chat:** move the `goto_file_action` to `strategies.chat.opts`
* **chat:** move `opts.goto_file_action` to `strategies.chat.opts` ([#1571](https://github.com/olimorris/codecompanion.nvim/issues/1571))
* **chat:** reuse existing tabs when jumping to a file. ([#1569](https://github.com/olimorris/codecompanion.nvim/issues/1569))

### Features

* **chat:** chat buffer acts more like a normal buffer ([#1556](https://github.com/olimorris/codecompanion.nvim/issues/1556)) ([ebcdd78](https://github.com/olimorris/codecompanion.nvim/commit/ebcdd78a9d5d0d95c64fe9a106999b9f9603d2f3))
* **chat:** reuse existing tabs when jumping to a file. ([#1569](https://github.com/olimorris/codecompanion.nvim/issues/1569)) ([8747d88](https://github.com/olimorris/codecompanion.nvim/commit/8747d8871e310942996431d5374001a8b29ab0b7))
* **chat:** support `:map-arguments` in keymaps ([#1572](https://github.com/olimorris/codecompanion.nvim/issues/1572)) ([d8e94cf](https://github.com/olimorris/codecompanion.nvim/commit/d8e94cfff7525ff5fdcc376093666c2cf57bb0e5))
* **tools:** can load tools via relative paths ([#1552](https://github.com/olimorris/codecompanion.nvim/issues/1552)) ([7991e53](https://github.com/olimorris/codecompanion.nvim/commit/7991e53c0270db489b94e1a26c0d1608aa2d6206))


### Bug Fixes

* **adapters:** fix streaming for gemini adapter ([#1561](https://github.com/olimorris/codecompanion.nvim/issues/1561)) ([585fade](https://github.com/olimorris/codecompanion.nvim/commit/585fadef1940a66216124bdbd1bace55be3b1e73))
* **chat:** correct yank command syntax in keymaps ([#1568](https://github.com/olimorris/codecompanion.nvim/issues/1568)) ([05555a4](https://github.com/olimorris/codecompanion.nvim/commit/05555a40f263488592556c3acfb61ef323805136))
* **chat:** Register cmp completions when filetype is set ([#1560](https://github.com/olimorris/codecompanion.nvim/issues/1560)) ([3d62ac3](https://github.com/olimorris/codecompanion.nvim/commit/3d62ac3ebe840245b157e169d06b8d87ee878dc5))
* **inline:** remove blank lines in diffs ([#1565](https://github.com/olimorris/codecompanion.nvim/issues/1565)) ([fee2dd1](https://github.com/olimorris/codecompanion.nvim/commit/fee2dd137b515b779c57c915ca031921e6591d85))


### Code Refactoring

* **chat:** move `opts.goto_file_action` to `strategies.chat.opts` ([#1571](https://github.com/olimorris/codecompanion.nvim/issues/1571)) ([cdf7721](https://github.com/olimorris/codecompanion.nvim/commit/cdf772165782e55a451c0793bf4c2a89926b89bd))
* **chat:** move the `goto_file_action` to `strategies.chat.opts` ([cdf7721](https://github.com/olimorris/codecompanion.nvim/commit/cdf772165782e55a451c0793bf4c2a89926b89bd))

## [15.12.0](https://github.com/olimorris/codecompanion.nvim/compare/v15.11.0...v15.12.0) (2025-06-01)


### Features

* **adapters:** new copilot default is gpt-4.1 ([#1540](https://github.com/olimorris/codecompanion.nvim/issues/1540)) ([15b0614](https://github.com/olimorris/codecompanion.nvim/commit/15b06141cb9d66ebb3b3038fbe4fa9cd0ee0fc15))
* **chat:** can set default params for variables ([#1516](https://github.com/olimorris/codecompanion.nvim/issues/1516)) ([c0549d5](https://github.com/olimorris/codecompanion.nvim/commit/c0549d54203160020b4214d3e8827b2103a95b97))
* **providers:** add coc.nvim ([#1421](https://github.com/olimorris/codecompanion.nvim/issues/1421)) ([c22d2a6](https://github.com/olimorris/codecompanion.nvim/commit/c22d2a675f76a97ede327a49baddec02ecd6f3f5))
* **slash_commands:** add Telescope provider for `/image` ([#1542](https://github.com/olimorris/codecompanion.nvim/issues/1542)) ([a12d3aa](https://github.com/olimorris/codecompanion.nvim/commit/a12d3aa9a0825ae72733fcffc646615bc3bee484))


### Bug Fixes

* **providers:** register coc execute function ([#1548](https://github.com/olimorris/codecompanion.nvim/issues/1548)) ([92ba84c](https://github.com/olimorris/codecompanion.nvim/commit/92ba84cddf19d936809d9775884699e66a070ec4))
* **tools:** auto submit sends updated buffer ([#1545](https://github.com/olimorris/codecompanion.nvim/issues/1545)) ([82f5917](https://github.com/olimorris/codecompanion.nvim/commit/82f5917455cb7156f36daa99b2ec8049a7958ce5))

## [15.11.0](https://github.com/olimorris/codecompanion.nvim/compare/v15.10.0...v15.11.0) (2025-05-31)


### Features

* **chat:** add keymap to jump to file under cursor ([#1408](https://github.com/olimorris/codecompanion.nvim/issues/1408)) ([4c54348](https://github.com/olimorris/codecompanion.nvim/commit/4c5434883fff08bc9814fb71aff0f51518276acb))
* **chat:** remember cursor position when toggling ([#1523](https://github.com/olimorris/codecompanion.nvim/issues/1523)) ([51fb1df](https://github.com/olimorris/codecompanion.nvim/commit/51fb1dfa7227ace2e6635c8fcc75cc2ab1b607c6))
* **prompt_library:** custom prompts can add references ([#1384](https://github.com/olimorris/codecompanion.nvim/issues/1384)) ([3117350](https://github.com/olimorris/codecompanion.nvim/commit/31173502852f0d524e9e74e51255177f094c45e0))
* **tools:** improve auto-submit and turn on by default ([#1539](https://github.com/olimorris/codecompanion.nvim/issues/1539)) ([3388e15](https://github.com/olimorris/codecompanion.nvim/commit/3388e1562aaa6d6deab90e8ad141439ed2bcac2f))

## [15.10.0](https://github.com/olimorris/codecompanion.nvim/compare/v15.9.0...v15.10.0) (2025-05-31)


### Features

* **adapters:** support Copilot enterprise ([#1533](https://github.com/olimorris/codecompanion.nvim/issues/1533)) ([7572e35](https://github.com/olimorris/codecompanion.nvim/commit/7572e35f22395ad2ab095e75b419a70a00ca2036))


### Bug Fixes

* **adapters:** resolving adapters from prompt library ([#1536](https://github.com/olimorris/codecompanion.nvim/issues/1536)) ([9964f48](https://github.com/olimorris/codecompanion.nvim/commit/9964f4880c66376e4c9f0d45f5fd2ab1e5496254)), closes [#1521](https://github.com/olimorris/codecompanion.nvim/issues/1521)

## [15.9.0](https://github.com/olimorris/codecompanion.nvim/compare/v15.8.0...v15.9.0) (2025-05-28)


### Features

* **adapters:** users can specify models for strategies ([#1518](https://github.com/olimorris/codecompanion.nvim/issues/1518)) ([763c81b](https://github.com/olimorris/codecompanion.nvim/commit/763c81b4823af3e3ef9cfb3f55f15f7f8f8b4b15))
* **slash_commands:** better caching and restoring of URLs ([#1491](https://github.com/olimorris/codecompanion.nvim/issues/1491)) ([d39890c](https://github.com/olimorris/codecompanion.nvim/commit/d39890cb432801cfe5b2a97104289e1cc4b9c415))

## [15.8.0](https://github.com/olimorris/codecompanion.nvim/compare/v15.7.0...v15.8.0) (2025-05-26)


### Features

* **tools:** add tavily adapter and `[@web](https://github.com/web)_search` tool ([#1279](https://github.com/olimorris/codecompanion.nvim/issues/1279)) ([a5a8701](https://github.com/olimorris/codecompanion.nvim/commit/a5a8701bf8814ff0ba9bf5f76b3a3deedf3e5f28))


### Bug Fixes

* **slash_commands:** update adapter reference ([#1502](https://github.com/olimorris/codecompanion.nvim/issues/1502)) ([41108b2](https://github.com/olimorris/codecompanion.nvim/commit/41108b2ee7d71eca50ff6c5008b30a853e14cf35))
* **workflows:** successive prompts and tools now work ([#1508](https://github.com/olimorris/codecompanion.nvim/issues/1508)) ([0112caf](https://github.com/olimorris/codecompanion.nvim/commit/0112caf54a79bb6cfbcb6e67cd16a3a9f18af9a7)), closes [#1496](https://github.com/olimorris/codecompanion.nvim/issues/1496)

## [15.7.0](https://github.com/olimorris/codecompanion.nvim/compare/v15.6.1...v15.7.0) (2025-05-25)


### Features

* **adapters:** add new Anthropic models ([#1488](https://github.com/olimorris/codecompanion.nvim/issues/1488)) ([70d52e0](https://github.com/olimorris/codecompanion.nvim/commit/70d52e00c23a6df9ccf3bc927e2658b320764302))

## [15.6.1](https://github.com/olimorris/codecompanion.nvim/compare/v15.6.0...v15.6.1) (2025-05-22)


### Bug Fixes

* **adapters:** enable OpenAI vision support ([#1486](https://github.com/olimorris/codecompanion.nvim/issues/1486)) ([f8e14ae](https://github.com/olimorris/codecompanion.nvim/commit/f8e14ae0be51c0f65b0284f787277407db30ace7))
* **providers:** only use `mini.diff` if initialized ([#1472](https://github.com/olimorris/codecompanion.nvim/issues/1472)) ([f7bb598](https://github.com/olimorris/codecompanion.nvim/commit/f7bb59888b201507a43c856460d455f786c989f8))
* **references:** unlock buffer when adding reference after a tool output ([#1477](https://github.com/olimorris/codecompanion.nvim/issues/1477)) ([df44594](https://github.com/olimorris/codecompanion.nvim/commit/df4459401180612bc5b7b167eff7133324e85f1c))

## [15.6.0](https://github.com/olimorris/codecompanion.nvim/compare/v15.5.0...v15.6.0) (2025-05-21)


### Features

* **adapters:** add vision support ([#1455](https://github.com/olimorris/codecompanion.nvim/issues/1455)) ([1a4f0a4](https://github.com/olimorris/codecompanion.nvim/commit/1a4f0a44b1e52d1c569ce2f66b03b6804e74b183))
* **adapters:** can use adapter.opts.request to override Client:request ([#1469](https://github.com/olimorris/codecompanion.nvim/issues/1469)) ([ec73b64](https://github.com/olimorris/codecompanion.nvim/commit/ec73b64df3d0767eb0a5b42d942f9e02970ee95c))
* **adapters:** set Copilot default model to `gpt-4.1` ([bd14edb](https://github.com/olimorris/codecompanion.nvim/commit/bd14edb82ea07423c5c0f7484ef885a895374719))


### Bug Fixes

* **inline:** keymap modes ([#1468](https://github.com/olimorris/codecompanion.nvim/issues/1468)) ([7ac8234](https://github.com/olimorris/codecompanion.nvim/commit/7ac823450c490201af3362a0861c2c1c19b827a8))
* **variables:** ensure special chars are matched ([#1470](https://github.com/olimorris/codecompanion.nvim/issues/1470)) ([a682004](https://github.com/olimorris/codecompanion.nvim/commit/a682004d4ff97c0450617975699bfc78029862be))

## [15.5.0](https://github.com/olimorris/codecompanion.nvim/compare/v15.4.2...v15.5.0) (2025-05-20)


### Features

* **action_palette:** add `fzf_lua` provider ([#1443](https://github.com/olimorris/codecompanion.nvim/issues/1443)) ([03caa41](https://github.com/olimorris/codecompanion.nvim/commit/03caa41555d6615006d0ac8f6fcfee317cb967f0))


### Bug Fixes

* **adapters:** resolve adapters with correct name ([#1459](https://github.com/olimorris/codecompanion.nvim/issues/1459)) ([0beb918](https://github.com/olimorris/codecompanion.nvim/commit/0beb9183954ae1afa2e1f5a91812706764d1a743))
* **adapters:** resolve not using custom adapter ([#1461](https://github.com/olimorris/codecompanion.nvim/issues/1461)) ([b79b33a](https://github.com/olimorris/codecompanion.nvim/commit/b79b33a58304cd386f72ee0ab159824fa21321c6))
* **ui:** include `kind` option in all `vim.ui.select` calls ([#1456](https://github.com/olimorris/codecompanion.nvim/issues/1456)) ([9d8fc51](https://github.com/olimorris/codecompanion.nvim/commit/9d8fc51a1923333de683ebf85c633fd003ad2b9b))

## [15.4.2](https://github.com/olimorris/codecompanion.nvim/compare/v15.4.1...v15.4.2) (2025-05-16)


### Bug Fixes

* **inline:** don't modify prompts going to the chat buffer ([#1447](https://github.com/olimorris/codecompanion.nvim/issues/1447)) ([a3b2b63](https://github.com/olimorris/codecompanion.nvim/commit/a3b2b633c6e17f0a891713c724285843c9706e1e))

## [15.4.1](https://github.com/olimorris/codecompanion.nvim/compare/v15.4.0...v15.4.1) (2025-05-11)


### Bug Fixes

* **adapters:** stack overflow if default model is function ([#1417](https://github.com/olimorris/codecompanion.nvim/issues/1417)) ([2d28420](https://github.com/olimorris/codecompanion.nvim/commit/2d284203ec63136f72e75a61b1cb19abb31a1ebe)), closes [#1415](https://github.com/olimorris/codecompanion.nvim/issues/1415)

## [15.4.0](https://github.com/olimorris/codecompanion.nvim/compare/v15.3.1...v15.4.0) (2025-05-10)


### Features

* **chat:** call slash commands with keymaps ([#1412](https://github.com/olimorris/codecompanion.nvim/issues/1412)) ([598af68](https://github.com/olimorris/codecompanion.nvim/commit/598af68b53394cfd43f7a098dcd463da86c5dc3f))

## [15.3.1](https://github.com/olimorris/codecompanion.nvim/compare/v15.3.0...v15.3.1) (2025-05-10)


### Bug Fixes

* **deepseek:** inline prompt to chat causes error ([#1406](https://github.com/olimorris/codecompanion.nvim/issues/1406)) ([c912e2d](https://github.com/olimorris/codecompanion.nvim/commit/c912e2d72a91629f554142af3e9a648e54112ca4)), closes [#1405](https://github.com/olimorris/codecompanion.nvim/issues/1405)

## [15.3.0](https://github.com/olimorris/codecompanion.nvim/compare/v15.2.0...v15.3.0) (2025-05-06)


### Features

* **action_palette:** Add snacks.nvim as provider ([#1380](https://github.com/olimorris/codecompanion.nvim/issues/1380)) ([5b4a004](https://github.com/olimorris/codecompanion.nvim/commit/5b4a004ea082a0608aa98bb9041f79e56676cfeb))


### Bug Fixes

* **openai:** do not send empty tools array ([#1381](https://github.com/olimorris/codecompanion.nvim/issues/1381)) ([33364a0](https://github.com/olimorris/codecompanion.nvim/commit/33364a070f06e3d8cf5276ac409c58de4f922716))

## [15.2.0](https://github.com/olimorris/codecompanion.nvim/compare/v15.1.4...v15.2.0) (2025-05-05)


### Features

* **adapters:** can automatically choose default model when switching adapters ([#1369](https://github.com/olimorris/codecompanion.nvim/issues/1369)) ([90e82ab](https://github.com/olimorris/codecompanion.nvim/commit/90e82abf4d65b64b0986a5be0981ba13e84eee8b))


### Bug Fixes

* **adapters:** improve resolving adapters ([#1367](https://github.com/olimorris/codecompanion.nvim/issues/1367)) ([2c296ba](https://github.com/olimorris/codecompanion.nvim/commit/2c296ba17c4bc581eee11fc90683e5b130f65d89))
* **chat:** tools should be empty table if not used ([#1373](https://github.com/olimorris/codecompanion.nvim/issues/1373)) ([3f72bac](https://github.com/olimorris/codecompanion.nvim/commit/3f72bacfd74fc4e4b4ea07257e61ec6fb3fb004f)), closes [#1371](https://github.com/olimorris/codecompanion.nvim/issues/1371)
* **providers:** use mini.diff by default if available ([#1368](https://github.com/olimorris/codecompanion.nvim/issues/1368)) ([127a2c1](https://github.com/olimorris/codecompanion.nvim/commit/127a2c1614df2e8565a98e83e3567980c32d9876))
* **tools:** call subscribers after an LLM response ([#1365](https://github.com/olimorris/codecompanion.nvim/issues/1365)) ([8dc896a](https://github.com/olimorris/codecompanion.nvim/commit/8dc896af23c1e086aee13fe7c850eab365ad337e))
* **workflows:** ensure references are rendered ([#1376](https://github.com/olimorris/codecompanion.nvim/issues/1376)) ([598a444](https://github.com/olimorris/codecompanion.nvim/commit/598a4443e2906a382bc182e5558371ea2dd3df64))

## [15.1.4](https://github.com/olimorris/codecompanion.nvim/compare/v15.1.3...v15.1.4) (2025-05-04)


### Bug Fixes

* **snacks:** focus on floating chat windows after closing picker ([#1359](https://github.com/olimorris/codecompanion.nvim/issues/1359)) ([6090826](https://github.com/olimorris/codecompanion.nvim/commit/60908265b78145c7c8595d81b36792bc01cd56e5))
* **tools:** tool groups are replaced properly in the chat buffer ([#1364](https://github.com/olimorris/codecompanion.nvim/issues/1364)) ([9402ae3](https://github.com/olimorris/codecompanion.nvim/commit/9402ae373f23269f1baef8ccc32578c128cbf2ed))

## [15.1.3](https://github.com/olimorris/codecompanion.nvim/compare/v15.1.2...v15.1.3) (2025-05-04)


### Bug Fixes

* **chat:** various chat buffer fixes ([#1336](https://github.com/olimorris/codecompanion.nvim/issues/1336)) ([1e2f69a](https://github.com/olimorris/codecompanion.nvim/commit/1e2f69a9a65bd716cf897393e7af65fc74907ed8))
* **tools:** tools can now be deleted as references ([#1357](https://github.com/olimorris/codecompanion.nvim/issues/1357)) ([7d0938c](https://github.com/olimorris/codecompanion.nvim/commit/7d0938c1dc117c9c63569a388b9d091ee884d2ce))

## [15.1.2](https://github.com/olimorris/codecompanion.nvim/compare/v15.1.1...v15.1.2) (2025-05-03)


### Bug Fixes

* **chat:** prevent double references in the chat buffer ([#1348](https://github.com/olimorris/codecompanion.nvim/issues/1348)) ([aafbb62](https://github.com/olimorris/codecompanion.nvim/commit/aafbb62c5ceb3f019610fb0e9ed3c04305b59a23))

## [15.1.1](https://github.com/olimorris/codecompanion.nvim/compare/v15.1.0...v15.1.1) (2025-05-03)


### Bug Fixes

* **inline:** "new" placement doesn't create diffview ([#1343](https://github.com/olimorris/codecompanion.nvim/issues/1343)) ([9ab6ac1](https://github.com/olimorris/codecompanion.nvim/commit/9ab6ac1126d89f74b9882e4343eb1397e4b052da))

## [15.1.0](https://github.com/olimorris/codecompanion.nvim/compare/v15.0.8...v15.1.0) (2025-05-02)


### Features

* **chat:** decorate your prompts ([080e8c9](https://github.com/olimorris/codecompanion.nvim/commit/080e8c9324ce40dd6b5e9aaf4ea27450707a55a7))
* **gemini:** add gemini-2.5-flash ([#1347](https://github.com/olimorris/codecompanion.nvim/issues/1347)) ([b4d96cb](https://github.com/olimorris/codecompanion.nvim/commit/b4d96cbdca7ddc7870b0db0aded898ce9e6ea709))
* **openai:** update models ([#1346](https://github.com/olimorris/codecompanion.nvim/issues/1346)) ([b114cd1](https://github.com/olimorris/codecompanion.nvim/commit/b114cd1c24e784ef6ad0af9770bc141f5b81affd))

## [15.0.8](https://github.com/olimorris/codecompanion.nvim/compare/v15.0.7...v15.0.8) (2025-05-02)


### Bug Fixes

* **tools:** multiple bug fixes ([07f7518](https://github.com/olimorris/codecompanion.nvim/commit/07f75181d716a07d683ca66afb8f4dc6b6acbdd3))

## [15.0.7](https://github.com/olimorris/codecompanion.nvim/compare/v15.0.6...v15.0.7) (2025-05-01)


### Bug Fixes

* **refs:** do not parse non-existent message ([#1332](https://github.com/olimorris/codecompanion.nvim/issues/1332)) ([c7aeeab](https://github.com/olimorris/codecompanion.nvim/commit/c7aeeaba79c48234f3be61d04f77fe88cf2a7025))

## [15.0.6](https://github.com/olimorris/codecompanion.nvim/compare/v15.0.5...v15.0.6) (2025-05-01)


### Bug Fixes

* **tools:** auto_submitting processes requests in order ([#1325](https://github.com/olimorris/codecompanion.nvim/issues/1325)) ([0d910ae](https://github.com/olimorris/codecompanion.nvim/commit/0d910ae6ddb4af6e5e2c34838760da241999cd3f))

## [15.0.5](https://github.com/olimorris/codecompanion.nvim/compare/v15.0.4...v15.0.5) (2025-04-30)


### Bug Fixes

* **chat:** header line when used with prompt library closes [#1319](https://github.com/olimorris/codecompanion.nvim/issues/1319) ([#1327](https://github.com/olimorris/codecompanion.nvim/issues/1327)) ([77ff03d](https://github.com/olimorris/codecompanion.nvim/commit/77ff03d4ce89ca3b4ec06033df4106d11eb536ad))

## [15.0.4](https://github.com/olimorris/codecompanion.nvim/compare/v15.0.3...v15.0.4) (2025-04-30)


### Bug Fixes

* **ui:** add blank line before user role ([#1225](https://github.com/olimorris/codecompanion.nvim/issues/1225)) ([ddda7e8](https://github.com/olimorris/codecompanion.nvim/commit/ddda7e8208856df8c7d32c7fcf6276962ebbb437))

## [15.0.3](https://github.com/olimorris/codecompanion.nvim/compare/v15.0.2...v15.0.3) (2025-04-30)


### Bug Fixes

* **references:** don't remove tools by checking chat refs while auto_submitting ([#1320](https://github.com/olimorris/codecompanion.nvim/issues/1320)) ([b2a0aa2](https://github.com/olimorris/codecompanion.nvim/commit/b2a0aa2aa71e0f401099ed88f35cc94e0163aeea))
* **tools:** file tool now outputs content to the LLM ([#1321](https://github.com/olimorris/codecompanion.nvim/issues/1321)) ([50ce548](https://github.com/olimorris/codecompanion.nvim/commit/50ce548b099318d6c14c56949d4a3f3a4693b7b1))

## [15.0.2](https://github.com/olimorris/codecompanion.nvim/compare/v15.0.1...v15.0.2) (2025-04-30)


### Bug Fixes

* **tools:** files tool can now edit files ([#1317](https://github.com/olimorris/codecompanion.nvim/issues/1317)) ([668fecc](https://github.com/olimorris/codecompanion.nvim/commit/668fecc61777e62a65d624cc88f2a8468ac4cd39))

## [15.0.1](https://github.com/olimorris/codecompanion.nvim/compare/v15.0.0...v15.0.1) (2025-04-30)


### Bug Fixes

* **refs:** can handle blank messages closes [#1311](https://github.com/olimorris/codecompanion.nvim/issues/1311) ([#1314](https://github.com/olimorris/codecompanion.nvim/issues/1314)) ([c3d2326](https://github.com/olimorris/codecompanion.nvim/commit/c3d2326ec1f1ef9f1a6867d478f3be4930fcdf7d))

## [15.0.0](https://github.com/olimorris/codecompanion.nvim/compare/v14.13.0...v15.0.0) (2025-04-29)


### ⚠ BREAKING CHANGES

* **tools:** move to function calling ([#1141](https://github.com/olimorris/codecompanion.nvim/issues/1141))

### Features

* add extensions api ([#1290](https://github.com/olimorris/codecompanion.nvim/issues/1290)) ([96bda85](https://github.com/olimorris/codecompanion.nvim/commit/96bda85c8bc77ac7a8f0b1a431c38e2c4103ad90))
* **tools:** move to function calling ([#1141](https://github.com/olimorris/codecompanion.nvim/issues/1141)) ([4fdf370](https://github.com/olimorris/codecompanion.nvim/commit/4fdf3707f6d8492b34629580935220c13dcac490))

## [14.13.0](https://github.com/olimorris/codecompanion.nvim/compare/v14.12.0...v14.13.0) (2025-04-27)


### Features

* **chat_buffer:** hide grouped tools in completion menu ([#1295](https://github.com/olimorris/codecompanion.nvim/issues/1295)) ([8380ee8](https://github.com/olimorris/codecompanion.nvim/commit/8380ee85fcd63a6752c545ed46fb9a2455f49527))

## [14.12.0](https://github.com/olimorris/codecompanion.nvim/compare/v14.11.0...v14.12.0) (2025-04-26)


### Features

* **events:** add context to event data payload ([03f55cb](https://github.com/olimorris/codecompanion.nvim/commit/03f55cb3dc0735ae9846bd420fa51ff36bb21fae))
* **events:** add context to InlineStarted event data payload ([#1293](https://github.com/olimorris/codecompanion.nvim/issues/1293)) ([03f55cb](https://github.com/olimorris/codecompanion.nvim/commit/03f55cb3dc0735ae9846bd420fa51ff36bb21fae))

## [14.11.0](https://github.com/olimorris/codecompanion.nvim/compare/v14.10.1...v14.11.0) (2025-04-21)


### Features

* **action_palette:** preview open chats in telescope ([#1269](https://github.com/olimorris/codecompanion.nvim/issues/1269)) ([98a8d56](https://github.com/olimorris/codecompanion.nvim/commit/98a8d56e8cfc8e18396f03d6ebb2a44488eb477c))

## [14.10.1](https://github.com/olimorris/codecompanion.nvim/compare/v14.10.0...v14.10.1) (2025-04-21)


### Bug Fixes

* **adapters:** model choice in azure openai closes [#1273](https://github.com/olimorris/codecompanion.nvim/issues/1273) ([#1274](https://github.com/olimorris/codecompanion.nvim/issues/1274)) ([4dd516a](https://github.com/olimorris/codecompanion.nvim/commit/4dd516ae6880b612073849f78ece5f67c854c44d))

## [14.10.0](https://github.com/olimorris/codecompanion.nvim/compare/v14.9.1...v14.10.0) (2025-04-20)


### Features

* **adapters:** move ollama adapter to OpenAI endpoint ([79b2697](https://github.com/olimorris/codecompanion.nvim/commit/79b26971e4215e07d225c0d180248753de0036ff))

## [14.9.1](https://github.com/olimorris/codecompanion.nvim/compare/v14.9.0...v14.9.1) (2025-04-13)


### Bug Fixes

* **snacks:** focus on chat window after closing picker ([#1248](https://github.com/olimorris/codecompanion.nvim/issues/1248)) ([bd6bd19](https://github.com/olimorris/codecompanion.nvim/commit/bd6bd199bc019037613cb64bcdb70e6b8952c038))

## [14.9.0](https://github.com/olimorris/codecompanion.nvim/compare/v14.8.1...v14.9.0) (2025-04-13)


### Features

* **ui:** allow toggling the visibility of individual references. ([#1245](https://github.com/olimorris/codecompanion.nvim/issues/1245)) ([cc25e49](https://github.com/olimorris/codecompanion.nvim/commit/cc25e49e33de63064026a7ad0295e517a8f11391))

## [14.8.1](https://github.com/olimorris/codecompanion.nvim/compare/v14.8.0...v14.8.1) (2025-04-08)


### Bug Fixes

* **tools:** be more explicit about the xml schema ([95bb7a5](https://github.com/olimorris/codecompanion.nvim/commit/95bb7a579b1e9455c855f59bd4b6bb2ca860aee3))
* **tools:** be more explicit about the xml schema in files tool ([#1232](https://github.com/olimorris/codecompanion.nvim/issues/1232)) ([95bb7a5](https://github.com/olimorris/codecompanion.nvim/commit/95bb7a579b1e9455c855f59bd4b6bb2ca860aee3))

## [14.8.0](https://github.com/olimorris/codecompanion.nvim/compare/v14.7.1...v14.8.0) (2025-04-07)


### Features

* **slash_cmds:** auto select providers based on installed plugins ([#1216](https://github.com/olimorris/codecompanion.nvim/issues/1216)) ([78b260c](https://github.com/olimorris/codecompanion.nvim/commit/78b260c1df2d37f7c91790685e0db82b338760e2))

## [14.7.1](https://github.com/olimorris/codecompanion.nvim/compare/v14.7.0...v14.7.1) (2025-04-06)


### Bug Fixes

* **chat:** `:CodeCompanionChat` now works ([#1219](https://github.com/olimorris/codecompanion.nvim/issues/1219)) ([593f2c5](https://github.com/olimorris/codecompanion.nvim/commit/593f2c5e4ead3247e5daca37bf673d0a6fcb1759))

## [14.7.0](https://github.com/olimorris/codecompanion.nvim/compare/v14.6.1...v14.7.0) (2025-04-05)


### Features

* **tools:** system_prompt in tool groups can be a function ([#1210](https://github.com/olimorris/codecompanion.nvim/issues/1210)) ([825f5ea](https://github.com/olimorris/codecompanion.nvim/commit/825f5eabc2e62f8a3d100f5246cd02a301681295))


### Bug Fixes

* **prompt_library:** don't trim empty lines with user role content ([#1211](https://github.com/olimorris/codecompanion.nvim/issues/1211)) ([5a18f89](https://github.com/olimorris/codecompanion.nvim/commit/5a18f8910dbae5b153045f7be2051a042a11e764))

## [14.6.1](https://github.com/olimorris/codecompanion.nvim/compare/v14.6.0...v14.6.1) (2025-04-04)


### Bug Fixes

* **ui:** respect opts.visible for non-"system" roles ([#1204](https://github.com/olimorris/codecompanion.nvim/issues/1204)) ([ef9cdc6](https://github.com/olimorris/codecompanion.nvim/commit/ef9cdc6f7a04d99b74988af70d0e724ec32cf236))

## [14.6.0](https://github.com/olimorris/codecompanion.nvim/compare/v14.5.0...v14.6.0) (2025-04-03)


### Features

* **diff:** improve default diff settings ([#1189](https://github.com/olimorris/codecompanion.nvim/issues/1189)) ([30da620](https://github.com/olimorris/codecompanion.nvim/commit/30da620ad79de0e6616b59e4f6d9c77f2d08f081))
* improve Telescope as action palette provider ([#1195](https://github.com/olimorris/codecompanion.nvim/issues/1195)) ([4fe008e](https://github.com/olimorris/codecompanion.nvim/commit/4fe008e43700bf45b5fbe8a22b0c32eee0d9dc75))

## [14.5.0](https://github.com/olimorris/codecompanion.nvim/compare/v14.4.0...v14.5.0) (2025-03-29)


### Features

* **symbols:** add Java support ([#1182](https://github.com/olimorris/codecompanion.nvim/issues/1182)) ([36ffd9c](https://github.com/olimorris/codecompanion.nvim/commit/36ffd9cd335afdc668e7bcc91ac6ae65149a4b2b))

## [14.4.0](https://github.com/olimorris/codecompanion.nvim/compare/v14.3.0...v14.4.0) (2025-03-27)


### Features

* **adapters:** add gemini 2.5 pro option ([#1180](https://github.com/olimorris/codecompanion.nvim/issues/1180)) ([f134b6c](https://github.com/olimorris/codecompanion.nvim/commit/f134b6c8f35ea1df4fa45d4f50319554178308fb))


### Bug Fixes

* **blink:** cursor put at wrong position after accepting ([#1179](https://github.com/olimorris/codecompanion.nvim/issues/1179)) ([f83641b](https://github.com/olimorris/codecompanion.nvim/commit/f83641ba9e3a8993afb03a856701623c746a05b8))

## [14.3.0](https://github.com/olimorris/codecompanion.nvim/compare/v14.2.2...v14.3.0) (2025-03-27)


### Features

* **inline:** vars can now be callbacks closes [#1175](https://github.com/olimorris/codecompanion.nvim/issues/1175)  ([#1176](https://github.com/olimorris/codecompanion.nvim/issues/1176)) ([ccbaf20](https://github.com/olimorris/codecompanion.nvim/commit/ccbaf205d2d842dbef4c9ad9532576cf08fd4b1f))

## [14.2.2](https://github.com/olimorris/codecompanion.nvim/compare/v14.2.1...v14.2.2) (2025-03-19)


### Bug Fixes

* **adapters:** copilot token issue when changing adapter closes [#1149](https://github.com/olimorris/codecompanion.nvim/issues/1149) ([#1155](https://github.com/olimorris/codecompanion.nvim/issues/1155)) ([0cc0541](https://github.com/olimorris/codecompanion.nvim/commit/0cc054199c20416da45bdbcadd10b3a9ea748557))
* **adapters:** remove `tfs_z` from Ollama schema ([#1152](https://github.com/olimorris/codecompanion.nvim/issues/1152)) ([52e2969](https://github.com/olimorris/codecompanion.nvim/commit/52e296963a0a8e6414c0ec72f6bc687b16f2eca7))

## [14.2.1](https://github.com/olimorris/codecompanion.nvim/compare/v14.2.0...v14.2.1) (2025-03-18)


### Bug Fixes

* **adapters:** ensure cache_expires is set ([#1146](https://github.com/olimorris/codecompanion.nvim/issues/1146)) ([5d6e3c5](https://github.com/olimorris/codecompanion.nvim/commit/5d6e3c5ad3436e1d0baca6588e96426e11f105e2))

## [14.2.0](https://github.com/olimorris/codecompanion.nvim/compare/v14.1.1...v14.2.0) (2025-03-18)


### Features

* **adapters:** add caching to adapters that make http calls to model endpoints ([#1145](https://github.com/olimorris/codecompanion.nvim/issues/1145)) ([9e779b2](https://github.com/olimorris/codecompanion.nvim/commit/9e779b2a4abfc154ba09f3a2d25bc684a413cefd))
* **adapters:** add support for novita ([#1136](https://github.com/olimorris/codecompanion.nvim/issues/1136)) ([d55dc41](https://github.com/olimorris/codecompanion.nvim/commit/d55dc41e380fffcf3f799d8ed7257ff7a6d51521))


### Bug Fixes

* **adapters:** anthropic inline editing ([#1142](https://github.com/olimorris/codecompanion.nvim/issues/1142)) ([ad99cda](https://github.com/olimorris/codecompanion.nvim/commit/ad99cdaca4df56bb3db5ac0a17b423740ce0396d))
* **blink:** add support to blink newer than 0.13.1 ([#1139](https://github.com/olimorris/codecompanion.nvim/issues/1139)) ([3ee07d6](https://github.com/olimorris/codecompanion.nvim/commit/3ee07d6805d85ddd9c97715af5bc79c8e7f2adb1))

## [14.1.1](https://github.com/olimorris/codecompanion.nvim/compare/v14.1.0...v14.1.1) (2025-03-17)


### Bug Fixes

* **adapters:** add mistral to the config ([#1133](https://github.com/olimorris/codecompanion.nvim/issues/1133)) ([fbb0e1d](https://github.com/olimorris/codecompanion.nvim/commit/fbb0e1d0ccdd2eaa16ea9ba0f94ca8e4c64f5b97))
* **completion:** disable default execute implementation for blink.cmp ([#1137](https://github.com/olimorris/codecompanion.nvim/issues/1137)) ([b88684d](https://github.com/olimorris/codecompanion.nvim/commit/b88684d97af444947cedaeda9cc7ba0205b0d3b4))

## [14.1.0](https://github.com/olimorris/codecompanion.nvim/compare/v14.0.1...v14.1.0) (2025-03-17)


### Features

* **adapters:** add Mistral adapter ([#1118](https://github.com/olimorris/codecompanion.nvim/issues/1118)) ([e4754bb](https://github.com/olimorris/codecompanion.nvim/commit/e4754bb2501685721daa50ed843fb98af9d01725))

## [14.0.1](https://github.com/olimorris/codecompanion.nvim/compare/v14.0.0...v14.0.1) (2025-03-17)


### Bug Fixes

* **anthropic:** inline editing closes [#1127](https://github.com/olimorris/codecompanion.nvim/issues/1127) ([#1130](https://github.com/olimorris/codecompanion.nvim/issues/1130)) ([bc89f11](https://github.com/olimorris/codecompanion.nvim/commit/bc89f118f1991e9be24c784f72f57f373aa6f84b))

## [14.0.0](https://github.com/olimorris/codecompanion.nvim/compare/v13.5.0...v14.0.0) (2025-03-13)


### ⚠ BREAKING CHANGES

* **workspaces:** new workspace file format ([#1089](https://github.com/olimorris/codecompanion.nvim/issues/1089))

### Features

* **workspaces:** new workspace file format ([#1089](https://github.com/olimorris/codecompanion.nvim/issues/1089)) ([3f7fd62](https://github.com/olimorris/codecompanion.nvim/commit/3f7fd6292b9d43d38e9760f43b581652210b0349))

## [13.5.0](https://github.com/olimorris/codecompanion.nvim/compare/v13.4.0...v13.5.0) (2025-03-12)


### Features

* **tools:** function-based tools can be async ([#1107](https://github.com/olimorris/codecompanion.nvim/issues/1107)) ([97636b9](https://github.com/olimorris/codecompanion.nvim/commit/97636b902ac20c665b0b3d9d5b2c62c16676e136))

## [13.4.0](https://github.com/olimorris/codecompanion.nvim/compare/v13.3.1...v13.4.0) (2025-03-12)


### Features

* **chat:** hide system prompts by default ([#1113](https://github.com/olimorris/codecompanion.nvim/issues/1113)) ([161aaba](https://github.com/olimorris/codecompanion.nvim/commit/161aaba38b06bf76f03a35c92ae809f819b88766))


### Bug Fixes

* **prompts:** do not ignore user prompt ([#1110](https://github.com/olimorris/codecompanion.nvim/issues/1110)) ([5ee7873](https://github.com/olimorris/codecompanion.nvim/commit/5ee7873342e254828963930e5c9e922c8d978211))

## [13.3.1](https://github.com/olimorris/codecompanion.nvim/compare/v13.3.0...v13.3.1) (2025-03-11)


### Bug Fixes

* **tool:** output handler can be any type ([#1106](https://github.com/olimorris/codecompanion.nvim/issues/1106)) ([8823590](https://github.com/olimorris/codecompanion.nvim/commit/8823590f3cb251eb09315682bb3f40abf212969b))

## [13.3.0](https://github.com/olimorris/codecompanion.nvim/compare/v13.2.4...v13.3.0) (2025-03-10)


### Features

* **ui** allow for full height chat windows when opening ([0e75d3b](https://github.com/olimorris/codecompanion.nvim/commit/0e75d3b9768e6a139bb2d51a1d05a6e2691171a8))
* **chat** toggle for auto-scrolling in chat buffer ([481aad8](https://github.com/olimorris/codecompanion.nvim/commit/481aad839cecbc7d9e8fe54e276bdc556f62d69e))

## [13.2.4](https://github.com/olimorris/codecompanion.nvim/compare/v13.2.3...v13.2.4) (2025-03-09)


### Bug Fixes

* **deepseek:** reasoning output closes [#1091](https://github.com/olimorris/codecompanion.nvim/issues/1091) ([#1095](https://github.com/olimorris/codecompanion.nvim/issues/1095)) ([bcdfa2b](https://github.com/olimorris/codecompanion.nvim/commit/bcdfa2b15232058964c53856cfbf736988ba0066))

## [13.2.3](https://github.com/olimorris/codecompanion.nvim/compare/v13.2.2...v13.2.3) (2025-03-06)


### Bug Fixes

* **chat:** update system prompt to avoid using h1 and h2 headers ([#1084](https://github.com/olimorris/codecompanion.nvim/issues/1084)) ([8f53a3a](https://github.com/olimorris/codecompanion.nvim/commit/8f53a3ab541545fdf325bb0dc3bec1de7207aab6))

## [13.2.2](https://github.com/olimorris/codecompanion.nvim/compare/v13.2.1...v13.2.2) (2025-03-06)


### Bug Fixes

* **tools:** [@files](https://github.com/files) tool reject causes error ([#1082](https://github.com/olimorris/codecompanion.nvim/issues/1082)) ([e9e7b26](https://github.com/olimorris/codecompanion.nvim/commit/e9e7b26187e3574a41aa09330e6dd4bb28c1fa9e))

## [13.2.1](https://github.com/olimorris/codecompanion.nvim/compare/v13.2.0...v13.2.1) (2025-03-05)


### Bug Fixes

* **chat:** can set system prompt dynamically when switching adapters closes [#1033](https://github.com/olimorris/codecompanion.nvim/issues/1033) ([#1077](https://github.com/olimorris/codecompanion.nvim/issues/1077)) ([b76a47a](https://github.com/olimorris/codecompanion.nvim/commit/b76a47a62383dcf22dd41839467ea37d2e82ee59))

## [13.2.0](https://github.com/olimorris/codecompanion.nvim/compare/v13.1.0...v13.2.0) (2025-03-05)


### Features

* **tools:** function tools can update the agent status + doc updates ([#1074](https://github.com/olimorris/codecompanion.nvim/issues/1074)) ([e59c1f0](https://github.com/olimorris/codecompanion.nvim/commit/e59c1f04983edac15f195bfc73cd90bf08a3565b))

## [13.1.0](https://github.com/olimorris/codecompanion.nvim/compare/v13.0.1...v13.1.0) (2025-03-04)


### Features

* **tools:** callbacks can be functions ([#1065](https://github.com/olimorris/codecompanion.nvim/issues/1065)) ([dff8a1c](https://github.com/olimorris/codecompanion.nvim/commit/dff8a1c969b66987923c14a305a654ea51b5e2a6))


### Bug Fixes

* **chat:** references not being added with `show_header_separators` closes [#1067](https://github.com/olimorris/codecompanion.nvim/issues/1067) ([#1069](https://github.com/olimorris/codecompanion.nvim/issues/1069)) ([9cd4094](https://github.com/olimorris/codecompanion.nvim/commit/9cd4094e5ccc428faae487568aabeb4873393f1b))

## [13.0.1](https://github.com/olimorris/codecompanion.nvim/compare/v13.0.0...v13.0.1) (2025-03-04)


### Bug Fixes

* **chat:** show tools and groups in helper window ([#1062](https://github.com/olimorris/codecompanion.nvim/issues/1062)) ([baa283e](https://github.com/olimorris/codecompanion.nvim/commit/baa283efe3ecf8d1d5183b10ac3cdfae2c9c8820))

## [13.0.0](https://github.com/olimorris/codecompanion.nvim/compare/v12.15.0...v13.0.0) (2025-03-04)


### ⚠ BREAKING CHANGES

* **tools:** add queue and streamline implementation ([#965](https://github.com/olimorris/codecompanion.nvim/issues/965))

### Code Refactoring

* **tools:** add queue and streamline implementation ([#965](https://github.com/olimorris/codecompanion.nvim/issues/965)) ([acd48ef](https://github.com/olimorris/codecompanion.nvim/commit/acd48eff972e334bb863c6b083db90c7fcb0b053))

## [12.15.0](https://github.com/olimorris/codecompanion.nvim/compare/v12.14.2...v12.15.0) (2025-03-02)


### Features

* blink completions on invoke, without trigger char ([#872](https://github.com/olimorris/codecompanion.nvim/issues/872)) ([51abcf1](https://github.com/olimorris/codecompanion.nvim/commit/51abcf1b4cfeb84c160f7589384b13636fa27e95))


### Bug Fixes

* **slash_cmds:** add spacing to `/fetch` input ([#953](https://github.com/olimorris/codecompanion.nvim/issues/953)) ([5f3332b](https://github.com/olimorris/codecompanion.nvim/commit/5f3332bb86a5c6afefb11659db3d78c11350cb66))

## [12.14.2](https://github.com/olimorris/codecompanion.nvim/compare/v12.14.1...v12.14.2) (2025-03-02)


### Bug Fixes

* **adapters:** replace vars on every request closes [#1052](https://github.com/olimorris/codecompanion.nvim/issues/1052) ([#1054](https://github.com/olimorris/codecompanion.nvim/issues/1054)) ([942fd80](https://github.com/olimorris/codecompanion.nvim/commit/942fd80b82d7059fa6fe494adea0b15168302e54))

## [12.14.1](https://github.com/olimorris/codecompanion.nvim/compare/v12.14.0...v12.14.1) (2025-02-28)


### Bug Fixes

* **ui:** render settings ([#1047](https://github.com/olimorris/codecompanion.nvim/issues/1047)) ([6bcebbf](https://github.com/olimorris/codecompanion.nvim/commit/6bcebbfaccb4fed649bf901bac3654373dece54c))

## [12.14.0](https://github.com/olimorris/codecompanion.nvim/compare/v12.13.3...v12.14.0) (2025-02-27)


### Features

* **slash_cmds:** remove git dependency for defualt provider ([#1042](https://github.com/olimorris/codecompanion.nvim/issues/1042)) ([a5c5a32](https://github.com/olimorris/codecompanion.nvim/commit/a5c5a3263ba825b7cd708597e541d2deac3c52f7))

## [12.13.3](https://github.com/olimorris/codecompanion.nvim/compare/v12.13.2...v12.13.3) (2025-02-27)


### Bug Fixes

* **adapters:** openai_compatible hardcoded models endpoint closes [#1022](https://github.com/olimorris/codecompanion.nvim/issues/1022) ([#1038](https://github.com/olimorris/codecompanion.nvim/issues/1038)) ([4585695](https://github.com/olimorris/codecompanion.nvim/commit/4585695d2537ccc4cf9b14bc5559b6c29353a588))

## [12.13.2](https://github.com/olimorris/codecompanion.nvim/compare/v12.13.1...v12.13.2) (2025-02-27)


### Bug Fixes

* **adapters:** dynamically getting copilot adapters when switching adapters ([c0a820e](https://github.com/olimorris/codecompanion.nvim/commit/c0a820e0184ac0714c608b06fd3822abe79492cb))
* **adapters:** inline editing with copilot closes [#1036](https://github.com/olimorris/codecompanion.nvim/issues/1036) [#1027](https://github.com/olimorris/codecompanion.nvim/issues/1027) ([#1037](https://github.com/olimorris/codecompanion.nvim/issues/1037)) ([aae4ad7](https://github.com/olimorris/codecompanion.nvim/commit/aae4ad785dea43b1adfb2d0c0c6b546fe09c1819))

## [12.13.1](https://github.com/olimorris/codecompanion.nvim/compare/v12.13.0...v12.13.1) (2025-02-27)


### Bug Fixes

* **adapters:** max_tokens error with anthropic ([#1031](https://github.com/olimorris/codecompanion.nvim/issues/1031)) ([59c9109](https://github.com/olimorris/codecompanion.nvim/commit/59c91098f967ffd57f7ae90846a6f751d1c96d2d))

## [12.13.0](https://github.com/olimorris/codecompanion.nvim/compare/v12.12.0...v12.13.0) (2025-02-25)


### Features

* **adapters:** dynamically get available models from copilot endpoint ([#1012](https://github.com/olimorris/codecompanion.nvim/issues/1012)) ([d62c8e1](https://github.com/olimorris/codecompanion.nvim/commit/d62c8e16291e113c877db8c6adc9ec45835b9a66))

## [12.12.0](https://github.com/olimorris/codecompanion.nvim/compare/v12.11.0...v12.12.0) (2025-02-25)


### Features

* **adapters:** add extended thinking and extended output for claude-3.7 ([#998](https://github.com/olimorris/codecompanion.nvim/issues/998)) ([a497adb](https://github.com/olimorris/codecompanion.nvim/commit/a497adb166fcfc29ef0a4fdad04bb0320e08e912))

## [12.11.0](https://github.com/olimorris/codecompanion.nvim/compare/v12.10.1...v12.11.0) (2025-02-25)


### Features

* **adapters:** add gemini-2.0-pro-exp-02-05 model option ([#1007](https://github.com/olimorris/codecompanion.nvim/issues/1007)) ([bef6d90](https://github.com/olimorris/codecompanion.nvim/commit/bef6d90a73652672c09b1b6323c8d5a0215020c0))

## [12.10.1](https://github.com/olimorris/codecompanion.nvim/compare/v12.10.0...v12.10.1) (2025-02-25)


### Bug Fixes

* **ollama:** allow users to customize the authorization header in get_models closes [#976](https://github.com/olimorris/codecompanion.nvim/issues/976) ([#985](https://github.com/olimorris/codecompanion.nvim/issues/985)) ([a4f1046](https://github.com/olimorris/codecompanion.nvim/commit/a4f1046e26e1ca537fcc21b881051c41f00e337c))

## [12.10.0](https://github.com/olimorris/codecompanion.nvim/compare/v12.9.0...v12.10.0) (2025-02-25)


### Features

* **adapters:** add claude 3.7 thought to copilot adapter ([#1001](https://github.com/olimorris/codecompanion.nvim/issues/1001)) ([6e53570](https://github.com/olimorris/codecompanion.nvim/commit/6e535709234e07995bacae08f267c0823457f1c5))

## [12.9.0](https://github.com/olimorris/codecompanion.nvim/compare/v12.8.1...v12.9.0) (2025-02-25)


### Features

* **adapters:** add claude-3.7-sonnet to copilot ([#1002](https://github.com/olimorris/codecompanion.nvim/issues/1002)) ([9729441](https://github.com/olimorris/codecompanion.nvim/commit/9729441037518c487a4a223165d463abcd1bdd67))

## [12.8.1](https://github.com/olimorris/codecompanion.nvim/compare/v12.8.0...v12.8.1) (2025-02-25)


### Bug Fixes

* **adapters:** only try and replace str variables ([#999](https://github.com/olimorris/codecompanion.nvim/issues/999)) ([c5990b4](https://github.com/olimorris/codecompanion.nvim/commit/c5990b43d0801438aac4afaef7a779ff98297a85))

## [12.8.0](https://github.com/olimorris/codecompanion.nvim/compare/v12.7.2...v12.8.0) (2025-02-24)


### Features

* **adapters:** add claude-3.7-sonnet and make default ([#996](https://github.com/olimorris/codecompanion.nvim/issues/996)) ([c207203](https://github.com/olimorris/codecompanion.nvim/commit/c207203a005baf0bd5bae3401ac202f568c60581))

## [12.7.2](https://github.com/olimorris/codecompanion.nvim/compare/v12.7.1...v12.7.2) (2025-02-23)


### Bug Fixes

* **inline:** setting placement from prompt library closes [#990](https://github.com/olimorris/codecompanion.nvim/issues/990) ([#991](https://github.com/olimorris/codecompanion.nvim/issues/991)) ([836dafc](https://github.com/olimorris/codecompanion.nvim/commit/836dafca125ec713f8a9379c69319f7889504824))

## [12.7.1](https://github.com/olimorris/codecompanion.nvim/compare/v12.7.0...v12.7.1) (2025-02-22)


### Bug Fixes

* **adapter:** variable substitution in 'raw'. ([#980](https://github.com/olimorris/codecompanion.nvim/issues/980)) ([6c628f5](https://github.com/olimorris/codecompanion.nvim/commit/6c628f56419ce8cca7b93cfaba89cde90a3a3a51))

## [12.7.0](https://github.com/olimorris/codecompanion.nvim/compare/v12.6.1...v12.7.0) (2025-02-20)


### Features

* add reference handling to workflow processing ([#969](https://github.com/olimorris/codecompanion.nvim/issues/969)) ([4c9f120](https://github.com/olimorris/codecompanion.nvim/commit/4c9f120033c1c1b4c17536c2407c288d91d34e95))

## [12.6.1](https://github.com/olimorris/codecompanion.nvim/compare/v12.6.0...v12.6.1) (2025-02-20)


### Bug Fixes

* **tools:** add missing write flag attribute when editing files ([#966](https://github.com/olimorris/codecompanion.nvim/issues/966)) ([d5bc944](https://github.com/olimorris/codecompanion.nvim/commit/d5bc9441d55a9e6f81191ec96871ae4a48890997))

## [12.6.0](https://github.com/olimorris/codecompanion.nvim/compare/v12.5.2...v12.6.0) (2025-02-19)


### Features

* **chat:** easier to add refs from external sources ([#960](https://github.com/olimorris/codecompanion.nvim/issues/960)) ([b7b43f6](https://github.com/olimorris/codecompanion.nvim/commit/b7b43f62ede6814fc5ab90d464016c63546d22a9))
* **tools:** when `stderr` is not empty, do not discard `stdout` when exit code is 0 ([#955](https://github.com/olimorris/codecompanion.nvim/issues/955)) ([d8de491](https://github.com/olimorris/codecompanion.nvim/commit/d8de491ebf2ed4bca7006ae33e6990ec3f8d60d0))

## [12.5.2](https://github.com/olimorris/codecompanion.nvim/compare/v12.5.1...v12.5.2) (2025-02-18)


### Bug Fixes

* **inline:** ensure placement is in lower case ([#949](https://github.com/olimorris/codecompanion.nvim/issues/949)) ([04019d5](https://github.com/olimorris/codecompanion.nvim/commit/04019d5aefd70c7d44031c97e2f2126b6ed408af))

## [12.5.1](https://github.com/olimorris/codecompanion.nvim/compare/v12.5.0...v12.5.1) (2025-02-18)


### Bug Fixes

* **tools:** can now chain jobs effectively ([#945](https://github.com/olimorris/codecompanion.nvim/issues/945)) ([2bab6d7](https://github.com/olimorris/codecompanion.nvim/commit/2bab6d78a3c4b05e852c80cadb13fbc8b1e0c99f))
* **tools:** make stderr capturing work for "streaming" output ([#943](https://github.com/olimorris/codecompanion.nvim/issues/943)) ([199824e](https://github.com/olimorris/codecompanion.nvim/commit/199824e89b0c459cc489d176aac60ce6c909d5a1))

## [12.5.0](https://github.com/olimorris/codecompanion.nvim/compare/v12.4.0...v12.5.0) (2025-02-18)


### Features

* **inline:** new and improved assistant ([#904](https://github.com/olimorris/codecompanion.nvim/issues/904)) ([3e4fb61](https://github.com/olimorris/codecompanion.nvim/commit/3e4fb6176a9c1df456795a22891f865a2f4ee56a))


### Bug Fixes

* **adapters:** `on_exit` is called when request is cancelled ([#942](https://github.com/olimorris/codecompanion.nvim/issues/942)) ([df2c5f6](https://github.com/olimorris/codecompanion.nvim/commit/df2c5f6abe7a8e14eb792cf633fafee826d892a2))

## [12.4.0](https://github.com/olimorris/codecompanion.nvim/compare/v12.3.1...v12.4.0) (2025-02-17)


### Features

* **tools:** allow passing a table as the `callback` of a tool. ([#936](https://github.com/olimorris/codecompanion.nvim/issues/936)) ([689ea6e](https://github.com/olimorris/codecompanion.nvim/commit/689ea6edbcdf0d1d16a90d41d5fa96cbdac4633f))

## [12.3.1](https://github.com/olimorris/codecompanion.nvim/compare/v12.3.0...v12.3.1) (2025-02-17)


### Bug Fixes

* **adapters:** `openai_compatible` no longer forces schema ([#914](https://github.com/olimorris/codecompanion.nvim/issues/914)) ([ba06239](https://github.com/olimorris/codecompanion.nvim/commit/ba0623998febc50859b172bfd7c8fe8bf180a22b)), closes [#918](https://github.com/olimorris/codecompanion.nvim/issues/918)

## [12.3.0](https://github.com/olimorris/codecompanion.nvim/compare/v12.2.5...v12.3.0) (2025-02-16)


### Features

* **adapters:** can hide default adapters ([#925](https://github.com/olimorris/codecompanion.nvim/issues/925)) ([f4b72d7](https://github.com/olimorris/codecompanion.nvim/commit/f4b72d746eb9549747e5236649306f5c56c1ae5a))

## [12.2.5](https://github.com/olimorris/codecompanion.nvim/compare/v12.2.4...v12.2.5) (2025-02-15)


### Bug Fixes

* **chat:** debug window height and width asfunctions ([#926](https://github.com/olimorris/codecompanion.nvim/issues/926)) ([1d67908](https://github.com/olimorris/codecompanion.nvim/commit/1d67908153855bacc28a766ecb0903c68f14b2d8)), closes [#905](https://github.com/olimorris/codecompanion.nvim/issues/905)

## [12.2.4](https://github.com/olimorris/codecompanion.nvim/compare/v12.2.3...v12.2.4) (2025-02-14)


### Bug Fixes

* **chat:** [#915](https://github.com/olimorris/codecompanion.nvim/issues/915) parsing show_settings when InsertLeave is executed ([#916](https://github.com/olimorris/codecompanion.nvim/issues/916)) ([1103551](https://github.com/olimorris/codecompanion.nvim/commit/1103551e8ba5772522422017ca618a65d385db2c))

## [12.2.3](https://github.com/olimorris/codecompanion.nvim/compare/v12.2.2...v12.2.3) (2025-02-12)


### Bug Fixes

* **chat:** [#906](https://github.com/olimorris/codecompanion.nvim/issues/906) ignore system prompt now works ([#909](https://github.com/olimorris/codecompanion.nvim/issues/909)) ([4d0e4dd](https://github.com/olimorris/codecompanion.nvim/commit/4d0e4dd80016a63ffcf28953ba13da72a1ccd953))

## [12.2.2](https://github.com/olimorris/codecompanion.nvim/compare/v12.2.1...v12.2.2) (2025-02-12)


### Bug Fixes

* **chat:** [#887](https://github.com/olimorris/codecompanion.nvim/issues/887) header separator is now detected ([#902](https://github.com/olimorris/codecompanion.nvim/issues/902)) ([63e76c5](https://github.com/olimorris/codecompanion.nvim/commit/63e76c580d49eb30c147594a8bf9ca50f145f8f7))

## [12.2.1](https://github.com/olimorris/codecompanion.nvim/compare/v12.2.0...v12.2.1) (2025-02-11)


### Bug Fixes

* **workspaces:** add description to urls from cache and check they exist ([#900](https://github.com/olimorris/codecompanion.nvim/issues/900)) ([2d08176](https://github.com/olimorris/codecompanion.nvim/commit/2d0817684206b6caa17c72c2a58d3e21641d96fe))

## [12.2.0](https://github.com/olimorris/codecompanion.nvim/compare/v12.1.2...v12.2.0) (2025-02-11)


### Features

* **slash_cmds:** terminal command only shows latest changes ([#898](https://github.com/olimorris/codecompanion.nvim/issues/898)) ([cde1882](https://github.com/olimorris/codecompanion.nvim/commit/cde18827e796f898b18899b5dbecf3badf72d2a9))


### Bug Fixes

* **openai:** model streaming ([#896](https://github.com/olimorris/codecompanion.nvim/issues/896)) ([28a03a3](https://github.com/olimorris/codecompanion.nvim/commit/28a03a38c7f9019fd303614d1d42b4539f324b97))

## [12.1.2](https://github.com/olimorris/codecompanion.nvim/compare/v12.1.1...v12.1.2) (2025-02-11)


### Bug Fixes

* **openai:** [#892](https://github.com/olimorris/codecompanion.nvim/issues/892) handle different finish reasons ([#893](https://github.com/olimorris/codecompanion.nvim/issues/893)) ([70179b0](https://github.com/olimorris/codecompanion.nvim/commit/70179b00092a1ab45114448b256bb02c2fdb34de))

## [12.1.1](https://github.com/olimorris/codecompanion.nvim/compare/v12.1.0...v12.1.1) (2025-02-11)


### Bug Fixes

* **chat:** [#889](https://github.com/olimorris/codecompanion.nvim/issues/889) pinned file references always have same id ([#890](https://github.com/olimorris/codecompanion.nvim/issues/890)) ([cbac9bc](https://github.com/olimorris/codecompanion.nvim/commit/cbac9bc6552a0eb3c3b6b0a64adb5ddd71617dbc))

## [12.1.0](https://github.com/olimorris/codecompanion.nvim/compare/v12.0.1...v12.1.0) (2025-02-11)


### Features

* adapter and debug window improvement ([#880](https://github.com/olimorris/codecompanion.nvim/pull/880)) ([be55c9b](https://github.com/olimorris/codecompanion.nvim/commit/be55c9b05d34940a15ad5aed70f62f04e333c7c4))
* **events:** new request streaming event ([#878](https://github.com/olimorris/codecompanion.nvim/issues/878)) ([6846482](https://github.com/olimorris/codecompanion.nvim/commit/68464826515b764ebae5fdf28e4d3f8c01c80296))

## [12.0.1](https://github.com/olimorris/codecompanion.nvim/compare/v12.0.0...v12.0.1) (2025-02-09)


### Bug Fixes

* **chat:** incorrectly applying settings ([#881](https://github.com/olimorris/codecompanion.nvim/issues/881)) ([2b0fe19](https://github.com/olimorris/codecompanion.nvim/commit/2b0fe199ca7d4b38895a8ab29b6320ca877809c6))

## [12.0.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.28.0...v12.0.0) (2025-02-09)


### Features

* :sparkles: Agentic Workflows and much more ([#832](https://github.com/olimorris/codecompanion.nvim/issues/832)) ([f26fa4e](https://github.com/olimorris/codecompanion.nvim/commit/f26fa4eb8d0bd1ac0b0a2ab980839965db381fc2))

## [11.28.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.27.1...v11.28.0) (2025-02-08)


### Features

* **adapters:** add GitHub Models support ([#862](https://github.com/olimorris/codecompanion.nvim/issues/862)) ([4a6567b](https://github.com/olimorris/codecompanion.nvim/commit/4a6567b2a563503b157705ec284fb922f81b784a))

## [11.27.1](https://github.com/olimorris/codecompanion.nvim/compare/v11.27.0...v11.27.1) (2025-02-07)


### Bug Fixes

* delete diff buffers instead of closing ([#852](https://github.com/olimorris/codecompanion.nvim/issues/852)) ([4c48bd3](https://github.com/olimorris/codecompanion.nvim/commit/4c48bd336e900ed7bf3be95689ac1cc147b3701e))

## [11.27.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.26.0...v11.27.0) (2025-02-07)


### Features

* **copilot:** add support for gemini 2.0 flash ([#855](https://github.com/olimorris/codecompanion.nvim/issues/855)) ([#856](https://github.com/olimorris/codecompanion.nvim/issues/856)) ([c0ea1c0](https://github.com/olimorris/codecompanion.nvim/commit/c0ea1c0faf57a61c1121532cad9bbeea58dcd0cc))

## [11.26.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.25.3...v11.26.0) (2025-02-05)


### Features

* **slash_cmds:** can be functions and modules ([#844](https://github.com/olimorris/codecompanion.nvim/issues/844)) ([59ea59e](https://github.com/olimorris/codecompanion.nvim/commit/59ea59e3c2bd336334b706a99446b792c32464bf))

## [11.25.3](https://github.com/olimorris/codecompanion.nvim/compare/v11.25.2...v11.25.3) (2025-02-05)


### Bug Fixes

* **http:** prevent model from no schema.model ([#839](https://github.com/olimorris/codecompanion.nvim/issues/839)) ([abaf645](https://github.com/olimorris/codecompanion.nvim/commit/abaf645cfcb64bddc8f9124fb4bf71999372e752))

## [11.25.2](https://github.com/olimorris/codecompanion.nvim/compare/v11.25.1...v11.25.2) (2025-02-03)


### Bug Fixes

* **chat:** prevent duplicate references ([fb6444b](https://github.com/olimorris/codecompanion.nvim/commit/fb6444b739c01c2009a6adb6dbeea23c425b4c7c))

## [11.25.1](https://github.com/olimorris/codecompanion.nvim/compare/v11.25.0...v11.25.1) (2025-02-03)


### Bug Fixes

* **chat:** better cancelling of requests ([#828](https://github.com/olimorris/codecompanion.nvim/issues/828)) ([84e8098](https://github.com/olimorris/codecompanion.nvim/commit/84e80986e2915a003f1609d8e3107d7046c6e3b8))

## [11.25.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.24.0...v11.25.0) (2025-02-01)


### Features

* **chat:** ui title is configurable ([8c93ab0](https://github.com/olimorris/codecompanion.nvim/commit/8c93ab0ecb031261d026cf3e8f7b84fe48b81f73))

## [11.24.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.23.1...v11.24.0) (2025-02-01)


### Features

* **events:** add strategy and adapter to payload ([#822](https://github.com/olimorris/codecompanion.nvim/issues/822)) ([b2e06de](https://github.com/olimorris/codecompanion.nvim/commit/b2e06de23f4b19f472ed97259260102fa7f9af0e))

## [11.23.1](https://github.com/olimorris/codecompanion.nvim/compare/v11.23.0...v11.23.1) (2025-02-01)


### Bug Fixes

* **chat:** [#814](https://github.com/olimorris/codecompanion.nvim/issues/814) `show_header_separator` ([#816](https://github.com/olimorris/codecompanion.nvim/issues/816)) ([38793d3](https://github.com/olimorris/codecompanion.nvim/commit/38793d32f2d00df580e7648f7e8109817bc70855))

## [11.23.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.22.0...v11.23.0) (2025-02-01)


### Features

* **adapters:** add reasoning effort to copilot and openai ([#812](https://github.com/olimorris/codecompanion.nvim/issues/812)) ([b9a58eb](https://github.com/olimorris/codecompanion.nvim/commit/b9a58eb8f151f9771938105220d81c7577a52e0e))
* **copilot:** add o3-mini support ([#810](https://github.com/olimorris/codecompanion.nvim/issues/810)) ([2816d12](https://github.com/olimorris/codecompanion.nvim/commit/2816d1244f0ce905c330fd9041d96ead51bbb0c2))

## [11.22.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.21.0...v11.22.0) (2025-01-31)


### Features

* **workspaces:** :sparkles: now supporting URLs ([#808](https://github.com/olimorris/codecompanion.nvim/issues/808)) ([5a1212d](https://github.com/olimorris/codecompanion.nvim/commit/5a1212d1124618853a6e39ecdc98c003619564f1))

## [11.21.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.20.6...v11.21.0) (2025-01-31)


### Features

* **workspaces:** handle multiple workflows better ([#806](https://github.com/olimorris/codecompanion.nvim/issues/806)) ([e463d65](https://github.com/olimorris/codecompanion.nvim/commit/e463d65ed4a5ba023acd58039b8f223eb82308c0))

## [11.20.6](https://github.com/olimorris/codecompanion.nvim/compare/v11.20.5...v11.20.6) (2025-01-31)


### Bug Fixes

* **slash_commands:** [#803](https://github.com/olimorris/codecompanion.nvim/issues/803) mini_pick provider ([#804](https://github.com/olimorris/codecompanion.nvim/issues/804)) ([4a895b9](https://github.com/olimorris/codecompanion.nvim/commit/4a895b9f4385e8c04dd70411c3628423dfd6b8a6))

## [11.20.5](https://github.com/olimorris/codecompanion.nvim/compare/v11.20.4...v11.20.5) (2025-01-31)


### Bug Fixes

* **chat:** can debug adapters with `schema.model.default` as a function ([#797](https://github.com/olimorris/codecompanion.nvim/issues/797)) ([fbb15a8](https://github.com/olimorris/codecompanion.nvim/commit/fbb15a8b10d203c8c4df5fb938d5c9ac841725fa))

## [11.20.4](https://github.com/olimorris/codecompanion.nvim/compare/v11.20.3...v11.20.4) (2025-01-31)


### Bug Fixes

* [#769](https://github.com/olimorris/codecompanion.nvim/issues/769) ollama adapter ([#793](https://github.com/olimorris/codecompanion.nvim/issues/793)) ([8a98c71](https://github.com/olimorris/codecompanion.nvim/commit/8a98c71cbdbde65230824c01d10eed262717c7a7))

## [11.20.3](https://github.com/olimorris/codecompanion.nvim/compare/v11.20.2...v11.20.3) (2025-01-30)


### Bug Fixes

* **slash_commands:** scope constants to be local ([#787](https://github.com/olimorris/codecompanion.nvim/issues/787)) ([7daf143](https://github.com/olimorris/codecompanion.nvim/commit/7daf143c46c9710697ee3e17f2043664c0859951))

## [11.20.2](https://github.com/olimorris/codecompanion.nvim/compare/v11.20.1...v11.20.2) (2025-01-30)


### Bug Fixes

* **chat:** [#783](https://github.com/olimorris/codecompanion.nvim/issues/783) display settings in chat buffer ([#784](https://github.com/olimorris/codecompanion.nvim/issues/784)) ([cd712c5](https://github.com/olimorris/codecompanion.nvim/commit/cd712c5cafe9fcf2d17c5564bb2bd0141b16f15d))
* logging in plugin ([#786](https://github.com/olimorris/codecompanion.nvim/issues/786)) ([ec30170](https://github.com/olimorris/codecompanion.nvim/commit/ec301700c01414abbe7bfb7883b80ebb9255762b))

## [11.20.1](https://github.com/olimorris/codecompanion.nvim/compare/v11.20.0...v11.20.1) (2025-01-30)


### Bug Fixes

* **chat:** navigate between H2 headers in buffer only ([#781](https://github.com/olimorris/codecompanion.nvim/issues/781)) ([391aeae](https://github.com/olimorris/codecompanion.nvim/commit/391aeae6b0dbbe6e4d31bd0ac77a25fefa0ea9de))

## [11.20.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.19.0...v11.20.0) (2025-01-30)


### Features

* **chat:** :sparkles: LLM header name can now be a function ([#778](https://github.com/olimorris/codecompanion.nvim/issues/778)) ([5a82a54](https://github.com/olimorris/codecompanion.nvim/commit/5a82a5422494c44e6bbcf6c8afedacfe61659b03))

## [11.19.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.18.1...v11.19.0) (2025-01-29)


### Features

* add symbols for scala ([#768](https://github.com/olimorris/codecompanion.nvim/issues/768)) ([4535cb5](https://github.com/olimorris/codecompanion.nvim/commit/4535cb5bdf92e3bc88d4cf061c606447131e27db))


### Bug Fixes

* **chat:** message editing for adapters with model schema as a function ([b6dcc37](https://github.com/olimorris/codecompanion.nvim/commit/b6dcc378c95014b0a3e62593c9150f682206e61f))

## [11.18.1](https://github.com/olimorris/codecompanion.nvim/compare/v11.18.0...v11.18.1) (2025-01-29)


### Bug Fixes

* **adapter:** [#769](https://github.com/olimorris/codecompanion.nvim/issues/769) ollama adapter model not being expanded ([6a78557](https://github.com/olimorris/codecompanion.nvim/commit/6a78557b3fbd69a0f1dcec3e962c353b0b79db85))
* **adapters:** handle multiline userdata in copilot adapter ([#770](https://github.com/olimorris/codecompanion.nvim/issues/770)) ([4282c68](https://github.com/olimorris/codecompanion.nvim/commit/4282c68476f60ea9328790508ff3b191b6ec512b))

## [11.18.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.17.5...v11.18.0) (2025-01-29)


### Features

* :sparkles: can edit setting and message history ([#753](https://github.com/olimorris/codecompanion.nvim/issues/753)) ([2592d26](https://github.com/olimorris/codecompanion.nvim/commit/2592d26eb3da9462174c858464324c31eb35eb91))

## [11.17.5](https://github.com/olimorris/codecompanion.nvim/compare/v11.17.4...v11.17.5) (2025-01-29)


### Bug Fixes

* **workspaces:** workspace path constant cleared after first use ([#761](https://github.com/olimorris/codecompanion.nvim/issues/761)) ([b39acc1](https://github.com/olimorris/codecompanion.nvim/commit/b39acc15dfdf057f6e7f2d0b87e0183d3d151409))

## [11.17.4](https://github.com/olimorris/codecompanion.nvim/compare/v11.17.3...v11.17.4) (2025-01-29)


### Bug Fixes

* **deepseek:** [#760](https://github.com/olimorris/codecompanion.nvim/issues/760) tooling and update adapter utils ([3d3b1a1](https://github.com/olimorris/codecompanion.nvim/commit/3d3b1a1f5deb5e06a86d67a9b792a263ea8e9191))

## [11.17.3](https://github.com/olimorris/codecompanion.nvim/compare/v11.17.2...v11.17.3) (2025-01-29)


### Bug Fixes

* **slash_command:** create cache folder on windows for `/fetch` ([#756](https://github.com/olimorris/codecompanion.nvim/issues/756)) ([223e35f](https://github.com/olimorris/codecompanion.nvim/commit/223e35f8150f49a16ec19c966d822594c2bcf4b7))

## [11.17.2](https://github.com/olimorris/codecompanion.nvim/compare/v11.17.1...v11.17.2) (2025-01-28)


### Bug Fixes

* **inline:** tweak system prompt ([#754](https://github.com/olimorris/codecompanion.nvim/issues/754)) ([4985375](https://github.com/olimorris/codecompanion.nvim/commit/4985375c6256498ff6991179404557c16118568a))

## [11.17.1](https://github.com/olimorris/codecompanion.nvim/compare/v11.17.0...v11.17.1) (2025-01-28)


### Bug Fixes

* **adapter:** [#731](https://github.com/olimorris/codecompanion.nvim/issues/731) openai_compat adapter calling API too much ([#738](https://github.com/olimorris/codecompanion.nvim/issues/738)) ([184ca40](https://github.com/olimorris/codecompanion.nvim/commit/184ca40c1f802b7eb2b0dc5236dab56a10d9e96e))

## [11.17.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.16.1...v11.17.0) (2025-01-27)


### Features

* :sparkles: add support for `snacks.nvim` ([#741](https://github.com/olimorris/codecompanion.nvim/issues/741)) ([5407aba](https://github.com/olimorris/codecompanion.nvim/commit/5407aba817d11c4e1f27da34210e4cd58e88a388))

## [11.16.1](https://github.com/olimorris/codecompanion.nvim/compare/v11.16.0...v11.16.1) (2025-01-27)


### Bug Fixes

* **chat:** more graceful cancellations ([#739](https://github.com/olimorris/codecompanion.nvim/issues/739)) ([05c8853](https://github.com/olimorris/codecompanion.nvim/commit/05c8853ff0ff931a0daed569367d69524c792292))

## [11.16.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.15.3...v11.16.0) (2025-01-27)


### Features

* **slash_command:** control system prompts in `/workspace` ([#736](https://github.com/olimorris/codecompanion.nvim/issues/736)) ([16d7f62](https://github.com/olimorris/codecompanion.nvim/commit/16d7f62239bea7b716b06c9ec588f977e054f90e))

## [11.15.3](https://github.com/olimorris/codecompanion.nvim/compare/v11.15.2...v11.15.3) (2025-01-27)


### Bug Fixes

* [#732](https://github.com/olimorris/codecompanion.nvim/issues/732) can use deepseek with no config ([#733](https://github.com/olimorris/codecompanion.nvim/issues/733)) ([23d81a9](https://github.com/olimorris/codecompanion.nvim/commit/23d81a946e71c28cf2bdd025c1a3708f07f8d880))

## [11.15.2](https://github.com/olimorris/codecompanion.nvim/compare/v11.15.1...v11.15.2) (2025-01-27)


### Bug Fixes

* **chat:** change deepseek models ([7e211d5](https://github.com/olimorris/codecompanion.nvim/commit/7e211d522d0cf1f8cbd3b5f25d486e80f4276693))

## [11.15.1](https://github.com/olimorris/codecompanion.nvim/compare/v11.15.0...v11.15.1) (2025-01-27)


### Bug Fixes

* **slash_command:** typescript ft not recognised ([#723](https://github.com/olimorris/codecompanion.nvim/issues/723)) ([c114e42](https://github.com/olimorris/codecompanion.nvim/commit/c114e4203d858aef99a835280e02a67a6d0d9082))

## [11.15.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.14.2...v11.15.0) (2025-01-26)


### Features

* **deepseek:** [#692](https://github.com/olimorris/codecompanion.nvim/issues/692) [#669](https://github.com/olimorris/codecompanion.nvim/issues/669) show reasoning output ([#716](https://github.com/olimorris/codecompanion.nvim/issues/716)) ([b4467a1](https://github.com/olimorris/codecompanion.nvim/commit/b4467a1af36e8b99ffadc95dfed55154b18aebf8))

## [11.14.2](https://github.com/olimorris/codecompanion.nvim/compare/v11.14.1...v11.14.2) (2025-01-26)


### Bug Fixes

* [#698](https://github.com/olimorris/codecompanion.nvim/issues/698) custom variables ([#711](https://github.com/olimorris/codecompanion.nvim/issues/711)) ([104f913](https://github.com/olimorris/codecompanion.nvim/commit/104f91331979be7c44fa9b766b8356863ab955cd))

## [11.14.1](https://github.com/olimorris/codecompanion.nvim/compare/v11.14.0...v11.14.1) (2025-01-26)


### Performance Improvements

* **chat:** [#552](https://github.com/olimorris/codecompanion.nvim/issues/552) improve settings tree-sitter query ([#708](https://github.com/olimorris/codecompanion.nvim/issues/708)) ([c7e54d2](https://github.com/olimorris/codecompanion.nvim/commit/c7e54d28cc29e7cd2b221b585b90640c7fa21483))

## [11.14.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.13.2...v11.14.0) (2025-01-25)


### Features

* :sparkles: workspace slash command ([#702](https://github.com/olimorris/codecompanion.nvim/issues/702)) ([8173b5d](https://github.com/olimorris/codecompanion.nvim/commit/8173b5df1cd8da856b9449b4f68a8cd64d60f08d))

## [11.13.2](https://github.com/olimorris/codecompanion.nvim/compare/v11.13.1...v11.13.2) (2025-01-25)

### Bug Fixes

* **deepseek:** messages order ([#700](https://github.com/olimorris/codecompanion.nvim/issues/700)) ([c911a8e](https://github.com/olimorris/codecompanion.nvim/commit/c911a8e6f0bc87f557587cc60b2af27d6151ad19))

## [11.13.1](https://github.com/olimorris/codecompanion.nvim/compare/v11.13.0...v11.13.1) (2025-01-24)

### Bug Fixes

- fix(inline): #688 end_col out of range

### Others

- chore(ci): remove release workflow
- chore(ci): update release workflow
- chore: update CHANGELOG.md

## [11.13.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.12.1...v11.13.0) (2025-01-23)

### Features

* **adapters:** add DeepSeek Adapter ([6668b5c](https://github.com/olimorris/codecompanion.nvim/commit/6668b5c517978207a7b00f3f5a9bc8c7760ebcad))


## [11.12.1](https://github.com/olimorris/codecompanion.nvim/compare/v11.12.0...v11.12.1) (2025-01-18)


### Bug Fixes

* **slash_command:** stop double wrapping output from `fetch` ([c53a917](https://github.com/olimorris/codecompanion.nvim/commit/c53a917803888458ba7955e52870353345c9c48c))

## [11.12.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.11.0...v11.12.0) (2025-01-18)


### Features

* register source for filetype in blink.cmp ([#661](https://github.com/olimorris/codecompanion.nvim/issues/661)) ([2214916](https://github.com/olimorris/codecompanion.nvim/commit/2214916416dcf18741c65fe3afd034d0fe046263))
* **tools:** `[@files](https://github.com/files)` tool can now read specific lines ([26c5b57](https://github.com/olimorris/codecompanion.nvim/commit/26c5b57aa80cb7a12baefa5a5a2e9cfe0a20126a))

## [11.11.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.10.0...v11.11.0) (2025-01-15)


### Features

* **chat:** :sparkles: can watch buffers ([176c13e](https://github.com/olimorris/codecompanion.nvim/commit/176c13e227cf39c4e22bec68d4631a8c47b643de))


### Bug Fixes

* **slash_cmd:** improve symbols notifcations ([e6b36b4](https://github.com/olimorris/codecompanion.nvim/commit/e6b36b4448cb12215fb74372ce9868f61e046bea))

## [11.10.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.9.2...v11.10.0) (2025-01-15)


### Features

* add new events ([9b85331](https://github.com/olimorris/codecompanion.nvim/commit/9b8533143e381fb0dd4e5c733217dac8f9852ea4))

## [11.9.2](https://github.com/olimorris/codecompanion.nvim/compare/v11.9.1...v11.9.2) (2025-01-13)


### Bug Fixes

* **slash_commands:** handle no content in `terminal` slash command ([aae2085](https://github.com/olimorris/codecompanion.nvim/commit/aae208550ade2d1cbcfaada2c72aeeee83b989b0))
* **yaml:** handle nil values in show_settings ([9b44789](https://github.com/olimorris/codecompanion.nvim/commit/9b447897320ee149531b6d6d8f90b25d97880666))

## [11.9.1](https://github.com/olimorris/codecompanion.nvim/compare/v11.9.0...v11.9.1) (2025-01-11)


### Bug Fixes

* **slash_cmds:** `file` slash command will show hidden files with telescope ([39c7ca0](https://github.com/olimorris/codecompanion.nvim/commit/39c7ca07918999fa5daf8ef344a4490befa56858))
* **utils:** parse "boolean_scalar" fields when decoding yaml ([#635](https://github.com/olimorris/codecompanion.nvim/issues/635)) ([3bf8cac](https://github.com/olimorris/codecompanion.nvim/commit/3bf8cacd5298dfa1b103c52d8fd460b0be3b2d08))

## [11.9.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.8.6...v11.9.0) (2025-01-10)


### Features

* **prompts:** :sparkles: can now add references to the prompt library ([d5d86c9](https://github.com/olimorris/codecompanion.nvim/commit/d5d86c9af92555d2cafcb147573871445b8688b5))

## [11.8.6](https://github.com/olimorris/codecompanion.nvim/compare/v11.8.5...v11.8.6) (2025-01-09)


### Bug Fixes

* **chat:** changing adapters for models with table type ([3a961bb](https://github.com/olimorris/codecompanion.nvim/commit/3a961bb2df0dd9245bdf2c9cc2e3fcdb7d9f3654))

## [11.8.5](https://github.com/olimorris/codecompanion.nvim/compare/v11.8.4...v11.8.5) (2025-01-09)


### Bug Fixes

* **chat:** [#622](https://github.com/olimorris/codecompanion.nvim/issues/622) parse messages when `show_header_separator` is on ([6040ce4](https://github.com/olimorris/codecompanion.nvim/commit/6040ce4b45e0b9378e4c51c2d86cf5f40b2af2c5))
* **completion:** blink.cmp failing for slash commands ([6dd3309](https://github.com/olimorris/codecompanion.nvim/commit/6dd3309e6761d7ae8cbda386781eb48354f00db2))
* **copilot:** show token output in chat ([6908fd7](https://github.com/olimorris/codecompanion.nvim/commit/6908fd71b589c9a4813f2dad9f460a6368003617))
* **inline:** [#613](https://github.com/olimorris/codecompanion.nvim/issues/613) negative column indexing ([977a521](https://github.com/olimorris/codecompanion.nvim/commit/977a521d1a3780d2278d1f175e37ca439b10a372))

## [11.8.4](https://github.com/olimorris/codecompanion.nvim/compare/v11.8.3...v11.8.4) (2025-01-08)


### Bug Fixes

* use slash commands with `:CodeCompanion` cmd ([8cbf696](https://github.com/olimorris/codecompanion.nvim/commit/8cbf6960960bf386d85badad99152bf021554986))

## [11.8.3](https://github.com/olimorris/codecompanion.nvim/compare/v11.8.2...v11.8.3) (2025-01-08)


### Bug Fixes

* **openai:** [#619](https://github.com/olimorris/codecompanion.nvim/issues/619) o1 streaming ([83786d8](https://github.com/olimorris/codecompanion.nvim/commit/83786d878ebf46b50ae0a3717ad033934a80a390))
* **openai:** [#619](https://github.com/olimorris/codecompanion.nvim/issues/619) o1 streaming ([8bfb496](https://github.com/olimorris/codecompanion.nvim/commit/8bfb49633b6cd9194807856636b6b63047a06ac4))

## [11.8.2](https://github.com/olimorris/codecompanion.nvim/compare/v11.8.1...v11.8.2) (2025-01-08)


### Bug Fixes

* **chat:** agent's tools are no displayed individually ([d889210](https://github.com/olimorris/codecompanion.nvim/commit/d889210fd2c536940fb57ec0ad90d018e76c275c))
* **chat:** always strip references from messages ([4c91a46](https://github.com/olimorris/codecompanion.nvim/commit/4c91a46136b6db99880c694313c9cabee24bd715))
* **chat:** changing adapter in empty chat w/o system prompt ([#616](https://github.com/olimorris/codecompanion.nvim/issues/616)) ([3e64e6c](https://github.com/olimorris/codecompanion.nvim/commit/3e64e6c89af1c3e841bbd59b67265f475983c164))

## [11.8.1](https://github.com/olimorris/codecompanion.nvim/compare/v11.8.0...v11.8.1) (2025-01-07)


### Bug Fixes

* **tools:** better error handling ([0d8de44](https://github.com/olimorris/codecompanion.nvim/commit/0d8de4456c67a8867688497787d3794d5e09e751))

## [11.8.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.7.0...v11.8.0) (2025-01-06)


### Features

* **tools:** `files` tool now uses search/replace block to edit text ([a02f6c7](https://github.com/olimorris/codecompanion.nvim/commit/a02f6c7bcbfdf955ca1c603b635cd9bc5baaaa7c))

## [11.7.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.6.2...v11.7.0) (2025-01-06)


### Features

* [#604](https://github.com/olimorris/codecompanion.nvim/issues/604) `send_code` can be a function ([30b899e](https://github.com/olimorris/codecompanion.nvim/commit/30b899e638d5525494b64eacd19b1c0eb50f988c))

## [11.6.2](https://github.com/olimorris/codecompanion.nvim/compare/v11.6.1...v11.6.2) (2025-01-06)


### Performance Improvements

* **http:** improve resiliency of requests ([d99928b](https://github.com/olimorris/codecompanion.nvim/commit/d99928b5503788651b0b67bb3a577746763c7349))

## [11.6.1](https://github.com/olimorris/codecompanion.nvim/compare/v11.6.0...v11.6.1) (2025-01-05)


### Bug Fixes

* **tools:** output correctly in the chat buffer ([3a6acfb](https://github.com/olimorris/codecompanion.nvim/commit/3a6acfbc52989848b8264fe415380747a9af5615))

## [11.6.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.5.0...v11.6.0) (2025-01-05)


### Features

* **completion:** suggestions in blink have better score ([4317513](https://github.com/olimorris/codecompanion.nvim/commit/4317513cdb5fb7f35147448e3ca696756bf82cf2))


### Bug Fixes

* **completion:** [#597](https://github.com/olimorris/codecompanion.nvim/issues/597) blink configuration ([a1166d5](https://github.com/olimorris/codecompanion.nvim/commit/a1166d5a2e9249f81060d328859382be57eae79d))

## [11.5.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.4.0...v11.5.0) (2025-01-05)


### Features

* **slash_cmds:** `buffer` slash command now sends line numbers ([25dab99](https://github.com/olimorris/codecompanion.nvim/commit/25dab9939e5065a59207d3b77eefc63e4b6e9fc0))


### Bug Fixes

* **cmp:** extend default sources ([8b0ebb4](https://github.com/olimorris/codecompanion.nvim/commit/8b0ebb4092c3266746663443d1b8dff13e3ba723))

## [11.4.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.3.0...v11.4.0) (2025-01-05)


### Features

* **completion:** auto setup blink.cmp ([90a6603](https://github.com/olimorris/codecompanion.nvim/commit/90a66033ffddb2f1daac0e5d23723214673ab0e5))

## [11.3.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.2.0...v11.3.0) (2025-01-05)


### Features

* **event:** add `CodeCompanionChatPin` event ([f86f4a7](https://github.com/olimorris/codecompanion.nvim/commit/f86f4a72dd154bb677d117e06cab9a9ee8d35f56))

## [11.2.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.1.2...v11.2.0) (2025-01-05)


### Features

* **slash_cmd:** notify if no terminal buffer is found ([3687b88](https://github.com/olimorris/codecompanion.nvim/commit/3687b8807746700851f13a373ad6ead04bb082bd))

## [11.1.2](https://github.com/olimorris/codecompanion.nvim/compare/v11.1.1...v11.1.2) (2025-01-05)


### Bug Fixes

* **blink:** [#587](https://github.com/olimorris/codecompanion.nvim/issues/587) slash commands ([1b8ab18](https://github.com/olimorris/codecompanion.nvim/commit/1b8ab18cd0be76f13d13e6deaa56e6c33dce5a23))
* **blink:** slash commands leaving brackes in chat buffer ([820bc52](https://github.com/olimorris/codecompanion.nvim/commit/820bc52c7b4a5a494773a3aa4e25e9e36659e378))

## [11.1.1](https://github.com/olimorris/codecompanion.nvim/compare/v11.1.0...v11.1.1) (2025-01-04)


### Bug Fixes

* allow for multiple completions in a single line ([3516e46](https://github.com/olimorris/codecompanion.nvim/commit/3516e46a62ebb151e6fa0afe4ac631432994cc3a))

## [11.1.0](https://github.com/olimorris/codecompanion.nvim/compare/v11.0.1...v11.1.0) (2025-01-03)


### Features

* **adapters:** update `copilot` and `openai` adapters for o1 models ([c7ba92a](https://github.com/olimorris/codecompanion.nvim/commit/c7ba92ad367939e94bfa23df7e3eb1bc74909348))
* **copilot:** add token count ([4fd26a6](https://github.com/olimorris/codecompanion.nvim/commit/4fd26a6fd9bc6aa4e88176350a05ff7e16b3a789))

## [11.0.1](https://github.com/olimorris/codecompanion.nvim/compare/v11.0.0...v11.0.1) (2024-12-29)


### Bug Fixes

* **gemini:** remove cycle from system prompt ([d6b95bb](https://github.com/olimorris/codecompanion.nvim/commit/d6b95bb6cbf074e2e431c6a7f9acdd1af7cc9397))

## [11.0.0](https://github.com/olimorris/codecompanion.nvim/compare/v10.10.0...v11.0.0) (2024-12-28)


### ⚠ BREAKING CHANGES

* **agents:** agents are now in `strategies.chat.agents`
* **chat:** :sparkles: can pin buffers and files to requests

### Features

* **chat:** :sparkles: can pin buffers and files to requests ([fc8ee3a](https://github.com/olimorris/codecompanion.nvim/commit/fc8ee3a085a44d0ef0111be0499f6552d7dbe865))


### Code Refactoring

* **agents:** agents are now in `strategies.chat.agents` ([3f437a6](https://github.com/olimorris/codecompanion.nvim/commit/3f437a62d55ad6efe14a4af2ffdc4e474696852a))

## [10.10.0](https://github.com/olimorris/codecompanion.nvim/compare/v10.9.1...v10.10.0) (2024-12-24)


### Features

* **chat:** adding to chat initializes buffer if needed ([#567](https://github.com/olimorris/codecompanion.nvim/issues/567)) ([8c82ced](https://github.com/olimorris/codecompanion.nvim/commit/8c82cedc3d70255ec6ea0fdb348b3e931c435fba))


### Bug Fixes

* **adapters:** gemini-2.0-flash-exp inline strategy ([#568](https://github.com/olimorris/codecompanion.nvim/issues/568)) ([a9faa69](https://github.com/olimorris/codecompanion.nvim/commit/a9faa69d3bf8308b78deab97292af2acc57d2f87))

## [10.9.1](https://github.com/olimorris/codecompanion.nvim/compare/v10.9.0...v10.9.1) (2024-12-23)


### Bug Fixes

* **adapters:** openai_compatible ([0d1388f](https://github.com/olimorris/codecompanion.nvim/commit/0d1388f7409f06e96ef2a7eadfa76c1dcfb74648))

## [10.9.0](https://github.com/olimorris/codecompanion.nvim/compare/v10.8.2...v10.9.0) (2024-12-23)


### Features

* **chat:** customize split position ([#556](https://github.com/olimorris/codecompanion.nvim/issues/556)) ([7374192](https://github.com/olimorris/codecompanion.nvim/commit/73741920097f36c762bb8fe1f4de6617389e2d4c))

## [10.8.2](https://github.com/olimorris/codecompanion.nvim/compare/v10.8.1...v10.8.2) (2024-12-22)


### Bug Fixes

* **adapters:** [#560](https://github.com/olimorris/codecompanion.nvim/issues/560) nil url in openai_compatible adpater ([5cc2693](https://github.com/olimorris/codecompanion.nvim/commit/5cc26934b0732dda03d311195e6d3f357e4f4a0c))
* **adapters:** further openai_compatible fixes ([a84f6ff](https://github.com/olimorris/codecompanion.nvim/commit/a84f6ff4be745bcff7d69af96fdbdae2465a33a2))

## [10.8.1](https://github.com/olimorris/codecompanion.nvim/compare/v10.8.0...v10.8.1) (2024-12-20)


### Bug Fixes

* **workflow:** can auto_submit the first prompt ([86f96d5](https://github.com/olimorris/codecompanion.nvim/commit/86f96d5419915b0711afbc93d948a3312bfc25b6))
* **workflows:** wrap in `vim.schedule` for performance ([f0f6e26](https://github.com/olimorris/codecompanion.nvim/commit/f0f6e260a98c5ffe6ff6257227d1f429a4ecb07c))

## [10.8.0](https://github.com/olimorris/codecompanion.nvim/compare/v10.7.0...v10.8.0) (2024-12-18)


### Features

* **chat:** can delete references ([367eccc](https://github.com/olimorris/codecompanion.nvim/commit/367eccc7cc57edcc249bae850ac4ccdf599a060c))
* **chat:** can delete references ([c0b8c25](https://github.com/olimorris/codecompanion.nvim/commit/c0b8c2522c20b8369201132a4ce953f3cdf7b5e2))


### Bug Fixes

* [#542](https://github.com/olimorris/codecompanion.nvim/issues/542) use vim.treesitter instead of nvim-treesitter. ([#543](https://github.com/olimorris/codecompanion.nvim/issues/543)) ([b741490](https://github.com/olimorris/codecompanion.nvim/commit/b741490066c0129554300e493f27767b760ffa16))
* **chat:** show documentation for blink.cmp ([f41dbab](https://github.com/olimorris/codecompanion.nvim/commit/f41dbab850572b290e37e0b52244b8ccb9699870))

## [10.7.0](https://github.com/olimorris/codecompanion.nvim/compare/v10.6.0...v10.7.0) (2024-12-14)


### Features

* **chat:** add `CodeCompanionChatOpened` event ([fdfc640](https://github.com/olimorris/codecompanion.nvim/commit/fdfc640f638de7e44580c75882b81cc6dd99b950))

## [10.6.0](https://github.com/olimorris/codecompanion.nvim/compare/v10.5.3...v10.6.0) (2024-12-13)


### Features

* **adapters:** add Hugging Face adapter ([#527](https://github.com/olimorris/codecompanion.nvim/issues/527)) ([48747c4](https://github.com/olimorris/codecompanion.nvim/commit/48747c4e36eb0a3f44d6d9e55f8089b9e27cacfc))

## [10.5.3](https://github.com/olimorris/codecompanion.nvim/compare/v10.5.2...v10.5.3) (2024-12-13)


### Bug Fixes

* **inline:** [#531](https://github.com/olimorris/codecompanion.nvim/issues/531) inline edits in c++ buffers ([73e8ea5](https://github.com/olimorris/codecompanion.nvim/commit/73e8ea561e81cce3b9c75d825b8294e0a82fc4e9))

## [10.5.2](https://github.com/olimorris/codecompanion.nvim/compare/v10.5.1...v10.5.2) (2024-12-12)


### Bug Fixes

* **adapters:** [#528](https://github.com/olimorris/codecompanion.nvim/issues/528) Gemini adapter fails if system prompt is removed ([7ca4364](https://github.com/olimorris/codecompanion.nvim/commit/7ca43642376d7768a3f2ecea2cd99ae9a792451a))

## [10.5.1](https://github.com/olimorris/codecompanion.nvim/compare/v10.5.0...v10.5.1) (2024-12-10)


### Bug Fixes

* **slash_commands:** prompt library now works with blink.cmp ([1027f47](https://github.com/olimorris/codecompanion.nvim/commit/1027f47c6c583a6b6592ae60a8008d780517792a))

## [10.5.0](https://github.com/olimorris/codecompanion.nvim/compare/v10.4.6...v10.5.0) (2024-12-09)


### Features

* **chat:** :sparkles: `blink.cmp` support ([cb2c93f](https://github.com/olimorris/codecompanion.nvim/commit/cb2c93f8a6b0ab0522a814f244b8011a7275ea3b))
* **slash_commands:** `help` cmd now prompts user to trim if exceeding max_lines ([33c326a](https://github.com/olimorris/codecompanion.nvim/commit/33c326a0d31473ecf3112d783dbcc22afccfb801))

## [10.4.6](https://github.com/olimorris/codecompanion.nvim/compare/v10.4.5...v10.4.6) (2024-12-09)


### Bug Fixes

* **cmd:** strategy now respects `vim.g.codecompanion_adapter` ([b629005](https://github.com/olimorris/codecompanion.nvim/commit/b629005f0467471b4439192492cea2d49f22d52f))

## [10.4.5](https://github.com/olimorris/codecompanion.nvim/compare/v10.4.4...v10.4.5) (2024-12-09)


### Bug Fixes

* **chat:** prevent double adding of references ([953b20d](https://github.com/olimorris/codecompanion.nvim/commit/953b20dabf63e4e5c7b30b9d32cd1136291aceb1))
* **inline:** [#516](https://github.com/olimorris/codecompanion.nvim/issues/516) switching adapters via `vim.g.codecompanion_adapter` ([0d91c08](https://github.com/olimorris/codecompanion.nvim/commit/0d91c086b30da050aa0a95dd9e69d16d9d88c587))
* **slash_commands:** [#515](https://github.com/olimorris/codecompanion.nvim/issues/515) help tags line limit can be customised ([e1b9876](https://github.com/olimorris/codecompanion.nvim/commit/e1b9876641e4ea0fa80f78339c260b16b729a21f))

## [10.4.4](https://github.com/olimorris/codecompanion.nvim/compare/v10.4.3...v10.4.4) (2024-12-06)


### Bug Fixes

* [#501](https://github.com/olimorris/codecompanion.nvim/issues/501) `blink.compat` causing issues with completion menu ([c5065d0](https://github.com/olimorris/codecompanion.nvim/commit/c5065d02916d8c1bf5dd3baf9f0dd5e1f017fd57))

## [10.4.3](https://github.com/olimorris/codecompanion.nvim/compare/v10.4.2...v10.4.3) (2024-12-05)


### Bug Fixes

* **tools:** remove ANSI sequences from all output ([2836849](https://github.com/olimorris/codecompanion.nvim/commit/2836849c6e1533fc54d06e88d52354374efc728d))

## [10.4.2](https://github.com/olimorris/codecompanion.nvim/compare/v10.4.1...v10.4.2) (2024-12-05)


### Bug Fixes

* **tools:** [#503](https://github.com/olimorris/codecompanion.nvim/issues/503) shell redirection ([7023e58](https://github.com/olimorris/codecompanion.nvim/commit/7023e58a056cb834cd3620fec6c42de37469109b))

## [10.4.1](https://github.com/olimorris/codecompanion.nvim/compare/v10.4.0...v10.4.1) (2024-12-05)


### Bug Fixes

* **tools:** explictly add cwd to `plenary.job` call ([e78006d](https://github.com/olimorris/codecompanion.nvim/commit/e78006d5a09f0bc9ec78aab4f2a53a4d6bf40149))
* **tools:** strip ansi from cmd output ([679a9a5](https://github.com/olimorris/codecompanion.nvim/commit/679a9a513f61a5d4e622c7506599cad55f35e502))

## [10.4.0](https://github.com/olimorris/codecompanion.nvim/compare/v10.3.1...v10.4.0) (2024-12-02)


### Features

* **prompts:** system prompt is optional for custom prompts ([90820fc](https://github.com/olimorris/codecompanion.nvim/commit/90820fcdb5e6a570dc4f92731fade4d5f716ea02))

## [10.3.1](https://github.com/olimorris/codecompanion.nvim/compare/v10.3.0...v10.3.1) (2024-11-28)


### Bug Fixes

* **utils:** [#488](https://github.com/olimorris/codecompanion.nvim/issues/488) fix edge cases in visual selection ([84a8e89](https://github.com/olimorris/codecompanion.nvim/commit/84a8e8962e9ae20b8357d813dee1ea44a8079605))

## [10.3.0](https://github.com/olimorris/codecompanion.nvim/compare/v10.2.4...v10.3.0) (2024-11-27)


### Features

* **chat:** keymaps can be custom functions ([5f729f9](https://github.com/olimorris/codecompanion.nvim/commit/5f729f91a6b6a4025f8e4753d2c2c29810da0149))

## [10.2.4](https://github.com/olimorris/codecompanion.nvim/compare/v10.2.3...v10.2.4) (2024-11-25)


### Bug Fixes

* **chat:** slash commands from prompt library not visible ([3376f60](https://github.com/olimorris/codecompanion.nvim/commit/3376f6052217737cb936236d9069bd4a63ccbace))

## [10.2.3](https://github.com/olimorris/codecompanion.nvim/compare/v10.2.2...v10.2.3) (2024-11-25)


### Bug Fixes

* mini.pick as action_palette provider ([adeb7c4](https://github.com/olimorris/codecompanion.nvim/commit/adeb7c42fb7fb1187c64773a46d5bfee8f85dacf))

## [10.2.2](https://github.com/olimorris/codecompanion.nvim/compare/v10.2.1...v10.2.2) (2024-11-24)


### Bug Fixes

* **tools:** rejected cmd tools close properly ([50d0d25](https://github.com/olimorris/codecompanion.nvim/commit/50d0d2543ed3115477cfacfd80db0e029857127e))

## [10.2.1](https://github.com/olimorris/codecompanion.nvim/compare/v10.2.0...v10.2.1) (2024-11-24)


### Bug Fixes

* **utils:** visual selection range no longer uses feedkeys ([e981da2](https://github.com/olimorris/codecompanion.nvim/commit/e981da23ae0e900a4086e8dcbc0b6abf86b737a9))

## [10.2.0](https://github.com/olimorris/codecompanion.nvim/compare/v10.1.2...v10.2.0) (2024-11-23)


### Features

* **keymaps:** add condition logic ([c4eb21e](https://github.com/olimorris/codecompanion.nvim/commit/c4eb21e89ecf466416b75395ac00bf3db83838e7))


### Bug Fixes

* **config:** wrap completion condition in pcall ([d19ae05](https://github.com/olimorris/codecompanion.nvim/commit/d19ae05f561a7d3b5d311453285996e84cc925de))

## [10.1.2](https://github.com/olimorris/codecompanion.nvim/compare/v10.1.1...v10.1.2) (2024-11-22)


### Bug Fixes

* **keymaps:** completion menu is now `&lt;c-_&gt;` ([24f296b](https://github.com/olimorris/codecompanion.nvim/commit/24f296bd2382bc9f50d387b5ac849410d6c2d491))

## [10.1.1](https://github.com/olimorris/codecompanion.nvim/compare/v10.1.0...v10.1.1) (2024-11-22)


### Bug Fixes

* **completion:** setting of keymaps ([03fbb0a](https://github.com/olimorris/codecompanion.nvim/commit/03fbb0ac20d3a028d9462efe49f3d53b60e92a8a))

## [10.1.0](https://github.com/olimorris/codecompanion.nvim/compare/v10.0.4...v10.1.0) (2024-11-22)


### Features

* add native completions ([a1147f8](https://github.com/olimorris/codecompanion.nvim/commit/a1147f8133707251603525acf6a87f5c12ef3a70))


### Bug Fixes

* **slash_commands:** fetch doesn't error on no input ([be9e36c](https://github.com/olimorris/codecompanion.nvim/commit/be9e36c217f15ff53b06c9eb2ba7c42de026dc70))

## [10.0.4](https://github.com/olimorris/codecompanion.nvim/compare/v10.0.3...v10.0.4) (2024-11-21)


### Bug Fixes

* **tools:** editor diff should be cleared on_exit ([b143ee0](https://github.com/olimorris/codecompanion.nvim/commit/b143ee0831c59fe2ad3582883c09a24f6659b7b0))

## [10.0.3](https://github.com/olimorris/codecompanion.nvim/compare/v10.0.2...v10.0.3) (2024-11-21)


### Bug Fixes

* opening existing chats from the action palette ([59823c2](https://github.com/olimorris/codecompanion.nvim/commit/59823c232da7cbbc8a5fde5edbbf32578bd653b4))

## [10.0.2](https://github.com/olimorris/codecompanion.nvim/compare/v10.0.1...v10.0.2) (2024-11-21)


### Bug Fixes

* **tools:** [#467](https://github.com/olimorris/codecompanion.nvim/issues/467) reading of files on disk ([034ed9e](https://github.com/olimorris/codecompanion.nvim/commit/034ed9eec8f8726cc30f9854d92d6f608e399717))

## [10.0.1](https://github.com/olimorris/codecompanion.nvim/compare/v10.0.0...v10.0.1) (2024-11-20)


### Bug Fixes

* **diff:** is_visible() a nil value in default diff ([8d7a796](https://github.com/olimorris/codecompanion.nvim/commit/8d7a7965095925039dbfe34f56b0d72920e67545))

## [10.0.0](https://github.com/olimorris/codecompanion.nvim/compare/v9.12.4...v10.0.0) (2024-11-20)


### ⚠ BREAKING CHANGES

* **adapters:** azure_openai deployment model mapping

### Bug Fixes

* **adapters:** azure_openai deployment model mapping ([907e47a](https://github.com/olimorris/codecompanion.nvim/commit/907e47ac490a9ab91be8db820e99be6845e0cdc5))

## [9.12.4](https://github.com/olimorris/codecompanion.nvim/compare/v9.12.3...v9.12.4) (2024-11-20)


### Bug Fixes

* **openai:** [#458](https://github.com/olimorris/codecompanion.nvim/issues/458) handle models being a function ([041193b](https://github.com/olimorris/codecompanion.nvim/commit/041193b1b238d7b4980847a24c19c74dcf080029))

## [9.12.3](https://github.com/olimorris/codecompanion.nvim/compare/v9.12.2...v9.12.3) (2024-11-20)


### Bug Fixes

* **chat:** display tokens in chat buffer ([de55dd5](https://github.com/olimorris/codecompanion.nvim/commit/de55dd5c270e486cebf2d11861da41d816926051))

## [9.12.2](https://github.com/olimorris/codecompanion.nvim/compare/v9.12.1...v9.12.2) (2024-11-20)


### Bug Fixes

* **cmd:** users can now change adapters ([ec2e4df](https://github.com/olimorris/codecompanion.nvim/commit/ec2e4dfedbaf35fa79f03d9f73c4cf4089425359))

## [9.12.1](https://github.com/olimorris/codecompanion.nvim/compare/v9.12.0...v9.12.1) (2024-11-19)


### Bug Fixes

* **inline:** [#426](https://github.com/olimorris/codecompanion.nvim/issues/426) concat of lines ([34beee3](https://github.com/olimorris/codecompanion.nvim/commit/34beee3a1f5e97cde61bd906afa9ddd534aeb88c))
* **openai:** support streaming in o1 models ([7c77a82](https://github.com/olimorris/codecompanion.nvim/commit/7c77a82b1c726734c6b6022b3f4b657660e37b57))

## [9.12.0](https://github.com/olimorris/codecompanion.nvim/compare/v9.11.2...v9.12.0) (2024-11-19)


### Features

* :sparkles: `CodeCompanionCmd` to write command-line commands ([da52e53](https://github.com/olimorris/codecompanion.nvim/commit/da52e53bcc69fb00c28e19edce61f927af2e683d))

## [9.11.2](https://github.com/olimorris/codecompanion.nvim/compare/v9.11.1...v9.11.2) (2024-11-19)


### Bug Fixes

* **chat:** [#450](https://github.com/olimorris/codecompanion.nvim/issues/450) no longer remove autocmds ([ca1e4d8](https://github.com/olimorris/codecompanion.nvim/commit/ca1e4d837d224fc879e031fcea4613c29fade1c0))

## [9.11.1](https://github.com/olimorris/codecompanion.nvim/compare/v9.11.0...v9.11.1) (2024-11-19)


### Bug Fixes

* **keymaps:** closing and opening chat buffer ([91a08d7](https://github.com/olimorris/codecompanion.nvim/commit/91a08d76d47e16f3779545b1f4267a1eb0be1cb1))

## [9.11.0](https://github.com/olimorris/codecompanion.nvim/compare/v9.10.0...v9.11.0) (2024-11-19)


### Features

* **mini_pick:** allow multi selection in /files ([#444](https://github.com/olimorris/codecompanion.nvim/issues/444)) ([68e0610](https://github.com/olimorris/codecompanion.nvim/commit/68e0610fa847ad818f621006746ff4a5f911371f))


### Bug Fixes

* **chat:** [#447](https://github.com/olimorris/codecompanion.nvim/issues/447) moving between windows ([d3e88dd](https://github.com/olimorris/codecompanion.nvim/commit/d3e88dd8f66bf746d361c8ba96e862d4e3e4aa0f))
* OpenAI-compatible adapter ([#446](https://github.com/olimorris/codecompanion.nvim/issues/446)) ([3bfc575](https://github.com/olimorris/codecompanion.nvim/commit/3bfc575dd69e43cb1b2d01868f1689d024d3bbe4))

## [9.10.0](https://github.com/olimorris/codecompanion.nvim/compare/v9.9.1...v9.10.0) (2024-11-17)


### Features

* **chat:** tools and variables are now added to references ([a291a05](https://github.com/olimorris/codecompanion.nvim/commit/a291a05233f8ecf7b86a163dcd8bd349f319ff43))

## [9.9.1](https://github.com/olimorris/codecompanion.nvim/compare/v9.9.0...v9.9.1) (2024-11-17)


### Bug Fixes

* **chat:** changing model always changes settings ([318f40d](https://github.com/olimorris/codecompanion.nvim/commit/318f40d35bb53d663f8f80f26737b69430fe1c55))

## [9.9.0](https://github.com/olimorris/codecompanion.nvim/compare/v9.8.2...v9.9.0) (2024-11-16)


### Features

* **openai:** support for o1 models ([6f98005](https://github.com/olimorris/codecompanion.nvim/commit/6f980055b49d1c96af1c63943152147b4f303ab8))

## [9.8.2](https://github.com/olimorris/codecompanion.nvim/compare/v9.8.1...v9.8.2) (2024-11-16)


### Bug Fixes

* [#435](https://github.com/olimorris/codecompanion.nvim/issues/435) navigate chat buffers ([5779868](https://github.com/olimorris/codecompanion.nvim/commit/5779868e2db9fd056c835f375a57287bf46444f0))

## [9.8.1](https://github.com/olimorris/codecompanion.nvim/compare/v9.8.0...v9.8.1) (2024-11-16)


### Bug Fixes

* **slash_commands:** telescope selection ([6184bd4](https://github.com/olimorris/codecompanion.nvim/commit/6184bd4e60d4f301cc5f47416a9a90731eb7f8fb))

## [9.8.0](https://github.com/olimorris/codecompanion.nvim/compare/v9.7.0...v9.8.0) (2024-11-15)


### Features

* **adapters:** allow for o1 models at some point with improved schema ([601fa72](https://github.com/olimorris/codecompanion.nvim/commit/601fa72b09327f57e0703539673ef120ba3f420c))
* **copilot:** now working with o1 models ([7283611](https://github.com/olimorris/codecompanion.nvim/commit/72836115615b62065507431b8a9a8523d224f8e4))


### Bug Fixes

* **chat:** clear references table ([7c0f6fb](https://github.com/olimorris/codecompanion.nvim/commit/7c0f6fb1687c4499075d02913e308279cfeb1b2a))

## [9.7.0](https://github.com/olimorris/codecompanion.nvim/compare/v9.6.1...v9.7.0) (2024-11-14)


### Features

* **slash_commands:** help can now select multiple docs ([57e8e54](https://github.com/olimorris/codecompanion.nvim/commit/57e8e54df850749eb98001f52af5bc4f60b79f0e))

## [9.6.1](https://github.com/olimorris/codecompanion.nvim/compare/v9.6.0...v9.6.1) (2024-11-14)


### Bug Fixes

* [#423](https://github.com/olimorris/codecompanion.nvim/issues/423) diff provider and `before` inline prompt ([f9a54cc](https://github.com/olimorris/codecompanion.nvim/commit/f9a54cc28a861770c3b3db787353b24e7fd0cd2d))
* [#427](https://github.com/olimorris/codecompanion.nvim/issues/427) long prompts causing issue with curl ([d5bef40](https://github.com/olimorris/codecompanion.nvim/commit/d5bef403460908069810726ffe79039d4c69f054))

## [9.6.0](https://github.com/olimorris/codecompanion.nvim/compare/v9.5.2...v9.6.0) (2024-11-13)


### Features

* **chat:** display references which are shared with the LLM in the UI ([767efee](https://github.com/olimorris/codecompanion.nvim/commit/767efee2ff8fd7d84ac9a5ff35bac52eecec5584))

## [9.5.2](https://github.com/olimorris/codecompanion.nvim/compare/v9.5.1...v9.5.2) (2024-11-13)


### Bug Fixes

* **slash_commands:** [#408](https://github.com/olimorris/codecompanion.nvim/issues/408) no symbols found in file ([aececa0](https://github.com/olimorris/codecompanion.nvim/commit/aececa030a05ad86614df3fcb0fae0c40c7bac13))

## [9.5.1](https://github.com/olimorris/codecompanion.nvim/compare/v9.5.0...v9.5.1) (2024-11-09)


### Bug Fixes

* **tools:** add XML block formatting guidance ([#417](https://github.com/olimorris/codecompanion.nvim/issues/417)) ([315da62](https://github.com/olimorris/codecompanion.nvim/commit/315da62c789fd9053d5b17ba28bb78364d687d49))

## [9.5.0](https://github.com/olimorris/codecompanion.nvim/compare/v9.4.0...v9.5.0) (2024-11-07)


### Features

* mini_pick can select multiple buffers ([#413](https://github.com/olimorris/codecompanion.nvim/issues/413)) ([031a9e9](https://github.com/olimorris/codecompanion.nvim/commit/031a9e9d253872308d22c6619fa7e7db62ba7fc7))

## [9.4.0](https://github.com/olimorris/codecompanion.nvim/compare/v9.3.0...v9.4.0) (2024-11-06)


### Features

* /buffer slash command can select multiple buffers ([e88b703](https://github.com/olimorris/codecompanion.nvim/commit/e88b7036a6428ce82b7254b0a2d58ae869635bbd))

## [9.3.0](https://github.com/olimorris/codecompanion.nvim/compare/v9.2.0...v9.3.0) (2024-11-06)


### Features

* add language configuration for LLM responses ([#410](https://github.com/olimorris/codecompanion.nvim/issues/410)) ([e1a39bb](https://github.com/olimorris/codecompanion.nvim/commit/e1a39bb4e19cbda955a0f3caf09b78b798d10c4c))

## [9.2.0](https://github.com/olimorris/codecompanion.nvim/compare/v9.1.0...v9.2.0) (2024-11-05)


### Features

* **adapters:** ✨ add Azure OpenAI ([#386](https://github.com/olimorris/codecompanion.nvim/issues/386)) ([542628d](https://github.com/olimorris/codecompanion.nvim/commit/542628dd68e26bbb59699aa48fe98b83a3798999))
* **adapters:** update the new haiku model ([#404](https://github.com/olimorris/codecompanion.nvim/issues/404)) ([9b00ed3](https://github.com/olimorris/codecompanion.nvim/commit/9b00ed39c11f43fbb829bcbada2f0a7105dfcee6))


### Bug Fixes

* cancel requests to llm ([3a69421](https://github.com/olimorris/codecompanion.nvim/commit/3a694217ec868a8551fb6ec3203b98dad11888c9))
* **copilot:** make gpt-4o the default again ([28e8ddc](https://github.com/olimorris/codecompanion.nvim/commit/28e8ddc97e0044e5f04ddd261ac6fa06da9deca6))

## [9.1.0](https://github.com/olimorris/codecompanion.nvim/compare/v9.0.0...v9.1.0) (2024-11-04)


### Features

* :sparkles: support `render-markdown.nvim` plugin ([9b137be](https://github.com/olimorris/codecompanion.nvim/commit/9b137be7a9c275d865c9b10d5173e0a1f588aa47))

## [9.0.0](https://github.com/olimorris/codecompanion.nvim/compare/v8.13.0...v9.0.0) (2024-11-03)


### ⚠ BREAKING CHANGES

* move tools/slash/vars from helpers to strategies.chat
* **tools:** remove `code_runner` tool

### Features

* **adapters:** add claude-3-5-sonnet to Copilot ([1121015](https://github.com/olimorris/codecompanion.nvim/commit/1121015dbbce25afce88746861edc6fe930b7a9f))
* **tools:** :sparkles: Add `cmd_runner` tool ([ff7ad7f](https://github.com/olimorris/codecompanion.nvim/commit/ff7ad7f9e18fb9656e8de23bc540988336a7a93c))
* **tools:** :sparkles: tools can be stacked to form agents ([ee483b4](https://github.com/olimorris/codecompanion.nvim/commit/ee483b4e11d4c4e64a01ca6fb03c07edf6b2e20c))
* **tools:** add read option to `[@files](https://github.com/files)` tool ([cb63d59](https://github.com/olimorris/codecompanion.nvim/commit/cb63d59fa3ec4a31ebed1a1db00e1b25f8886686))


### Code Refactoring

* move tools/slash/vars from helpers to strategies.chat ([806ed9c](https://github.com/olimorris/codecompanion.nvim/commit/806ed9cf17889347e03752516462e149e03a3ddf))
* **tools:** remove `code_runner` tool ([362076b](https://github.com/olimorris/codecompanion.nvim/commit/362076b1e10748dd8999f73fbe993fb9a446733f))

## [8.13.0](https://github.com/olimorris/codecompanion.nvim/compare/v8.12.2...v8.13.0) (2024-10-29)


### Features

* **tools:** :sparkles: add `[@files](https://github.com/files)` tool ([22ebfb8](https://github.com/olimorris/codecompanion.nvim/commit/22ebfb8437e833aa6b25d032a0e1833e736d1d06))


### Bug Fixes

* **code_runner:** Ensure code is wrapped in CDATA ([f814137](https://github.com/olimorris/codecompanion.nvim/commit/f8141375d3b5c4e3b2d387e62d1754b72b62f517))
* **slash_commands:** show tracked and untracked files ([a7ad936](https://github.com/olimorris/codecompanion.nvim/commit/a7ad936a0b92177aa78be78d7661c3336e0ec7cf))

## [8.12.2](https://github.com/olimorris/codecompanion.nvim/compare/v8.12.1...v8.12.2) (2024-10-25)


### Bug Fixes

* **utils:** vim.api being replaced with api.api ([40114d7](https://github.com/olimorris/codecompanion.nvim/commit/40114d760af19f2ac21a1c248a34dc4c734acf9f))

## [8.12.1](https://github.com/olimorris/codecompanion.nvim/compare/v8.12.0...v8.12.1) (2024-10-25)


### Bug Fixes

* [#362](https://github.com/olimorris/codecompanion.nvim/issues/362) use actual line breaks for new lines ([9938867](https://github.com/olimorris/codecompanion.nvim/commit/993886723868b6fe0340d294f2f3d2a7acc6ae26))

## [8.12.0](https://github.com/olimorris/codecompanion.nvim/compare/v8.11.3...v8.12.0) (2024-10-25)


### Features

* **chat:** `yank_code` can now copy current code block and highlight the yank ([a84f826](https://github.com/olimorris/codecompanion.nvim/commit/a84f8267c1deca5b81e4974e2190a58fd71c3733))
* **chat:** can toggle system prompt on/off in the chat buffer ([c157329](https://github.com/olimorris/codecompanion.nvim/commit/c15732913d695a7def6b99f22210293bb7d58889))

## [8.11.3](https://github.com/olimorris/codecompanion.nvim/compare/v8.11.2...v8.11.3) (2024-10-24)


### Bug Fixes

* **copilot:** [#363](https://github.com/olimorris/codecompanion.nvim/issues/363) parameters overwritten when stream is true ([1c3449c](https://github.com/olimorris/codecompanion.nvim/commit/1c3449cf5b63b8b20bbe13842f047f2a220bf70a))

## [8.11.2](https://github.com/olimorris/codecompanion.nvim/compare/v8.11.1...v8.11.2) (2024-10-24)


### Bug Fixes

* **diff:** diff split window wrongly opened in chat window ([#359](https://github.com/olimorris/codecompanion.nvim/issues/359)) ([21801b8](https://github.com/olimorris/codecompanion.nvim/commit/21801b88c5abb7c4b4b3e715a897505366a986d4))

## [8.11.1](https://github.com/olimorris/codecompanion.nvim/compare/v8.11.0...v8.11.1) (2024-10-23)


### Bug Fixes

* **slash_command:** symbols parsing ([ffbcefb](https://github.com/olimorris/codecompanion.nvim/commit/ffbcefbccaf9d59a9c0a56ce55507297c0130658))

## [8.11.0](https://github.com/olimorris/codecompanion.nvim/compare/v8.10.1...v8.11.0) (2024-10-23)


### Features

* **slash_commands:** `symbols` can now be from a selected file ([5356829](https://github.com/olimorris/codecompanion.nvim/commit/53568298687773f1c0113b873fd8cdd2968208a7))
* **slash_commands:** add a `default` provider ([c938304](https://github.com/olimorris/codecompanion.nvim/commit/c938304fd494a0bb29c917de5963230334649a15))

## [8.10.1](https://github.com/olimorris/codecompanion.nvim/compare/v8.10.0...v8.10.1) (2024-10-23)


### Miscellaneous Chores

* release 8.10.1 ([1d3de26](https://github.com/olimorris/codecompanion.nvim/commit/1d3de2645b8f52c41caf502441a8299934a60dbe))

## [8.10.0](https://github.com/olimorris/codecompanion.nvim/compare/v8.9.0...v8.10.0) (2024-10-23)


### Features

* **anthropic:** update to latest anthropic models ([#353](https://github.com/olimorris/codecompanion.nvim/issues/353)) ([bdf4acc](https://github.com/olimorris/codecompanion.nvim/commit/bdf4acc623316e0f63f1a5d71b0c5bbceeb7263b))

## [8.9.0](https://github.com/olimorris/codecompanion.nvim/compare/v8.8.0...v8.9.0) (2024-10-23)


### Features

* **anthropic:** update to latest sonnet-3-5 model ([#346](https://github.com/olimorris/codecompanion.nvim/issues/346)) ([1d36e27](https://github.com/olimorris/codecompanion.nvim/commit/1d36e272a6e0d8ea7a4e940667335320762b6bc6))

## [8.8.0](https://github.com/olimorris/codecompanion.nvim/compare/v8.7.1...v8.8.0) (2024-10-22)


### Features

* **adapters:** :sparkles: add xAI ([516e320](https://github.com/olimorris/codecompanion.nvim/commit/516e3204f6e9fefb827bad985b7104a2fb82a291))

## [8.7.1](https://github.com/olimorris/codecompanion.nvim/compare/v8.7.0...v8.7.1) (2024-10-19)


### Bug Fixes

* allow register to be customised ([dc98cf2](https://github.com/olimorris/codecompanion.nvim/commit/dc98cf2f12129d5dd5300d9b7d323d8ecd8be974))

## [8.7.0](https://github.com/olimorris/codecompanion.nvim/compare/v8.6.0...v8.7.0) (2024-10-19)


### Features

* add undojoin for inline inserts ([#338](https://github.com/olimorris/codecompanion.nvim/issues/338)) ([8c56f8f](https://github.com/olimorris/codecompanion.nvim/commit/8c56f8fccadc3cc965d397d250f7b3e3f091266f))
* **chat:** :sparkles: yank the last code block ([f095b77](https://github.com/olimorris/codecompanion.nvim/commit/f095b77f43a6fd4ef014304dee636f78c02faba5))


### Bug Fixes

* [#336](https://github.com/olimorris/codecompanion.nvim/issues/336) use CDATA sections in editor tool XML schemas ([310cb7f](https://github.com/olimorris/codecompanion.nvim/commit/310cb7f30babe3e526dfb9bbac09e55a6f80b6c7))

## [8.6.0](https://github.com/olimorris/codecompanion.nvim/compare/v8.5.1...v8.6.0) (2024-10-17)


### Features

* :sparkles: improved workflows ([4bc19d1](https://github.com/olimorris/codecompanion.nvim/commit/4bc19d10c7b8026be5e943cccd98a1d5b086d5af))

## [8.5.1](https://github.com/olimorris/codecompanion.nvim/compare/v8.5.0...v8.5.1) (2024-10-17)


### Bug Fixes

* [#322](https://github.com/olimorris/codecompanion.nvim/issues/322) `CodeCompanionChat Add` command locking buffer ([e96b6e5](https://github.com/olimorris/codecompanion.nvim/commit/e96b6e5df28622e31092f90aa64daff92eef52e8))

## [8.5.0](https://github.com/olimorris/codecompanion.nvim/compare/v8.4.2...v8.5.0) (2024-10-17)


### Features

* **adapter:** add generic openai compatible adapter ([e5e9d39](https://github.com/olimorris/codecompanion.nvim/commit/e5e9d3920131f0b645c4501741f72fd8fcd8847e))

## [8.4.2](https://github.com/olimorris/codecompanion.nvim/compare/v8.4.1...v8.4.2) (2024-10-17)


### Bug Fixes

* always use the default diff in commit prompt ([e8ba37a](https://github.com/olimorris/codecompanion.nvim/commit/e8ba37a3d922f890464f66c0b21fab74f2263d31))

## [8.4.1](https://github.com/olimorris/codecompanion.nvim/compare/v8.4.0...v8.4.1) (2024-10-16)


### Bug Fixes

* custom tools and slash commands fail to load ([0f2e8de](https://github.com/olimorris/codecompanion.nvim/commit/0f2e8de176c5409b7d8587447f2b872cc15b04dd))

## [8.4.0](https://github.com/olimorris/codecompanion.nvim/compare/v8.3.1...v8.4.0) (2024-10-14)


### Features

* **adapters:** global var to allow override ([4535243](https://github.com/olimorris/codecompanion.nvim/commit/453524395fb6d5fd6b82e69fe68fd9256a6f5de3))

## [8.3.1](https://github.com/olimorris/codecompanion.nvim/compare/v8.3.0...v8.3.1) (2024-10-10)


### Bug Fixes

* **chat:** can prompt llm with slash commands and no user prompt ([167a786](https://github.com/olimorris/codecompanion.nvim/commit/167a786007abf7429d0f54c587dd4e49b7bc36e7))

## [8.3.0](https://github.com/olimorris/codecompanion.nvim/compare/v8.2.0...v8.3.0) (2024-10-09)


### Features

* slash command output is now hidden ([dba83b9](https://github.com/olimorris/codecompanion.nvim/commit/dba83b9c632d099a6f8acc3cc178f7b51156750f))

## [8.2.0](https://github.com/olimorris/codecompanion.nvim/compare/v8.1.0...v8.2.0) (2024-10-08)


### Features

* add `:CodeCompanionChat` sub-commands ([98761d6](https://github.com/olimorris/codecompanion.nvim/commit/98761d6d30a36d1ab8bd5995ffbc3620d761bbba))

## [8.1.0](https://github.com/olimorris/codecompanion.nvim/compare/v8.0.1...v8.1.0) (2024-10-08)


### Features

* `:CodeCompanion` can now show sub commands ([06d01fa](https://github.com/olimorris/codecompanion.nvim/commit/06d01fac5553561f5b450f292462abc501f9fc05))


### Bug Fixes

* [#299](https://github.com/olimorris/codecompanion.nvim/issues/299) switching adapters in chat buffer ([bb14105](https://github.com/olimorris/codecompanion.nvim/commit/bb14105df0485e40e646185148578a1458553bc0))

## [8.0.1](https://github.com/olimorris/codecompanion.nvim/compare/v8.0.0...v8.0.1) (2024-10-08)


### Bug Fixes

* type for prompt() [#305](https://github.com/olimorris/codecompanion.nvim/issues/305) ([8ca9dfb](https://github.com/olimorris/codecompanion.nvim/commit/8ca9dfb46e427a141bfdb7db1a341f342db3f613))

## [8.0.0](https://github.com/olimorris/codecompanion.nvim/compare/v7.0.0...v8.0.0) (2024-10-08)


### ⚠ BREAKING CHANGES

* use prompt library in chat buffer and better keymap support

### Features

* use prompt library in chat buffer and better keymap support ([b462c42](https://github.com/olimorris/codecompanion.nvim/commit/b462c42281541567f9197e289dbb2d5e6c7ad220))

## [7.0.0](https://github.com/olimorris/codecompanion.nvim/compare/v6.0.1...v7.0.0) (2024-10-06)


### ⚠ BREAKING CHANGES

* Plugin now only supports Neovim 0.10.0 and above

### Bug Fixes

* **anthropic:** token count calculation ([d518113](https://github.com/olimorris/codecompanion.nvim/commit/d51811389eaed3bb910a297b3fc6273e285d1585))
* **client:** [#293](https://github.com/olimorris/codecompanion.nvim/issues/293) use vim.schedule for `on_error` calls ([4c6dc82](https://github.com/olimorris/codecompanion.nvim/commit/4c6dc826bc96ee48bcc2986cc86d63b8e6aa3fab))


### Code Refactoring

* Plugin now only supports Neovim 0.10.0 and above ([38297a5](https://github.com/olimorris/codecompanion.nvim/commit/38297a5403446978cbb237f0eb4adcb98ed6143a))

## [6.0.1](https://github.com/olimorris/codecompanion.nvim/compare/v6.0.0...v6.0.1) (2024-10-03)


### Bug Fixes

* stop non_llm adapters from appearing in chat buffer ([12f5925](https://github.com/olimorris/codecompanion.nvim/commit/12f59259d63504269895723d7bd913fce1bf424d))

## [6.0.0](https://github.com/olimorris/codecompanion.nvim/compare/v5.3.0...v6.0.0) (2024-10-03)


### Features

* :sparkles: add /fetch slash command ([1389762](https://github.com/olimorris/codecompanion.nvim/commit/1389762b54d494fa6f98b099f49b682b7a56ec1d))


### Miscellaneous Chores

* release 6.0.0 ([5641236](https://github.com/olimorris/codecompanion.nvim/commit/56412362ab568420c7d6e40d09327416608c7de2))

## [5.3.0](https://github.com/olimorris/codecompanion.nvim/compare/v5.2.0...v5.3.0) (2024-10-03)


### Features

* **chat:** fire event when the model changes in the chat buffer ([2510965](https://github.com/olimorris/codecompanion.nvim/commit/251096585038085edfca6a94b4eb9be18808324b))

## [5.2.0](https://github.com/olimorris/codecompanion.nvim/compare/v5.1.0...v5.2.0) (2024-10-02)


### Features

* **adapters:** make it easier to work with non-streaming endpoints ([4ae9236](https://github.com/olimorris/codecompanion.nvim/commit/4ae9236012adf898b588bb8f5c5d882ab86e34b3))


### Bug Fixes

* **openai:** streaming should be the default ([0224ff9](https://github.com/olimorris/codecompanion.nvim/commit/0224ff91a29279b03a5a1dc7a3fc26a968628767))

## [5.1.0](https://github.com/olimorris/codecompanion.nvim/compare/v5.0.0...v5.1.0) (2024-10-02)


### Features

* **editor:** streamline system prompt ([1c12cab](https://github.com/olimorris/codecompanion.nvim/commit/1c12cabbc8698bfea8b4e9ed5846412521b437db))


### Bug Fixes

* **openai:** check for choices ([9eb573e](https://github.com/olimorris/codecompanion.nvim/commit/9eb573e80b4c2558ce2f430fa96e82b4eb99c8b5))
* **slash:** use loadfile for user's own commands ([6c349c8](https://github.com/olimorris/codecompanion.nvim/commit/6c349c8365d1c7aa59f4bda3edcdb9f35a51d080))

## [5.0.0](https://github.com/olimorris/codecompanion.nvim/compare/v4.1.0...v5.0.0) (2024-09-30)


### ⚠ BREAKING CHANGES

* all adapter handlers now have self as first param

### Features

* all adapter handlers now have self as first param ([ec5c353](https://github.com/olimorris/codecompanion.nvim/commit/ec5c353e8c6f3d5fa2f4a8325b02e062d7c18352))
* **prompts:** only use staged files for commit messages prompt ([77a4a94](https://github.com/olimorris/codecompanion.nvim/commit/77a4a94304122f3943415eacc5a7e359ea40511d))

## [4.1.0](https://github.com/olimorris/codecompanion.nvim/compare/v4.0.0...v4.1.0) (2024-09-30)


### Features

* add mini pick as provider for action_palette ([#272](https://github.com/olimorris/codecompanion.nvim/issues/272)) ([7d02085](https://github.com/olimorris/codecompanion.nvim/commit/7d0208511a97dc7e015b145afd2246175aba3f24))
* add picker field to prompt resolution ([#275](https://github.com/olimorris/codecompanion.nvim/issues/275)) ([1808fd9](https://github.com/olimorris/codecompanion.nvim/commit/1808fd9bbbd4cbc1497eb09dc772e29d4d6d19ba))


### Bug Fixes

* prompt library conditionals ([#277](https://github.com/olimorris/codecompanion.nvim/issues/277)) ([a0518b9](https://github.com/olimorris/codecompanion.nvim/commit/a0518b9828a4542bd8a51a572f101fa11a0dcbae))
* telescope extension can take opts ([423447f](https://github.com/olimorris/codecompanion.nvim/commit/423447f225f6cad02696c61b8875d8ee7485c435))
* telescope extension for the action palette ([#267](https://github.com/olimorris/codecompanion.nvim/issues/267)) ([bf3722b](https://github.com/olimorris/codecompanion.nvim/commit/bf3722b4132036b28308ba220b38e32989e1fee1))
* **tools:** remove print statement for RAG tool ([0ab3a6a](https://github.com/olimorris/codecompanion.nvim/commit/0ab3a6a42d89513c43b98485749c9e68fa5b18f0))

## [4.0.0](https://github.com/olimorris/codecompanion.nvim/compare/v3.5.1...v4.0.0) (2024-09-26)


### ⚠ BREAKING CHANGES

* `CodeCompanionToggle` becomes `CodeCompanionChat Toggle`
* rename variable #editor to #viewport
* move `use_default_prompt_library` to `display.action_palette.opts` and rename to `show_default_prompt_library`
* move `use_default_actions` to `display.action_palette.opts` and rename to `show_default_actions`
* make copilot the default adapter
* remove `pre_defined_prompts` config option

### Features

* :sparkles: can now do `:CodeCompanionChat &lt;prompt&gt;` ([a13d030](https://github.com/olimorris/codecompanion.nvim/commit/a13d030679554af315f9f03e2deed88f37e99bdb))
* [#249](https://github.com/olimorris/codecompanion.nvim/issues/249) option to turn off prompt library keymaps ([6d585b5](https://github.com/olimorris/codecompanion.nvim/commit/6d585b5c136a089eaf9b5afe68393438c0d8e073))
* `CodeCompanionToggle` becomes `CodeCompanionChat Toggle` ([f694b22](https://github.com/olimorris/codecompanion.nvim/commit/f694b22bf5b9cb609ac149e8e0685b76089a9e08))
* **actions:** add telescope as action palette provider ([1721bc1](https://github.com/olimorris/codecompanion.nvim/commit/1721bc1154d4114a0cde99501c321abb93ea512d))
* **tools:** :sparkles: much improved `[@editor](https://github.com/editor)` tool ([07fd7c4](https://github.com/olimorris/codecompanion.nvim/commit/07fd7c439fd7da4a22d45d64fa65e781a88da2ca))


### Code Refactoring

* make copilot the default adapter ([a2f11ad](https://github.com/olimorris/codecompanion.nvim/commit/a2f11ad64625b705d8cf72e04e2c98885351c713))
* move `use_default_actions` to `display.action_palette.opts` and rename to `show_default_actions` ([1624702](https://github.com/olimorris/codecompanion.nvim/commit/16247029282e8e57fa696bdad1ed11ab89dcf5b3))
* move `use_default_prompt_library` to `display.action_palette.opts` and rename to `show_default_prompt_library ([247923b](https://github.com/olimorris/codecompanion.nvim/commit/247923be33c765afc0dce4327b82ab1dceb785f8))
* remove `pre_defined_prompts` config option ([8052344](https://github.com/olimorris/codecompanion.nvim/commit/80523445ef1ca0cbef113d34b6b4301676dda63c))
* rename variable #editor to #viewport ([1bbc762](https://github.com/olimorris/codecompanion.nvim/commit/1bbc76202b7eb09609485d82e882ab04afabc228))

## [3.5.1](https://github.com/olimorris/codecompanion.nvim/compare/v3.5.0...v3.5.1) (2024-09-25)


### Bug Fixes

* [#255](https://github.com/olimorris/codecompanion.nvim/issues/255) remove system prompt ([56603af](https://github.com/olimorris/codecompanion.nvim/commit/56603af3fdb86d1f38ad93979aedccf5da492bb9))

## [3.5.0](https://github.com/olimorris/codecompanion.nvim/compare/v3.4.0...v3.5.0) (2024-09-23)


### Features

* **tools:** improved schema and editor tool can have multiple actions ([cfd1d07](https://github.com/olimorris/codecompanion.nvim/commit/cfd1d071c159cf7d2d4a3eff86aa2dd4c865c4c5))

## [3.4.0](https://github.com/olimorris/codecompanion.nvim/compare/v3.3.2...v3.4.0) (2024-09-23)


### Features

* add mini_pick to /help command ([#245](https://github.com/olimorris/codecompanion.nvim/issues/245)) ([66c2d8a](https://github.com/olimorris/codecompanion.nvim/commit/66c2d8aa93579a7dee2a9dd023442822149b9f62))


### Bug Fixes

* mini_diff not resetting ([6329698](https://github.com/olimorris/codecompanion.nvim/commit/6329698f9f98f59da079e179c8b81f43d8692cba))

## [3.3.2](https://github.com/olimorris/codecompanion.nvim/compare/v3.3.1...v3.3.2) (2024-09-19)


### Bug Fixes

* **slash_cmd:** include buffer number ([9ef7840](https://github.com/olimorris/codecompanion.nvim/commit/9ef78403f19d2ed972be3325174542597fd569bb))

## [3.3.1](https://github.com/olimorris/codecompanion.nvim/compare/v3.3.0...v3.3.1) (2024-09-19)


### Bug Fixes

* add buffer number to terminal slash command ([635a922](https://github.com/olimorris/codecompanion.nvim/commit/635a922b5f364b022c1c3f06c5d159fc8146ae5c))
* **chat:** don't index an empty table ([#241](https://github.com/olimorris/codecompanion.nvim/issues/241)) ([0fa1748](https://github.com/olimorris/codecompanion.nvim/commit/0fa174846246b07bde80107c876c65fc626b7936))
* **chat:** LLM returning the whole buffer ([37c51a9](https://github.com/olimorris/codecompanion.nvim/commit/37c51a94212158581ff7f96bcdff51b7789cd728))
* **tools:** editor handles buffers out of context ([7997faa](https://github.com/olimorris/codecompanion.nvim/commit/7997faabf40d13cc87b728c8320109889bf1a1c4))
* **tools:** on error do not send output ([93c0579](https://github.com/olimorris/codecompanion.nvim/commit/93c0579ef8b8e1714eec54b238631654b9721db8))

## [3.3.0](https://github.com/olimorris/codecompanion.nvim/compare/v3.2.2...v3.3.0) (2024-09-18)


### Features

* :sparkles: `/terminal` slash command ([43a9f0c](https://github.com/olimorris/codecompanion.nvim/commit/43a9f0c4b7aa9139528bf778d120855dd74da51f))

## [3.2.2](https://github.com/olimorris/codecompanion.nvim/compare/v3.2.1...v3.2.2) (2024-09-18)


### Bug Fixes

* **ollama:** [#223](https://github.com/olimorris/codecompanion.nvim/issues/223) ollama can be slow when `num_ctx` is large ([4b60b0e](https://github.com/olimorris/codecompanion.nvim/commit/4b60b0ef26d180c214b075e788470fd1c6cac729))

## [3.2.1](https://github.com/olimorris/codecompanion.nvim/compare/v3.2.0...v3.2.1) (2024-09-17)


### Bug Fixes

* **chat:** entering insert mode ([c7bbfac](https://github.com/olimorris/codecompanion.nvim/commit/c7bbfac0e914b2d13067e5a2f89f2190bbcd44b7))

## [3.2.0](https://github.com/olimorris/codecompanion.nvim/compare/v3.1.0...v3.2.0) (2024-09-17)


### Features

* **chat:** option to start in insert mode ([12bb02d](https://github.com/olimorris/codecompanion.nvim/commit/12bb02d61a11dbe6209055bf31c2cf88cf622501))

## [3.1.0](https://github.com/olimorris/codecompanion.nvim/compare/v3.0.2...v3.1.0) (2024-09-17)


### Features

* `vim.ui.input` prompt is now customizable ([#231](https://github.com/olimorris/codecompanion.nvim/issues/231)) ([f761716](https://github.com/olimorris/codecompanion.nvim/commit/f761716be16eeac12ad8b7a144fa8bca23ae2f21))
* add back mini.diff ([#230](https://github.com/olimorris/codecompanion.nvim/issues/230)) ([574c0ac](https://github.com/olimorris/codecompanion.nvim/commit/574c0ac5cb0cdd8b999a2bbd7c81ecf63d2b2f76))


### Bug Fixes

* diff provider in editor tool ([#232](https://github.com/olimorris/codecompanion.nvim/issues/232)) ([3422b1c](https://github.com/olimorris/codecompanion.nvim/commit/3422b1ccd8bed844c25965de8428c05581bdfc2f))
* move `opts.diff` to `display.diff` ([b5f3378](https://github.com/olimorris/codecompanion.nvim/commit/b5f337861a47e7ce3af9ba96b2735e2c3c45d5af))

## [3.0.2](https://github.com/olimorris/codecompanion.nvim/compare/v3.0.1...v3.0.2) (2024-09-16)


### Bug Fixes

* **tools:** auto-submit errors if enabled ([d409ec4](https://github.com/olimorris/codecompanion.nvim/commit/d409ec48f5d923a9d5fd82ea2e0de8d7865755a4))

## [3.0.1](https://github.com/olimorris/codecompanion.nvim/compare/v3.0.0...v3.0.1) (2024-09-16)


### Bug Fixes

* duplicate tags in help ([#226](https://github.com/olimorris/codecompanion.nvim/issues/226)) ([34049a8](https://github.com/olimorris/codecompanion.nvim/commit/34049a8f248ca91e86ce9e8ae6aef498439e8c88))

## [3.0.0](https://github.com/olimorris/codecompanion.nvim/compare/v2.7.0...v3.0.0) (2024-09-16)


### ⚠ BREAKING CHANGES

* `default_prompts` removed

### Features

* :sparkles: add /help slash-command ([#212](https://github.com/olimorris/codecompanion.nvim/issues/212)) ([51cd95c](https://github.com/olimorris/codecompanion.nvim/commit/51cd95c9582cb4ba41f2050d96f51cb5e9bdeb17))
* **tools:** :sparkles: improved tools ([c2a319f](https://github.com/olimorris/codecompanion.nvim/commit/c2a319f5a3885fda1030af0485055f6a3dc00e26))


### Bug Fixes

* [#224](https://github.com/olimorris/codecompanion.nvim/issues/224) cmp and settings error in chat buffer ([39448da](https://github.com/olimorris/codecompanion.nvim/commit/39448dac0afaacdab6ae48ea408e376c71b38a39))
* **copilot:** token retrieval logic ([6679b60](https://github.com/olimorris/codecompanion.nvim/commit/6679b60d463b2fb3d1c030872f4856c0a6e167ba))


### Code Refactoring

* `default_prompts` removed ([63e7009](https://github.com/olimorris/codecompanion.nvim/commit/63e70098da4e11b9f50aaea4ba46ada8c2101e61))

## [2.7.0](https://github.com/olimorris/codecompanion.nvim/compare/v2.6.6...v2.7.0) (2024-09-13)


### Features

* add mini.diff as option for inline diffs ([#210](https://github.com/olimorris/codecompanion.nvim/issues/210)) ([a33d4ae](https://github.com/olimorris/codecompanion.nvim/commit/a33d4aefbf3d4cc21c23dcbcfc27b61fb6b26245))

## [2.6.6](https://github.com/olimorris/codecompanion.nvim/compare/v2.6.5...v2.6.6) (2024-09-11)


### Bug Fixes

* **chat:** [#190](https://github.com/olimorris/codecompanion.nvim/issues/190) folding slash commands in nightly ([8276e79](https://github.com/olimorris/codecompanion.nvim/commit/8276e797fe56c7a92bb599db051bb2f85f6cd17d))

## [2.6.5](https://github.com/olimorris/codecompanion.nvim/compare/v2.6.4...v2.6.5) (2024-09-11)


### Bug Fixes

* **cmp:** chat buffer is no longer listed ([1e1fd7b](https://github.com/olimorris/codecompanion.nvim/commit/1e1fd7b1559c02cffddb842b511b80be30cf6e3f))
* **cmp:** slash commands works across all chat buffers ([5ce2af1](https://github.com/olimorris/codecompanion.nvim/commit/5ce2af1cd4a5da1bf91d6ead400f281845c2b986))

## [2.6.4](https://github.com/olimorris/codecompanion.nvim/compare/v2.6.3...v2.6.4) (2024-09-11)


### Bug Fixes

* **chat:** syntax highlighting ([1ee1b86](https://github.com/olimorris/codecompanion.nvim/commit/1ee1b86d6f8da8e49c46a4935cabfc55f314cd6a))

## [2.6.3](https://github.com/olimorris/codecompanion.nvim/compare/v2.6.2...v2.6.3) (2024-09-11)


### Bug Fixes

* [#197](https://github.com/olimorris/codecompanion.nvim/issues/197) autocomplete for slash-command ([#200](https://github.com/olimorris/codecompanion.nvim/issues/200)) ([491f5f2](https://github.com/olimorris/codecompanion.nvim/commit/491f5f2a47c8d555f6d31b1e6e5030172a336d58))

## [2.6.2](https://github.com/olimorris/codecompanion.nvim/compare/v2.6.1...v2.6.2) (2024-09-11)


### Bug Fixes

* **adapters:** extend adapters ([#202](https://github.com/olimorris/codecompanion.nvim/issues/202)) ([e3cf855](https://github.com/olimorris/codecompanion.nvim/commit/e3cf8558337a1b83665aee2287490d1ba8b7134c))

## [2.6.1](https://github.com/olimorris/codecompanion.nvim/compare/v2.6.0...v2.6.1) (2024-09-10)


### Bug Fixes

* **chat:** folds ([d83d497](https://github.com/olimorris/codecompanion.nvim/commit/d83d497500f38c31b564a6b1b723c34f1a761ea1))

## [2.6.0](https://github.com/olimorris/codecompanion.nvim/compare/v2.5.5...v2.6.0) (2024-09-10)


### Features

* :sparkles: customisable system prompts ([96e5405](https://github.com/olimorris/codecompanion.nvim/commit/96e54058cfee38f2618c5adc116b8edaad70b04c))

## [2.5.5](https://github.com/olimorris/codecompanion.nvim/compare/v2.5.4...v2.5.5) (2024-09-10)


### Bug Fixes

* [#194](https://github.com/olimorris/codecompanion.nvim/issues/194) actually fix it this time ([bf6c1db](https://github.com/olimorris/codecompanion.nvim/commit/bf6c1db575f5f88016f0c3ce48952965b1b68800))

## [2.5.4](https://github.com/olimorris/codecompanion.nvim/compare/v2.5.3...v2.5.4) (2024-09-10)


### Bug Fixes

* [#194](https://github.com/olimorris/codecompanion.nvim/issues/194) update for deprecations ([d0fe55f](https://github.com/olimorris/codecompanion.nvim/commit/d0fe55fcb532fa5ae104b4b0413e497199d6d98f))
* **config:** `contains_code` in slash commands ([cd5afb9](https://github.com/olimorris/codecompanion.nvim/commit/cd5afb956a7b2c5e535ab01131d6527f222d90b9))

## [2.5.3](https://github.com/olimorris/codecompanion.nvim/compare/v2.5.2...v2.5.3) (2024-09-10)


### Bug Fixes

* **copilot:** refreshes token if it expires ([082986d](https://github.com/olimorris/codecompanion.nvim/commit/082986d53e5acbbb6c9c51d3d98e3448af65189f))

## [2.5.2](https://github.com/olimorris/codecompanion.nvim/compare/v2.5.1...v2.5.2) (2024-09-10)


### Bug Fixes

* **copilot:** [#189](https://github.com/olimorris/codecompanion.nvim/issues/189) "bad request: unknown integration" ([372607d](https://github.com/olimorris/codecompanion.nvim/commit/372607d1109cc93c4d499330ed3ae98f93202c48))

## [2.5.1](https://github.com/olimorris/codecompanion.nvim/compare/v2.5.0...v2.5.1) (2024-09-10)


### Bug Fixes

* properly closing Mini.pick after choosing file/buffer ([#188](https://github.com/olimorris/codecompanion.nvim/issues/188)) ([6ae1de8](https://github.com/olimorris/codecompanion.nvim/commit/6ae1de8e71bd71d9ad96cf9c9ff9dfd78a5aaa1f))

## [2.5.0](https://github.com/olimorris/codecompanion.nvim/compare/v2.4.1...v2.5.0) (2024-09-09)


### Features

* **chat:** :sparkles: add `symbols` and `now` slash commands ([9c41484](https://github.com/olimorris/codecompanion.nvim/commit/9c41484d4fd1b1b74b34be7d4888980a5b495213))

## [2.4.1](https://github.com/olimorris/codecompanion.nvim/compare/v2.4.0...v2.4.1) (2024-09-09)


### Bug Fixes

* **inline:** send_code check ([b2ba430](https://github.com/olimorris/codecompanion.nvim/commit/b2ba43050fa2280016e0f23e0287c9b89eef7f1b))

## [2.4.0](https://github.com/olimorris/codecompanion.nvim/compare/v2.3.1...v2.4.0) (2024-09-09)


### Features

* add mini_pick option for buffer slash command ([5bb3e16](https://github.com/olimorris/codecompanion.nvim/commit/5bb3e163b58cfce528a36b2c31d80b5e85a121df))


### Bug Fixes

* default configs ([6262ad5](https://github.com/olimorris/codecompanion.nvim/commit/6262ad578a17587ffb41f017994436ea50a6ab07))
* mini_pick file slash command ([345c094](https://github.com/olimorris/codecompanion.nvim/commit/345c094983f3e1222a48f90913c9e0f87320647f))

## [2.3.1](https://github.com/olimorris/codecompanion.nvim/compare/v2.3.0...v2.3.1) (2024-09-09)


### Bug Fixes

* **anthropic:** respect breakpoints used ([acfbaed](https://github.com/olimorris/codecompanion.nvim/commit/acfbaed735a82a95ebbfb96b2d25b358295d0d02))

## [2.3.0](https://github.com/olimorris/codecompanion.nvim/compare/v2.2.5...v2.3.0) (2024-09-08)


### Features

* add `fzf_lua` for slash commands ([895fbf9](https://github.com/olimorris/codecompanion.nvim/commit/895fbf9587db87c9722eb9d4cc3fdd512bfbd6b2))

## [2.2.5](https://github.com/olimorris/codecompanion.nvim/compare/v2.2.4...v2.2.5) (2024-09-07)


### Bug Fixes

* **copilot:** [#176](https://github.com/olimorris/codecompanion.nvim/issues/176) InsertLeave error with nil choices ([05bf031](https://github.com/olimorris/codecompanion.nvim/commit/05bf0311ef1e49ccb705ff5ce6b80ea591241932))

## [2.2.4](https://github.com/olimorris/codecompanion.nvim/compare/v2.2.3...v2.2.4) (2024-09-07)


### Bug Fixes

* **chat:** folding of code ([39ab8d8](https://github.com/olimorris/codecompanion.nvim/commit/39ab8d8da8d83403ed123455882e4c87681a11dd))

## [2.2.3](https://github.com/olimorris/codecompanion.nvim/compare/v2.2.2...v2.2.3) (2024-09-07)


### Bug Fixes

* **chat:** default prompts not being passed to llm ([bb081c6](https://github.com/olimorris/codecompanion.nvim/commit/bb081c6d8929b5c84f2ed7472e25432812377050))
* **cmp:** models completion ([0d90e71](https://github.com/olimorris/codecompanion.nvim/commit/0d90e717a0b8a05fe7c04ddfadcb0d0f3c509cd8))

## [2.2.2](https://github.com/olimorris/codecompanion.nvim/compare/v2.2.1...v2.2.2) (2024-09-06)


### Bug Fixes

* **chat:** additional space at top of buffer ([7c44bd1](https://github.com/olimorris/codecompanion.nvim/commit/7c44bd1c6362e0a2d78e6a99633d256faece0c0a))

## [2.2.1](https://github.com/olimorris/codecompanion.nvim/compare/v2.2.0...v2.2.1) (2024-09-06)


### Bug Fixes

* **chat:** double sending of messages when outside the chat buffer ([bfb45ff](https://github.com/olimorris/codecompanion.nvim/commit/bfb45ffbe9ee09e1ee9528821c81273f2923bc42))

## [2.2.0](https://github.com/olimorris/codecompanion.nvim/compare/v2.1.1...v2.2.0) (2024-09-06)


### Features

* **chat:** [#163](https://github.com/olimorris/codecompanion.nvim/issues/163) customise token output in chat buffer ([b68a283](https://github.com/olimorris/codecompanion.nvim/commit/b68a283528d54ec651cf8ae0d0f048d155f14ef8))

## [2.1.1](https://github.com/olimorris/codecompanion.nvim/compare/v2.1.0...v2.1.1) (2024-09-06)


### Bug Fixes

* mini.pick with with relative path ([#170](https://github.com/olimorris/codecompanion.nvim/issues/170)) ([ab5844c](https://github.com/olimorris/codecompanion.nvim/commit/ab5844ce1597a351ec5f94a59fef368f042a4f92))

## [2.1.0](https://github.com/olimorris/codecompanion.nvim/compare/v2.0.1...v2.1.0) (2024-09-06)


### Features

* add mini.pick as provider for file slash cmd ([#167](https://github.com/olimorris/codecompanion.nvim/issues/167)) ([835b4b7](https://github.com/olimorris/codecompanion.nvim/commit/835b4b7e657d3c4513c7c3c1f588ef43c1a5eb9f))

## [2.0.1](https://github.com/olimorris/codecompanion.nvim/compare/v2.0.0...v2.0.1) (2024-09-05)


### Bug Fixes

* **chat:** file slash command ([c0306ac](https://github.com/olimorris/codecompanion.nvim/commit/c0306acbe7655f7d3cbdf4f83ef20b202711b25a))

## [2.0.0](https://github.com/olimorris/codecompanion.nvim/compare/v1.8.2...v2.0.0) (2024-09-04)


### ⚠ BREAKING CHANGES

* **workflow:** move `start` and `auto_submit` into `opts`
* **config:** `contains_code` now moved into `opts`
* **config:** rename separator
* **chat:** remove `buffers` as a variable
* **chat:** remove deprecations

### Features

* **chat:** :sparkles: slash commands ([91adfac](https://github.com/olimorris/codecompanion.nvim/commit/91adfacdbe61f3ddcfcec688d9029e7b63f79616))


### Bug Fixes

* **chat:** lsp variable ([b558e5b](https://github.com/olimorris/codecompanion.nvim/commit/b558e5b8e71fd82b010a70890a43732f053e4a11))
* prompts check ([c5ab93e](https://github.com/olimorris/codecompanion.nvim/commit/c5ab93e005d410195c408f41d1984946904ce124))


### Code Refactoring

* **chat:** remove `buffers` as a variable ([c4e586c](https://github.com/olimorris/codecompanion.nvim/commit/c4e586c82b447e683147a673c1c8c5115e3d2fad))
* **chat:** remove deprecations ([c32dc6d](https://github.com/olimorris/codecompanion.nvim/commit/c32dc6da4fa879368f218ee95898aed24d87452a))
* **config:** `contains_code` now moved into `opts` ([e1268a0](https://github.com/olimorris/codecompanion.nvim/commit/e1268a0e29acff2270a79728285fb174cde6a107))
* **config:** rename separator ([9254a96](https://github.com/olimorris/codecompanion.nvim/commit/9254a96ca096b2a85c11f14fa3a30f887037ace8))
* **workflow:** move `start` and `auto_submit` into `opts` ([f565e0c](https://github.com/olimorris/codecompanion.nvim/commit/f565e0c6a0b4722103b25869cba88652cc2a64a1))

## [1.8.2](https://github.com/olimorris/codecompanion.nvim/compare/v1.8.1...v1.8.2) (2024-09-02)


### Bug Fixes

* **copilot:** [#160](https://github.com/olimorris/codecompanion.nvim/issues/160) get token correctly ([b0ab19a](https://github.com/olimorris/codecompanion.nvim/commit/b0ab19ad70bff8022bd0138c263cae5c77626fea))

## [1.8.1](https://github.com/olimorris/codecompanion.nvim/compare/v1.8.0...v1.8.1) (2024-08-31)


### Bug Fixes

* **keymaps:** update next and previous header keybindings ([#155](https://github.com/olimorris/codecompanion.nvim/issues/155)) ([ba49ec6](https://github.com/olimorris/codecompanion.nvim/commit/ba49ec66d56bb748ea84bb3ce152f63d7671307c))

## [1.8.0](https://github.com/olimorris/codecompanion.nvim/compare/v1.7.2...v1.8.0) (2024-08-30)


### Features

* **inline:** :sparkles: improved diff mode ([bc400fa](https://github.com/olimorris/codecompanion.nvim/commit/bc400fa755b808fe1c60ca715a1b2a5bdc426e7b))

## [1.7.2](https://github.com/olimorris/codecompanion.nvim/compare/v1.7.1...v1.7.2) (2024-08-29)


### Bug Fixes

* **ollama:** fetching models from remote repo ([1863500](https://github.com/olimorris/codecompanion.nvim/commit/18635001d55e1241c5641e8b79e7fca142c0dbf6))

## [1.7.1](https://github.com/olimorris/codecompanion.nvim/compare/v1.7.0...v1.7.1) (2024-08-29)


### Bug Fixes

* **copilot:** rewrite adapter ([d4ca465](https://github.com/olimorris/codecompanion.nvim/commit/d4ca465883d9a26299f1ef4186eab2e21ba85861))

## [1.7.0](https://github.com/olimorris/codecompanion.nvim/compare/v1.6.0...v1.7.0) (2024-08-29)


### Features

* **client:** [#141](https://github.com/olimorris/codecompanion.nvim/issues/141) add proxy support ([b3ec426](https://github.com/olimorris/codecompanion.nvim/commit/b3ec4263043ea876b1e6aace1c1b64726f21f9bd))


### Bug Fixes

* **chat:** add system message after clearing chat ([8c1119b](https://github.com/olimorris/codecompanion.nvim/commit/8c1119b3eae07d0dbc4efad82f9d6ab4263b06c9))

## [1.6.0](https://github.com/olimorris/codecompanion.nvim/compare/v1.5.0...v1.6.0) (2024-08-28)


### Features

* **chat:** :sparkles: keymap to regenerate the last response ([c6b583d](https://github.com/olimorris/codecompanion.nvim/commit/c6b583dfa0a84bbdf0bc9a4ccbc6f2dc9399c0b2))

## [1.5.0](https://github.com/olimorris/codecompanion.nvim/compare/v1.4.1...v1.5.0) (2024-08-28)


### Features

* **inline:** transformations can replace selections ([b8ca077](https://github.com/olimorris/codecompanion.nvim/commit/b8ca0776f51fde418a314d34d35116f626966909))


### Bug Fixes

* **inline:** replace method now works ([ffceaf7](https://github.com/olimorris/codecompanion.nvim/commit/ffceaf77ee3466fea0187e9c2737477ea6ed1305))

## [1.4.1](https://github.com/olimorris/codecompanion.nvim/compare/v1.4.0...v1.4.1) (2024-08-28)


### Bug Fixes

* **keymaps:** changing adapter to copilot in chat buffer ([1e46028](https://github.com/olimorris/codecompanion.nvim/commit/1e460280b2219b06f34cd438776e3f3ef8c00f9e))
* **ollama:** getting models from remote endpoint ([9f7af1e](https://github.com/olimorris/codecompanion.nvim/commit/9f7af1ee22804cb3ccd5ad1f6ec2169a5ef52b0f))

## [1.4.0](https://github.com/olimorris/codecompanion.nvim/compare/v1.3.2...v1.4.0) (2024-08-28)


### Features

* **copilot:** :sparkles: add copilot ([18b0d73](https://github.com/olimorris/codecompanion.nvim/commit/18b0d73ec1382c189fc509420d48117af2fdbcfe))

## [1.3.2](https://github.com/olimorris/codecompanion.nvim/compare/v1.3.1...v1.3.2) (2024-08-28)


### Bug Fixes

* **adapters:** check type of env vars ([e290322](https://github.com/olimorris/codecompanion.nvim/commit/e29032247c9b9fef38df10a88e26af3b987ae050))
* **adapters:** setup method should return boolean value ([fe8512a](https://github.com/olimorris/codecompanion.nvim/commit/fe8512ab62425c0a1c5c796d80be1de808190f4b))

## [1.3.1](https://github.com/olimorris/codecompanion.nvim/compare/v1.3.0...v1.3.1) (2024-08-28)


### Bug Fixes

* Prevent nil error ([#131](https://github.com/olimorris/codecompanion.nvim/issues/131)) ([2f28efd](https://github.com/olimorris/codecompanion.nvim/commit/2f28efdbdd7083a6d1e3973b3f35ad0e464b3d92))

## [1.3.0](https://github.com/olimorris/codecompanion.nvim/compare/v1.2.0...v1.3.0) (2024-08-27)


### Features

* **inline:** :sparkles: inline transformations ([c76b545](https://github.com/olimorris/codecompanion.nvim/commit/c76b545b41c45db8322ea84b13272618d37bf0b5))

## [1.2.0](https://github.com/olimorris/codecompanion.nvim/compare/v1.1.2...v1.2.0) (2024-08-26)


### Features

* **anthropic:** :sparkles: [#111](https://github.com/olimorris/codecompanion.nvim/issues/111) [#99](https://github.com/olimorris/codecompanion.nvim/issues/99) add prompt caching ([175c901](https://github.com/olimorris/codecompanion.nvim/commit/175c901b036bdcf5098503a83f32149e44fe4cf4))

## [1.1.2](https://github.com/olimorris/codecompanion.nvim/compare/v1.1.1...v1.1.2) (2024-08-26)


### Bug Fixes

* **anthropic:** [#123](https://github.com/olimorris/codecompanion.nvim/issues/123) consecutive roles error ([c345c97](https://github.com/olimorris/codecompanion.nvim/commit/c345c977dcf8e23365efa875ad568d36739d12a8))
* **chat:** clearing of chat buffer ([8588aed](https://github.com/olimorris/codecompanion.nvim/commit/8588aed30c0f38a2b4e359137f66b3728eb21009))

## [1.1.1](https://github.com/olimorris/codecompanion.nvim/compare/v1.1.0...v1.1.1) (2024-08-25)


### Bug Fixes

* **chat:** ensure correct role is added to the buffer ([a01731f](https://github.com/olimorris/codecompanion.nvim/commit/a01731f739085fc1d6d31fee1dd8409b6f88bcec))
* **chat:** tool prompts getting continuously added ([ad283dd](https://github.com/olimorris/codecompanion.nvim/commit/ad283dd23d63604da3796324f39d9b5240730d88))
* **config:** missspelling in system prompt ([98e0ec2](https://github.com/olimorris/codecompanion.nvim/commit/98e0ec2f1a8653f4a883cf523a14f63c49ad7464))

## [1.1.0](https://github.com/olimorris/codecompanion.nvim/compare/v1.0.4...v1.1.0) (2024-08-25)


### Features

* **chat:** [#116](https://github.com/olimorris/codecompanion.nvim/issues/116) add event for setting an adapter ([8561dc7](https://github.com/olimorris/codecompanion.nvim/commit/8561dc7ebe6f02abd4997d1d3973d0c3cea1424f))

## [1.0.4](https://github.com/olimorris/codecompanion.nvim/compare/v1.0.3...v1.0.4) (2024-08-25)


### Bug Fixes

* [#117](https://github.com/olimorris/codecompanion.nvim/issues/117) not resolving adapter role ([4b17557](https://github.com/olimorris/codecompanion.nvim/commit/4b1755751468675302869eaa57bdc9cd315d5fab))
* **chat:** ability to debug messages in chat buffer ([a841e9e](https://github.com/olimorris/codecompanion.nvim/commit/a841e9eff3e92579a1785b8418d951d746179342))
* **chat:** clear chat messages ([cd6cf55](https://github.com/olimorris/codecompanion.nvim/commit/cd6cf5510a6868c9273ec6f33f77cdfe6fd689f9))
* **chat:** deepcopy messages before changing roles ([e811e6a](https://github.com/olimorris/codecompanion.nvim/commit/e811e6a46b89bd4c345abc6a75ffb3d5af5b985f))

## [1.0.3](https://github.com/olimorris/codecompanion.nvim/compare/v1.0.2...v1.0.3) (2024-08-22)


### Bug Fixes

* avoid setting keybindings if use_default_prompt=false ([#108](https://github.com/olimorris/codecompanion.nvim/issues/108)) ([be2465e](https://github.com/olimorris/codecompanion.nvim/commit/be2465e3b0a0a1d03b766de93c5c3ff294cc93f0))
* fix [#108](https://github.com/olimorris/codecompanion.nvim/issues/108) avoid setting keybindings if use_default_prompt=false ([8c1f0c0](https://github.com/olimorris/codecompanion.nvim/commit/8c1f0c0f0503962fd849466beb57e34cbafc1ca7))

## [1.0.2](https://github.com/olimorris/codecompanion.nvim/compare/v1.0.1...v1.0.2) (2024-08-22)


### Bug Fixes

* [#105](https://github.com/olimorris/codecompanion.nvim/issues/105) disabling default prompts still creates slash cmds ([d92baf0](https://github.com/olimorris/codecompanion.nvim/commit/d92baf01a317b4b7bc6658ac1afad91a82033f13))
* setup slash cmds even if `use_default_prompts` is false ([ea727c2](https://github.com/olimorris/codecompanion.nvim/commit/ea727c2dfa689c479e305e33620826f6389ea4e5))

## [1.0.1](https://github.com/olimorris/codecompanion.nvim/compare/v1.0.0...v1.0.1) (2024-08-21)


### Bug Fixes

* **chat:** changing adapters in chat buffer to Ollama ([5cc04a1](https://github.com/olimorris/codecompanion.nvim/commit/5cc04a1825db71a16d11f90d3b2150788926ad84))
