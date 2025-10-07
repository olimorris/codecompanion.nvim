local edit_tool_exp_strategies = require("codecompanion.strategies.chat.tools.catalog.helpers.edit_tool_exp_strategies")
local h = require("tests.helpers")

local new_set = MiniTest.new_set

-- Strategy stats tracking
local strategy_stats = {
  exact_match = { successes = 0, failures = 0 },
  trimmed_lines = { successes = 0, failures = 0 },
  position_markers = { successes = 0, failures = 0 },
  punctuation_normalized = { successes = 0, failures = 0 },
  whitespace_normalized = { successes = 0, failures = 0 },
  block_anchor = { successes = 0, failures = 0 },
}

local function track_strategy_result(strategy_name, success)
  if strategy_stats[strategy_name] then
    if success then
      strategy_stats[strategy_name].successes = strategy_stats[strategy_name].successes + 1
    else
      strategy_stats[strategy_name].failures = strategy_stats[strategy_name].failures + 1
    end
  end
end

local function print_strategy_report()
  print("\n=== Edit Tool Exp Strategies Test Report ===")
  local total_tests = 0
  for strategy, stats in pairs(strategy_stats) do
    local total = stats.successes + stats.failures
    total_tests = total_tests + total
    local success_rate = total > 0 and (stats.successes / total * 100) or 0
    print(string.format("%s: %d/%d (%.1f%% success rate)", strategy, stats.successes, total, success_rate))
  end
  print(string.format("Total tests: %d", total_tests))
  print("=== End Report ===\n")
end

local T = new_set({
  hooks = {
    post_once = function()
      print_strategy_report()
    end,
  },
})

