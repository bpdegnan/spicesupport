#!/usr/bin/env python3
"""
Parse HSPICE .out file and convert DC sweep analysis data to CSV.

Handles HSPICE's paginated output format where columns are split across
multiple sections when there are many output variables.

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
    """Parse HSPICE .out file and extract DC sweep data.
    
    Handles paginated output where columns are split across multiple sections.
    """
    with open(filepath, 'r') as f:
        lines = f.readlines()
    
    # Find all header sections (start of each page)
    # Header pattern: line with "volt" and/or "voltage" and/or "current"
    sections = []
    i = 0
    while i < len(lines):
        line = lines[i].strip().lower()
        # Look for header line with type indicators
        if re.match(r'^(volt(age)?|current)(\s+(volt(age)?|current))*\s*$', line):
            # Found a header line
            header_types = lines[i].split()
            
            # Next line should have column names
            i += 1
            if i >= len(lines):
                break
            subheader_line = lines[i]
            subheader_parts = subheader_line.split()
            
            # Build column info for this section
            # First column type may not have a name (it's the sweep variable)
            columns = []
            for j, htype in enumerate(header_types):
                htype_lower = htype.lower()
                if j < len(subheader_parts):
                    name = subheader_parts[j]
                else:
                    name = f'col{j}'
                
                if htype_lower in ('volt', 'voltage'):
                    columns.append(f'v({name})')
                else:  # current
                    columns.append(f'i({name})')
            
            # If subheader has fewer parts, the first column name is implicit (sweep var)
            # Check if first subheader entry aligns with types
            if len(subheader_parts) < len(header_types):
                # First column has no name - it's the sweep variable
                # Shift names to align
                columns = ['sweep']
                for j, htype in enumerate(header_types[1:], 0):
                    htype_lower = htype.lower()
                    if j < len(subheader_parts):
                        name = subheader_parts[j]
                    else:
                        name = f'col{j+1}'
                    if htype_lower in ('volt', 'voltage'):
                        columns.append(f'v({name})')
                    else:
                        columns.append(f'i({name})')
            
            # Skip to data
            i += 1
            
            # Parse data rows until we hit end markers
            data_rows = []
            while i < len(lines):
                data_line = lines[i].strip()
                
                # End markers
                if not data_line:
                    i += 1
                    continue
                if data_line.lower().startswith(('y', 'x', '*', '$', '>')):
                    break
                if 'job' in data_line.lower():
                    break
                if not re.match(r'^[\-\d]', data_line):
                    break
                
                # Parse data row
                try:
                    parts = data_line.split()
                    row = [parse_hspice_value(p) for p in parts]
                    if all(v is not None for v in row):
                        data_rows.append(row)
                except (ValueError, IndexError):
                    pass
                
                i += 1
            
            if data_rows:
                sections.append({
                    'columns': columns,
                    'data': data_rows
                })
        else:
            i += 1
    
    if not sections:
        raise ValueError("Could not find any data sections in HSPICE output")
    
    # Merge sections by sweep value (first column)
    # First section defines the sweep values
    primary = sections[0]
    sweep_values = [row[0] for row in primary['data']]
    
    # Build merged data
    # Start with all columns from first section
    all_columns = primary['columns'][:]
    merged_data = [row[:] for row in primary['data']]
    
    # Add columns from subsequent sections (skip their sweep column)
    for section in sections[1:]:
        # Add new column names (skip 'sweep' which is first)
        for col in section['columns'][1:]:
            all_columns.append(col)
        
        # Build lookup by sweep value for this section
        section_lookup = {}
        for row in section['data']:
            sweep_val = row[0]
            section_lookup[sweep_val] = row[1:]  # Skip sweep column
        
        # Merge into primary data
        for j, sweep_val in enumerate(sweep_values):
            if sweep_val in section_lookup:
                merged_data[j].extend(section_lookup[sweep_val])
            else:
                # Find closest match (floating point tolerance)
                matched = False
                for sv, vals in section_lookup.items():
                    if abs(sv - sweep_val) < 1e-12:
                        merged_data[j].extend(vals)
                        matched = True
                        break
                if not matched:
                    # Fill with NaN
                    merged_data[j].extend([float('nan')] * (len(section['columns']) - 1))
    
    # Clean up column names
    # Replace 'sweep' with proper name if we can infer it
    if all_columns[0] == 'sweep' and len(all_columns) > 1:
        # First voltage column after sweep is usually the sweep variable
        all_columns[0] = 'v(sweep)'
    
    return all_columns, merged_data

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
    print(f"Columns ({len(columns)}): {columns}", file=sys.stderr)
    
    if len(data) == 0:
        print("Warning: No data found!", file=sys.stderr)
        sys.exit(1)
    
    write_csv(columns, data, output_file)
    print(f"Wrote {output_file}", file=sys.stderr)

if __name__ == '__main__':
    main()
