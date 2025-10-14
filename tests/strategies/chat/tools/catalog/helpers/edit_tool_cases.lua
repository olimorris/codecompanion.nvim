local M = {}

-- Test cases with different languages and edge cases
M.test_cases = {
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

M.run_test_case = function(test_case, edit_tool_exp_strategies, track_strategy_result)
  local result = edit_tool_exp_strategies.find_best_match(test_case.content, test_case.old_text, false)
  if result.success then
    track_strategy_result(result.strategy_used, true)
  else
    track_strategy_result(test_case.expected_strategy or "unknown", false)
  end
  return result
end

return M
