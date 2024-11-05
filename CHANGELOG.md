# Changelog

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
