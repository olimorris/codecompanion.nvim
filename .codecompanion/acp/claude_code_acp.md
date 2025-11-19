# Claude Code ACP

This file shows the Claude Code ACP adapter's JSON RPC output when various tools are called.

## edit

When editing a file:

```json
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a5121-cbef-746c-aece-adc08cef75cd","update":{"toolCallId":"toolu_01VRjmb5Vsv9WwwKu6cgH8a4","sessionUpdate":"tool_call","rawInput":{},"status":"pending","title":"Write","kind":"edit","content":[],"locations":[]}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a5121-cbef-746c-aece-adc08cef75cd","update":{"toolCallId":"toolu_01VRjmb5Vsv9WwwKu6cgH8a4","sessionUpdate":"tool_call","rawInput":{"file_path":"/Users/Oli/Code/Neovim/codecompanion.nvim/quotes.lua","content":"-- Simple test comment for ACP capture\nreturn {}\n"},"status":"pending","title":"Write /Users/Oli/Code/Neovim/codecompanion.nvim/quotes.lua","kind":"edit","content":[{"type":"diff","path":"/Users/Oli/Code/Neovim/codecompanion.nvim/quotes.lua","oldText":null,"newText":"-- Simple test comment for ACP capture\nreturn {}\n"}],"locations":[{"path":"/Users/Oli/Code/Neovim/codecompanion.nvim/quotes.lua"}]}}}
{"jsonrpc":"2.0","id":6,"method":"session/request_permission","params":{"options":[{"kind":"allow_always","name":"Always Allow","optionId":"allow_always"},{"kind":"allow_once","name":"Allow","optionId":"allow"},{"kind":"reject_once","name":"Reject","optionId":"reject"}],"sessionId":"019a5121-cbef-746c-aece-adc08cef75cd","toolCall":{"toolCallId":"toolu_01VRjmb5Vsv9WwwKu6cgH8a4","rawInput":{"file_path":"/Users/Oli/Code/Neovim/codecompanion.nvim/quotes.lua","content":"-- Simple test comment for ACP capture\nreturn {}\n"}}}}
{"jsonrpc":"2.0","id":6,"result":{"outcome":{"outcome":"selected","optionId":"allow_always"}}}
{"jsonrpc":"2.0","id":7,"method":"fs/write_text_file","params":{"sessionId":"019a5121-cbef-746c-aece-adc08cef75cd","path":"/Users/Oli/Code/Neovim/codecompanion.nvim/quotes.lua","content":"-- Simple test comment for ACP capture\nreturn {}\n"}}
```

## read_file

To read a file:

```json
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a50a9-1217-7536-9bf1-ebb36898ca96","update":{"toolCallId":"toolu_01LpQDoSXz49Yb64gPmXySai","sessionUpdate":"tool_call","rawInput":{},"status":"pending","title":"Read File","kind":"read","locations":[],"content":[]}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a50a9-1217-7536-9bf1-ebb36898ca96","update":{"toolCallId":"toolu_01LpQDoSXz49Yb64gPmXySai","sessionUpdate":"tool_call","rawInput":{"file_path":"/Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/strategies/chat/acp/formatters.lua"},"status":"pending","title":"Read /Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/strategies/chat/acp/formatters.lua","kind":"read","locations":[{"path":"/Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/strategies/chat/acp/formatters.lua","line":0}],"content":[]}}}
{"jsonrpc":"2.0","id":0,"method":"fs/read_text_file","params":{"sessionId":"019a50a9-1217-7536-9bf1-ebb36898ca96","path":"/Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/strategies/chat/acp/formatters.lua","line":1,"limit":2000}}
{"result":{"content":""},"jsonrpc":"2.0","id":0}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a50a9-1217-7536-9bf1-ebb36898ca96","update":{"toolCallId":"toolu_01LpQDoSXz49Yb64gPmXySai","sessionUpdate":"tool_call_update","status":"completed","content":[{"type":"content","content":{"type":"text","text":"```\n\n```"}}]}}}
```

## execute

When executing a command:

```json
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a50a9-1217-7536-9bf1-ebb36898ca96","update":{"toolCallId":"toolu_017FaiLJGYNSVToDmZhrHqhA","sessionUpdate":"tool_call","rawInput":{},"status":"pending","title":"Terminal","kind":"execute","content":[]}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a50a9-1217-7536-9bf1-ebb36898ca96","update":{"toolCallId":"toolu_017FaiLJGYNSVToDmZhrHqhA","sessionUpdate":"tool_call","rawInput":{"command":"ls -la lua/codecompanion/strategies/chat/acp/formatters/","description":"List files in formatters directory"},"status":"pending","title":"`ls -la lua/codecompanion/strategies/chat/acp/formatters/`","kind":"execute","content":[{"type":"content","content":{"type":"text","text":"List files in formatters directory"}}]}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a50a9-1217-7536-9bf1-ebb36898ca96","update":{"toolCallId":"toolu_017FaiLJGYNSVToDmZhrHqhA","sessionUpdate":"tool_call_update","status":"completed","content":[{"type":"content","content":{"type":"text","text":"total 56\ndrwxr-xr-x@ 6 Oli  staff    192  4 Nov 18:04 .\ndrwxr-xr-x@ 7 Oli  staff    224  4 Nov 18:05 ..\n-rw-r--r--@ 1 Oli  staff   4153  4 Nov 18:04 claude_code.lua\n-rw-r--r--@ 1 Oli  staff   3168  4 Nov 17:14 codex.lua\n-rw-r--r--@ 1 Oli  staff  11006  4 Nov 17:14 default.lua\n-rw-r--r--@ 1 Oli  staff    989  4 Nov 17:15 init.lua"}}]}}}
```

