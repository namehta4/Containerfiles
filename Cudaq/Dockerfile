FROM docker.io/nersc/base_gpu:26.04
WORKDIR /opt
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    libblas-dev \
    liblapack-dev \
    libgsl-dev \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/basic
ENV PATH=/opt/basic/bin:$PATH

RUN pip install --no-cache-dir --upgrade pip build ipython ipykernel

# Pin torch to CUDA 12.9 wheels — runtime only supports CUDA 12.x
RUN pip install --no-cache-dir \
    torch \
    torchvision \
    --index-url https://download.pytorch.org/whl/cu129

RUN pip install --no-cache-dir \
    cuequivariance-ops-torch-cu12 \
    cuequivariance-torch \
    cuequivariance \
    cupy-cuda12x

RUN pip install --no-cache-dir \
    cython \
    setuptools \
    pyfftw

RUN pip install --no-cache-dir mpi4py -i https://pypi.anaconda.org/mpi4py/simple

RUN pip install --no-cache-dir \
    pandas \
    seaborn \
    numpy \
    qibo \
    qibojit \
    jupyterlab \
    notebook \
    lightning \
    transformers \
    ml-collections \
    astpretty \
    scipy \
    requests \
    h5py \
    torchdiffeq \
    scikit-build-core \
    pytest

RUN pip install --no-cache-dir \
    openfermionpyscf==0.4 \
    ffsim \
    pyscf \
    openfermion \
    qiskit \
    qiskit-nature \
    qutip \
    matplotlib \
    general-superstaq \
    qldpc==0.2.1

RUN pip install --no-cache-dir \
    breathe \
    enum_tools \
    myst_parser \
    nbsphinx \
    sphinx_copybutton \
    sphinx_inline_tabs \
    sphinx-cmake \
    sphinx_gallery \
    sphinxcontrib-moderncmakedomain \
    sphinx_reredirects \
    sphinx_toolbox \
    sphinx_rtd_theme \
    sphinx-autobuild \
    sphinxcontrib-napoleon \
    sphinx-autodoc-typehints \
    sphinx-design

ENV PYTHONPATH=/opt/basic/lib/python3.12/site-packages:$PYTHONPATH

#RUN pip install cudaq-qec[tensor-network-decoder] matplotlib scipy

# Install cuTensor
ARG CUTENSOR_INSTALL_PREFIX=/usr/local/cutensor
ARG cutensor_archive=libcutensor-linux-x86_64-2.2.0.0-archive.tar.xz
RUN wget https://developer.download.nvidia.com/compute/cutensor/redist/libcutensor/linux-x86_64/libcutensor-linux-x86_64-2.2.0.0-archive.tar.xz \
    && mkdir -p "${CUTENSOR_INSTALL_PREFIX}" \
    && tar xf "${cutensor_archive}" --strip-components 1 -C "${CUTENSOR_INSTALL_PREFIX}" \
    && rm -rf "${cutensor_archive}"

# --- cuda-quantum: build prerequisites ---

# cmake (pinned <3.29 for scikit-build-core), ninja, auditwheel for wheel repair
RUN pip install --no-cache-dir "cmake>=3.27,<3.29" ninja auditwheel

