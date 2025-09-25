# Adapters

In CodeCompanion, adapters are used to connect to LLMs or Agents. HTTP adapters contain various options for the LLM's endpoint alongside a defined schema for properties such as the model, temperature, top k, top p etc. HTTP adapters also contain various handler functions which define how messages which are sent to the LLM should be formatted alongside how output from the LLM should be received and displayed in the chat buffer. The adapters are defined in the `lua/codecompanion/adapters` directory.

## Relevant Files

### adapters/init.lua

@./lua/codecompanion/adapters/init.lua

Currently CodeCompanion supports http and ACP adapters.

### adapters/shared.lua

@./lua/codecompanion/adapters/shared.lua

There are some functions that are shared between the two adapter types and these are contained in this file.

### adapters/http/init.lua

@./lua/codecompanion/adapters/http/init.lua

This is the logic for the HTTP adapters. Various logic sits within this file which allows the adapter to be resolved into a CodeCompanion.HTTPAdapter object before it's used throughout the plugin to connect to an LLM endpoint.

### Example Adapter: openai.lua

@./lua/codecompanion/adapters/http/openai.lua

Sharing an example HTTP adapter for OpenAI.

## HTTP Client

@./lua/codecompanion/http.lua
@.codecompanion/adapters/plenary_curl.md

The http.lua module implements a provider-agnostic HTTP client for CodeCompanion that centralizes request construction, streaming, scheduling, and testability. It exposes three APIs: request (legacy, callback-based), send (async, handle-based), and send_sync (blocking). The client is built around a set of static methods (post, get, encode, schedule, schedule_wrap) that default to plenary.curl and vim scheduling primitives but can be overridden, making it straightforward to stub in tests. Each request starts by deep-copying the adapter, running optional setup hooks, expanding environment variables into URL/headers/raw flags, and encoding a JSON body that’s written to a temporary file. It then dispatches to GET or POST with a “raw” curl option list, optional streaming flags, and a single final callback that plenary.curl guarantees will run once when the request completes.

For the legacy request API, the final curl callback is wrapped in a scheduled function that: forwards the response to the caller (non-streaming success only), runs adapter on_exit/teardown hooks, invokes actions.done, derives success/error state (emitting an error callback for HTTP status >= 400), fires RequestFinished events, and removes the temp body file (subject to log level and status). When stream=true, a stream handler (schedule_wrap) delivers chunks incrementally and fires a RequestStreaming event on first chunk; the final callback is still invoked once for cleanup and events, but chunk data is not forwarded again as a “final” success. The newer send API delegates to request under the hood and returns a lightweight handle with cancel() and status(); it defers on_done by one tick so an error arriving after “finish” can suppress a success notification. The send_sync API performs the same preparation work in-process and immediately returns either a response or an error for non-streaming use-cases. Across all paths, the client consistently routes work through the overridable schedule/schedule_wrap to keep behavior deterministic and easily testable, and it emits RequestStarted/RequestFinished (and optional custom) events so the rest of the plugin can react.

