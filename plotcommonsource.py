import numpy as np
import matplotlib.pyplot as plt

# Load data, skip header row
data = np.loadtxt('commonsource.csv', skiprows=1)

vin = data[:, 1]
vout1 = data[:, 2]
vout2 = data[:, 3]

plt.figure(figsize=(10, 6))
plt.plot(vin, vout1, label='Bias = 100mV')
plt.plot(vin, vout2, label='Bias = 200mV')
plt.xlabel('Vin (V)')
plt.ylabel('Vout (V)')
plt.title('Common Source Amplifier')
plt.legend()
plt.grid(True)
plt.savefig('commonsource.png', dpi=150)
plt.show()