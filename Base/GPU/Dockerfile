FROM nvcr.io/nvidia/cuda:12.9.1-cudnn-devel-ubuntu24.04
WORKDIR /opt
ENV DEBIAN_FRONTEND noninteractive

# TARGETARCH is populated automatically by podman/buildah (and docker buildx)
# from --platform: "amd64" on Perlmutter-class x86_64 hosts, "arm64" on
# Grace/Grace-Hopper hosts (e.g. TACC Vista). The CUDA toolkit installs its
# per-arch libs under a differently-named "targets/<arch>-linux" directory
# (x86_64-linux vs sbsa-linux) — alias it to one stable path so the rest of
# this file doesn't need to branch on arch again.
ARG TARGETARCH
RUN set -eu; \
    case "${TARGETARCH}" in \
      amd64) arch_dir=x86_64-linux ;; \
      arm64) arch_dir=sbsa-linux ;; \
      *) echo "Unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    ln -s "/usr/local/cuda/targets/${arch_dir}" /usr/local/cuda/targets/this-arch

RUN apt-get update
RUN apt-get install -y \
        build-essential ca-certificates pkg-config automake autoconf libtool  \ 
        cmake gdb strace wget git bzip2 python3 python3-pip python3-venv      \
        python3-dev python-is-python3 build-essential gfortran rdma-core      \
        numactl libconfig-dev libuv1-dev libfuse-dev libfuse3-dev libyaml-dev \
        libnl-3-dev libnuma-dev libsensors-dev libcurl4-openssl-dev libjson-c-dev \
        libibverbs-dev librdmacm-dev plocate vim libzip-dev \
        --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Install XPMEM
# Use commit according to Spack package versioning rule:
# https://github.com/spack/spack/blob/develop/var/spack/repos/spack_repo/builtin/packages/xpmem/package.py#L28
ARG xpmem_ref=0d0bad4e1d07b38d53ecc8f20786bb1328c446da
RUN git clone https://github.com/hpc/xpmem.git \
    && cd xpmem \
    && git checkout ${xpmem_ref} \
    && ./autogen.sh \
    && ./configure --prefix=/usr --with-default-prefix=/usr --disable-kernel-module \
    && make -j$(nproc) \
    && make install \
    && cd .. \
    && rm -r xpmem

ARG GDRCOPY_VER=2.5
RUN git clone --depth 1 --branch v${GDRCOPY_VER} https://github.com/NVIDIA/gdrcopy.git \
    && cd gdrcopy \
    && export CUDA_PATH=${CUDA_HOME:-$(echo $(which nvcc) | grep -o '.*cuda')} \
    && make CC=gcc CUDA=$CUDA_PATH lib \
    && make lib_install \
    && cd ../ && rm -rf gdrcopy

