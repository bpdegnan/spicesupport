#!/usr/bin/env python3
"""
Plot comparison of DC vs Transient simulations for the same gmin.
Both are plotted against Vg for direct comparison.

Usage:
    python3 plot_dc_vs_trans.py dcnfet/nfetdc.gmin1e-12.host.csv transnfet/nfettrans.gmin1e-12.host.csv
"""

import argparse
import numpy as np
import matplotlib.pyplot as plt
import re
import os

def load_csv(filepath):
    """Load CSV file (comma or whitespace delimited) and extract metadata."""
    with open(filepath, 'r') as f:
        lines = f.readlines()
    
    # Extract metadata from # comments
    metadata = {}
    header_idx = 0
    for i, line in enumerate(lines):
        line_stripped = line.strip()
        if line_stripped.startswith('#'):
            if ':' in line_stripped:
                key, _, value = line_stripped[1:].partition(':')
                metadata[key.strip()] = value.strip()
        elif line_stripped:
            header_idx = i
            break
    
    header_line = lines[header_idx]
    delimiter = ',' if ',' in header_line else None
    
    if delimiter:
        raw_header = [h.strip().replace('-', '_') for h in header_line.split(delimiter)]
    else:
        raw_header = [h.replace('-', '_') for h in header_line.split()]
    
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
                if delimiter:
                    data_lines.append([float(x.strip()) for x in line.split(delimiter)])
                else:
                    data_lines.append([float(x) for x in line.split()])
            except ValueError:
                continue
    
    arr = np.array(data_lines)
    dtype = [(name, float) for name in header]
    data = np.zeros(len(data_lines), dtype=dtype)
    for i, name in enumerate(header):
        if i < arr.shape[1]:
            data[name] = arr[:, i]
    
    return data, header, metadata

def extract_gmin_from_filename(filepath):
    """Extract gmin value from filename."""
    basename = os.path.basename(filepath)
    match = re.match(r'nfet(?:dc|trans)\.(gmin[^.]+)\.', basename)
    if match:
        return match.group(1)
    return None

def find_column(names, patterns):
    """Find first column matching any pattern (case-insensitive)."""
    for pattern in patterns:
        for name in names:
            if pattern.lower() in name.lower():
                return name
    return None

