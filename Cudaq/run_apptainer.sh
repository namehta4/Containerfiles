#!/usr/bin/bash

#SBATCH -A <allocation>      # Your Vista project/allocation
#SBATCH -p gh                # gh-dev instead for short test runs (<=2h, <=8 nodes)
#SBATCH -t 00:30:00
#SBATCH -N 1                 # gh/gh-dev nodes have exactly 1 H200 GPU each — scale
#SBATCH -n 1                 # via -N for multi-GPU/multi-node, not GPUs-per-node
#SBATCH -J cudaq
# Do not request specific nodes (TACC policy on Vista).

export OMP_NUM_THREADS=1
export OMP_PROC_BIND=spread
export OMP_PLACES=threads

# Base/GPU/Dockerfile builds libfabric with both the cxi provider (Slingshot,
# for Perlmutter) and verbs (InfiniBand, for Vista's Quantum-2 NDR fabric)
# compiled in. Force verbs explicitly rather than letting it fall back to
# tcp — the only interconnect workaround TACC's own container docs mention is
# an FI_PROVIDER=tcp fallback for old Mellanox drivers on unrelated RTX
# nodes; that's not what we want on Vista's NDR ConnectX-7 fabric.
export FI_PROVIDER=verbs

# Pull once on a login node (compute nodes typically have no internet
# egress) and point this at the resulting .sif:
#   apptainer pull cudaq.sif docker://docker.io/nersc/cudaq:26.10
IMAGE="$WORK/containers/cudaq.sif"

# What to run inside the container. Defaults to the SC25 tutorial's Hour3
# decoding example; point this at your own script/notebook as needed.
RUN_CMD="python3 Hour3/mhc_qldpc_decoding.py"

# Apptainer's default (non --contain) mode shares the host's /dev, network,
# and PID namespaces as-is — unlike podman-hpc on Perlmutter, no manual
# /dev/infiniband-style device bind-mounts are needed: the container's own
# MPICH+libfabric(verbs) stack just sees the host's real IB devices
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
# scale -N above and launch through ibrun so one apptainer invocation (and
# one rank) is spawned per allocated host:
#
#   ibrun apptainer exec --nv --bind "$SCRATCH:$SCRATCH" --bind "$WORK:$WORK" \
#       --pwd "$PWD" "$IMAGE" bash -c "$RUN_CMD"
#
# This is UNVERIFIED on Vista specifically — TACC's own docs show ibrun
# launching multi-node apptainer+MPI jobs successfully in general, but that
# depends on ibrun's process launch (PMI/PMIx) being compatible with
# whatever MPI is actually built into the container. Confirm on a small
# interactive allocation first (idev -p gh-dev -N 2 -n 2) before trusting
# this for a real job.
