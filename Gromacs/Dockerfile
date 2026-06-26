FROM docker.io/nersc/base_gpu:26.04
WORKDIR /opt
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && \
    apt-get install -y libblas-dev liblapack-dev libgsl-dev unzip && \
    rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/basic
ENV PATH=$PATH:/opt/basic/bin
RUN ln -sf /opt/basic/bin/pip /usr/local/bin/pip
RUN pip install --no-cache-dir cuequivariance-ops-torch-cu12 cuequivariance-torch cuequivariance
RUN pip install --no-cache-dir cupy-cuda12x
RUN pip install --no-cache-dir cython setuptools pyfftw
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cu128
RUN pip install --no-cache-dir mace-torch
RUN pip install --no-cache-dir mpi4py -i https://pypi.anaconda.org/mpi4py/simple
ENV PATH=$PATH:/opt/basic/bin
ENV PYTHONPATH=$PYTHONPATH:/opt/basic/lib/python3.12/site-packages

ENV PATH=$PATH:/opt/lammps/build/plumed_build-prefix/bin
ENV PATH=$PATH:/opt/lammps/build/plumed_build-prefix/include
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/lammps/build/plumed_build-prefix/lib
ENV PKG_CONFIG_PATH=$PKG_CONFIG_PATH:/opt/lammps/build/plumed_build-prefix/lib/pkgconfig
ENV PLUMED_KERNEL=/opt/lammps/build/plumed_build-prefix/lib/libplumedKernel.so
ARG BLAS_LIBRARIES=/usr/local/blas/lib
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/fftw/install/lib
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/blas
ENV PKG_CONFIG_PATH=$PKG_CONFIG_PATH:/opt/fftw

# Installing libtorch
RUN wget https://download.pytorch.org/libtorch/cu128/libtorch-shared-with-deps-2.11.0%2Bcu128.zip -O /opt/libtorch-shared-with-deps-2.11.0+cu128.zip && \
    unzip /opt/libtorch-shared-with-deps-2.11.0+cu128.zip -d /opt && \
    rm /opt/libtorch-shared-with-deps-2.11.0+cu128.zip
ENV LIBTORCH=/opt/libtorch
ENV LD_LIBRARY_PATH=/opt/libtorch/lib:$LD_LIBRARY_PATH

