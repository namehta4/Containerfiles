#!/usr/bin/bash

#SBATCH -A <allocation>      # Your Vista project/allocation
#SBATCH -p gh                # gh-dev instead for short test runs (<=2h, <=8 nodes)
#SBATCH -t 00:30:00
#SBATCH -N 1                 # gh/gh-dev nodes have exactly 1 GH200 120GB GPU each —
#SBATCH -n 1                 # scale via -N for multi-GPU/multi-node, not GPUs-per-node
#SBATCH -J cudaq
# Do not request specific nodes (TACC policy on Vista).

export OMP_NUM_THREADS=1
export OMP_PROC_BIND=spread
export OMP_PLACES=threads

# Base/GPU/Dockerfile builds MPICH with two netmods: ofi (libfabric, the
# default — tuned for Slingshot on Perlmutter) and ucx. On Vista's InfiniBand
# (ConnectX-7, mlx5_0) UCX is the faster path, especially for GPU buffers, so
# select it explicitly. Apptainer passes these host variables through.
export MPIR_CVAR_CH4_NETMOD=ucx
export UCX_NET_DEVICES=mlx5_0:1
# Fallback if UCX misbehaves: libfabric's verbs provider (works, but slower).
# Force verbs rather than letting it drop to tcp:
#   export MPIR_CVAR_CH4_NETMOD=ofi FI_PROVIDER=verbs
#
# Swapping in Vista's own MVAPICH-Plus is NOT an option: its libmpi has
# soname libmpi.so.0 and is built against the host UCX, while this image's
# software links MPICH's libmpi.so.12.

# Pull once and point this at the resulting .sif. TACC blocks Apptainer on
# Vista's login nodes, so the pull itself has to run under idev or sbatch
# (a plain login-node login(1) shell won't work):
#   idev -p gh-dev -N 1 -n 1 -m 30
#   apptainer pull cudaq.sif docker://docker.io/nersc/cudaq:26.10
IMAGE="$WORK/containers/cudaq.sif"

# What to run inside the container. Defaults to the SC25 tutorial's Hour3
# decoding example; point this at your own script/notebook as needed.
RUN_CMD="python3 Hour3/mhc_qldpc_decoding.py"

# Apptainer's default (non --contain) mode shares the host's /dev, network,
# and PID namespaces as-is — unlike podman-hpc on Perlmutter, no manual
# /dev/infiniband-style device bind-mounts are needed: the container's own
# MPICH+UCX stack just sees the host's real IB devices
# directly through the kernel RDMA interface. --nv handles GPU driver/device
# exposure the way podman-hpc's manual --device/-v nvidia-smi dance did on
# Perlmutter, but automatically (it also injects the driver libs into the
# container's LD_LIBRARY_PATH itself — no manual override needed here).
apptainer exec --nv \
    --bind "$SCRATCH:$SCRATCH" \
    --bind "$WORK:$WORK" \
    --pwd "$PWD" \
    "$IMAGE" \
    bash -c "$RUN_CMD"

# For multi-node cudaq::mpi runs (e.g. distributed state-vector or AFQMC),
# scale -N above and launch one apptainer invocation (one rank) per
# allocated host. Use srun, NOT ibrun: checked on Vista, ibrun defaults to
# MODE=openmpi_ssh (launching through the host's own OpenMPI mpirun) unless
# a TACC MPI module is loaded, which would bypass Slurm PMI entirely — a
# plain self-built MPICH container under that would likely come up as N
# separate size-1 jobs rather than one N-rank job. Slurm offers pmi2/pmix
# directly, which is what this image's MPICH (ch4:ofi,ucx) expects:
#
#   srun --mpi=pmi2 apptainer exec --nv --bind "$SCRATCH:$SCRATCH" \
#       --bind "$WORK:$WORK" --pwd "$PWD" "$IMAGE" bash -c "$RUN_CMD"
#
# Still UNVERIFIED on Vista — a 2-node idev test (idev -p gh-dev -N 2 -n 2)
# was started but cancelled before it ran. Confirm this actually launches
# as one job before trusting it for a real run.
