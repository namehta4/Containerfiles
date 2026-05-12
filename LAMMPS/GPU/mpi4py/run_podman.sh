#!/usr/bin/bash

#SBATCH -A nstaff
#SBATCH -C gpu              # Specifically request the 40gb GPUs; this is purely for throughput reasons
#SBATCH --qos debug         # Update as appropriate
#SBATCH -t 0:30:00          # One hour runtime
#SBATCH -N 2                # This is the total number of nodes
#SBATCH --ntasks-per-node=4 # Number of tasks per node
#SBATCH --gpus-per-task=1   # 1 GPU per MPI task
#SBATCH --gpu-bind=none     # This is necessary to let all 4 ranks on a node access all 4 GPUs.

export NNODES=${SLURM_JOB_NUM_NODES}
export NGPUS=${SLURM_NTASKS_PER_NODE}
export NRANK=$((${NGPUS} * ${NNODES}))
export RUNSTRING="${NNODES}node-${NGPUS}gpu-J${SLURM_JOB_ID}"

export OMP_NUM_THREADS=1
export OMP_PROC_BIND=spread
export OMP_PLACES=threads
export SLURM_CPU_BIND=cores
export CRAY_ACCEL_TARGET=nvidia80
export SUPPRESS_NVIDIA_HEADER=1

IMAGE="docker://docker.io/nersc/flux:26.05"

LD_PATH="/usr/lib64"
LD_PATH="${LD_PATH}:/opt/lammps/build/kim_build-prefix/lib"
LD_PATH="${LD_PATH}:/usr/local/cuda/lib64:/usr/local/cuda/compat"
LD_PATH="${LD_PATH}:/opt/fftw/install/lib"
LD_PATH="${LD_PATH}:/opt/hdf5/install/lib"
LD_PATH="${LD_PATH}:/opt/lammps/build/plumed_build-prefix/lib"
LD_PATH="${LD_PATH}:/opt/lammps/install/lib"
LD_PATH="${LD_PATH}:/usr/local/blas"
LD_PATH="${LD_PATH}:/opt/basic/lib/python3.12/site-packages/torch/lib"

PODMAN_ARGS="--rm \
  -e SLURM_* -e PALS_* -e PMI_* \
  --ipc=host --network=host --pid=host --privileged \
  -v /dev/shm:/dev/shm \
  -v /dev/cxi0:/dev/cxi0 -v /dev/cxi1:/dev/cxi1 \
  -v /dev/cxi2:/dev/cxi2 -v /dev/cxi3:/dev/cxi3 \
  -v /dev/xpmem:/dev/xpmem \
  -v /var/spool/slurmd:/var/spool/slurmd \
  -v /run/munge:/run/munge -v /run/nscd:/run/nscd \
  -v /dev/nvidia-caps-imex-channels:/dev/nvidia-caps-imex-channels \
  --device /dev/nvidia0 --device /dev/nvidia1 \
  --device /dev/nvidia2 --device /dev/nvidia3 \
  --device /dev/nvidiactl --device /dev/nvidia-uvm \
  --device /dev/nvidia-uvm-tools \
  -v /usr/lib64:/usr/local/nvidia/lib64 \
  -v /usr/bin/nvidia-smi:/usr/bin/nvidia-smi \
  -e MPICH_GPU_SUPPORT_ENABLED=1 \
  -e SUPPRESS_NVIDIA_HEADER \
  -e KOKKOS_PRINT_CONFIGURATION=1 \
  -e OMP_NUM_THREADS -e OMP_PROC_BIND -e OMP_PLACES \
  -e LD_LIBRARY_PATH=/usr/local/nvidia/lib64:${LD_PATH} \
  -v $SCRATCH:$SCRATCH -w $PWD"

srun --cpu-bind=none --mpi=pmi2 \
     podman-hpc run $PODMAN_ARGS $IMAGE \
     python benchmark.py
