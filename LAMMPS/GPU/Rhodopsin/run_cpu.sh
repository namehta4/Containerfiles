#! /usr/bin/bash

#SBATCH -A nstaff
#SBATCH -C cpu              # Request CPU nodes only
#SBATCH --qos debug         # Update as appropriate
#SBATCH -t 0:30:00          # One hour runtime
#SBATCH -N 2                # This is the total number of nodes
#SBATCH --ntasks-per-node=128 # Number of tasks per node

export NNODES=${SLURM_JOB_NUM_NODES}
export NTASKS=${SLURM_NTASKS_PER_NODE}
export NRANK=$((${NTASKS} * ${NNODES}))

### Cray/Slurm runtime flags
export OMP_NUM_THREADS=1
export SLURM_CPU_BIND=cores
export OMP_PROC_BIND=spread 
export OMP_PLACES=threads

export RUNSTRING="${NNODES}node-${NTASKS}task-J${SLURM_JOB_ID}"
binding=" --mpi=pmi2 podman-hpc run --rm \
           -e SLURM_* -e PALS_* -e PMI_* -e OMP_* --ipc=host --network=host --pid=host \
           --privileged -v /dev/shm:/dev/shm -v /dev/cxi0:/dev/cxi0 \
           -v /dev/xpmem:/dev/xpmem -v /var/spool/slurmd:/var/spool/slurmd \
           -v /run/munge:/run/munge -v /run/nscd:/run/nscd \
           -v $SCRATCH:$SCRATCH -w $PWD"
image="docker://docker.io/nersc/lammps_cpu:26.02"
input="-k on -sf kk -pk kokkos newton off neigh half -in in.rhodo"

srun -N $NNODES --cpu-bind cores --ntasks-per-node $NTASKS \
     $binding $image lmp $input