# Extract only cuFFTMp headers + shared lib from HPC SDK deb (no static libs, no other math libs)
RUN printf 'import tarfile,sys\nwith tarfile.open(fileobj=sys.stdin.buffer,mode="r|") as tf:\n    for m in tf:\n        n=m.name\n        if ("cufftmp" in n.lower() or "libcufftMp" in n) and not n.endswith(".a"):\n            m.name=n.lstrip("./")\n            tf.extract(m,"/",set_attrs=False)\n' > /tmp/extract_math.py
RUN wget -qO- https://developer.download.nvidia.com/hpc-sdk/ubuntu/DEB-GPG-KEY-NVIDIA-HPC-SDK | \
        gpg --dearmor -o /usr/share/keyrings/nvidia-hpcsdk-keyring.gpg && \
    echo 'deb [signed-by=/usr/share/keyrings/nvidia-hpcsdk-keyring.gpg] https://developer.download.nvidia.com/hpc-sdk/ubuntu/amd64/ /' \
        > /etc/apt/sources.list.d/nvhpc.list && \
    apt-get update && \
    apt-get download nvhpc-26-3 && \
    dpkg-deb --fsys-tarfile nvhpc-26-3_26.3-0_amd64.deb | python3 /tmp/extract_math.py && \
    rm nvhpc-26-3_26.3-0_amd64.deb /tmp/extract_math.py /etc/apt/sources.list.d/nvhpc.list && \
    rm -rf /var/lib/apt/lists/*
ENV NVHPC_MATH=/opt/nvidia/hpc_sdk/Linux_x86_64/26.3/math_libs/13.1/targets/x86_64-linux
ENV LD_LIBRARY_PATH=${NVHPC_MATH}/lib:$LD_LIBRARY_PATH

# Build NVSHMEM from source against MPICH (provides libnvshmem_host.so needed by libcufftMp)
WORKDIR /opt
ARG NVSHMEM_VER=3.6.5-0
RUN wget https://github.com/NVIDIA/nvshmem/archive/refs/tags/v${NVSHMEM_VER}.tar.gz -O nvshmem.tar.gz && \
    tar -xf nvshmem.tar.gz && \
    cd nvshmem-${NVSHMEM_VER} && \
    cmake -S . -B build \
          -DCMAKE_INSTALL_PREFIX=/opt/nvshmem/install \
          -DNVSHMEM_MPI_SUPPORT=ON \
          -DMPI_HOME=/usr \
          -DNVSHMEM_UCX_SUPPORT=ON \
          -DUCX_HOME=/usr \
          -DCMAKE_CUDA_ARCHITECTURES="80;86;89;90" \
          -DNVSHMEM_BUILD_EXAMPLES=OFF \
          -DNVSHMEM_BUILD_TESTS=OFF && \
    cmake --build build -j$(nproc) && \
    cmake --install build && \
    cd .. && rm -rf nvshmem-${NVSHMEM_VER} nvshmem.tar.gz
ENV LD_LIBRARY_PATH=/opt/nvshmem/install/lib:$LD_LIBRARY_PATH

#Installing Plumed with multi-GPU support
WORKDIR /opt
RUN git clone -b v2.10 https://github.com/plumed/plumed2.git                && \
    cd plumed2                                                              && \
    ./configure CC=mpicc CXX=mpicxx CXXFLAGS="-std=c++17 -O3 -mavx2 -mfma -ffast-math -DUSE_CUDA" \
    CPPFLAGS="-I/opt/libtorch/include -I/opt/libtorch/include/torch/csrc/api/include -I/usr/local/cuda/include" \
    LDFLAGS="-L/opt/libtorch/lib -L/usr/local/cuda/lib64 -Wl,-rpath,/opt/libtorch/lib:/usr/local/cuda/lib64" \
    --enable-modules=all+opes+pytorch --enable-python                       \
    --enable-libtorch --enable-cuda --prefix=/opt/plumed/install           && \
    echo "=== libtorch config.log ===" && grep -A 5 "checking libtorch" config.log && \
    echo "=== end ===" && \
    make -j 4                                                               && \
    make install                                                            && \
    cd /opt && rm -rf /opt/plumed2
ENV PATH=/opt/plumed/install/bin:$PATH
ENV LD_LIBRARY_PATH=/opt/plumed/install/lib:$LD_LIBRARY_PATH
ENV PLUMED_KERNEL=/opt/plumed/install/lib/libplumedKernel.so

# Install GROMACS
WORKDIR /opt
ARG gromacs=2025.0
ARG gmx_prefix=gromacs-$gromacs
RUN git clone -b v2025.0 https://github.com/Colvars/gromacs.git gromacs    
WORKDIR /opt/gromacs/src/gromacs/utility
RUN sed -i 's\MPIX_Query_cuda_support()\1\g' mpiinfo.cpp
WORKDIR /opt
RUN cd gromacs                                                              && \
    plumed patch -p --runtime -e $gmx_prefix                                && \
    mkdir build && cd build                                                 && \
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/gromacs/install  \
          -DCMAKE_PREFIX_PATH="/opt/libtorch;/usr/local/cuda" \
          -DCMAKE_CUDA_ARCHITECTURES="80;86;89;90" \
          -DGMX_BUILD_OWN_FFTW=ON -DREGRESSIONTEST_DOWNLOAD=ON \
          -DGMX_MPI=on -DGMX_OPENMP=ON -DGMX_SIMD=AVX2_256 -DGMX_GPU=CUDA \
          -DGMX_CUDA_TARGET_COMPUTE=80 -DBUILD_SHARED_LIBS=OFF \
          -DGMX_PREFER_STATIC_LIBS=ON \
          -DGMX_USE_CUFFTMP=ON \
          -DcuFFTMp_ROOT=/opt/nvidia/hpc_sdk/Linux_x86_64/26.3/math_libs/13.1/targets/x86_64-linux \
          -DNVSHMEM_ROOT=/opt/nvshmem/install \
          -DGMX_GPU_PME_PP_COMMUNICATION=ON \
          -DGMX_MPI_GPU_AWARE_SUPPORT=ON \
          -DTORCH_CUDA_ARCH_LIST="8.0" ../                                  && \
    make -j 20                                                              && \
    make install                                                            && \
    cd /opt && rm -rf /opt/gromacs

ENV PATH=/opt/gromacs/install/bin:$PATH
ENV LD_LIBRARY_PATH=/opt/gromacs/install/lib:$LD_LIBRARY_PATH
ENV PKG_CONFIG_PATH=/opt/gromacs/install/lib/pkgconfig:$PKG_CONFIG_PATH
ENV MANPATH=/opt/gromacs/install/share/man/:$MANPATH

# Multi-GPU configuration
ENV CUDA_VISIBLE_DEVICES=0,1,2,3
ENV CUDA_DEVICE_ORDER=PCI_BUS_ID
ENV OMP_NUM_THREADS=8
ENV GMX_GPU_DD_COMMS=on
ENV GMX_GPU_PMEPME_COMMS=on
ENV NCCL_DEBUG=INFO

