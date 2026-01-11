#!/usr/bin/env python3
"""
Parse HSPICE .out file and convert DC sweep analysis data to CSV.

Usage:
    python3 hspice_dc_to_csv.py hspice.out [output.csv]
    
If output.csv is not specified, outputs to hspice.out.csv
"""

import re
import sys

# HSPICE engineering notation suffixes
SUFFIXES = {
    'a': 1e-18,  # atto
    'f': 1e-15,  # femto
    'p': 1e-12,  # pico
    'n': 1e-9,   # nano
    'u': 1e-6,   # micro
    'm': 1e-3,   # milli
    'k': 1e3,    # kilo
    'x': 1e6,    # mega (HSPICE uses 'x' for mega)
    'g': 1e9,    # giga
    't': 1e12,   # tera
}

def parse_hspice_value(s):
    """
    Parse HSPICE engineering notation value.
    Examples: '1.00000k' -> 1000.0, '-137.2197n' -> -1.372197e-7
    """
    s = s.strip()
    if not s:
        return None
    
    # Check if last character is a suffix
    if s[-1].lower() in SUFFIXES:
        multiplier = SUFFIXES[s[-1].lower()]
        number = float(s[:-1])
        return number * multiplier
    else:
        return float(s)

def parse_hspice_dc_output(filepath):
    """
    Parse HSPICE .out file and extract DC sweep analysis data.
    Returns: (column_names, data_rows)
    """
    with open(filepath, 'r') as f:
        content = f.read()
        lines = content.split('\n')
    
    # Find the DC sweep section - look for "dc transfer curves"
    dc_start = None
    for i, line in enumerate(lines):
        if 'dc transfer' in line.lower() or 'dc analysis' in line.lower():
            dc_start = i
            break
    
    if dc_start is None:
        # Try alternate detection - look for volt/current header
        for i, line in enumerate(lines):
            if re.search(r'^\s*(volt|current)\s+(volt|current)', line.lower()):
                dc_start = max(0, i - 2)
                break
    
    if dc_start is None:
        raise ValueError("Could not find DC sweep section")
    
    # Find the header lines - look for pattern like "volt  current  current..."
    header_line_idx = None
    subheader_line_idx = None
    
    for i in range(dc_start, min(dc_start + 30, len(lines))):
        line = lines[i].lower().strip()
        # Look for header with volt/current types
        if re.match(r'^(volt|current)(\s+(volt|current))+', line):
            header_line_idx = i
            # Check next line for node/source names
            if i + 1 < len(lines):
                next_line = lines[i + 1].strip()
                # If next line doesn't start with a number, it's a subheader
                if next_line and not re.match(r'^[\-\d\.]', next_line):
                    subheader_line_idx = i + 1
            break
    
    if header_line_idx is None:
        raise ValueError("Could not find header line in DC output")
    
    # Parse headers
    header_parts = lines[header_line_idx].split()
    
    if subheader_line_idx:
        subheader_parts = lines[subheader_line_idx].split()
        # Build column names from type + name
        columns = []
        for j, htype in enumerate(header_parts):
            if j < len(subheader_parts):
                name = subheader_parts[j]
                if htype.lower() == 'volt':
                    columns.append(f'v({name})')
                elif htype.lower() == 'current':
                    columns.append(f'i({name})')
                else:
                    columns.append(f'{htype}({name})')
            else:
                columns.append(f'col{j}')
        data_start = subheader_line_idx + 1
    else:
        # Default column names based on expected format
        columns = ['v(ng)', 'i(Vd_sat)', 'i(Vd_lin)', 'i(Vp_sat)', 'i(Vp_lin)']
        data_start = header_line_idx + 1
    
    # Find where data actually starts (first line starting with a number)
    for i in range(data_start, len(lines)):
        line = lines[i].strip()
        if line and re.match(r'^[\-\d\.]', line):
            data_start = i
            break
    
    # Parse data rows
    data = []
    for i in range(data_start, len(lines)):
        line = lines[i].strip()
        
        # Stop at end of data section
        if not line:
            continue
        if line.startswith('y') or line.startswith('*') or line.startswith('$'):
            break
        if 'job' in line.lower() or 'cpu' in line.lower():
            break
        if line.startswith('x'):
            continue
        
        # Split the line into values
        parts = line.split()
        if not parts:
            continue
        
        # Check if first part looks like a number
        if not re.match(r'^[\-\d]', parts[0]):
            continue
        
        try:
            row = [parse_hspice_value(p) for p in parts]
            if all(v is not None for v in row):
                data.append(row)
        except ValueError:
            continue
    
    # Adjust columns to match data width
    if data and len(data[0]) != len(columns):
        num_cols = len(data[0])
        columns = ['v(ng)', 'i(Vd_sat)', 'i(Vd_lin)', 'i(Vp_sat)', 'i(Vp_lin)'][:num_cols]
        while len(columns) < num_cols:
            columns.append(f'col{len(columns)}')
    
    return columns, data

def write_csv(columns, data, output_path=None):
    """Write data to CSV file or stdout."""
    if output_path:
        f = open(output_path, 'w')
    else:
        f = sys.stdout
    
    try:
        # Write header (space-delimited to match ngspice format)
        f.write(' ' + '\t'.join(f'{c:>15}' for c in columns) + '\n')
        # Write data
        for row in data:
            f.write(' ' + '\t'.join(f'{v:>15.8e}' for v in row) + '\n')
    finally:
        if output_path:
            f.close()

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
