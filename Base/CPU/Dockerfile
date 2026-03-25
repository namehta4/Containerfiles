FROM ubuntu:24.04
WORKDIR /opt
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update 
RUN apt-get install -y \
        build-essential ca-certificates pkg-config automake autoconf libtool  \ 
        cmake gdb strace wget git bzip2 python3 python3-pip python3-venv      \
        python3-dev python-is-python3 build-essential gfortran rdma-core      \
        numactl libconfig-dev libuv1-dev libfuse-dev libfuse3-dev libyaml-dev \
        libnl-3-dev libnuma-dev libsensors-dev libcurl4-openssl-dev libjson-c-dev \
        libibverbs-dev plocate vim libzip-dev \
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
    && ./configure --prefix=/usr \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && cd .. \
    && rm -r shs-libcxi

# Install libfabric
ARG libfabric_version=2.1.0
RUN git clone --branch v${libfabric_version} --depth 1 https://github.com/ofiwg/libfabric.git \
    && cd libfabric \
    && ./autogen.sh \
    && ./configure --prefix=/usr --enable-xpmem=/usr --enable-cxi --enable-lnx --enable-efa \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && cd .. \
    && rm -rf libfabric

# Install UCX
ARG UCX_VERSION=1.20.0
RUN wget -q https://github.com/openucx/ucx/releases/download/v${UCX_VERSION}/ucx-${UCX_VERSION}.tar.gz \
    && tar xzf ucx-${UCX_VERSION}.tar.gz \
    && cd ucx-${UCX_VERSION} \
    && mkdir build \
    && cd build \
    && ../configure --prefix=/usr --enable-mt --enable-devel-headers \
    && make -j$(nproc) \
    && make install \
    && cd ../.. \
    && rm -rf ucx-${UCX_VERSION}.tar.gz ucx-${UCX_VERSION}

# Install mpich
ARG MPI_VER=5.0.0
RUN wget -q https://www.mpich.org/static/downloads/${MPI_VER}/mpich-${MPI_VER}.tar.gz \
    && tar xf mpich-${MPI_VER}.tar.gz \
    && cd mpich-${MPI_VER} \
    && ./autogen.sh \
    && ./configure --prefix=/usr --enable-fast=O3,ndebug \
       --enable-fortran --disable-cxx \
       --with-device=ch4:ofi --with-libfabric=/usr \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && cd .. \
    && rm -rf mpich-${MPI_VER}.tar.gz mpich-${MPI_VER}


#Install FFTW
WORKDIR /opt
RUN wget https://fftw.org/pub/fftw/fftw-3.3.10.tar.gz                         && \
    tar -xvzf fftw-3.3.10.tar.gz                                              && \
    mv fftw-3.3.10 fftw                                                       && \
    cd /opt/fftw                                                              && \
    ./configure --prefix=/opt/fftw/install MPICC=mpicc                           \
                --enable-shared --enable-static --enable-mpi                     \
                --enable-threads --enable-sse2 --enable-avx --enable-avx2     && \
    make -j 4                                                                 && \
    make install
ENV PATH=$PATH:/opt/fftw/install/bin
ENV PATH=$PATH:/opt/fftw/install/include
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/fftw/install/lib


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
    cmake --build . --config Release                                        && \
#    ctest -C Release                                                        && \
    cpack -C Release CPackConfig.cmake                                      && \
    make -j 4                                                               && \
    make install
ENV PATH=$PATH:/opt/hdf5/install/bin
ENV PATH=$PATH:/opt/hdf5/install/lib
ENV PATH=$PATH:/opt/hdf5/install/include
ENV PATH=$PATH:/opt/hdf5/install/share
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/hdf5/install/lib
