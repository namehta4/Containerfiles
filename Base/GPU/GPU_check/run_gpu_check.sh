#!/usr/bin/bash

#SBATCH -A nstaff
#SBATCH -C gpu
#SBATCH --qos debug
#SBATCH -t 0:10:00
#SBATCH -N 2
#SBATCH --ntasks-per-node=4
#SBATCH --gpus-per-task=1
#SBATCH --gpu-bind=none
#SBATCH --exclusive

export CRAY_ACCEL_TARGET=nvidia80

IMAGE="docker://docker.io/nersc/lammps:26.02"

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
  -e LD_LIBRARY_PATH=/usr/local/nvidia/lib64:${LD_PATH} \
  -v $SCRATCH:$SCRATCH -w $PWD"

srun --cpu-bind=none --mpi=pmi2 \
     podman-hpc run $PODMAN_ARGS $IMAGE \
     python3 $PWD/gpu_check.py
