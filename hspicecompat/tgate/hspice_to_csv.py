#!/usr/bin/env python3
"""
Parse HSPICE .out file and convert AC analysis data to CSV.

Usage:
    python3 hspice_to_csv.py hspice.out [output.csv]
    
If output.csv is not specified, outputs to stdout or hspice.out.csv
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

def parse_hspice_output(filepath):
    """
    Parse HSPICE .out file and extract AC analysis data.
    Returns: (column_names, data_rows)
    """
    with open(filepath, 'r') as f:
        lines = f.readlines()
    
    # Find the AC analysis section
    ac_start = None
    for i, line in enumerate(lines):
        if 'ac analysis' in line.lower() and 'tnom' in line.lower():
            ac_start = i
            break
    
    if ac_start is None:
        raise ValueError("Could not find AC analysis section")
    
    # Find the header lines (freq, volt db, etc.)
    header_line = None
    subheader_line = None
    data_start = None
    
    for i in range(ac_start, min(ac_start + 20, len(lines))):
        line = lines[i]
        if 'freq' in line.lower():
            header_line = i
            # Next non-empty line should be the node names
            for j in range(i + 1, i + 5):
                if lines[j].strip() and not lines[j].strip().startswith('x'):
                    # Check if it's a data line or subheader
                    if re.match(r'\s*\d', lines[j]):
                        # It's a data line
                        data_start = j
                        break
                    else:
                        subheader_line = j
            break
    
    if header_line is None:
        raise ValueError("Could not find header line")
    
    # Parse header to get column names
    header = lines[header_line]
    if subheader_line:
        subheader = lines[subheader_line]
        # Combine header types with node names
        # "freq  volt db  volt db  volt phase  volt phase"
        # "      out1     out2     out1        out2"
        header_parts = header.split()
        subheader_parts = subheader.split()
        
        columns = ['freq']
        sub_idx = 0
        i = 1
        while i < len(header_parts):
            if header_parts[i] == 'volt' and i + 1 < len(header_parts):
                col_type = header_parts[i + 1]  # 'db' or 'phase'
                if sub_idx < len(subheader_parts):
                    node = subheader_parts[sub_idx]
                    if col_type == 'db':
                        columns.append(f'vdb_{node}')
                    elif col_type == 'phase':
                        columns.append(f'vp_{node}')
                    else:
                        columns.append(f'{col_type}_{node}')
                    sub_idx += 1
                i += 2
            else:
                i += 1
        data_start = subheader_line + 1
    else:
        columns = ['freq', 'vdb_out1', 'vdb_out2', 'vp_out1', 'vp_out2']
    
    # Find where data actually starts (first line with a number)
    for i in range(data_start if data_start else header_line + 1, len(lines)):
        line = lines[i].strip()
        if line and re.match(r'[\d\s\-\.]', line):
            data_start = i
            break
    
    # Parse data rows
    data = []
    for i in range(data_start, len(lines)):
        line = lines[i].strip()
        
        # Stop at end of data section
        if not line or line.startswith('y') or line.startswith('*') or 'job' in line.lower():
            break
        
        # Split the line into values
        parts = line.split()
        if not parts:
            continue
        
        # Check if first part looks like a number (possibly with suffix)
        if not re.match(r'^[\-\d]', parts[0]):
            continue
        
        try:
            row = [parse_hspice_value(p) for p in parts]
            if all(v is not None for v in row):
                data.append(row)
        except ValueError:
            continue
    
    return columns, data

def write_csv(columns, data, output_path=None):
    """Write data to CSV file or stdout."""
    import csv
    
    if output_path:
        f = open(output_path, 'w', newline='')
    else:
        f = sys.stdout
    
    try:
        writer = csv.writer(f)
        writer.writerow(columns)
        for row in data:
            writer.writerow(row)
    finally:
        if output_path:
            f.close()

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 hspice_to_csv.py <hspice.out> [output.csv]", file=sys.stderr)
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else input_file.replace('.out', '.csv')
    
    print(f"Parsing {input_file}...", file=sys.stderr)
    columns, data = parse_hspice_output(input_file)
    
    print(f"Found {len(data)} data points", file=sys.stderr)
    print(f"Columns: {columns}", file=sys.stderr)
    
    write_csv(columns, data, output_file)
    print(f"Wrote {output_file}", file=sys.stderr)

if __name__ == '__main__':
    main()
