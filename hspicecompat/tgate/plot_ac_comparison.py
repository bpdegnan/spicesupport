#!/usr/bin/env python3
"""
Plot HSPICE and/or ngspice AC analysis results for comparison.

Usage:
    # Plot HSPICE only
    python3 plot_ac_comparison.py --hspice hspice.csv
    
    # Plot ngspice only  
    python3 plot_ac_comparison.py --ngspice ngspice.csv
    
    # Compare both
    python3 plot_ac_comparison.py --hspice hspice.csv --ngspice ngspice.csv
    
    # Specify output filename
    python3 plot_ac_comparison.py --hspice hspice.csv -o comparison.png
"""

import argparse
import numpy as np
import matplotlib.pyplot as plt
import re

def load_csv(filepath):
    """
    Load CSV file and return as dict of arrays.
    Handles various CSV formats from HSPICE and ngspice.
    """
    # First, try to read the header to understand the format
    with open(filepath, 'r') as f:
        first_line = f.readline().strip()
    
    # Check if it's a proper CSV with headers
    if ',' in first_line and not first_line[0].isdigit():
        # Standard CSV with comma delimiter
        data = np.genfromtxt(filepath, delimiter=',', names=True, dtype=float, encoding='utf-8')
    elif '\t' in first_line or '  ' in first_line:
        # Tab or space delimited (ngspice wrdata format)
        # Read header separately
        with open(filepath, 'r') as f:
            lines = f.readlines()
        
        # Find header line (first non-empty line)
        header_idx = 0
        for i, line in enumerate(lines):
            if line.strip() and not line.strip().startswith('#'):
                header_idx = i
                break
        
        header = lines[header_idx].split()
        
        # Read data starting after header
        data_lines = []
        for line in lines[header_idx + 1:]:
            line = line.strip()
            if line and not line.startswith('#'):
                parts = line.split()
                if parts and parts[0].replace('.', '').replace('-', '').replace('+', '').replace('e', '').replace('E', '').isdigit():
                    data_lines.append([float(x) for x in parts])
        
        if data_lines:
            arr = np.array(data_lines)
            # Create structured array
            dtype = [(name, float) for name in header]
            data = np.zeros(len(data_lines), dtype=dtype)
            for i, name in enumerate(header):
                if i < arr.shape[1]:
                    data[name] = arr[:, i]
        else:
            raise ValueError(f"Could not parse data from {filepath}")
    else:
        # Try standard genfromtxt
        data = np.genfromtxt(filepath, names=True, dtype=float, encoding='utf-8')
    
    return data

def find_columns(data, col_type):
    """
    Find columns matching a type (db or phase).
    Returns list of (column_name, label) tuples.
    """
    col_names = list(data.dtype.names)
    results = []
    
    if col_type == 'db':
        patterns = ['vdb', 'db']
    elif col_type == 'phase':
        patterns = ['vp_', 'phase', 'vp(']
    else:
        patterns = [col_type]
    
    for name in col_names:
        name_lower = name.lower()
        for pattern in patterns:
            if pattern in name_lower:
                # Extract node name for label
                label = name
                results.append((name, label))
                break
    
    return results