def plot_comparison(dc_file, trans_file, output_file=None):
    """Plot DC vs Transient comparison."""
    
    # Load data
    dc_data, dc_cols, dc_meta = load_csv(dc_file)
    trans_data, trans_cols, trans_meta = load_csv(trans_file)
    
    print(f"DC columns: {dc_cols}")
    print(f"Trans columns: {trans_cols}")
    
    # Extract gmin for output filename
    gmin_str = extract_gmin_from_filename(dc_file) or 'unknown'
    if output_file is None:
        output_file = f'compare.{gmin_str}.png'
    
    # Find columns
    dc_vg_col = find_column(dc_cols, ['v(ng)', 'v_ng'])
    dc_ig_col = find_column(dc_cols, ['i(vg_sense)', 'i_vg_sense'])
    dc_id_col = find_column(dc_cols, ['i(vd_sense)', 'i_vd_sense', 'i(vd)'])
    dc_is_col = find_column(dc_cols, ['i(vs_sense)', 'i_vs_sense'])
    dc_ib_col = find_column(dc_cols, ['i(vb_sense)', 'i_vb_sense'])
    
    trans_vg_col = find_column(trans_cols, ['v(ng)', 'v_ng'])
    trans_ig_col = find_column(trans_cols, ['i(vg_sense)', 'i_vg_sense'])
    trans_id_col = find_column(trans_cols, ['i(vd_sense)', 'i_vd_sense', 'i(vd)'])
    trans_is_col = find_column(trans_cols, ['i(vs_sense)', 'i_vs_sense'])
    trans_ib_col = find_column(trans_cols, ['i(vb_sense)', 'i_vb_sense'])
    
    # Get Vg for x-axis
    dc_vg = dc_data[dc_vg_col] if dc_vg_col else dc_data[dc_cols[0]]
    trans_vg = trans_data[trans_vg_col] if trans_vg_col else None
    
    # If trans doesn't have Vg, derive from time (assuming 0-1.8V over 1ms)
    if trans_vg is None or trans_vg_col is None:
        time_col = find_column(trans_cols, ['time'])
        if time_col:
            trans_time = trans_data[time_col]
            trans_vg = trans_time / 1e-3 * 1.8  # Linear ramp
    
    # Get currents
    dc_id = dc_data[dc_id_col] if dc_id_col else None
    dc_ig = dc_data[dc_ig_col] if dc_ig_col else None
    dc_is = dc_data[dc_is_col] if dc_is_col else None
    dc_ib = dc_data[dc_ib_col] if dc_ib_col else None
    
    trans_id = trans_data[trans_id_col] if trans_id_col else None
    trans_ig = trans_data[trans_ig_col] if trans_ig_col else None
    trans_is = trans_data[trans_is_col] if trans_is_col else None
    trans_ib = trans_data[trans_ib_col] if trans_ib_col else None
    
    # Create figure
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))
    (ax_id, ax_ig), (ax_is, ax_ib) = axes
    
    # Plot each terminal current
    terminals = [
        (ax_id, 'Id (drain)', dc_id, trans_id),
        (ax_ig, 'Ig (gate)', dc_ig, trans_ig),
        (ax_is, 'Is (source)', dc_is, trans_is),
        (ax_ib, 'Ib (bulk)', dc_ib, trans_ib),
    ]
    
    for ax, title, dc_curr, trans_curr in terminals:
        if dc_curr is not None:
            # DC: solid lines
            dc_pos = np.where(dc_curr > 0, dc_curr, np.nan)
            dc_neg = np.where(dc_curr < 0, -dc_curr, np.nan)
            ax.semilogy(dc_vg, dc_pos, '-', color='blue', linewidth=1.5, label='DC +')
            ax.semilogy(dc_vg, dc_neg, '--', color='blue', linewidth=1.5, label='DC −')
        
        if trans_curr is not None:
            # Transient: dashed lines with different color
            trans_pos = np.where(trans_curr > 0, trans_curr, np.nan)
            trans_neg = np.where(trans_curr < 0, -trans_curr, np.nan)
            ax.semilogy(trans_vg, trans_pos, '-', color='red', linewidth=1.5, label='Trans +')
            ax.semilogy(trans_vg, trans_neg, '--', color='red', linewidth=1.5, label='Trans −')
        
        ax.set_xlabel('Vg (V)')
        ax.set_ylabel('|I| (A)')
        ax.set_title(title)
        ax.grid(True, which='both', linestyle='--', alpha=0.5)
        ax.set_xlim(0, 1.8)
        ax.set_ylim(1e-14, 1e-2)
        ax.legend(loc='best', fontsize=8)
    
    # Build title with metadata
    gmin_val = dc_meta.get('gmin', gmin_str)
    hostname = dc_meta.get('hostname', 'unknown')
    fig.suptitle(f'DC vs Transient Comparison — {gmin_str} — {hostname}', fontsize=12)
    
    # Add metadata text
    meta_text = f"DC: {os.path.basename(dc_file)}\nTrans: {os.path.basename(trans_file)}"
    fig.text(0.02, 0.01, meta_text, fontsize=8, family='monospace',
            verticalalignment='bottom', alpha=0.7)
    
    plt.tight_layout()
    plt.subplots_adjust(top=0.93, bottom=0.08)
    plt.savefig(output_file, dpi=150)
    print(f"\nSaved {output_file}")
    plt.show()

def main():
    parser = argparse.ArgumentParser(description='Compare DC vs Transient simulations')
    parser.add_argument('dc_file', help='DC simulation CSV file')
    parser.add_argument('trans_file', help='Transient simulation CSV file')
    parser.add_argument('-o', '--output', default=None, help='Output PNG file')
    args = parser.parse_args()
    
    plot_comparison(args.dc_file, args.trans_file, args.output)

if __name__ == '__main__':
    main()
