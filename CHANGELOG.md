# Changelog

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