# System build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    gfortran \
    libtool \
    automake \
    patchelf \
    && rm -rf /var/lib/apt/lists/*

# Clone cuda-quantum with LLVM submodule (submodule needed for LLVM build from source)
RUN git clone --recurse-submodules https://github.com/namehta4/cuda-quantum.git /opt/cuda-quantum

WORKDIR /opt/cuda-quantum

# Zlib 1.3.1 (static) — needed by LLVM linker, OpenSSL, CURL, AWS SDK
ENV ZLIB_INSTALL_PREFIX=/usr/local/zlib
RUN ZLIB_VERSION=1.3.1 && \
    wget https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz && \
    tar xzf zlib-${ZLIB_VERSION}.tar.gz && cd zlib-${ZLIB_VERSION} && \
    CFLAGS="-fPIC" ./configure --prefix=${ZLIB_INSTALL_PREFIX} --static && make && make install && \
    cd contrib/minizip && autoreconf --install && \
    CFLAGS="-fPIC" ./configure --prefix=${ZLIB_INSTALL_PREFIX} --disable-shared && make && make install && \
    cd /opt/cuda-quantum && rm -rf zlib-${ZLIB_VERSION} zlib-${ZLIB_VERSION}.tar.gz

# LLVM (from git submodule) — main compiler infrastructure for cuda-quantum (~30-60 min build)
ENV LLVM_INSTALL_PREFIX=/opt/llvm
ENV PYBIND11_INSTALL_PREFIX=/usr/local/pybind11
RUN bash scripts/build_llvm.sh -v

# BLAS 3.11.0 (static) — needed for certain optimizers
ENV BLAS_INSTALL_PREFIX=/usr/local/blas
RUN BLAS_VERSION=3.11.0 && \
    wget http://www.netlib.org/blas/blas-${BLAS_VERSION}.tgz && \
    tar xzf blas-${BLAS_VERSION}.tgz && cd BLAS-3.11.0 && \
    make FC=gfortran && \
    mkdir -p ${BLAS_INSTALL_PREFIX} && mv blas_*.a ${BLAS_INSTALL_PREFIX}/libblas.a && \
    cd /opt/cuda-quantum && rm -rf BLAS-3.11.0 blas-${BLAS_VERSION}.tgz

# OpenSSL 3.5.1 (static) — needed for CURL and AWS SDK
# Builds its own Perl (5.38.2) to avoid platform-specific module gaps
ENV OPENSSL_INSTALL_PREFIX=/usr/local/openssl
RUN OPENSSL_VERSION=3.5.1 && PERL_VERSION=5.38.2 && \
    BUILDDIR=$(mktemp -d) && cd ${BUILDDIR} && \
    wget https://www.cpan.org/src/5.0/perl-${PERL_VERSION}.tar.gz && \
    tar xzf perl-${PERL_VERSION}.tar.gz && cd perl-${PERL_VERSION} && \
    ./Configure -des -Dprefix=${BUILDDIR}/perl5 && make && make install && \
    cd ${BUILDDIR} && \
    wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz && \
    tar xf openssl-${OPENSSL_VERSION}.tar.gz && cd openssl-${OPENSSL_VERSION} && \
    CFLAGS="-fPIC" CXXFLAGS="-fPIC" \
    ${BUILDDIR}/perl5/bin/perl Configure no-shared \
        --prefix=${OPENSSL_INSTALL_PREFIX} zlib \
        --with-zlib-include=${ZLIB_INSTALL_PREFIX}/include \
        --with-zlib-lib=${ZLIB_INSTALL_PREFIX}/lib && \
    make && make install && \
    rm -rf ${BUILDDIR}

# CURL 8.5.0 (static) — needed for communication with external services
ENV CURL_INSTALL_PREFIX=/usr/local/curl
RUN CURL_VERSION=8.5.0 && \
    BUILDDIR=$(mktemp -d) && cd ${BUILDDIR} && \
    wget https://curl.se/ca/cacert.pem && wget https://curl.se/ca/cacert.pem.sha256 && \
    mkdir -p ${CURL_INSTALL_PREFIX} && mv cacert.pem ${CURL_INSTALL_PREFIX}/ && \
    wget https://github.com/curl/curl/releases/download/curl-8_5_0/curl-${CURL_VERSION}.tar.gz && \
    tar xzf curl-${CURL_VERSION}.tar.gz && cd curl-${CURL_VERSION} && \
    cmake -G Ninja -B build \
        -DCMAKE_C_FLAGS="-fPIC" \
        -DCMAKE_INSTALL_PREFIX=${CURL_INSTALL_PREFIX} \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DCURL_USE_OPENSSL=ON \
        -DOPENSSL_ROOT_DIR=${OPENSSL_INSTALL_PREFIX} \
        -DCURL_ZLIB=ON \
        -DZLIB_ROOT=${ZLIB_INSTALL_PREFIX} \
        -DCURL_CA_BUNDLE=none \
        -DCURL_CA_PATH=none \
        -DCURL_USE_LIBSSH2=OFF -DCURL_USE_LIBPSL=OFF -DUSE_LIBIDN2=OFF \
        -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF -DUSE_NGHTTP2=OFF -DENABLE_ARES=OFF \
        -DCURL_DISABLE_FTP=ON -DCURL_DISABLE_TFTP=ON -DCURL_DISABLE_SMTP=ON \
        -DCURL_DISABLE_LDAP=ON -DCURL_DISABLE_LDAPS=ON -DCURL_DISABLE_SMB=ON \
        -DCURL_DISABLE_GOPHER=ON -DCURL_DISABLE_TELNET=ON -DCURL_DISABLE_RTSP=ON \
        -DCURL_DISABLE_POP3=ON -DCURL_DISABLE_IMAP=ON -DCURL_DISABLE_FILE=ON \
        -DCURL_DISABLE_DICT=ON && \
    cmake --build build --config Release && \
    cmake --install build --config Release && \
    rm -rf ${BUILDDIR}

# AWS SDK C++ 1.11.454 (static) — needed for Braket integration
ENV AWS_INSTALL_PREFIX=/usr/local/aws
RUN BUILDDIR=$(mktemp -d) && cd ${BUILDDIR} && \
    git clone --filter=tree:0 https://github.com/aws/aws-sdk-cpp . && \
    git checkout 1.11.454 && git submodule update --init --recursive && \
    mkdir build && cd build && \
    cmake -G Ninja .. \
        -DCMAKE_INSTALL_PREFIX=${AWS_INSTALL_PREFIX} \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_COMPILE_WARNING_AS_ERROR=OFF \
        -DAWS_SDK_WARNINGS_ARE_ERRORS=OFF \
        -DBUILD_ONLY="braket;s3-crt;sts" \
        -DBUILD_SHARED_LIBS=OFF \
        -DZLIB_ROOT=${ZLIB_INSTALL_PREFIX} \
        -DZLIB_USE_STATIC_LIBS=ON \
        -DOPENSSL_ROOT_DIR=${OPENSSL_INSTALL_PREFIX} \
        -DCURL_LIBRARY=${CURL_INSTALL_PREFIX}/lib/libcurl.a \
        -DCURL_INCLUDE_DIR=${CURL_INSTALL_PREFIX}/include \
        -Dcrypto_LIBRARY=$(find ${OPENSSL_INSTALL_PREFIX} -name libcrypto.a | head -1) \
        -Dcrypto_INCLUDE_DIR=${OPENSSL_INSTALL_PREFIX}/include \
        -DENABLE_TESTING=OFF \
        -DAUTORUN_UNIT_TESTS=OFF && \
    cmake --build . --config=Release && \
    cmake --install . --config=Release && \
    rm -rf ${BUILDDIR}

# QRMI 0.12.0 (pre-built binary) — needed for Pasqal QRMI connector
ENV QRMI_INSTALL_PREFIX=/usr/local/qrmi
RUN QRMI_VERSION=0.12.0 && \
    QRMI_ARCHIVE=libqrmi-${QRMI_VERSION}-el8-x86_64.tar.gz && \
    EXPECTED_SHA256=2986150d4f55e1f6566bef16d9fb3897ca04dd7eaa681865f7ef244f298a6746 && \
    wget https://github.com/qiskit-community/qrmi/releases/download/v${QRMI_VERSION}/${QRMI_ARCHIVE} && \
    computed=$(sha256sum ${QRMI_ARCHIVE} | awk '{print $1}') && \
    [ "$computed" = "$EXPECTED_SHA256" ] || (echo "SHA256 mismatch for QRMI!" && exit 1) && \
    mkdir -p ${QRMI_INSTALL_PREFIX}/include ${QRMI_INSTALL_PREFIX}/lib64 && \
    tar xzf ${QRMI_ARCHIVE} && \
    cp libqrmi-${QRMI_VERSION}/qrmi.h ${QRMI_INSTALL_PREFIX}/include/ && \
    cp libqrmi-${QRMI_VERSION}/libqrmi.so ${QRMI_INSTALL_PREFIX}/lib64/ && \
    rm -rf ${QRMI_ARCHIVE} libqrmi-${QRMI_VERSION}

# cuQuantum 26.01.0.4 — GPU-accelerated quantum simulation backends
ENV CUQUANTUM_INSTALL_PREFIX=/opt/nvidia/cuquantum
RUN CUQUANTUM_VERSION=26.01.0.4 && \
    cuquantum_archive=cuquantum-linux-x86_64-${CUQUANTUM_VERSION}_cuda12-archive.tar.xz && \
    wget https://developer.download.nvidia.com/compute/cuquantum/redist/cuquantum/linux-x86_64/${cuquantum_archive} && \
    mkdir -p ${CUQUANTUM_INSTALL_PREFIX} && \
    tar xf ${cuquantum_archive} --strip-components 1 -C ${CUQUANTUM_INSTALL_PREFIX} && \
    rm -rf ${cuquantum_archive}

# Build the cu12 wheel (all prerequisites pre-installed above — no -p flag needed)
ENV CUDA_QUANTUM_VERSION=0.0.0
ENV CUTENSOR_INSTALL_PREFIX=/usr/local/cutensor
# Patch pyproject.toml.cu12 before building:
#   - Disable warnings-as-errors (compiler version mismatch causes -Werror failures)
#   - Enable verbose cmake output for better diagnostics
#   - Relax cupy version pin (we have 14.x installed, pin is ~=13.6)
RUN sed -i \
    's/cmake\.verbose = false/cmake.verbose = true/' pyproject.toml.cu12 && \
    sed -i \
    's/"-DCUDAQ_ENABLE_PASQAL_QRMI_CONNECTOR=OFF"/"-DCUDAQ_ENABLE_PASQAL_QRMI_CONNECTOR=OFF",\n    "-DCMAKE_COMPILE_WARNING_AS_ERROR=OFF"/' pyproject.toml.cu12 && \
    sed -i \
    "s/'cupy-cuda12x ~= 13.6.0'/'cupy-cuda12x >= 13.6.0'/" pyproject.toml.cu12

# Build wheel, install it, then build nvq++ toolchain from the same _skbuild, then delete
# all build artifacts in one layer so they don't persist in the image.
# _skbuild is ~10-15 GB; keeping creation and deletion in one RUN avoids layer bloat.
RUN cp pyproject.toml.cu12 pyproject.toml && \
    PYTHON=/opt/basic/bin/python3 bash scripts/build_wheel.sh -c 12 -o /opt/cudaq-dist && \
    pip install --no-cache-dir /opt/cudaq-dist/cuda_quantum*.whl && \
    cmake -S /opt/cuda-quantum -B /opt/cuda-quantum/_skbuild \
        -U "Python*" -U "PYTHON*" \
        -DCUDAQ_DISABLE_CPP_FRONTEND=OFF \
        -DCUDAQ_DISABLE_TOOLS=OFF \
        -DPYTHON_EXECUTABLE=/opt/basic/bin/python3 \
        -DPython3_EXECUTABLE=/opt/basic/bin/python3 && \
    ninja -C /opt/cuda-quantum/_skbuild \
        'nvq++' cudaq-target-conf cudaq-quake cudaq-translate cudaq-opt fixup-linkage && \
    for tool in nvq++ cudaq-target-conf cudaq-quake cudaq-translate cudaq-opt fixup-linkage; do \
        [ -f /opt/cuda-quantum/_skbuild/bin/${tool} ] && \
        install -m 755 /opt/cuda-quantum/_skbuild/bin/${tool} \
            /opt/basic/lib/python3.12/site-packages/bin/${tool}; \
    done && \
    rm -rf /opt/cuda-quantum/_skbuild /opt/cuda-quantum/tpls /opt/cudaq-dist
# Note: targets/*.yml are already installed by the pip wheel at site-packages/targets/

WORKDIR /opt
ARG GIT_USERNAME=namehta4
ARG GIT_PASSWORD=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
RUN git clone https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/rr637/QC-AFQMC.git
RUN pip install -e /opt/QC-AFQMC/SC_Tutorial/ipie

# Build and install cudaqx from source
# CUDAQ cmake configs come from the pip wheel install location
ENV CUDAQ_DIR=/opt/basic/lib/python3.12/site-packages/lib/cmake/cudaq
ENV CUDAQX_INSTALL_PREFIX=/opt/nvidia/cudaqx

RUN git clone https://github.com/namehta4/cudaqx.git /opt/cudaqx

RUN apt-get update && apt-get install -y --no-install-recommends doxygen && rm -rf /var/lib/apt/lists/*

RUN cmake -G Ninja -S /opt/cudaqx -B /opt/cudaqx/build \
        -DCMAKE_INSTALL_PREFIX=${CUDAQX_INSTALL_PREFIX} \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_COMPILE_WARNING_AS_ERROR=OFF \
        -DCUDAQ_DIR=${CUDAQ_DIR} \
        -DLLVM_DIR=/opt/llvm/lib/cmake/llvm \
        -DCUDAQX_ENABLE_LIBS="qec;solvers" \
        -DCUDAQX_BINDINGS_PYTHON=ON \
        -DCUDAQX_INCLUDE_DOCS=OFF \
        -DCUDAQX_INCLUDE_TESTS=OFF && \
    ninja -C /opt/cudaqx/build install && \
    rm -rf /opt/cudaqx/build

# libcudaq-em-default.so defines getRegisteredExecutionManager() which libcudaq-qec.so needs.
# It gets loaded and immediately unloaded during 'import cudaq' (ref count drops to 0 when no
# permanent handle holds it), so the symbol is absent when cudaq_qec is imported next.
# Fix: add it as an explicit NEEDED dependency of libcudaq-qec.so so the dynamic linker
# keeps it resident whenever libcudaq-qec.so is loaded.
RUN patchelf --add-needed libcudaq-em-default.so \
        /opt/nvidia/cudaqx/lib/libcudaq-qec.so

ENV PYTHONPATH=${CUDAQX_INSTALL_PREFIX}:${CUDAQX_INSTALL_PREFIX}/lib/python3.12/site-packages:$PYTHONPATH
ENV PATH=${CUDAQX_INSTALL_PREFIX}/bin:$PATH

# Strip debug symbols from shared libraries to reduce image size
RUN find /opt/basic/lib/python3.12/site-packages/lib \
         /opt/nvidia/cudaqx/lib \
         /opt/nvidia/cuquantum/lib \
         -name "*.so*" -type f \
         -exec strip --strip-debug {} \; 2>/dev/null || true && \
    find /opt/llvm/lib -name "*.so*" -type f \
         -exec strip --strip-debug {} \; 2>/dev/null || true && \
    rm -rf /root/.cache /tmp/* /var/tmp/*
