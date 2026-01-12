#!/usr/bin/env python3
"""
Plot HSPICE and/or ngspice PFET gate sweep (Id-Vgs) results.

Usage:
    python3 plot_pfet_comparison.py --ngspice pfet_ngspice.csv
    python3 plot_pfet_comparison.py --hspice pfet_hspice.csv
    python3 plot_pfet_comparison.py --hspice pfet_hspice.csv --ngspice pfet_ngspice.csv
"""

import argparse
import numpy as np
import matplotlib.pyplot as plt
import re

def load_csv(filepath):
    """Load space/tab delimited CSV file."""
    with open(filepath, 'r') as f:
        lines = f.readlines()
    
    # Find header
    header_idx = 0
    for i, line in enumerate(lines):
        if line.strip() and not line.strip().startswith('#'):
            header_idx = i
            break
    
    header = [h.replace('-', '_') for h in lines[header_idx].split()]
    
    # Read data
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
    """Find first column matching any pattern."""
    for pattern in patterns:
        for name in data.dtype.names:
            if pattern.lower() in name.lower():
                return name
    return None

def plot_comparison(hspice_file=None, ngspice_file=None, output_file='pfet_comparison.png'):
    """Plot PFET Id-Vgs comparison."""
    
    fig, ax = plt.subplots(figsize=(10, 7))
    has_data = False
    
    vgs_patterns = ['v(ng)', 'v_ng', 'vng', 'v_sweep']
    sat_patterns = ['i(vp_sat)', 'i(Vp_sat)', 'i_vp_sat']
    lin_patterns = ['i(vp_lin)', 'i(Vp_lin)', 'i_vp_lin']
    
    def plot_dataset(data, label, colors, linestyle='-'):
        nonlocal has_data
        col_names = list(data.dtype.names)
        print(f"{label} columns: {col_names}")
        
        # Find Vgs (use second column, first is often v-sweep)
        vgs_col = find_column(data, vgs_patterns)
        if vgs_col is None:
            vgs_col = col_names[1] if len(col_names) > 1 else col_names[0]
        vgs = data[vgs_col]
        
        # Find current columns
        sat_col = find_column(data, sat_patterns) or (col_names[2] if len(col_names) > 2 else None)
        lin_col = find_column(data, lin_patterns) or (col_names[3] if len(col_names) > 3 else None)
        
        if sat_col:
            ax.semilogy(vgs, np.abs(data[sat_col]), color=colors[0], linestyle=linestyle,
                       linewidth=2, label=f'{label} |Vds|=1.8V')
            has_data = True
        if lin_col:
            ax.semilogy(vgs, np.abs(data[lin_col]), color=colors[1], linestyle=linestyle,
                       linewidth=2, label=f'{label} |Vds|=100mV')
    
    if hspice_file:
        try:
            hdata = load_csv(hspice_file)
            plot_dataset(hdata, 'HSPICE', ['red', 'lightcoral'], '-')
        except Exception as e:
            print(f"Warning: Could not load HSPICE data: {e}")
    
    if ngspice_file:
        try:
            ndata = load_csv(ngspice_file)
            ls = '--' if hspice_file else '-'
            colors = ['darkviolet', 'violet'] if hspice_file else ['red', 'lightcoral']
            plot_dataset(ndata, 'ngspice', colors, ls)
        except Exception as e:
            print(f"Warning: Could not load ngspice data: {e}")
    
    if not has_data:
        print("Error: No data to plot")
        return
    
    ax.set_xlabel('Vgs (V)')
    ax.set_ylabel('|Id| (A)')
    title = 'PFET Id-Vgs Characterization'
    if hspice_file and ngspice_file:
        title += ': HSPICE vs ngspice'
    ax.set_title(title)
    ax.axvline(x=1.8, color='gray', linestyle=':', alpha=0.5)
    ax.legend(loc='lower left')
    ax.grid(True, which='both', linestyle='--', alpha=0.5)
    ax.set_xlim(0, 1.8)
    ax.set_ylim(1e-14, 1e-2)
    
    plt.tight_layout()
    plt.savefig(output_file, dpi=150)
    print(f"Saved {output_file}")
    plt.close()

def main():
    parser = argparse.ArgumentParser(description='Plot PFET Id-Vgs comparison')
    parser.add_argument('--hspice', '-H', help='HSPICE CSV file')
    parser.add_argument('--ngspice', '-N', help='ngspice CSV file')
    parser.add_argument('-o', '--output', default='pfet_comparison.png', help='Output PNG file')
    
    args = parser.parse_args()
    
    if not args.hspice and not args.ngspice:
        parser.error("At least one of --hspice or --ngspice is required")
    
    plot_comparison(args.hspice, args.ngspice, args.output)

if __name__ == '__main__':
    main()
