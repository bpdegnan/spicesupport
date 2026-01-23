#!/usr/bin/env python3
"""
Plot comparison of nfettrans results from multiple hosts.

Usage:
    python3 plot_transient_comparison.py nfettrans.host1.csv nfettrans.host2.csv ...
    python3 plot_transient_comparison.py nfettrans.*.csv -o comparison.png
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
    
    # Handle duplicate column names by appending _N suffix
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
    
    return data

def extract_hostname(filepath):
    """Extract hostname from filename like nfettrans.hostname.csv"""
    basename = os.path.basename(filepath)
    match = re.match(r'nfettrans\.(.+)\.csv', basename)
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

def plot_comparison(csv_files, output_file='nfettrans_comparison.png'):
    """Plot transient comparison from multiple hosts."""
    
    fig, axes = plt.subplots(3, 1, figsize=(12, 10))
    ax1, ax2, ax3 = axes
    
    # Use a colormap for distinct colors
    colors = plt.cm.tab10(np.linspace(0, 1, len(csv_files)))
    
    time_patterns = ['time', 'time_1', 't']
    vg_patterns = ['v(ng)', 'v_ng', 'vng']
    id_patterns = ['i(vd)', 'i(Vd)', 'i_vd', 'ivd']
    
    all_data = {}
    
    for i, filepath in enumerate(csv_files):
        hostname = extract_hostname(filepath)
        color = colors[i]
        
        try:
            data = load_csv(filepath)
            col_names = list(data.dtype.names)
            print(f"{hostname}: columns = {col_names}")
            
            # Find time column
            time_col = find_column(data, time_patterns)
            if time_col is None:
                time_col = col_names[0]
            time = data[time_col] * 1e6  # Convert to µs
            
            # Find Vg column
            vg_col = find_column(data, vg_patterns)
            if vg_col is None and len(col_names) > 1:
                vg_col = col_names[1]
            vg = data[vg_col] if vg_col else None
            
            # Find Id column
            id_col = find_column(data, id_patterns)
            if id_col is None and len(col_names) > 2:
                id_col = col_names[2]
            #id_curr = np.abs(data[id_col]) if id_col else None
            id_curr = np.abs(data[id_col]) if id_col else None

            # Store for difference calculation
            all_data[hostname] = {'time': time, 'vg': vg, 'id': id_curr}
            
            # Plot Vg vs time
            if vg is not None:
                ax1.plot(time, vg, color=color, linewidth=1.5, label=hostname)
            
            # Plot Id vs time (semilog)
            if id_curr is not None:
                ax2.plot(time, id_curr, color=color, linewidth=1.5, label=hostname)
                
        except Exception as e:
            print(f"Warning: Could not load {filepath}: {e}")
            import traceback
            traceback.print_exc()
    
    if not all_data:
        print("Error: No data to plot")
        return
    
    # Format Vg plot
    ax1.set_xlabel('Time (µs)')
    ax1.set_ylabel('Vg (V)')
    ax1.set_title('Gate Voltage vs Time')
    ax1.legend(loc='lower right')
    ax1.grid(True, linestyle='--', alpha=0.5)
    ax1.set_xlim(0, 1000)
    
    # Format Id plot (semilog)
    ax2.set_xlabel('Time (µs)')
    ax2.set_ylabel('|Id| (A)')
    ax2.set_title('Drain Current vs Time (log scale)')
    ax2.legend(loc='lower right')
    ax2.grid(True, which='both', linestyle='--', alpha=0.5)
    ax2.set_xlim(0, 1000)
    ax2.set_ylim(1e-14, 1e-2)  # 10fA to 10mA
    
    # Plot differences if we have multiple datasets
    hostnames = list(all_data.keys())
    if len(hostnames) >= 2:
        ref_host = hostnames[0]
        ref_time = all_data[ref_host]['time']
        ref_id = all_data[ref_host]['id']
        
        for i, hostname in enumerate(hostnames[1:], 1):
            color = colors[i]
            time = all_data[hostname]['time']
            id_curr = all_data[hostname]['id']
            
            if id_curr is None or ref_id is None:
                continue
            
            # Check if same time points
            if len(time) == len(ref_time) and np.allclose(time, ref_time, rtol=1e-3):
                # Calculate absolute difference in A
                diff = (id_curr - ref_id)
                ax3.plot(ref_time, diff, color=color, linewidth=1.5, 
                        label=f'{hostname} - {ref_host}')
            else:
                # Interpolate to reference time points
                id_interp = np.interp(ref_time, time, id_curr)
                diff = (id_interp - ref_id)
                ax3.plot(ref_time, diff, color=color, linewidth=1.5, 
                        label=f'{hostname} - {ref_host} (interp)')
        
        ax3.set_xlabel('Time (µs)')
        ax3.set_ylabel('ΔId (A)')
        ax3.set_title(f'Current Difference (reference: {ref_host})')
        ax3.legend(loc='best')
        ax3.grid(True, linestyle='--', alpha=0.5)
        ax3.set_xlim(0, 1000)
        ax3.axhline(y=0, color='black', linestyle='-', linewidth=0.5)
    else:
        ax3.text(0.5, 0.5, 'Need 2+ hosts for difference plot', 
                ha='center', va='center', transform=ax3.transAxes, fontsize=14)
        ax3.set_title('Current Difference')
    
    plt.tight_layout()
    plt.show()
    #plt.savefig(output_file, dpi=150)
    #print(f"Saved {output_file}")
    #plt.close()

def main():
    parser = argparse.ArgumentParser(description='Plot nfettrans host comparison')
    parser.add_argument('csv_files', nargs='+', help='CSV files to compare')
    parser.add_argument('-o', '--output', default='nfettrans_comparison.png', 
                       help='Output PNG file')
    
    args = parser.parse_args()
    
    if len(args.csv_files) == 0:
        parser.error("At least one CSV file is required")
    
    plot_comparison(args.csv_files, args.output)

if __name__ == '__main__':
    main()
