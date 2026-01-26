#!/usr/bin/env python3
"""
Parse HSPICE .out file and convert DC sweep analysis data to CSV.

Handles the terminal current format:
    v(ng) i(Vg_sense) i(Vd_sense) i(Vs_sense) i(Vb_sense)

Usage:
    python3 hspice_dc_to_csv.py nfetdc.out [output.csv]
"""

import re
import sys

# HSPICE engineering notation suffixes
SUFFIXES = {
    'a': 1e-18, 'f': 1e-15, 'p': 1e-12, 'n': 1e-9,
    'u': 1e-6, 'm': 1e-3, 'k': 1e3, 'x': 1e6, 'g': 1e9, 't': 1e12,
}

def parse_hspice_value(s):
    """Parse HSPICE engineering notation value."""
    s = s.strip().lower()
    if not s:
        return None
    # Handle negative values
    negative = s.startswith('-')
    if negative:
        s = s[1:]
    # Check for suffix
    if s and s[-1] in SUFFIXES:
        value = float(s[:-1]) * SUFFIXES[s[-1]]
    else:
        value = float(s)
    return -value if negative else value

def parse_hspice_dc_output(filepath):
    """Parse HSPICE .out file and extract DC sweep data."""
    with open(filepath, 'r') as f:
        content = f.read()
    
    lines = content.split('\n')
    
    # Find the DC sweep data section
    # Look for pattern: "volt" and "current" header line
    header_line_idx = None
    for i, line in enumerate(lines):
        # Match header line with volt/current types
        if re.match(r'^\s*(volt|current)(\s+(volt|current))+\s*$', line.lower()):
            header_line_idx = i
            break
    
    if header_line_idx is None:
        # Try alternate pattern - look for column names directly
        for i, line in enumerate(lines):
            if 'v(ng)' in line.lower() or 'vg_sense' in line.lower():
                header_line_idx = i
                break
    
    if header_line_idx is None:
        raise ValueError("Could not find header line in HSPICE output")
    
    # Parse header types (volt/current)
    header_types = lines[header_line_idx].split()
    
    # Next line should have node/source names
    subheader_idx = header_line_idx + 1
    subheader_line = lines[subheader_idx].strip()
    
    # Check if subheader line is actually data (starts with number)
    if re.match(r'^[\-\d\.]', subheader_line):
        # No subheader, use default names
        columns = []
        for j, htype in enumerate(header_types):
            if htype.lower() == 'volt':
                columns.append(f'v(col{j})')
            else:
                columns.append(f'i(col{j})')
        data_start = subheader_idx
    else:
        # Parse subheader for column names
        subheader_parts = subheader_line.split()
        columns = []
        for j, htype in enumerate(header_types):
            if j < len(subheader_parts):
                name = subheader_parts[j]
                prefix = 'v' if htype.lower() == 'volt' else 'i'
                columns.append(f'{prefix}({name})')
            else:
                prefix = 'v' if htype.lower() == 'volt' else 'i'
                columns.append(f'{prefix}(col{j})')
        data_start = subheader_idx + 1
    
    # Skip any blank lines or separator lines
    while data_start < len(lines):
        line = lines[data_start].strip()
        if line and re.match(r'^[\-\d]', line):
            break
        data_start += 1
    
    # Parse data rows
    data = []
    for i in range(data_start, len(lines)):
        line = lines[i].strip()
        
        # Stop at end markers
        if not line:
            continue
        if line.startswith(('y', '*', '$', 'x', '>')):
            break
        if 'job' in line.lower() or 'concluded' in line.lower():
            break
        if not re.match(r'^[\-\d]', line):
            break
        
        # Parse values
        try:
            parts = line.split()
            row = [parse_hspice_value(p) for p in parts]
            if all(v is not None for v in row) and len(row) == len(columns):
                data.append(row)
            elif all(v is not None for v in row) and len(row) > 0:
                # Adjust columns if mismatch on first row
                if len(data) == 0:
                    while len(columns) < len(row):
                        columns.append(f'col{len(columns)}')
                    columns = columns[:len(row)]
                    data.append(row)
        except (ValueError, IndexError):
            continue
    
    return columns, data

def write_csv(columns, data, output_path):
    """Write data to CSV file (comma-separated)."""
    with open(output_path, 'w') as f:
        # Write header
        f.write(','.join(columns) + '\n')
        # Write data
        for row in data:
            f.write(','.join(f'{v:.10e}' for v in row) + '\n')

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 hspice_dc_to_csv.py <hspice.out> [output.csv]", file=sys.stderr)
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else input_file.replace('.out', '.csv')
    
    print(f"Parsing {input_file}...", file=sys.stderr)
    columns, data = parse_hspice_dc_output(input_file)
    print(f"Found {len(data)} data points", file=sys.stderr)
    print(f"Columns: {columns}", file=sys.stderr)
    
    if len(data) == 0:
        print("Warning: No data found!", file=sys.stderr)
        sys.exit(1)
    
    write_csv(columns, data, output_file)
    print(f"Wrote {output_file}", file=sys.stderr)

if __name__ == '__main__':
    main()
