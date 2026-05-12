FROM docker.io/nersc/base_gpu:26.04
WORKDIR /opt
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update
RUN apt-get install -y libblas-dev liblapack-dev libgsl-dev

RUN python3 -m venv /opt/basic
ENV PATH=$PATH:/opt/basic/bin
RUN ln -sf /opt/basic/bin/pip /usr/local/bin/pip
RUN pip install cuequivariance-ops-torch-cu12 cuequivariance-torch cuequivariance
RUN pip install cupy-cuda12x
RUN pip install cython setuptools pyfftw
RUN pip install torch torchvision --index-url https://download.pytorch.org/whl/cu128
RUN pip install mace-torch
RUN pip install mpi4py -i https://pypi.anaconda.org/mpi4py/simple
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

#Installing Plumed
WORKDIR /opt
RUN git clone -b v2.10 https://github.com/plumed/plumed2.git                 && \
    cd plumed2                                                              && \
    ./configure CC=mpicc CXX=mpicxx --enable-modules=all --disable-python --prefix=/opt/plumed/install && \
    make -j 4                                                               && \
    make install
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
          -DGMX_BUILD_OWN_FFTW=ON -DREGRESSIONTEST_DOWNLOAD=ON \
          -DGMX_MPI=on -DGMX_SIMD=AVX2_256 -DGMX_GPU=CUDA \ 
          -DGMX_CUDA_TARGET_COMPUTE=80 -DBUILD_SHARED_LIBS=OFF \
          -DGMX_PREFER_STATIC_LIBS=ON ../                                   && \
    make -j 20                                                              && \
    make install    

ENV PATH=/opt/gromacs/install/bin:$PATH
ENV PATH=/opt/gromacs/install/lib:$PATH
ENV LD_LIBRARY_PATH=/opt/gromacs/install/lib:$LD_LIBRARY_PATH
ENV PKG_CONFIG_PATH=/opt/gromacs/install/lib/pkgconfig:$PKG_CONFIG_PATH
ENV MANPATH=/opt/gromacs/install/share/man/:$MANPATH