def plot_comparison(hspice_file=None, ngspice_file=None, output_file='ac_comparison.png'):
    """Plot AC analysis comparison."""
    
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 8), sharex=True)
    
    has_data = False
    
    # Plot HSPICE data
    if hspice_file:
        try:
            hdata = load_csv(hspice_file)
            col_names = list(hdata.dtype.names)
            
            # Find frequency column
            freq_col = None
            for name in ['freq', 'frequency', 'hertz']:
                if name in col_names:
                    freq_col = name
                    break
            if freq_col is None:
                freq_col = col_names[0]
            
            freq = hdata[freq_col]
            
            # Find vdb columns
            vdb_cols = find_columns(hdata, 'db')
            vp_cols = find_columns(hdata, 'phase')
            
            colors = ['blue', 'red', 'green', 'purple']
            
            for i, (col, label) in enumerate(vdb_cols):
                color = colors[i % len(colors)]
                # Determine m value from column name
                if 'out1' in label.lower() or '_1' in label:
                    m_label = 'm=1'
                elif 'out2' in label.lower() or '_2' in label:
                    m_label = 'm=2'
                else:
                    m_label = label
                ax1.semilogx(freq, hdata[col], color=color, linewidth=2, 
                            label=f'HSPICE {m_label}')
                has_data = True
            
            for i, (col, label) in enumerate(vp_cols):
                color = colors[i % len(colors)]
                if 'out1' in label.lower() or '_1' in label:
                    m_label = 'm=1'
                elif 'out2' in label.lower() or '_2' in label:
                    m_label = 'm=2'
                else:
                    m_label = label
                ax2.semilogx(freq, hdata[col], color=color, linewidth=2,
                            label=f'HSPICE {m_label}')
                
        except Exception as e:
            print(f"Warning: Could not load HSPICE data: {e}")
    
    # Plot ngspice data
    if ngspice_file:
        try:
            ndata = load_csv(ngspice_file)
            col_names = list(ndata.dtype.names)
            
            # Find frequency column
            freq_col = None
            for name in ['freq', 'frequency', 'hertz', col_names[0]]:
                if name in col_names:
                    freq_col = name
                    break
            
            freq = ndata[freq_col]
            
            # Find vdb and vp columns
            vdb_cols = find_columns(ndata, 'db')
            vp_cols = find_columns(ndata, 'phase')
            
            colors = ['cyan', 'orange', 'lime', 'magenta']
            linestyle = '--' if hspice_file else '-'
            
            for i, (col, label) in enumerate(vdb_cols):
                color = colors[i % len(colors)]
                if 'out1' in label.lower() or '_1' in label:
                    m_label = 'm=1'
                elif 'out2' in label.lower() or '_2' in label:
                    m_label = 'm=2'
                else:
                    m_label = label
                ax1.semilogx(freq, ndata[col], color=color, linewidth=2,
                            linestyle=linestyle, label=f'ngspice {m_label}')
                has_data = True
            
            for i, (col, label) in enumerate(vp_cols):
                color = colors[i % len(colors)]
                if 'out1' in label.lower() or '_1' in label:
                    m_label = 'm=1'
                elif 'out2' in label.lower() or '_2' in label:
                    m_label = 'm=2'
                else:
                    m_label = label
                ax2.semilogx(freq, ndata[col], color=color, linewidth=2,
                            linestyle=linestyle, label=f'ngspice {m_label}')
                
        except Exception as e:
            print(f"Warning: Could not load ngspice data: {e}")
    
    if not has_data:
        print("Error: No data to plot")
        return
    
    # Format plots
    ax1.set_ylabel('Magnitude (dB)')
    title = 'Transmission Gate AC Response'
    if hspice_file and ngspice_file:
        title += ' - HSPICE vs ngspice'
    elif hspice_file:
        title += ' - HSPICE'
    else:
        title += ' - ngspice'
    ax1.set_title(title)
    ax1.legend(loc='lower left')
    ax1.grid(True, which='both', linestyle='--', alpha=0.7)
    ax1.set_xlim(1e3, 1e9)
    
    ax2.set_xlabel('Frequency (Hz)')
    ax2.set_ylabel('Phase (degrees)')
    ax2.legend(loc='lower left')
    ax2.grid(True, which='both', linestyle='--', alpha=0.7)
    
    plt.tight_layout()
    plt.savefig(output_file, dpi=150)
    print(f"Saved {output_file}")
    plt.close()

def main():
    parser = argparse.ArgumentParser(description='Plot AC analysis comparison')
    parser.add_argument('--hspice', '-H', help='HSPICE CSV file')
    parser.add_argument('--ngspice', '-N', help='ngspice CSV file')
    parser.add_argument('-o', '--output', default='tgate_comparison.png', help='Output PNG file')
    
    args = parser.parse_args()
    
    if not args.hspice and not args.ngspice:
        parser.error("At least one of --hspice or --ngspice is required")
    
    plot_comparison(args.hspice, args.ngspice, args.output)

if __name__ == '__main__':
    main()
