#!/usr/bin/env python3
"""
Plot NFET transient gatesweep with all terminal currents.
Supports comparison across multiple hosts.

Usage:
    python3 plot_transient_currents.py nfettrans.host1.csv
    python3 plot_transient_currents.py nfettrans.*.csv -o comparison.png
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
            # Parse "# key: value" format
            if ':' in line_stripped:
                key, _, value = line_stripped[1:].partition(':')
                metadata[key.strip()] = value.strip()
        elif line_stripped:
            header_idx = i
            break
    
    # Detect delimiter
    header_line = lines[header_idx]
    delimiter = ',' if ',' in header_line else None  # None = whitespace
    
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

def extract_hostname(filepath):
    """Extract hostname from filename like nfettrans.hostname.csv"""
    basename = os.path.basename(filepath)
    match = re.match(r'nfettrans\.(.+)\.csv', basename)
    if match:
        return match.group(1)
    return os.path.splitext(basename)[0]

def find_column(names, patterns):
    """Find first column matching any pattern (case-insensitive)."""
    for pattern in patterns:
        for name in names:
            if pattern.lower() in name.lower():
                return name
    return None

def plot_terminal_currents(csv_files, output_file='nfettrans_currents.png'):
    """Plot all terminal currents from transient simulation."""
    
    n_files = len(csv_files)
    colors = plt.cm.tab10(np.linspace(0, 1, max(n_files, 2)))
    
    fig, (ax_curr, ax_kcl) = plt.subplots(2, 1, figsize=(12, 8))
    
    # Colors for each terminal
    term_colors = {'ig': 'green', 'id': 'red', 'is': 'blue', 'ib': 'purple'}
    term_labels = {'ig': 'Ig (gate)', 'id': 'Id (drain)', 'is': 'Is (source)', 'ib': 'Ib (bulk)'}
    
    all_data = {}
    all_metadata = {}
    
    for file_idx, filepath in enumerate(csv_files):
        hostname = extract_hostname(filepath)
        color = colors[file_idx]
        
        try:
            data, col_names, metadata = load_csv(filepath)
            all_metadata[hostname] = metadata
            print(f"{hostname}: {col_names}")
            if metadata:
                for k, v in metadata.items():
                    print(f"  {k}: {v}")
            
            time_col = find_column(col_names, ['time'])
            ig_col = find_column(col_names, ['i(vg_sense)', 'i_vg_sense', 'i(vsense_g)'])
            id_col = find_column(col_names, ['i(vd_sense)', 'i_vd_sense', 'i(vsense_d)', 'i(vd)'])
            is_col = find_column(col_names, ['i(vs_sense)', 'i_vs_sense', 'i(vsense_s)'])
            ib_col = find_column(col_names, ['i(vb_sense)', 'i_vb_sense', 'i(vsense_b)'])
            
            if time_col is None:
                time_col = col_names[0]
            
            time_us = data[time_col] * 1e6
            ig = data[ig_col] if ig_col else None
            id_ = data[id_col] if id_col else None
            is_ = data[is_col] if is_col else None
            ib = data[ib_col] if ib_col else None
            
            all_data[hostname] = {
                'time': time_us, 'ig': ig, 'id': id_, 'is': is_, 'ib': ib
            }
            
            host_suffix = f' ({hostname})' if n_files > 1 else ''
            
            # Plot all terminal currents on semilogy
            # Solid = positive, dashed = negative
            for term, curr in [('ig', ig), ('id', id_), ('is', is_), ('ib', ib)]:
                if curr is not None:
                    curr_pos = np.where(curr > 0, curr, np.nan)
                    curr_neg = np.where(curr < 0, -curr, np.nan)
                    ax_curr.semilogy(time_us, curr_pos, '-', 
                                    color=term_colors[term], linewidth=1.5,
                                    label=f'{term_labels[term]} +{host_suffix}')
                    ax_curr.semilogy(time_us, curr_neg, '--', 
                                    color=term_colors[term], linewidth=1.5,
                                    label=f'{term_labels[term]} −{host_suffix}')
            
            # KCL
            if all(x is not None for x in [ig, id_, is_, ib]):
                kcl = ig + id_ + is_ + ib
                ax_kcl.semilogy(time_us, np.abs(kcl), color=color, linewidth=1.5, 
                           label=hostname if n_files > 1 else '|Ig+Id+Is+Ib|')
                print(f"  KCL max error: {np.max(np.abs(kcl)):.2e} A")
            
        except Exception as e:
            print(f"Error loading {filepath}: {e}")
            import traceback
            traceback.print_exc()
    
    # Build metadata text for figure
    meta_lines = []
    for hostname, meta in all_metadata.items():
        parts = [hostname]
        if 'ngspice' in meta:
            # Extract just version number
            ver = meta['ngspice'].split()[0] if meta['ngspice'] else ''
            parts.append(f"ngspice {ver}")
        if 'gmin' in meta:
            parts.append(f"gmin={meta['gmin']}")
        if 'source' in meta:
            parts.append(meta['source'])
        if 'note' in meta:
            parts.append(f"[{meta['note']}]")
        meta_lines.append(', '.join(parts))
    
    # Format
    ax_curr.set_xlabel('Time (µs)')
    ax_curr.set_ylabel('|I| (A)')
    ax_curr.set_title('Terminal Currents')
    ax_curr.grid(True, which='both', linestyle='--', alpha=0.5)
    ax_curr.set_xlim(0, 1000)
    ax_curr.set_ylim(1e-14, 1e-2)
    ax_curr.legend(loc='best', fontsize=8, ncol=2)
    
    ax_kcl.set_xlabel('Time (µs)')
    ax_kcl.set_ylabel('|Ig + Id + Is + Ib| (A)')
    ax_kcl.set_title('KCL Check (should be ~0)')
    ax_kcl.grid(True, which='both', linestyle='--', alpha=0.5)
    ax_kcl.set_xlim(0, 1000)
    ax_kcl.legend(loc='best')
    
    # Add metadata as figure text at bottom
    if meta_lines:
        meta_text = '\n'.join(meta_lines)
        fig.text(0.02, 0.01, meta_text, fontsize=8, family='monospace',
                verticalalignment='bottom', alpha=0.7)
    
    plt.tight_layout()
    plt.subplots_adjust(bottom=0.08 + 0.02 * len(meta_lines))  # Make room for metadata
    plt.savefig(output_file, dpi=150)
    print(f"\nSaved {output_file}")
    plt.show()

def main():
    parser = argparse.ArgumentParser(description='Plot NFET terminal currents')
    parser.add_argument('csv_files', nargs='+', help='CSV files to plot')
    parser.add_argument('-o', '--output', default='nfettrans_currents.png',
                       help='Output PNG file')
    args = parser.parse_args()
    plot_terminal_currents(args.csv_files, args.output)

if __name__ == '__main__':
    main()
