#!/usr/bin/bash

#SBATCH -A nstaff
#SBATCH -C gpu              # Specifically request the 40gb GPUs
#SBATCH --qos debug         # Update as appropriate
#SBATCH -t 0:30:00          # Update runtime as appropriate
#SBATCH -N 1                # Total number of nodes
#SBATCH --ntasks-per-node=1 # Single MPI rank (system too small for domain decomp)
#SBATCH --gpus-per-node=4   # Allocate all GPUs on node for device passthrough
#SBATCH --cpus-per-task=16  # OMP threads


# ---- Environment ----
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK}
export OMP_PROC_BIND=spread
export OMP_PLACES=threads
export SLURM_CPU_BIND=cores
export CRAY_ACCEL_TARGET=nvidia80
export SUPPRESS_NVIDIA_HEADER=1

# ---- Build --device flags from SLURM-allocated GPUs ----
GPU_DEVICE_FLAGS="--device /dev/nvidiactl --device /dev/nvidia-uvm --device /dev/nvidia-uvm-tools"
for gpu in $(echo "${CUDA_VISIBLE_DEVICES}" | tr ',' ' '); do
    GPU_DEVICE_FLAGS="${GPU_DEVICE_FLAGS} --device /dev/nvidia${gpu}"
done

# ---- Container image ----
IMAGE="docker://docker.io/nersc/gromacs:26.05"

INPUT_FILE="md_opes_1ns.tpr"       # your .tpr
DEFFNM="md_opes_abe8e_1ns"             # base name for output files (-deffnm)
PLUMED_FILE="plumed_cv_input_abe8e_hth.dat"  # PLUMED input


# ---- Build the GROMACS command-line arguments ----
GMX_INPUT="-s ${INPUT_FILE} \
           -deffnm ${DEFFNM} \
           -plumed ${PLUMED_FILE} \
           -ntomp ${OMP_NUM_THREADS} \
           -nb gpu -pme gpu -bonded gpu \
           -noappend -v"

# ---- Library paths inside the container ----
LD_PATH="/usr/lib64"
LD_PATH="${LD_PATH}:/usr/local/cuda/lib64:/usr/local/cuda/compat"
LD_PATH="${LD_PATH}:/opt/gromacs/lib"
LD_PATH="${LD_PATH}:/opt/plumed/lib"
LD_PATH="${LD_PATH}:/opt/libtorch/lib"

# ---- Podman arguments ----
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
  ${GPU_DEVICE_FLAGS} \
  -v /usr/lib64:/usr/local/nvidia/lib64 \
  -v /usr/bin/nvidia-smi:/usr/bin/nvidia-smi \
  -e MPICH_GPU_SUPPORT_ENABLED=1 \
  -e SUPPRESS_NVIDIA_HEADER \
  -e OMP_NUM_THREADS -e OMP_PROC_BIND -e OMP_PLACES \
  -e LD_LIBRARY_PATH=/usr/local/nvidia/lib64:${LD_PATH} \
  -v $SCRATCH:$SCRATCH -w $PWD"

# ---- Launch ----
srun --cpu-bind=none --mpi=pmi2 \
     podman-hpc run $PODMAN_ARGS $IMAGE \
     gmx_mpi mdrun $GMX_INPUT

