
#def get_forces_lmp(strcuture, ffield):
import sys
import types

# h5py in this container was compiled against HDF5 2.0.0 but bundles 1.14.3,
# causing a crash on import. mace.data.utils imports it at module level but
# only uses it for training data (HDF5 files), not inference. Stub it out.
_h5py_stub = types.ModuleType('h5py')
sys.modules['h5py'] = _h5py_stub

import lammps
import lammps.mliap

# Patch MACEEdgeForcesWrapper: newer MACE code expects self.total_charge but
# older model files don't include it. Default to 0 for neutral systems.
from mace.calculators.lammps_mliap_mace import MACEEdgeForcesWrapper as _MACEWrapper
if not hasattr(_MACEWrapper, 'total_charge'):
    _MACEWrapper.total_charge = 0.0

lmp = lammps.lammps(cmdargs=['-k', 'on', 'g', '1', '-sf', 'kk',
                      '-pk', 'kokkos', 'neigh', 'half',
                      'newton', 'off', '-echo', 'both',
                      "-log", "none"])

lammps.mliap.activate_mliappy_kokkos(lmp)

init_lmp ="""
units         metal
atom_style    atomic
atom_modify   map yes
newton        on
processors    * * *
dimension 3
boundary p p p
"""

output_file=sys.argv[1]
ff_file=sys.argv[2]

lmp.commands_string(init_lmp)
lmp.command(f'read_data  {output_file}')
lmp.command(f'pair_style mliap unified {ff_file} 0')
#lmp.command('pair_coeff    * * Se Bi O')
lmp.command('pair_coeff    * * C Cu O')


lmp.command('thermo 10')
lmp.command('minimize 0 1e-5 1000 1000')
lmp.command('write_data minimized_structure.lmp')
forces = lmp.numpy.extract_atom("f")
print ("forces:", forces)
