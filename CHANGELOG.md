# Changelog

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