ARG cassini_headers_version=release/shs-12.0.1
RUN git clone --branch ${cassini_headers_version} --depth 1 https://github.com/HewlettPackard/shs-cassini-headers.git \
    && cd shs-cassini-headers \
    && cp -r include/* /usr/include/ \
    && cp -r share/* /usr/share/ \
    && cd .. \
    && rm -r shs-cassini-headers

ARG cxi_driver_version=release/shs-12.0.1
RUN git clone --branch ${cxi_driver_version} --depth 1 https://github.com/HewlettPackard/shs-cxi-driver.git \
    && cd shs-cxi-driver \
    && cp -r include/* /usr/include/ \
    && cd .. \
    && rm -r shs-cxi-driver

ARG libcxi_version=release/shs-12.0.1
RUN git clone --branch ${libcxi_version} --depth 1 https://github.com/HewlettPackard/shs-libcxi.git \
    && cd shs-libcxi \
    && ./autogen.sh \
    && ./configure --prefix=/usr --with-cuda=/usr/local/cuda \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && cd .. \
    && rm -r shs-libcxi

# Install libfabric
# Build in both the "cxi" provider (HPE Slingshot-11, used on Perlmutter) and
# the "verbs" provider (InfiniBand, used on TACC Vista's Grace-Hopper nodes)
# so the same binary works on either fabric — libfabric picks the matching
# provider for the hardware it finds on the host at runtime.
ARG libfabric_version=2.1.0
RUN git clone --branch v${libfabric_version} --depth 1 https://github.com/ofiwg/libfabric.git \
    && cd libfabric \
    && ./autogen.sh \
    && ./configure --prefix=/usr --with-cuda=/usr/local/cuda --enable-cuda-dlopen --enable-gdrcopy-dlopen --enable-xpmem=/usr --enable-cxi --enable-verbs --enable-lnx --enable-efa \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && cd .. \
    && rm -rf libfabric

# Install UCX
# UCX is MPICH's netmod on InfiniBand systems (TACC Vista) — see the MPICH
# step below. Request verbs/rdmacm/xpmem explicitly so configure fails loudly
# instead of silently building a UCX without the IB or XPMEM transports.
ARG UCX_VERSION=1.20.0
RUN wget -q https://github.com/openucx/ucx/releases/download/v${UCX_VERSION}/ucx-${UCX_VERSION}.tar.gz \
    && tar xzf ucx-${UCX_VERSION}.tar.gz \
    && cd ucx-${UCX_VERSION} \
    && mkdir build \
    && cd build \
    && ../configure --prefix=/usr --with-cuda=/usr/local/cuda --with-gdrcopy=/usr/local \
       --with-verbs --with-rdmacm --with-xpmem=/usr --enable-mt --enable-devel-headers \
    && make -j$(nproc) \
    && make install \
    && cd ../.. \
    && rm -rf ucx-${UCX_VERSION}.tar.gz ucx-${UCX_VERSION}

# Install mpich
# Build both ch4 netmods and pick one at launch with MPIR_CVAR_CH4_NETMOD:
#   ofi (default, first in the list) -> libfabric cxi on Slingshot (Perlmutter)
#   ucx                              -> UCX over InfiniBand (TACC Vista)
# so one image runs at full speed on either fabric. XPMEM adds the
# single-copy intra-node path (/dev/xpmem is present on both systems).
# The netmod check reads the configured device from mpichinfo.h rather than
# running mpichversion, which needs the host driver's libcuda.so.1.
ARG MPI_VER=5.0.1
RUN wget -q https://www.mpich.org/static/downloads/${MPI_VER}/mpich-${MPI_VER}.tar.gz \
    && tar xf mpich-${MPI_VER}.tar.gz \
    && cd mpich-${MPI_VER} \
    && ./autogen.sh \
    && ./configure --prefix=/usr --enable-fast=O3,ndebug \
       --enable-fortran --disable-cxx \
       --with-device=ch4:ofi,ucx --with-libfabric=/usr --with-ucx=/usr \
       --with-xpmem=/usr \
       --with-cuda=/usr/local/cuda \
       CFLAGS="-L/usr/local/cuda/targets/this-arch/lib/stubs/ -lcuda" \
       CXXFLAGS="-L/usr/local/cuda/targets/this-arch/lib/stubs/ -lcuda" \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && grep -E 'MPICH_DEVICE ".*ofi.*ucx' src/include/mpichinfo.h \
    && cd .. \
    && rm -rf mpich-${MPI_VER}.tar.gz mpich-${MPI_VER}


#Install FFTW
# --enable-sse2/avx/avx2 are x86-only SIMD flags and fail configure on arm64;
# use --enable-neon there instead.
WORKDIR /opt
RUN wget https://fftw.org/pub/fftw/fftw-3.3.10.tar.gz                         && \
    tar -xvzf fftw-3.3.10.tar.gz                                              && \
    mv fftw-3.3.10 fftw                                                       && \
    cd /opt/fftw                                                              && \
    case "${TARGETARCH}" in \
      amd64) SIMD_FLAGS="--enable-sse2 --enable-avx --enable-avx2" ;; \
      arm64) SIMD_FLAGS="--enable-neon" ;; \
    esac && \
    ./configure --prefix=/opt/fftw/install MPICC=mpicc                           \
                --enable-shared --enable-static --enable-mpi                     \
                --enable-threads ${SIMD_FLAGS}                                && \
    make -j 4                                                                 && \
    make install
ENV PATH=$PATH:/opt/fftw/install/bin
ENV PATH=$PATH:/opt/fftw/install/include
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/fftw/install/lib


ENV PATH=$PATH:/usr/local/cuda/lib64/stubs
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64/stubs
ENV PATH=$PATH:/usr/local/cuda/targets/this-arch/lib/stubs
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/compat/:/usr/local/cuda/targets/this-arch/lib/stubs
RUN ln -s /usr/local/cuda/targets/this-arch/lib/stubs/libnvidia-ml.so /usr/local/cuda/targets/this-arch/lib/stubs/libnvidia-ml.so.1

#Install HDF5
WORKDIR /opt
RUN git clone -b hdf5_1_14_3 https://github.com/HDFGroup/hdf5.git hdf5    
RUN cd hdf5                                                                 && \
    mkdir build                                                             && \
    cd build                                                                && \
    cmake -G "Unix Makefiles" -DCMAKE_C_COMPILER=mpicc -DCMAKE_CXX_COMPILER=mpicxx \
          -DCMAKE_Fortran_COMPILER=mpif90 \
          -DCMAKE_BUILD_TYPE:STRING=Release -DBUILD_SHARED_LIBS:BOOL=ON \
          -DBUILD_TESTING:BOOL=ON -DHDF5_BUILD_TOOLS:BOOL=ON -DHDF5_BUILD_FORTRAN:BOOL=ON \
          -DHDF5_ENABLE_PARALLEL=ON -D CMAKE_INSTALL_PREFIX=/opt/hdf5/install ../ && \
    cmake --build . --config Release --parallel $(nproc)                    && \
    cpack -C Release CPackConfig.cmake                                      && \
    make -j 4                                                               && \
    make install
ENV PATH=$PATH:/opt/hdf5/install/bin
ENV PATH=$PATH:/opt/hdf5/install/lib
ENV PATH=$PATH:/opt/hdf5/install/include
ENV PATH=$PATH:/opt/hdf5/install/share
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/hdf5/install/lib
