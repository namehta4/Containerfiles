#!/usr/bin/bash

#SBATCH -A nstaff
#SBATCH -C gpu              # Specifically request the 40gb GPUs; this is purely for throughput reasons
#SBATCH --qos debug         # Update as appropriate
#SBATCH -t 0:30:00          # Update runtime as appropriate
#SBATCH -N 1                # Bump for multi-node cudaq::mpi (e.g. distributed state-vector/AFQMC) runs
#SBATCH --ntasks-per-node=1 # One cudaq process per GPU; bump alongside --gpus-per-task for multi-GPU
#SBATCH --gpus-per-task=1
#SBATCH --gpu-bind=none     # We pass device files through explicitly below instead

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

# Base/GPU/Dockerfile builds MPICH with two netmods (ofi, ucx). On Slingshot
# use ofi with libfabric's cxi provider. ofi is already MPICH's default here,
# but set it explicitly so a stray MPIR_CVAR_CH4_NETMOD can't override it.
export MPIR_CVAR_CH4_NETMOD=ofi
export FI_PROVIDER=cxi

IMAGE="docker://docker.io/nersc/cudaq:26.10"   # set to whatever tag you push

# What to run inside the container, and the directory to run it from. Defaults
# to the SC25 tutorial's Hour3 decoding example (sbatch from the tutorial root):
# the script opens mhc_sqale_data/ relative to cwd, so it must run in Hour3.
# Point these at your own script/notebook as needed.
RUN_DIR="${PWD}/Hour3"
RUN_CMD="python3 mhc_qldpc_decoding.py"

# Build --device flags from the GPUs Slurm's cgroup actually granted, rather
# than assuming a fixed count — this stays correct even if --gpus-per-task
# ever requests fewer than a full node's worth of GPUs.
GPU_DEVICE_FLAGS="--device /dev/nvidiactl --device /dev/nvidia-uvm --device /dev/nvidia-uvm-tools"
for gpu in $(echo "${CUDA_VISIBLE_DEVICES}" | tr ',' ' '); do
    GPU_DEVICE_FLAGS="${GPU_DEVICE_FLAGS} --device /dev/nvidia${gpu}"
done

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
  -e MPIR_CVAR_CH4_NETMOD -e FI_PROVIDER \
  -e SUPPRESS_NVIDIA_HEADER \
  -e OMP_NUM_THREADS -e OMP_PROC_BIND -e OMP_PLACES \
  -v $SCRATCH:$SCRATCH -w ${RUN_DIR}"

# Only the host NVIDIA driver path is genuinely runtime-unknown (the image
# can't know it at build time); everything cudaq itself needs (cutensor,
# cuquantum, qrmi, cudaqx, LLVM) is found via RPATHs baked in at build time,
# not LD_LIBRARY_PATH. So prepend to whatever the image already set instead
# of replacing it — expand $LD_LIBRARY_PATH *inside* the container, not from
# this host shell, so it extends the image's own env rather than guessing it.
srun --cpu-bind=none --mpi=pmi2 \
     podman-hpc run $PODMAN_ARGS $IMAGE \
     bash -c "export LD_LIBRARY_PATH=/usr/local/nvidia/lib64:\${LD_LIBRARY_PATH}; exec ${RUN_CMD}"
