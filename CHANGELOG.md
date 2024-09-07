# Changelog

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
