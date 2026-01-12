#!/usr/bin/env python3
"""
Plot HSPICE and/or ngspice PFET drain sweep (Id-Vds) results.

Usage:
    python3 plot_pfet_drainsweep_comparison.py --ngspice pfet_drainsweep_ngspice.csv
    python3 plot_pfet_drainsweep_comparison.py --hspice pfet_drainsweep_hspice.csv
    python3 plot_pfet_drainsweep_comparison.py --hspice pfet_drainsweep_hspice.csv --ngspice pfet_drainsweep_ngspice.csv
"""

import argparse
import numpy as np
import matplotlib.pyplot as plt
import re

# |Vgs| overdrive values used (Vgs values were 1.2, 0.9, 0.6, 0.3, 0)
VGS_OVERDRIVE = [0.6, 0.9, 1.2, 1.5, 1.8]
VDD = 1.8

def load_csv(filepath):
    """Load space/tab delimited CSV file."""
    with open(filepath, 'r') as f:
        lines = f.readlines()
    
    header_idx = 0
    for i, line in enumerate(lines):
        if line.strip() and not line.strip().startswith('#'):
            header_idx = i
            break
    
    header = [h.replace('-', '_') for h in lines[header_idx].split()]
    
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
    
    return data

def find_column(data, patterns):
    for pattern in patterns:
        for name in data.dtype.names:
            if pattern.lower() in name.lower():
                return name
    return None

def plot_comparison(hspice_file=None, ngspice_file=None, output_file='pfet_drainsweep_comparison.png'):
    """Plot PFET Id-Vds comparison."""
    
    fig, ax = plt.subplots(figsize=(10, 7))
    has_data = False
    
    vd_patterns = ['v(nd)', 'v_nd', 'vnd', 'v_sweep']
    
    # Colors for different |Vgs| values
    colors = ['blue', 'green', 'orange', 'red', 'purple']
    
    def plot_dataset(data, label_prefix, linestyle='-', alpha=1.0):
        nonlocal has_data
        col_names = list(data.dtype.names)
        print(f"{label_prefix} columns: {col_names}")
        
        # Find Vd column
        vd_col = find_column(data, vd_patterns)
        if vd_col is None:
            vd_col = col_names[1] if len(col_names) > 1 else col_names[0]
        vd = data[vd_col]
        
        # Calculate |Vds| = VDD - Vd
        vds_abs = VDD - vd
        
        # Find current columns and plot each
        for i, vgs_od in enumerate(VGS_OVERDRIVE):
            patterns = [f'i(vam_{i+1})', f'i_vam_{i+1}', f'ivam_{i+1}']
            col = find_column(data, patterns)
            if col is None and len(col_names) > i + 2:
                col = col_names[i + 2]
            
            if col:
                current = np.abs(data[col])
                ax.plot(vds_abs, current * 1e6, color=colors[i], linestyle=linestyle,
                       linewidth=2, alpha=alpha, label=f'{label_prefix} |Vgs|={vgs_od}V')
                has_data = True
    
    if hspice_file:
        try:
            hdata = load_csv(hspice_file)
            plot_dataset(hdata, 'HSPICE', '-', 1.0)
        except Exception as e:
            print(f"Warning: Could not load HSPICE data: {e}")
    
    if ngspice_file:
        try:
            ndata = load_csv(ngspice_file)
            ls = '--' if hspice_file else '-'
            plot_dataset(ndata, 'ngspice', ls, 0.9 if hspice_file else 1.0)
        except Exception as e:
            print(f"Warning: Could not load ngspice data: {e}")
    
    if not has_data:
        print("Error: No data to plot")
        return
    
    ax.set_xlabel('|Vds| (V)')
    ax.set_ylabel('|Id| (µA)')
    title = 'PFET Id-Vds Characterization'
    if hspice_file and ngspice_file:
        title += ': HSPICE vs ngspice'
    ax.set_title(title)
    ax.legend(loc='upper left', ncol=2)
    ax.grid(True, linestyle='--', alpha=0.5)
    ax.set_xlim(0, 1.8)
    ax.set_ylim(bottom=0)
    
    plt.tight_layout()
    plt.savefig(output_file, dpi=150)
    print(f"Saved {output_file}")
    plt.close()

def main():
    parser = argparse.ArgumentParser(description='Plot PFET Id-Vds drain sweep comparison')
    parser.add_argument('--hspice', '-H', help='HSPICE CSV file')
    parser.add_argument('--ngspice', '-N', help='ngspice CSV file')
    parser.add_argument('-o', '--output', default='pfet_drainsweep_comparison.png', help='Output PNG file')
    
    args = parser.parse_args()
    
    if not args.hspice and not args.ngspice:
        parser.error("At least one of --hspice or --ngspice is required")
    
    plot_comparison(args.hspice, args.ngspice, args.output)

if __name__ == '__main__':
    main()