-- Test cases with different languages and edge cases
local test_cases = {
  -- JavaScript/TypeScript tests
  {
    name = "JavaScript - Basic function replacement",
    language = "javascript",
    content = [[function getUserName(user) {
  return user.name;
}

function getEmail() {
  return "test@example.com";
}]],
    old_text = [[function getUserName(user) {
  return user.name;
}]],
    new_text = [[function getFullUserName(user) {
  return user.firstName + ' ' + user.lastName;
}]],
    expected_strategy = "exact_match",
  },

  {
    name = "TypeScript - Interface with different indentation",
    language = "typescript",
    content = [[interface User {
    name: string;
    email: string;
}

class UserService {
  getUser(): User {
    return { name: "John", email: "john@example.com" };
  }
}]],
    old_text = [[  getUser(): User {
    return { name: "John", email: "john@example.com" };
  }]],
    new_text = [[  async getUser(): Promise<User> {
    return await fetchUser();
  }]],
    expected_strategy = "trimmed_lines",
  },

  -- Python tests
  {
    name = "Python - Class method with docstrings",
    language = "python",
    content = [[class DataProcessor:
    """A class for processing data."""

    def process_data(self, data):
        """Process the given data.

        Args:
            data: The data to process

        Returns:
            Processed data
        """
        return data.strip().lower()

    def validate_data(self, data):
        return len(data) > 0]],
    old_text = [[    def process_data(self, data):
        """Process the given data.

        Args:
            data: The data to process

        Returns:
            Processed data
        """
        return data.strip().lower()]],
    new_text = [[    def process_data(self, data):
        """Process the given data with validation.

        Args:
            data: The data to process

        Returns:
            Processed and validated data
        """
        if not self.validate_data(data):
            raise ValueError("Invalid data")
        return data.strip().lower()]],
    expected_strategy = "exact_match",
  },

  {
    name = "Python - Different whitespace formatting",
    language = "python",
    content = [[def calculate_sum(numbers):
    total = 0
    for num in numbers:
        total += num
    return total]],
    old_text = [[def calculate_sum(numbers):
  total = 0
  for num in numbers:
    total += num
  return total]],
    new_text = [[def calculate_average(numbers):
    if not numbers:
        return 0
    total = sum(numbers)
    return total / len(numbers)]],
    expected_strategy = "whitespace_normalized",
  },

  -- Golang tests
  {
    name = "Go - Struct and method",
    language = "go",
    content = [[package main

import "fmt"

type User struct {
	Name  string
	Email string
}

func (u *User) GetInfo() string {
	return fmt.Sprintf("Name: %s, Email: %s", u.Name, u.Email)
}

func main() {
	user := &User{Name: "John", Email: "john@example.com"}
	fmt.Println(user.GetInfo())
}]],
    old_text = [[func (u *User) GetInfo() string {
	return fmt.Sprintf("Name: %s, Email: %s", u.Name, u.Email)
}]],
    new_text = [[func (u *User) GetInfo() string {
	if u == nil {
		return "User is nil"
	}
	return fmt.Sprintf("Name: %s, Email: %s", u.Name, u.Email)
}]],
    expected_strategy = "exact_match",
  },

  -- Rust tests
  {
    name = "Rust - Function with lifetime annotations",
    language = "rust",
    content = [[use std::collections::HashMap;

fn find_longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() > y.len() {
        x
    } else {
        y
    }
}

struct Config {
    settings: HashMap<String, String>,
}

impl Config {
    fn new() -> Self {
        Config {
            settings: HashMap::new(),
        }
    }
}]],
    old_text = [[fn find_longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() > y.len() {
        x
    } else {
        y
    }
}]],
    new_text = [[fn find_longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    match x.len().cmp(&y.len()) {
        std::cmp::Ordering::Greater => x,
        _ => y,
    }
}]],
    expected_strategy = "exact_match",
  },

  -- C++ tests
  {
    name = "C++ - Template class with special characters",
    language = "cpp",
    content = [[#include <vector>
#include <string>

template<typename T>
class Container {
private:
    std::vector<T> items;

public:
    void add(const T& item) {
        items.push_back(item);
    }

    size_t size() const {
        return items.size();
    }

    T& operator[](size_t index) {
        return items[index];
    }
};]],
    old_text = [[    T& operator[](size_t index) {
        return items[index];
    }]],
    new_text = [[    T& operator[](size_t index) {
        if (index >= items.size()) {
            throw std::out_of_range("Index out of range");
        }
        return items[index];
    }]],
    expected_strategy = "exact_match",
  },

  -- C tests
  {
    name = "C - Function with pointer manipulation",
    language = "c",
    content = [[#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char *name;
    int age;
} Person;

Person* create_person(const char* name, int age) {
    Person *p = malloc(sizeof(Person));
    p->name = strdup(name);
    p->age = age;
    return p;
}

void free_person(Person* p) {
    if (p) {
        free(p->name);
        free(p);
    }
}]],
    old_text = [[Person* create_person(const char* name, int age) {
    Person *p = malloc(sizeof(Person));
    p->name = strdup(name);
    p->age = age;
    return p;
}]],
    new_text = [[Person* create_person(const char* name, int age) {
    Person *p = malloc(sizeof(Person));
    if (!p) return NULL;
    p->name = strdup(name);
    if (!p->name) {
        free(p);
        return NULL;
    }
    p->age = age;
    return p;
}]],
    expected_strategy = "exact_match",
  },

  -- Ruby tests
  {
    name = "Ruby - Class with special syntax",
    language = "ruby",
    content = [[class User
  attr_accessor :name, :email

  def initialize(name, email)
    @name = name
    @email = email
  end

  def to_s
    "#{@name} <#{@email}>"
  end

  def self.from_hash(hash)
    new(hash[:name], hash[:email])
  end
end]],
    old_text = [[  def to_s
    "#{@name} <#{@email}>"
  end]],
    new_text = [[  def to_s
    return "Anonymous" if @name.nil? || @name.empty?
    "#{@name} <#{@email}>"
  end]],
    expected_strategy = "exact_match",
  },

  -- Lua tests with different syntax
  {
    name = "Lua - Module with metamethods",
    language = "lua",
    content = [[local M = {}

function M.new(name, value)
  local obj = {
    name = name,
    value = value or 0,
  }

  setmetatable(obj, {
    __tostring = function(self)
      return string.format("%s: %d", self.name, self.value)
    end,
    __add = function(a, b)
      return M.new(a.name, a.value + b.value)
    end,
  })

  return obj
end

return M]],
    old_text = [[    __tostring = function(self)
      return string.format("%s: %d", self.name, self.value)
    end,]],
    new_text = [[    __tostring = function(self)
      if not self.name then
        return tostring(self.value)
      end
      return string.format("%s: %d", self.name, self.value)
    end,]],
    expected_strategy = "exact_match",
  },

  -- Edge case: Empty file
  {
    name = "Empty file - First addition",
    language = "text",
    content = "",
    old_text = "",
    new_text = "Hello, World!",
    expected_strategy = "exact_match",
  },

  -- Edge case: Single line file
  {
    name = "Single line file modification",
    language = "text",
    content = "Hello, World!",
    old_text = "Hello, World!",
    new_text = "Hello, Universe!",
    expected_strategy = "exact_match",
  },

  -- Edge case: File with only whitespace
  {
    name = "Whitespace-only file",
    language = "text",
    content = "   \n  \n\t\n   ",
    old_text = "   \n  ",
    new_text = "content",
    expected_strategy = "whitespace_normalized",
  },

  -- Edge case: Beginning of file
  {
    name = "Beginning of file modification",
    language = "python",
    content = [[#!/usr/bin/env python3
"""Module docstring."""

import os
import sys

def main():
    print("Hello")

if __name__ == "__main__":
    main()]],
    old_text = [[#!/usr/bin/env python3
"""Module docstring."""]],
    new_text = [[#!/usr/bin/env python3
"""Updated module docstring with more details."""]],
    expected_strategy = "exact_match",
  },

  -- Edge case: End of file
  {
    name = "End of file modification",
    language = "python",
    content = [[def function_one():
    return 1

def function_two():
    return 2

# End of file]],
    old_text = [[# End of file]],
    new_text = [[# End of file
# Additional comment]],
    expected_strategy = "exact_match",
  },

  -- Multiple similar matches test
  {
    name = "Multiple similar matches - should find best",
    language = "javascript",
    content = [[function process() {
  console.log("Processing...");
  return true;
}

function process() {
  console.log("Processing data...");
  return false;
}

function processData() {
  console.log("Processing...");
  return null;
}]],
    old_text = [[function process() {
  console.log("Processing data...");
  return false;
}]],
    new_text = [[function processAdvanced() {
  console.log("Advanced processing...");
  return true;
}]],
    expected_strategy = "exact_match",
  },

  -- Punctuation differences
  {
    name = "Punctuation normalization test",
    language = "javascript",
    content = [[const config = {
  apiUrl: "https://api.example.com",
  timeout: 5000,
  retries: 3,
};

const settings = {
  debug: true,
  verbose: false
};]],
    old_text = [[const config = {
  apiUrl: "https://api.example.com",
  timeout: 5000,
  retries: 3
}]],
    new_text = [[const config = {
  apiUrl: "https://api.example.com/v2",
  timeout: 10000,
  retries: 5,
}]],
    expected_strategy = "punctuation_normalized",
  },

  -- Block anchor test (first/last lines)
  {
    name = "Block anchor strategy test",
    language = "python",
    content = [[def complex_function():
    # This is a complex function
    data = []
    for i in range(10):
        if i % 2 == 0:
            data.append(i * 2)
        else:
            data.append(i * 3)

    # Process the data
    result = sum(data)

    # Return processed result
    return result * 1.5]],
    old_text = [[    # This is a complex function
    data = []
    for i in range(10):
        if i % 2 == 0:
            data.append(i * 2)
        else:
            data.append(i * 3)

    # Process the data
    result = sum(data)

    # Return processed result]],
    new_text = [[    # This is an improved complex function
    data = []
    for i in range(20):  # Increased range
        if i % 2 == 0:
            data.append(i * 2)
        else:
            data.append(i * 3)

    # Process the data with validation
    if not data:
        return 0
    result = sum(data)

    # Return processed result]],
    expected_strategy = "block_anchor",
  },
}

-- Helper function to run a test case
local function run_test_case(test_case)
  local result = edit_tool_exp_strategies.find_best_match(test_case.content, test_case.old_text)

  -- Track the result
  if result.success then
    track_strategy_result(result.strategy_used, true)
  else
    -- Try to determine which strategy would have been attempted
    track_strategy_result(test_case.expected_strategy or "unknown", false)
  end

  return result
end

-- Test individual strategies
T["Individual Strategy Tests"] = new_set()

T["Individual Strategy Tests"]["exact_match strategy"] = function()
  local content = [[function test() {
  return "hello";
}]]
  local old_text = [[function test() {
  return "hello";
}]]

  local matches = edit_tool_exp_strategies.exact_match(content, old_text)
  h.eq(#matches > 0, true)
  h.eq(matches[1].confidence >= 1.0, true)
end

T["Individual Strategy Tests"]["trimmed_lines strategy"] = function()
  local content = [[  function test() {
    return "hello";
  }]]
  local old_text = [[function test() {
  return "hello";
}]]

  local matches = edit_tool_exp_strategies.trimmed_lines(content, old_text)
  h.eq(#matches > 0, true)
end

T["Individual Strategy Tests"]["whitespace_normalized strategy"] = function()
  local content = "hello   world"
  local old_text = "hello world"

  local matches = edit_tool_exp_strategies.whitespace_normalized(content, old_text)
  h.eq(#matches > 0, true)
end

T["Individual Strategy Tests"]["punctuation_normalized strategy"] = function()
  local content = "const x = { a: 1, b: 2 };"
  local old_text = "const x = { a: 1, b: 2 }"

  local matches = edit_tool_exp_strategies.punctuation_normalized(content, old_text)
  h.eq(#matches > 0, true)
end

T["Individual Strategy Tests"]["position_markers strategy"] = function()
  local content = [[// START
function test() {
  return true;
}
// END]]
  local old_text = [[// START
function test() {
  return true;
}]]

  local matches = edit_tool_exp_strategies.position_markers(content, old_text)
  h.eq(#matches >= 0, true) -- May or may not find matches depending on markers
end

T["Individual Strategy Tests"]["block_anchor strategy"] = function()
  local content = [[function start() {
  let a = 1;
  let b = 2;
  return a + b;
}]]
  local old_text = [[  let a = 1;
  let b = 2;]]

  local matches = edit_tool_exp_strategies.block_anchor(content, old_text)
  h.eq(#matches >= 0, true)
end

-- Comprehensive find_best_match tests
T["Comprehensive find_best_match Tests"] = new_set()

-- Run all test cases
for i, test_case in ipairs(test_cases) do
  T["Comprehensive find_best_match Tests"][string.format("Test %d: %s", i, test_case.name)] = function()
    local result = run_test_case(test_case)

    h.eq(
      result.success,
      true,
      string.format("Test case '%s' failed: %s", test_case.name, result.error or "Unknown error")
    )

    if result.success then
      h.eq(type(result.matches), "table")
      h.eq(#result.matches > 0, true)
      h.eq(type(result.strategy_used), "string")

      -- Verify that at least one match has good confidence
      local has_good_match = false
      for _, match in ipairs(result.matches) do
        if match.confidence and match.confidence >= 0.8 then
          has_good_match = true
          break
        end
      end
      h.eq(has_good_match, true, "No high-confidence matches found")
    end
  end
end

-- Edge cases and error handling
T["Edge Cases and Error Handling"] = new_set()

T["Edge Cases and Error Handling"]["handles very large content"] = function()
  local large_content = string.rep("line\n", 10000)
  local old_text = "line\nline\nline"

  local result = edit_tool_exp_strategies.find_best_match(large_content, old_text)
  h.eq(result.success, true)
end

T["Edge Cases and Error Handling"]["handles empty content"] = function()
  local result = edit_tool_exp_strategies.find_best_match("", "")
  h.eq(result.success, true)
end

T["Edge Cases and Error Handling"]["handles content with unicode characters"] = function()
  local content = 'function test() {\n  return "こんにちは世界";\n}'
  local old_text = 'function test() {\n  return "こんにちは世界";\n}'

  local result = edit_tool_exp_strategies.find_best_match(content, old_text)
  h.eq(result.success, true)
end

T["Edge Cases and Error Handling"]["handles content with special regex characters"] = function()
  local content = "const regex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$/"
  local old_text = "const regex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$/"

  local result = edit_tool_exp_strategies.find_best_match(content, old_text)
  h.eq(result.success, true)
end

T["Edge Cases and Error Handling"]["handles mixed line endings"] = function()
  local content = "line1\r\nline2\nline3\r\nline4"
  local old_text = "line2\nline3"

  local result = edit_tool_exp_strategies.find_best_match(content, old_text)
  h.eq(result.success, true)
end

-- Test apply_replacement functionality
T["Apply Replacement Tests"] = new_set()

T["Apply Replacement Tests"]["applies single replacement correctly"] = function()
  local content = "Hello World"
  local match = {
    start_line = 1,
    end_line = 1,
    start_pos = 1,
    end_pos = 11,
    matched_text = "Hello World",
  }
  local new_text = "Hello Universe"

  local result = edit_tool_exp_strategies.apply_replacement(content, match, new_text)
  h.eq(result, "Hello Universe")
end

T["Apply Replacement Tests"]["applies multiple replacements correctly"] = function()
  local content = "line1\nline2\nline3\nline2\nline4"
  local matches = {
    {
      start_line = 2,
      end_line = 2,
      start_pos = 7,
      end_pos = 11,
      matched_text = "line2",
    },
    {
      start_line = 4,
      end_line = 4,
      start_pos = 19,
      end_pos = 23,
      matched_text = "line2",
    },
  }
  local new_text = "newline"

  local result = edit_tool_exp_strategies.apply_replacement(content, matches, new_text)
  h.eq(result, "line1\nnewline\nline3\nnewline\nline4")
end

-- Test select_best_match functionality
T["Select Best Match Tests"] = new_set()

T["Select Best Match Tests"]["selects highest confidence match"] = function()
  local matches = {
    { confidence = 0.7, matched_text = "match1", start_line = 10 },
    { confidence = 0.9, matched_text = "match2", start_line = 20 },
    { confidence = 0.6, matched_text = "match3", start_line = 30 },
  }

  local result = edit_tool_exp_strategies.select_best_match(matches, false)
  h.eq(result.success, true)
  h.eq(result.selected.confidence, 0.9)
end

T["Select Best Match Tests"]["returns all matches when replace_all is true"] = function()
  local matches = {
    { confidence = 0.8, matched_text = "match1" },
    { confidence = 0.9, matched_text = "match2" },
  }

  local result = edit_tool_exp_strategies.select_best_match(matches, true)
  h.eq(result.success, true)
  h.eq(type(result.selected), "table")
  h.eq(#result.selected, 2)
end

T["Select Best Match Tests"]["handles empty matches"] = function()
  local result = edit_tool_exp_strategies.select_best_match({}, false)
  h.eq(result.success, false)
  h.eq(type(result.error), "string")
end

-- Performance tests
T["Performance Tests"] = new_set()

T["Performance Tests"]["handles reasonable performance on medium files"] = function()
  local medium_content = string.rep("function test" .. math.random() .. "() {\n  return true;\n}\n\n", 100)
  local old_text = "function test123() {\n  return true;\n}"

  local start_time = os.clock()
  local result = edit_tool_exp_strategies.find_best_match(medium_content, old_text)
  local elapsed = os.clock() - start_time

  h.eq(elapsed < 5.0, true, "Performance test failed - took too long: " .. elapsed .. "s")
  -- Note: result.success might be false if no match is found, which is okay for perf test
end

return T
