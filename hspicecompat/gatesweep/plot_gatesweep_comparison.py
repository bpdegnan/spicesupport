#!/usr/bin/env python3
"""
Plot HSPICE and/or ngspice gate sweep (Id-Vgs) results for comparison.

Usage:
    # Plot ngspice only
    python3 plot_gatesweep_comparison.py --ngspice gatesweep_ngspice.csv
    
    # Plot HSPICE only
    python3 plot_gatesweep_comparison.py --hspice gatesweep_hspice.csv
    
    # Compare both
    python3 plot_gatesweep_comparison.py --hspice gatesweep_hspice.csv --ngspice gatesweep_ngspice.csv
    
    # Specify output filename
    python3 plot_gatesweep_comparison.py --ngspice gatesweep_ngspice.csv -o myplot.png
"""

import argparse
import numpy as np
import matplotlib.pyplot as plt
import re

def load_csv(filepath):
    """
    Load CSV file and return as dict of arrays.
    Handles space/tab delimited format from ngspice wrdata and HSPICE converter.
    """
    with open(filepath, 'r') as f:
        lines = f.readlines()
    
    # Find header line (first non-empty, non-comment line)
    header_idx = 0
    for i, line in enumerate(lines):
        line = line.strip()
        if line and not line.startswith('#'):
            header_idx = i
            break
    
    header = lines[header_idx].split()
    # Clean up header names - make them consistent
    header = [h.replace('-', '_') for h in header]
    
    # Read data
    data_lines = []
    for line in lines[header_idx + 1:]:
        line = line.strip()
        if line and not line.startswith('#'):
            parts = line.split()
            if parts and re.match(r'^[\-\d\.]', parts[0]):
                try:
                    data_lines.append([float(x) for x in parts])
                except ValueError:
                    continue
    
    if not data_lines:
        raise ValueError(f"Could not parse data from {filepath}")
    
    arr = np.array(data_lines)
    dtype = [(name, float) for name in header]
    data = np.zeros(len(data_lines), dtype=dtype)
    for i, name in enumerate(header):
        if i < arr.shape[1]:
            data[name] = arr[:, i]
    
    return data

def find_column(data, patterns):
    """Find first column matching any pattern (case-insensitive)."""
    col_names = list(data.dtype.names)
    for pattern in patterns:
        for name in col_names:
            if pattern.lower() in name.lower():
                return name
    return None