## search

When searching for content and there's no data:

```json
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a5121-cbef-746c-aece-adc08cef75cd","update":{"toolCallId":"toolu_019YPt8kXTaoKTadxdQjfims","sessionUpdate":"tool_call","rawInput":{},"status":"pending","title":"Find","kind":"search","content":[],"locations":[]}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a5121-cbef-746c-aece-adc08cef75cd","update":{"toolCallId":"toolu_019YPt8kXTaoKTadxdQjfims","sessionUpdate":"tool_call","rawInput":{"pattern":"**/*add_buf_message*"},"status":"pending","title":"Find `**/*add_buf_message*`","kind":"search","content":[],"locations":[]}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a5121-cbef-746c-aece-adc08cef75cd","update":{"toolCallId":"toolu_019YPt8kXTaoKTadxdQjfims","sessionUpdate":"tool_call_update","status":"completed","content":[{"type":"content","content":{"type":"text","text":"No files found"}}]}}}
```

When searching for content and there is data:

```json
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a5121-cbef-746c-aece-adc08cef75cd","update":{"toolCallId":"toolu_01JQYavcZoNrCK5uA4W8qmJw","sessionUpdate":"tool_call","rawInput":{},"status":"pending","title":"grep \"undefined\"","kind":"search","content":[]}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a5121-cbef-746c-aece-adc08cef75cd","update":{"toolCallId":"toolu_01JQYavcZoNrCK5uA4W8qmJw","sessionUpdate":"tool_call","rawInput":{"pattern":"add_buf_message","output_mode":"files_with_matches"},"status":"pending","title":"grep \"add_buf_message\"","kind":"search","content":[]}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a5121-cbef-746c-aece-adc08cef75cd","update":{"toolCallId":"toolu_01JQYavcZoNrCK5uA4W8qmJw","sessionUpdate":"tool_call_update","status":"completed","content":[{"type":"content","content":{"type":"text","text":"Found 22 files\n/Users/Oli/Code/Neovim/codecompanion.nvim/tests/strategies/chat/test_chat.lua\n/Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/strategies/chat/acp/handler.lua\n/Users/Oli/Code/Neovim/codecompanion.nvim/tests/strategies/chat/test_context.lua\n/Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/providers/completion/init.lua\n/Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/strategies/chat/init.lua\n/Users/Oli/Code/Neovim/codecompanion.nvim/tests/strategies/chat/acp/test_handler.lua\n/Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/strategies/chat/tools/init.lua\n/Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/strategies/chat/slash_commands/catalog/now.lua\n/Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/init.lua\n/Users/Oli/Code/Neovim/codecompanion.nvim/tests/strategies/chat/tools/test_tools.lua\n/Users/Oli/Code/Neovim/codecompanion.nvim/tests/adapters/http/test_tools_in_chat_buffer.lua\n/Users/Oli/Code/Neovim/codecompanion.nvim/tests/stubs/messages.lua\n/Users/Oli/Code/Neovim/codecompanion.nvim/lua/codecompanion/strategies/init.lua\n/Users/Oli/Code/Neovim/codecompanion.nvim/.codecompanion/chat.md\n/Users/Oli/Code/Neovim/codecompanion.nvim/tests/helpers.lua\n/Users/Oli/Code/Neovim/codecompanion.nvim/tests/strategies/chat/test_subscribers.lua\n/Users/Oli/Code/Neovim/codecompanion.nvim/codecompanion-workspace.json\n/Users/Oli/Code/Neovim/codecompanion.nvim/.codecompanion/ui.md\n/Users/Oli/Code/Neovim/codecompanion.nvim/tests/strategies/chat/ui/test_fold_reasoning_output.lua\n/Users/Oli/Code/Neovim/codecompanion.nvim/tests/strategies/chat/ui/test_builder_state.lua\n/Users/Oli/Code/Neovim/codecompanion.nvim/tests/strategies/chat/tools/catalog/test_tool_output.lua\n/Users/Oli/Code/Neovim/codecompanion.nvim/tests/strategies/chat/test_messages.lua"}}]}}}
```

## fetch

When doing a web search:

```json
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a5121-cbef-746c-aece-adc08cef75cd","update":{"toolCallId":"toolu_01Sej4My9Mncay2CPSKWkZAJ","sessionUpdate":"tool_call","rawInput":{},"status":"pending","title":"\"undefined\"","kind":"fetch","content":[]}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a5121-cbef-746c-aece-adc08cef75cd","update":{"toolCallId":"toolu_01Sej4My9Mncay2CPSKWkZAJ","sessionUpdate":"tool_call","rawInput":{"query":"Sheffield United"},"status":"pending","title":"\"Sheffield United\"","kind":"fetch","content":[]}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a5121-cbef-746c-aece-adc08cef75cd","update":{"toolCallId":"toolu_01Sej4My9Mncay2CPSKWkZAJ","sessionUpdate":"tool_call_update","status":"completed","content":[{"type":"content","content":{"type":"text","text":"Web search results for query: \"Sheffield United\"\n\nLinks: [{\"title\":\"Wilder reacts to Sheffield United's defeat by Derby\",\"url\":\"https://www.aol.com/articles/wilder-reacts-sheffield-uniteds-defeat-184416563.html\"},{\"title\":\"Sheffield United F.C. - Wikipedia\",\"url\":\"https://en.wikipedia.org/wiki/Sheffield_United_F.C.\"},{\"title\":\"Sheffield United Scores, Stats and Highlights - ESPN\",\"url\":\"https://www.espn.com/soccer/team/_/id/398/sheffield-united\"},{\"title\":\"Sheffield United FC\",\"url\":\"https://www.sufc.co.uk/\"},{\"title\":\"Sheffield United (@SheffieldUnited) / X\",\"url\":\"https://x.com/SheffieldUnited\"},{\"title\":\"Sheffield United News, Fixtures, Results, Transfers | Sky Sports\",\"url\":\"https://www.skysports.com/sheffield-united\"},{\"title\":\"Sheffield United (@sheffieldunited) • Instagram photos and videos\",\"url\":\"https://www.instagram.com/sheffieldunited/\"},{\"title\":\"Sheffield United Team News, Fixtures & Results 2025/26 | Premier League\",\"url\":\"https://www.premierleague.com/en/clubs/49/sheffield-united/overview\"},{\"title\":\"Men's Team\",\"url\":\"https://www.sufc.co.uk/teams/\"},{\"title\":\"Sheffield United | Sheffield | Facebook\",\"url\":\"https://www.facebook.com/sheffieldunited/\"}]\n\nBased on the search results, here's information about Sheffield United:\n\n## Overview\nSheffield United Football Club is a professional football club based in Sheffield, South Yorkshire, England that competes in the EFL Championship, the second tier of English football.(no content)They are nicknamed \"the Blades\" due to Sheffield's history of cutlery production.\n\n## Home & History\nThe team have played home games at Bramall Lane since their formation.(no content)Sheffield United was formed as an offshoot of Sheffield United Cricket Club in 1889 and following strong performances in the Midland League and Northern League, they were invited to become a founding member of the Football League Second Division in 1892.\n\n## Recent News\nSheffield United manager Chris Wilder speaks to BBC Radio Sheffield after Saturday's 3-1 defeat by Derby County. This match occurred just three days ago.\n\n## League Status\nThe club played in the Premier League following a promotion from the EFL Championship in the 2022–23 season, but were relegated in the following season. They are currently competing in the Championship under manager Chris Wilder.\n\n## Rivals\nTheir main rivals are Sheffield Wednesday, with whom they contest the Steel City derby."}}]}}}
```

Fetching a specific web page:

```json
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a5121-cbef-746c-aece-adc08cef75cd","update":{"toolCallId":"toolu_01V4sSXxJ5CQALc3sKQR5mCu","sessionUpdate":"tool_call","rawInput":{},"status":"pending","title":"Fetch","kind":"fetch","content":[]}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a5121-cbef-746c-aece-adc08cef75cd","update":{"toolCallId":"toolu_01V4sSXxJ5CQALc3sKQR5mCu","sessionUpdate":"tool_call","rawInput":{"url":"https://example.com","prompt":"Summarize the content of this webpage"},"status":"pending","title":"Fetch https://example.com","kind":"fetch","content":[{"type":"content","content":{"type":"text","text":"Summarize the content of this webpage"}}]}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"019a5121-cbef-746c-aece-adc08cef75cd","update":{"toolCallId":"toolu_01V4sSXxJ5CQALc3sKQR5mCu","sessionUpdate":"tool_call_update","status":"completed","content":[{"type":"content","content":{"type":"text","text":"# Webpage Summary\n\nThis is the \"Example Domain\" page, a resource provided by IANA (Internet Assigned Numbers Authority). The page states that \"This domain is for use in documentation examples without needing permission.\" The site advises users to avoid utilizing it for operational purposes. \n\nThe page includes minimal styling and a link directing visitors to learn more information on IANA's website about example domains. It serves as a placeholder or reference point for developers and documentarians who need to demonstrate concepts in their work."}}]}}}
```
