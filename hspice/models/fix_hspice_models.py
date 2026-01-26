#!/usr/bin/env python3
"""
Fix ngspice-style curly brace expressions for HSPICE compatibility.

The PDK has expressions like:
  toxe={4.23e-09+sky130_fd_pr__pfet_01v8__toxe_slope_spectre*(4.23e-09*(sky130_fd_pr__pfet_01v8__toxe_slope/sqrt(l*w*mult)))}

Since all _slope_spectre params are set to 0.0, these simplify to just the nominal value:
  toxe=4.23e-09
"""

import re
import sys

def extract_nominal_value(expr):
    """
    Extract the nominal (first) value from expressions like:
    {4.23e-09+variable*(...)}  -> 4.23e-09
    {-1.05955351+variable*(...)} -> -1.05955351
    """
    # Match the first number (possibly negative, with scientific notation)
    match = re.match(r'\{([+-]?[0-9.]+(?:e[+-]?[0-9]+)?)', expr, re.IGNORECASE)
    if match:
        return match.group(1)
    return expr  # Return original if no match

def fix_line(line):
    """Fix a single line, replacing curly brace expressions with nominal values."""
    
    # Pattern for parameter={expression}
    # We need to handle nested parentheses inside the braces
    
    # Find all occurrences of ={...}
    result = line
    
    # Use a simple state machine to find matching braces
    i = 0
    while i < len(result):
        # Look for ={
        if result[i:i+2] == '={':
            start = i + 1  # Position of {
            # Find matching }
            brace_count = 1
            j = start + 1
            while j < len(result) and brace_count > 0:
                if result[j] == '{':
                    brace_count += 1
                elif result[j] == '}':
                    brace_count -= 1
                j += 1
            
            if brace_count == 0:
                # Extract the expression including braces
                expr = result[start:j]
                nominal = extract_nominal_value(expr)
                # Replace ={expr} with =nominal
                result = result[:i+1] + nominal + result[j:]
        i += 1
    
    return result

def process_file(input_path, output_path=None):
    """Process a model file and fix all expressions."""
    if output_path is None:
        output_path = input_path
    
    with open(input_path, 'r') as f:
        lines = f.readlines()
    
    fixed_lines = []
    fixes_made = 0
    
    for line in lines:
        fixed = fix_line(line)
        if fixed != line:
            fixes_made += 1
        fixed_lines.append(fixed)
    
    with open(output_path, 'w') as f:
        f.writelines(fixed_lines)
    
    return fixes_made

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: fix_hspice_models.py <file1.l> [file2.l ...]")
        sys.exit(1)
    
    for filepath in sys.argv[1:]:
        print(f"Processing: {filepath}")
        fixes = process_file(filepath)
        print(f"  Fixed {fixes} expressions")
    
    print("Done!")
