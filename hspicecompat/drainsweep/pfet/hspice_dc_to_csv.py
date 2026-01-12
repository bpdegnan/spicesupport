#!/usr/bin/env python3
"""
Parse HSPICE .out file and convert DC sweep analysis data to CSV.

Usage:
    python3 hspice_dc_to_csv.py hspice.out [output.csv]
"""

import re
import sys

SUFFIXES = {
    'a': 1e-18, 'f': 1e-15, 'p': 1e-12, 'n': 1e-9,
    'u': 1e-6, 'm': 1e-3, 'k': 1e3, 'x': 1e6, 'g': 1e9, 't': 1e12,
}

def parse_hspice_value(s):
    s = s.strip()
    if not s:
        return None
    if s[-1].lower() in SUFFIXES:
        return float(s[:-1]) * SUFFIXES[s[-1].lower()]
    return float(s)

def parse_hspice_dc_output(filepath):
    with open(filepath, 'r') as f:
        lines = f.read().split('\n')
    
    # Find header line
    header_line_idx = None
    for i, line in enumerate(lines):
        if re.match(r'^\s*(volt|current)(\s+(volt|current))+', line.lower()):
            header_line_idx = i
            break
    
    if header_line_idx is None:
        raise ValueError("Could not find header line")
    
    # Check for subheader
    subheader_line_idx = None
    next_line = lines[header_line_idx + 1].strip() if header_line_idx + 1 < len(lines) else ""
    if next_line and not re.match(r'^[\-\d\.]', next_line):
        subheader_line_idx = header_line_idx + 1
    
    # Build column names
    header_parts = lines[header_line_idx].split()
    if subheader_line_idx:
        subheader_parts = lines[subheader_line_idx].split()
        columns = []
        for j, htype in enumerate(header_parts):
            name = subheader_parts[j] if j < len(subheader_parts) else f'col{j}'
            prefix = 'v' if htype.lower() == 'volt' else 'i'
            columns.append(f'{prefix}({name})')
        data_start = subheader_line_idx + 1
    else:
        columns = ['v(nd)', 'i(Vam_1)', 'i(Vam_2)', 'i(Vam_3)', 'i(Vam_4)', 'i(Vam_5)']
        data_start = header_line_idx + 1
    
    # Find first data line
    for i in range(data_start, len(lines)):
        if lines[i].strip() and re.match(r'^[\-\d\.]', lines[i].strip()):
            data_start = i
            break
    
    # Parse data
    data = []
    for i in range(data_start, len(lines)):
        line = lines[i].strip()
        if not line or line.startswith(('y', '*', '$', 'x')) or 'job' in line.lower():
            break
        if not re.match(r'^[\-\d]', line):
            continue
        try:
            row = [parse_hspice_value(p) for p in line.split()]
            if all(v is not None for v in row):
                data.append(row)
        except ValueError:
            continue
    
    # Adjust columns if needed
    if data and len(data[0]) != len(columns):
        columns = ['v(nd)'] + [f'i(Vam_{i})' for i in range(1, len(data[0]))]
    
    return columns, data

def write_csv(columns, data, output_path):
    with open(output_path, 'w') as f:
        f.write(' ' + '\t'.join(f'{c:>15}' for c in columns) + '\n')
        for row in data:
            f.write(' ' + '\t'.join(f'{v:>15.8e}' for v in row) + '\n')

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
    
    write_csv(columns, data, output_file)
    print(f"Wrote {output_file}", file=sys.stderr)

if __name__ == '__main__':
    main()
