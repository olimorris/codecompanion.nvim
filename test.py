#!/usr/bin/env python3
"""
A simple Python script demonstrating various features.
"""

import random
from datetime import datetime


class Calculator:
    """A basic calculator class."""

    def __init__(self):
        self.history = []

    def add(self, a, b):
        result = a + b
        self.history.append(f"{a} + {b} = {result}")
        return result

    def multiply(self, a, b):
        result = a * b
        self.history.append(f"{a} * {b} = {result}")
        return result

    def get_history(self):
        return self.history


def generate_numbers(count=5):
    """Generate a list of random numbers."""
    return [random.randint(1, 100) for _ in range(count)]


def main():
    print("Python Test Script")
    print(f"Current time: {datetime.now()}")

    # Create calculator instance
    calc = Calculator()

    # Generate some random numbers
    numbers = generate_numbers(3)
    print(f"Generated numbers: {numbers}")

    # Perform calculations
    result1 = calc.add(numbers[0], numbers[1])
    result2 = calc.multiply(numbers[1], numbers[2])

    print(f"Addition result: {result1}")
    print(f"Multiplication result: {result2}")

    # Show calculation history
    print("\nCalculation History:")
    for entry in calc.get_history():
        print(f"  {entry}")

    # List comprehension example
    squares = [x**2 for x in numbers if x % 2 == 0]
    print(f"Squares of even numbers: {squares}")


if __name__ == "__main__":
    main()
