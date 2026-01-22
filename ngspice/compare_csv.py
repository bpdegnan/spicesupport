#!/usr/bin/env python3
"""
Compare two SPICE CSV files (DC vs transient, or any two datasets).

Usage:
    python3 compare_csv.py file1.csv file2.csv [-o output.png]
    python3 compare_csv.py nfetgatesweep.csv nfettrans.csv -o comparison.png

The script uses Vg (gate voltage) as the common x-axis and compares drain currents.
"""

import argparse
import numpy as np
import matplotlib.pyplot as plt
import re
import os

def load_csv(filepath):
    """Load space/tab delimited CSV file."""
    with open(filepath, 'r') as f:
        lines = f.readlines()
    
    header_idx = 0
    for i, line in enumerate(lines):
        if line.strip() and not line.strip().startswith('#'):
            header_idx = i
            break
    
    raw_header = [h.replace('-', '_') for h in lines[header_idx].split()]
    
    # Handle duplicate column names
    header = []
    seen = {}
    for h in raw_header:
        if h in seen:
            seen[h] += 1
            header.append(f"{h}_{seen[h]}")
        else:
            seen[h] = 0
            header.append(h)
    
    data_lines = []
    for line in lines[header_idx + 1:]:
        line = line.strip()
        if line and not line.startswith('#') and re.match(r'^[\-\d\.]', line):
            try:
                data_lines.append([float(x) for x in line.split()])
            except ValueError:
                continue
    
    arr = np.array(data_lines)
    dtype = [(name, float) for name in header]
    data = np.zeros(len(data_lines), dtype=dtype)
    for i, name in enumerate(header):
        if i < arr.shape[1]:
            data[name] = arr[:, i]
    
    return data, header

def find_column(data, patterns):
    """Find first column matching any pattern."""
    for pattern in patterns:
        for name in data.dtype.names:
            if pattern.lower() in name.lower():
                return name
    return None

def get_label(filepath):
    """Extract a nice label from filepath."""
    basename = os.path.basename(filepath)
    # Remove extension
    name = os.path.splitext(basename)[0]
    return name

def extract_vg_and_id(data, header):
    """Extract gate voltage and drain current from dataset."""
    vg_patterns = ['v(ng)', 'v_ng', 'vng']
    id_patterns = ['i(vd)', 'i(Vd)', 'i_vd', 'ivd', 'i(vd_sat)', 'i(Vd_sat)']
    
    # Find Vg column
    vg_col = find_column(data, vg_patterns)
    if vg_col is None:
        # Try second column (often v(ng) after v-sweep or time)
        vg_col = header[1] if len(header) > 1 else header[0]
    
    # Find Id column
    id_col = find_column(data, id_patterns)
    if id_col is None:
        # Try third column
        id_col = header[2] if len(header) > 2 else header[-1]
    
    vg = data[vg_col]
    id_curr = np.abs(data[id_col])
    
    return vg, id_curr, vg_col, id_col

def plot_comparison(file1, file2, output_file='comparison.png'):
    """Plot comparison between two CSV files."""
    
    # Load data
    data1, header1 = load_csv(file1)
    data2, header2 = load_csv(file2)
    
    label1 = get_label(file1)
    label2 = get_label(file2)
    
    print(f"File 1: {file1}")
    print(f"  Columns: {header1}")
    print(f"File 2: {file2}")
    print(f"  Columns: {header2}")
    
    # Extract Vg and Id
    vg1, id1, vg1_col, id1_col = extract_vg_and_id(data1, header1)
    vg2, id2, vg2_col, id2_col = extract_vg_and_id(data2, header2)
    
    print(f"\nFile 1: using {vg1_col} for Vg, {id1_col} for Id")
    print(f"  Vg range: [{vg1.min():.4f}, {vg1.max():.4f}] V")
    print(f"  Id range: [{id1.min():.3e}, {id1.max():.3e}] A")
    
    print(f"File 2: using {vg2_col} for Vg, {id2_col} for Id")
    print(f"  Vg range: [{vg2.min():.4f}, {vg2.max():.4f}] V")
    print(f"  Id range: [{id2.min():.3e}, {id2.max():.3e}] A")
    
    # Create figure
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 10))
    
    # Plot 1: Overlay comparison (semilog)
    ax1.semilogy(vg1, id1, 'b-', linewidth=2, label=label1)
    ax1.semilogy(vg2, id2, 'r--', linewidth=1.5, alpha=0.8, label=label2)
    ax1.set_xlabel('Vgs (V)')
    ax1.set_ylabel('|Id| (A)')
    ax1.set_title('Current Comparison (semilog)')
    ax1.legend(loc='lower right')
    ax1.grid(True, which='both', linestyle='--', alpha=0.5)
    ax1.set_xlim(0, max(vg1.max(), vg2.max()))
    ax1.set_ylim(1e-14, 1e-2)
    
    # Plot 2: Difference
    # Interpolate file2 to file1's Vg points
    id2_interp = np.interp(vg1, vg2, id2)
    
    # Calculate percent difference
    with np.errstate(divide='ignore', invalid='ignore'):
        pct_diff = 100 * (id2_interp - id1) / id1
        pct_diff = np.where(np.isfinite(pct_diff), pct_diff, 0)
    
    ax2.plot(vg1, pct_diff, 'g-', linewidth=1.5)
    ax2.set_xlabel('Vgs (V)')
    ax2.set_ylabel('Difference (%)')
    ax2.set_title(f'Percent Difference: ({label2} - {label1}) / {label1}')
    ax2.grid(True, linestyle='--', alpha=0.5)
    ax2.set_xlim(0, vg1.max())
    ax2.axhline(y=0, color='black', linestyle='-', linewidth=0.5)
    
    # Add some stats
    max_diff_idx = np.argmax(np.abs(pct_diff))
    max_diff = pct_diff[max_diff_idx]
    max_diff_vg = vg1[max_diff_idx]
    
    print(f"\n=== Statistics ===")
    print(f"Max difference: {max_diff:.2f}% at Vg = {max_diff_vg:.4f} V")
    print(f"Mean difference: {np.mean(pct_diff):.2f}%")
    print(f"Std difference: {np.std(pct_diff):.2f}%")
    
    # Annotate max difference
    ax2.annotate(f'Max: {max_diff:.1f}%\nat Vg={max_diff_vg:.3f}V', 
                xy=(max_diff_vg, max_diff), 
                xytext=(max_diff_vg + 0.2, max_diff),
                fontsize=9,
                arrowprops=dict(arrowstyle='->', color='red', lw=0.5))
    
    plt.tight_layout()
    plt.savefig(output_file, dpi=150)
    print(f"\nSaved {output_file}")
    plt.close()

def main():
    parser = argparse.ArgumentParser(description='Compare two SPICE CSV files')
    parser.add_argument('file1', help='First CSV file (reference)')
    parser.add_argument('file2', help='Second CSV file')
    parser.add_argument('-o', '--output', default='comparison.png', 
                       help='Output PNG file (default: comparison.png)')
    
    args = parser.parse_args()
    
    if not os.path.exists(args.file1):
        print(f"Error: {args.file1} not found")
        return 1
    if not os.path.exists(args.file2):
        print(f"Error: {args.file2} not found")
        return 1
    
    plot_comparison(args.file1, args.file2, args.output)
    return 0

if __name__ == '__main__':
    exit(main())