def plot_comparison(hspice_file=None, ngspice_file=None, output_file='gatesweep_comparison.png'):
    """Plot Id-Vgs gate sweep comparison with separate NMOS/PMOS subplots."""
    
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))
    
    has_data = False
    
    # Column patterns
    vgs_patterns = ['v(ng)', 'v_ng', 'vng', 'v_sweep']
    nmos_sat_patterns = ['i(vd_sat)', 'i(Vd_sat)', 'i_vd_sat']
    nmos_lin_patterns = ['i(vd_lin)', 'i(Vd_lin)', 'i_vd_lin']
    pmos_sat_patterns = ['i(vp_sat)', 'i(Vp_sat)', 'i_vp_sat']
    pmos_lin_patterns = ['i(vp_lin)', 'i(Vp_lin)', 'i_vp_lin']
    
    def plot_dataset(data, label_prefix, nmos_colors, pmos_colors, linestyle='-', alpha=1.0):
        """Plot a dataset (either HSPICE or ngspice)."""
        nonlocal has_data
        
        col_names = list(data.dtype.names)
        print(f"{label_prefix} columns: {col_names}")
        
        # Find Vgs column - use second column (first is often v-sweep duplicate)
        vgs_col = find_column(data, vgs_patterns)
        if vgs_col is None:
            vgs_col = col_names[1] if len(col_names) > 1 else col_names[0]
        vgs = data[vgs_col]
        
        # Find current columns
        nmos_sat_col = find_column(data, nmos_sat_patterns)
        nmos_lin_col = find_column(data, nmos_lin_patterns)
        pmos_sat_col = find_column(data, pmos_sat_patterns)
        pmos_lin_col = find_column(data, pmos_lin_patterns)
        
        # Fallback to positional
        if nmos_sat_col is None and len(col_names) > 2:
            nmos_sat_col = col_names[2]
        if nmos_lin_col is None and len(col_names) > 3:
            nmos_lin_col = col_names[3]
        if pmos_sat_col is None and len(col_names) > 4:
            pmos_sat_col = col_names[4]
        if pmos_lin_col is None and len(col_names) > 5:
            pmos_lin_col = col_names[5]
        
        # Plot NMOS (left subplot)
        if nmos_sat_col:
            id_nmos_sat = np.abs(data[nmos_sat_col])
            ax1.semilogy(vgs, id_nmos_sat, color=nmos_colors[0], linestyle=linestyle, 
                        linewidth=2, alpha=alpha, label=f'{label_prefix} Vds=1.8V')
            has_data = True
        if nmos_lin_col:
            id_nmos_lin = np.abs(data[nmos_lin_col])
            ax1.semilogy(vgs, id_nmos_lin, color=nmos_colors[1], linestyle=linestyle,
                        linewidth=2, alpha=alpha, label=f'{label_prefix} Vds=100mV')
        
        # Plot PMOS (right subplot)
        if pmos_sat_col:
            id_pmos_sat = np.abs(data[pmos_sat_col])
            ax2.semilogy(vgs, id_pmos_sat, color=pmos_colors[0], linestyle=linestyle,
                        linewidth=2, alpha=alpha, label=f'{label_prefix} |Vds|=1.8V')
        if pmos_lin_col:
            id_pmos_lin = np.abs(data[pmos_lin_col])
            ax2.semilogy(vgs, id_pmos_lin, color=pmos_colors[1], linestyle=linestyle,
                        linewidth=2, alpha=alpha, label=f'{label_prefix} |Vds|=100mV')
    
    # Plot HSPICE data (solid lines, blue/red)
    if hspice_file:
        try:
            hdata = load_csv(hspice_file)
            plot_dataset(hdata, 'HSPICE', 
                        nmos_colors=['blue', 'cornflowerblue'],
                        pmos_colors=['red', 'lightcoral'],
                        linestyle='-', alpha=1.0)
        except Exception as e:
            print(f"Warning: Could not load HSPICE data: {e}")
            import traceback
            traceback.print_exc()
    
    # Plot ngspice data (dashed if comparing, solid if standalone)
    if ngspice_file:
        try:
            ndata = load_csv(ngspice_file)
            ls = '--' if hspice_file else '-'
            # Use different colors if comparing
            if hspice_file:
                nmos_colors = ['darkgreen', 'limegreen']
                pmos_colors = ['darkviolet', 'violet']
            else:
                nmos_colors = ['blue', 'cornflowerblue']
                pmos_colors = ['red', 'lightcoral']
            plot_dataset(ndata, 'ngspice',
                        nmos_colors=nmos_colors,
                        pmos_colors=pmos_colors,
                        linestyle=ls, alpha=0.9 if hspice_file else 1.0)
        except Exception as e:
            print(f"Warning: Could not load ngspice data: {e}")
            import traceback
            traceback.print_exc()
    
    if not has_data:
        print("Error: No data to plot")
        return
    
    # Format NMOS subplot
    ax1.set_xlabel('Vgs (V)')
    ax1.set_ylabel('|Id| (A)')
    ax1.set_title('NMOS Gate Sweep')
    ax1.axvline(x=1.8, color='gray', linestyle=':', alpha=0.5)
    ax1.legend(loc='lower right')
    ax1.grid(True, which='both', linestyle='--', alpha=0.5)
    ax1.set_xlim(0, 1.8)
    ax1.set_ylim(1e-14, 1e-2)
    
    # Format PMOS subplot
    ax2.set_xlabel('Vgs (V)')
    ax2.set_ylabel('|Id| (A)')
    ax2.set_title('PMOS Gate Sweep')
    ax2.axvline(x=1.8, color='gray', linestyle=':', alpha=0.5)
    ax2.legend(loc='lower left')
    ax2.grid(True, which='both', linestyle='--', alpha=0.5)
    ax2.set_xlim(0, 1.8)
    ax2.set_ylim(1e-14, 1e-2)
    
    # Overall title
    if hspice_file and ngspice_file:
        fig.suptitle('Id-Vgs Characterization: HSPICE vs ngspice', fontsize=14)
    elif hspice_file:
        fig.suptitle('Id-Vgs Characterization: HSPICE', fontsize=14)
    else:
        fig.suptitle('Id-Vgs Characterization: ngspice', fontsize=14)
    
    plt.tight_layout()
    plt.savefig(output_file, dpi=150)
    print(f"Saved {output_file}")
    plt.close()

def main():
    parser = argparse.ArgumentParser(description='Plot Id-Vgs gate sweep comparison')
    parser.add_argument('--hspice', '-H', help='HSPICE CSV file')
    parser.add_argument('--ngspice', '-N', help='ngspice CSV file')
    parser.add_argument('-o', '--output', default='gatesweep_comparison.png', help='Output PNG file')
    
    args = parser.parse_args()
    
    if not args.hspice and not args.ngspice:
        parser.error("At least one of --hspice or --ngspice is required")
    
    plot_comparison(args.hspice, args.ngspice, args.output)

if __name__ == '__main__':
    main()
