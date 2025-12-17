import numpy as np
import matplotlib.pyplot as plt

# Load data, skip header row
data = np.loadtxt('tgate.csv', skiprows=1)

vout = data[:, 1]
ids1 = np.abs(data[:, 2])
ids2 = np.abs(data[:, 3])
ids3 = np.abs(data[:, 4])

# Calculate resistance (R = V/I = 25mV / I)
resistance1 = 0.025 / ids1
resistance2 = 0.025 / ids2
resistance3 = 0.025 / ids3

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))

# Current plot
ax1.plot(vout, ids1 * 1e6, label='Standard')
ax1.plot(vout, ids2 * 1e6, label='m=2')
ax1.plot(vout, ids3 * 1e6, label='mulid0=2')
ax1.set_xlabel('V (V)')
ax1.set_ylabel('I (µA)')
ax1.set_title('T-Gate Current (Vds=25mV)')
ax1.legend()
ax1.grid(True)

# Resistance plot
ax2.plot(vout, resistance1 / 1e3, label='Standard')
ax2.plot(vout, resistance2 / 1e3, label='m=2')
ax2.plot(vout, resistance3 / 1e3, label='mulid0=2')
ax2.set_xlabel('V (V)')
ax2.set_ylabel('Resistance (kΩ)')
ax2.set_title('T-Gate Resistance')
ax2.legend()
ax2.grid(True)

plt.tight_layout()
plt.savefig('tgate.png', dpi=150)
plt.show()