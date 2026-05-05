#!/usr/bin/python
# -*- encoding: utf8 -*-
# plot urms



import pencil as pc
import numpy as np
import pylab as plt
import os

plt.rc('text', usetex=False)
plt.rc('font', family='serif')
plt.rcParams['font.size'] = 20



# Default sample directory, change the path to your working directory
#sdir = os.path.join(os.environ['PENCIL_HOME'],'sample/conv-slab')
# Simulation directory: defaults to /simulation (Docker container path).
# Override with SIM_DIR environment variable for local use.
sdir = os.environ.get('SIM_DIR', '/simulation')

# Create simulation object
sim = pc.sim.simulation(sdir)

# Read time series
ts = pc.read.ts(sim=sim)

# Plot the urms

fig, ax = plt.subplots(figsize=(10, 8),constrained_layout = True)

# Monitor RMS velocity (main indicator of convective vigor)


ax.plot(ts.t,ts.urms)

ax.set_xlabel('Time')
ax.set_ylabel('RMS velocity')
ax.set_title('Convection Intensity Evolution')
ax.grid()

# Chose if you want to save your figures
savefig = True

if savefig:
        # Directory to save figures. Set to 'fig' by default
        figdir = os.path.join(sdir,'fig')
        # Check that the figs directory exist and create it if it does not
        if not os.path.isdir(figdir):
                os.makedirs(figdir)
                print(f"Created directory 'fig' inside {sdir}")

        savefig = os.path.join(figdir,'urms.png')
        plt.savefig(savefig, format='png', bbox_inches='tight')
        print(f"Figure saved as {savefig}")

plt.show()