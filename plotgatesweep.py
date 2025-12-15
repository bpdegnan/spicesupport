import numpy as np
import matplotlib.pyplot as plt

# Load data, skip header row
data = np.loadtxt('gatesweep.csv', skiprows=1)

vgs = data[:, 1]
id_nmos_sat = np.abs(data[:, 2])
id_nmos_lin = np.abs(data[:, 3])
id_pmos_sat = np.abs(data[:, 4])
id_pmos_lin = np.abs(data[:, 5])

plt.figure()
plt.semilogy(vgs, id_nmos_sat, 'b-', label='NMOS Vds=1.8V')
plt.semilogy(vgs, id_nmos_lin, 'b--', label='NMOS Vds=100mV')
plt.semilogy(vgs, id_pmos_sat, 'r-', label='PMOS |Vds|=1.8V')
plt.semilogy(vgs, id_pmos_lin, 'r--', label='PMOS |Vds|=100mV')
plt.axvline(x=1.8, color='gray', linestyle=':', label='VDD (1.8V)')
plt.xlabel('Vg (V)')
plt.ylabel('|Id| (A)')
plt.title('NMOS and PMOS Gate Sweep')
plt.legend()
plt.grid(True, which='both')
plt.savefig('gatesweep.png', dpi=150)
plt.show()