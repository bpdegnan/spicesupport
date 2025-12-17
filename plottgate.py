import numpy as np
import matplotlib.pyplot as plt

# Load data, skip header row
data = np.loadtxt('tgate.csv', skiprows=1)

vout = data[:, 1]
ids = np.abs(data[:, 2])

# Calculate resistance (R = V/I = 25mV / I)
resistance = 0.025 / ids

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))

# Current plot
ax1.plot(vout, ids * 1e6)
ax1.set_xlabel('V (V)')
ax1.set_ylabel('I (µA)')
ax1.set_title('T-Gate Current (Vds=25mV)')
ax1.grid(True)

# Resistance plot
ax2.plot(vout, resistance / 1e3)
ax2.set_xlabel('V (V)')
ax2.set_ylabel('Resistance (kΩ)')
ax2.set_title('T-Gate Resistance')
ax2.grid(True)

plt.tight_layout()
plt.savefig('tgate.png', dpi=150)
plt.show()