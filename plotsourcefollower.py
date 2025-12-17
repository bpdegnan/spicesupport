import numpy as np
import matplotlib.pyplot as plt

# Load data, skip header row
data = np.loadtxt('sourcefollower.csv', skiprows=1)

vin = data[:, 1]
vout1 = data[:, 2]
vout2 = data[:, 3]

plt.figure(figsize=(10, 6))
plt.plot(vin, vout1, label='PMOS Bias=100mV')
plt.plot(vin, vout2, label='PMOS Bias=900mV')
plt.plot(vin, vin, 'k--', alpha=0.3, label='Unity (Vin=Vout)')
plt.xlabel('Vin (V)')
plt.ylabel('Vout (V)')
plt.title('Source Follower (NMOS input, PMOS bias)')
plt.legend()
plt.grid(True)
plt.savefig('sourcefollower.png', dpi=150)
plt.show()