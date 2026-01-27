#!/usr/bin/env python3
"""
Plot NFET DC gatesweep with all terminal currents.
Supports comparison across multiple hosts.

Usage:
    python3 plot_dc_currents.py nfetdc.host1.csv
    python3 plot_dc_currents.py nfetdc.*.csv -o comparison.png
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
    """Extract hostname from filename like nfetdc.gminXX.hostname.csv or nfetdc.hostname.csv"""
    basename = os.path.basename(filepath)
    # Try new format: nfetdc.gminXX.hostname.csv
    match = re.match(r'nfetdc\.gmin[^.]+\.(.+)\.csv', basename)
    if match:
        return match.group(1)
    # Try old format: nfetdc.hostname.csv
    match = re.match(r'nfetdc\.(.+)\.csv', basename)
    if match:
        return match.group(1)
    return os.path.splitext(basename)[0]

def extract_gmin_from_filename(filepath):
    """Extract gmin value from filename like nfetdc.gminXX.hostname.csv"""
    basename = os.path.basename(filepath)
    match = re.match(r'nfetdc\.(gmin[^.]+)\.', basename)
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

def plot_dc_currents(csv_files, output_file='nfetdc_currents.png'):
    """Plot all terminal currents from DC simulation."""
    
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
            
            vg_col = find_column(col_names, ['v(ng)', 'v_ng'])
            ig_col = find_column(col_names, ['i(vg_sense)', 'i_vg_sense', 'i(vsense_g)'])
            id_col = find_column(col_names, ['i(vd_sense)', 'i_vd_sense', 'i(vsense_d)', 'i(vd)'])
            is_col = find_column(col_names, ['i(vs_sense)', 'i_vs_sense', 'i(vsense_s)'])
            ib_col = find_column(col_names, ['i(vb_sense)', 'i_vb_sense', 'i(vsense_b)'])
            
            if vg_col is None:
                vg_col = col_names[0]
            
            vg = data[vg_col]
            ig = data[ig_col] if ig_col else None
            id_ = data[id_col] if id_col else None
            is_ = data[is_col] if is_col else None
            ib = data[ib_col] if ib_col else None
            
            all_data[hostname] = {
                'vg': vg, 'ig': ig, 'id': id_, 'is': is_, 'ib': ib
            }
            
            # Plot all terminal currents on semilogy
            # Solid = positive, dashed = negative
            for term, curr in [('ig', ig), ('id', id_), ('is', is_), ('ib', ib)]:
                if curr is not None:
                    curr_pos = np.where(curr > 0, curr, np.nan)
                    curr_neg = np.where(curr < 0, -curr, np.nan)
                    # Only add label on first file to avoid duplicates
                    label_pos = f'{term_labels[term]} +' if file_idx == 0 else None
                    label_neg = f'{term_labels[term]} −' if file_idx == 0 else None
                    ax_curr.semilogy(vg, curr_pos, '-', 
                                    color=term_colors[term], linewidth=1.5,
                                    label=label_pos)
                    ax_curr.semilogy(vg, curr_neg, '--', 
                                    color=term_colors[term], linewidth=1.5,
                                    label=label_neg)
            
            # KCL
            if all(x is not None for x in [ig, id_, is_, ib]):
                kcl = ig + id_ + is_ + ib
                # Only label on first file
                kcl_label = '|Ig+Id+Is+Ib|' if file_idx == 0 else None
                ax_kcl.semilogy(vg, np.abs(kcl), color=color, linewidth=1.5, 
                           label=kcl_label)
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
    ax_curr.set_xlabel('Vg (V)')
    ax_curr.set_ylabel('|I| (A)')
    ax_curr.set_title('Terminal Currents (DC)')
    ax_curr.grid(True, which='both', linestyle='--', alpha=0.5)
    ax_curr.set_xlim(0, 1.8)
    ax_curr.set_ylim(1e-14, 1e-2)
    ax_curr.legend(loc='best', fontsize=8, ncol=2)
    
    ax_kcl.set_xlabel('Vg (V)')
    ax_kcl.set_ylabel('|Ig + Id + Is + Ib| (A)')
    ax_kcl.set_title('KCL Check (should be ~0)')
    ax_kcl.grid(True, which='both', linestyle='--', alpha=0.5)
    ax_kcl.set_xlim(0, 1.8)
    ax_kcl.legend(loc='best')
    
    # Add metadata as figure text at bottom
    if meta_lines:
        meta_text = '\n'.join(meta_lines)
        fig.text(0.02, 0.01, meta_text, fontsize=8, family='monospace',
                verticalalignment='bottom', alpha=0.7)
    
    plt.tight_layout()
    plt.subplots_adjust(bottom=0.08 + 0.02 * len(meta_lines))  # Make room for metadata
    # plt.savefig(output_file, dpi=150)
    # print(f"\nSaved {output_file}")
    plt.show()

def main():
    parser = argparse.ArgumentParser(description='Plot NFET DC terminal currents')
    parser.add_argument('csv_files', nargs='+', help='CSV files to plot')
    parser.add_argument('-o', '--output', default=None,
                       help='Output PNG file (default: auto from gmin)')
    args = parser.parse_args()
    
    # Auto-generate output filename from first CSV file's gmin metadata
    if args.output is None:
        # Read metadata from first file to get gmin
        try:
            _, _, metadata = load_csv(args.csv_files[0])
            gmin_val = metadata.get('gmin', None)
            if gmin_val:
                args.output = f'nfetdc.gmin{gmin_val}.png'
            else:
                # Fall back to filename extraction
                gmin_str = extract_gmin_from_filename(args.csv_files[0])
                if gmin_str:
                    args.output = f'nfetdc.{gmin_str}.png'
                else:
                    args.output = 'nfetdc_currents.png'
        except Exception:
            args.output = 'nfetdc_currents.png'
    
    plot_dc_currents(args.csv_files, args.output)

if __name__ == '__main__':
    main()
