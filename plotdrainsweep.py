import numpy as np
import matplotlib.pyplot as plt

# Load data, skip header row
data = np.loadtxt('drainsweep.csv', skiprows=1)

vds = data[:, 1]

vgs_values = [0.2, 0.6, 1.0, 1.4, 1.8]

plt.figure(figsize=(10, 6))

# NMOS
for i, vgs in enumerate(vgs_values):
    id = data[:, i + 2] * 1e6
    plt.plot(vds, abs(id), label=f'NMOS Vgs={vgs}V')

# PMOS
for i, vsg in enumerate(vgs_values):
    id = data[:, i + 7] * 1e6
    plt.plot(vds, id, '--', label=f'PMOS Vsg={vsg}V')

plt.xlabel('Vd (V)')
plt.ylabel('Id (µA)')
plt.title('NMOS and PMOS Drain Sweep')
plt.legend()
plt.grid(True)
plt.savefig('drainsweep.png', dpi=150)
plt.show()