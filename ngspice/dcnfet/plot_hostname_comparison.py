#!/usr/bin/env python3
"""
Plot comparison of nfetgatesweep results from multiple hosts.

Usage:
    python3 plot_hostname_comparison.py nfetgatesweep.host1.csv nfetgatesweep.host2.csv ...
    python3 plot_hostname_comparison.py nfetgatesweep.*.csv -o comparison.png
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

def extract_hostname(filepath):
    """Extract hostname from filename like nfetgatesweep.hostname.csv"""
    basename = os.path.basename(filepath)
    # Pattern: nfetgatesweep.HOSTNAME.csv
    match = re.match(r'nfetgatesweep\.(.+)\.csv', basename)
    if match:
        return match.group(1)
    return basename

def find_column(data, patterns):
    """Find first column matching any pattern."""
    for pattern in patterns:
        for name in data.dtype.names:
            if pattern.lower() in name.lower():
                return name
    return None

def plot_comparison(csv_files, output_file='nfetgatesweep_comparison.png'):
    """Plot Id-Vgs comparison from multiple hosts."""
    
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 10))
    
    # Use a colormap for distinct colors
    colors = plt.cm.tab10(np.linspace(0, 1, len(csv_files)))
    
    vgs_patterns = ['v(ng)', 'v_ng', 'vng', 'v_sweep']
    id_patterns = ['i(vd_sat)', 'i(Vd_sat)', 'i_vd_sat']
    
    all_data = {}
    
    for i, filepath in enumerate(csv_files):
        hostname = extract_hostname(filepath)
        color = colors[i]
        
        try:
            data = load_csv(filepath)
            col_names = list(data.dtype.names)
            print(f"{hostname}: columns = {col_names}")
            
            # Find Vgs column
            vgs_col = find_column(data, vgs_patterns)
            if vgs_col is None:
                vgs_col = col_names[1] if len(col_names) > 1 else col_names[0]
            vgs = data[vgs_col]
            
            # Find Id column
            id_col = find_column(data, id_patterns)
            if id_col is None and len(col_names) > 2:
                id_col = col_names[2]
            
            if id_col:
                id_abs = np.abs(data[id_col])
                
                # Store for difference calculation
                all_data[hostname] = {'vgs': vgs, 'id': id_abs}
                
                # Plot Id vs Vgs (semilog)
                ax1.semilogy(vgs, id_abs, color=color, linewidth=2, label=hostname)
                
        except Exception as e:
            print(f"Warning: Could not load {filepath}: {e}")
    
    if not all_data:
        print("Error: No data to plot")
        return
    
    # Format top plot
    ax1.set_xlabel('Vgs (V)')
    ax1.set_ylabel('|Id| (A)')
    ax1.set_title('NFET Id-Vgs: Host Comparison')
    ax1.legend(loc='lower right')
    ax1.grid(True, which='both', linestyle='--', alpha=0.5)
    ax1.set_xlim(0, 1.8)
    ax1.set_ylim(1e-14, 1e-2)
    
    # Plot differences if we have multiple datasets
    hostnames = list(all_data.keys())
    if len(hostnames) >= 2:
        ref_host = hostnames[0]
        ref_vgs = all_data[ref_host]['vgs']
        ref_id = all_data[ref_host]['id']
        
        for i, hostname in enumerate(hostnames[1:], 1):
            color = colors[i]
            vgs = all_data[hostname]['vgs']
            id_curr = all_data[hostname]['id']
            
            # Interpolate to same Vgs points if needed
            if len(vgs) == len(ref_vgs) and np.allclose(vgs, ref_vgs):
                # Calculate percent difference
                with np.errstate(divide='ignore', invalid='ignore'):
                    pct_diff = 100 * (id_curr - ref_id) / ref_id
                    pct_diff = np.where(np.isfinite(pct_diff), pct_diff, 0)
                
                ax2.plot(ref_vgs, pct_diff, color=color, linewidth=2, 
                        label=f'{hostname} vs {ref_host}')
            else:
                print(f"Warning: Cannot compare {hostname} with {ref_host} - different Vgs points")
        
        ax2.set_xlabel('Vgs (V)')
        ax2.set_ylabel('Difference (%)')
        ax2.set_title(f'Percent Difference (reference: {ref_host})')
        ax2.legend(loc='best')
        ax2.grid(True, linestyle='--', alpha=0.5)
        ax2.set_xlim(0, 1.8)
        ax2.axhline(y=0, color='black', linestyle='-', linewidth=0.5)
    else:
        ax2.text(0.5, 0.5, 'Need 2+ hosts for difference plot', 
                ha='center', va='center', transform=ax2.transAxes, fontsize=14)
        ax2.set_title('Percent Difference')
    
    plt.tight_layout()
    plt.savefig(output_file, dpi=150)
    print(f"Saved {output_file}")
    plt.close()

def main():
    parser = argparse.ArgumentParser(description='Plot nfetgatesweep host comparison')
    parser.add_argument('csv_files', nargs='+', help='CSV files to compare')
    parser.add_argument('-o', '--output', default='nfetgatesweep_comparison.png', 
                       help='Output PNG file')
    
    args = parser.parse_args()
    
    if len(args.csv_files) == 0:
        parser.error("At least one CSV file is required")
    
    plot_comparison(args.csv_files, args.output)

if __name__ == '__main__':
    main()
