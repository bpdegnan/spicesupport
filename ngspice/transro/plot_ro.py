#!/usr/bin/env python3
"""
Plot ring oscillator waveforms and supply currents.

Usage:
    python3 plot_ro.py ro20.hostname.csv
"""

import argparse
import numpy as np
import matplotlib.pyplot as plt
import re
import os

def load_csv(filepath):
    """Load CSV file and extract metadata."""
    with open(filepath, 'r') as f:
        lines = f.readlines()
    
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
        header = [h.strip().lower().replace('-', '_') for h in header_line.split(delimiter)]
    else:
        header = [h.lower().replace('-', '_') for h in header_line.split()]
    
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

def find_column(names, patterns):
    """Find first column matching any pattern."""
    for pattern in patterns:
        for name in names:
            if pattern.lower() in name.lower():
                return name
    return None

def plot_ro(csv_files):
    """Plot ring oscillator waveforms."""
    
    fig, axes = plt.subplots(3, 1, figsize=(14, 10), sharex=True)
    ax_volt, ax_ivdd, ax_ivss = axes
    
    for filepath in csv_files:
        data, cols, meta = load_csv(filepath)
        hostname = meta.get('hostname', os.path.basename(filepath))
        
        print(f"Loaded {filepath}")
        print(f"  Columns: {cols}")
        
        # Find columns
        time_col = find_column(cols, ['time'])
        en_col = find_column(cols, ['v(en)'])
        nand_out_col = find_column(cols, ['v(nand_out)', 'v(nand)'])
        fb_col = find_column(cols, ['v(fb)'])
        ivdd_col = find_column(cols, ['i(vdd_sense)', 'i(vdd)'])
        ivss_col = find_column(cols, ['i(vss_sense)', 'i(vss)'])
        
        if time_col is None:
            time_col = cols[0]
        
        time_ns = data[time_col] * 1e9  # Convert to ns
        
        # Plot voltages
        if en_col:
            ax_volt.plot(time_ns, data[en_col], '--', label=f'Enable ({hostname})', alpha=0.7)
        if nand_out_col:
            ax_volt.plot(time_ns, data[nand_out_col], label=f'NAND out ({hostname})')
        if fb_col:
            ax_volt.plot(time_ns, data[fb_col], label=f'Feedback ({hostname})', alpha=0.7)
        
        # Plot VDD current
        if ivdd_col:
            ax_ivdd.plot(time_ns, data[ivdd_col] * 1e6, label=f'I(VDD) ({hostname})')
        
        # Plot VSS current
        if ivss_col:
            ax_ivss.plot(time_ns, data[ivss_col] * 1e6, label=f'I(VSS) ({hostname})')
    
    # Format voltage plot
    ax_volt.set_ylabel('Voltage (V)')
    ax_volt.set_title('Ring Oscillator Waveforms')
    ax_volt.grid(True, linestyle='--', alpha=0.5)
    ax_volt.legend(loc='best', fontsize=8)
    ax_volt.set_ylim(-0.1, 2.0)
    
    # Format VDD current plot
    ax_ivdd.set_ylabel('I_VDD (µA)')
    ax_ivdd.set_title('VDD Supply Current')
    ax_ivdd.grid(True, linestyle='--', alpha=0.5)
    ax_ivdd.legend(loc='best', fontsize=8)
    
    # Format VSS current plot
    ax_ivss.set_xlabel('Time (ns)')
    ax_ivss.set_ylabel('I_VSS (µA)')
    ax_ivss.set_title('VSS (Ground) Current')
    ax_ivss.grid(True, linestyle='--', alpha=0.5)
    ax_ivss.legend(loc='best', fontsize=8)
    
    plt.tight_layout()
    plt.show()

def main():
    parser = argparse.ArgumentParser(description='Plot ring oscillator waveforms')
    parser.add_argument('csv_files', nargs='+', help='CSV files to plot')
    args = parser.parse_args()
    
    plot_ro(args.csv_files)

if __name__ == '__main__':
    main()
