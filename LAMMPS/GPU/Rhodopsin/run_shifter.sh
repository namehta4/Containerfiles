#!/bin/bash
#SBATCH -C gpu
#SBATCH -A nstaff
#SBATCH -q debug
#SBATCH -t 00:20:00
#SBATCH -N 2
#SBATCH --ntasks-per-node=4
#SBATCH --gpus-per-task=1
#SBATCH -c 32
#SBATCH -J lammps_flux
#SBATCH -o lammps_flux.o%j
#SBATCH --image=docker:nersc/lammps_flux:26.03

export MPICH_GPU_SUPPORT_ENABLED=1
export OMP_NUM_THREADS=8
export OMP_PROC_BIND=spread
export OMP_PLACES=threads

INPUT="-k on g 1 -sf kk -pk kokkos newton off neigh half -in in.rhodo"

echo "Launching Flux broker..."

# Start Flux across the allocation
srun --mpi=pmi2 flux start --nodes=$SLURM_NNODES --quiet &
FLUX_PID=$!

# Give Flux a moment to initialize
sleep 5

echo "Submitting LAMMPS job to Flux"

flux run \
    -N $SLURM_NNODES \
    -n $SLURM_NTASKS \
    -g 1 \
    lmp $INPUT

# Wait for Flux to exit cleanly
wait $FLUX_PID
