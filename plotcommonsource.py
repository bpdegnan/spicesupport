import numpy as np
import matplotlib.pyplot as plt

# Load data, skip header row
data = np.loadtxt('commonsource.csv', skiprows=1)

vin = data[:, 1]
voutn1 = data[:, 2]
voutn2 = data[:, 3]
voutp1 = data[:, 4]
voutp2 = data[:, 5]

plt.figure(figsize=(10, 6))
plt.plot(vin, voutn1, 'b-', label='NMOS Bias=100mV')
plt.plot(vin, voutn2, 'b--', label='NMOS Bias=200mV')
plt.plot(vin, voutp1, 'r-', label='PMOS |Bias|=100mV')
plt.plot(vin, voutp2, 'r--', label='PMOS |Bias|=200mV')
plt.xlabel('Vin (V)')
plt.ylabel('Vout (V)')
plt.title('Common Source Amplifier ')
plt.legend()
plt.grid(True)
plt.savefig('commonsource.png', dpi=150)
plt.show()