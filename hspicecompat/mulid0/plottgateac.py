import numpy as np
import matplotlib.pyplot as plt

# Load data, skip header row
data = np.loadtxt('tgateac.csv', skiprows=1)

freq = data[:, 1]
vdb1 = data[:, 2]
vdb2 = data[:, 3]
vdb3 = data[:, 4]
vp1 = data[:, 5]
vp2 = data[:, 6]
vp3 = data[:, 7]

fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8))

# Magnitude plot
ax1.semilogx(freq, vdb1, 'b-', linewidth=2, label='no m/mulid0')
ax1.semilogx(freq, vdb2, 'r--', linewidth=2.5, label='m=2')
ax1.semilogx(freq, vdb3, 'g:', linewidth=3, label='mulid0=2')
ax1.set_xlabel('Frequency (Hz)')
ax1.set_ylabel('Magnitude (dB)')
ax1.set_title('T-Gate Frequency Response')
ax1.legend()
ax1.grid(True, which='both')

# Phase plot
ax2.semilogx(freq, vp1, 'b-', linewidth=2, label='no m/mulid0')
ax2.semilogx(freq, vp2, 'r--', linewidth=2.5, label='m=2')
ax2.semilogx(freq, vp3, 'g:', linewidth=3, label='mulid0=2')
ax2.set_xlabel('Frequency (Hz)')
ax2.set_ylabel('Phase (degrees)')
ax2.set_title('T-Gate Phase Response')
ax2.legend()
ax2.grid(True, which='both')

plt.tight_layout()
plt.savefig('tgate_ac.png', dpi=150)
plt.show()