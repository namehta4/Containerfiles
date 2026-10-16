# Default assumes base_gpu:26.10 is a pushed multi-arch manifest combining
# 26.10-amd64 and 26.10-arm64. Until that manifest exists, override per
# build host to match whatever you actually tagged the base image locally,
# e.g.: --build-arg BASE_IMAGE=docker.io/nersc/base_gpu:26.10-amd64
ARG BASE_IMAGE=docker.io/nersc/base_gpu:26.10
FROM ${BASE_IMAGE}
WORKDIR /opt
ENV DEBIAN_FRONTEND=noninteractive

# amd64 = Perlmutter (x86_64 + A100), arm64 = Grace/Grace-Hopper (e.g. TACC
# Vista). NVIDIA's redistributable archives use "x86_64" and "sbsa" for these
# two targets respectively — map TARGETARCH to that naming once, up front.
ARG TARGETARCH
RUN set -eu; \
    case "${TARGETARCH}" in \
      amd64) echo x86_64 > /tmp/nv_arch ;; \
      arm64) echo sbsa   > /tmp/nv_arch ;; \
      *) echo "Unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac

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

# Prefer mpi4py's own wheel index; if it is unreachable, fall back to PyPI.
# Neither wheel bundles MPI: both load the base image's MPICH (libmpi.so.12)
# at runtime, so transport (ofi/cxi, ucx) is whatever MPICH selects.
RUN pip install --no-cache-dir mpi4py -i https://pypi.anaconda.org/mpi4py/simple \
    || pip install --no-cache-dir mpi4py

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

# Install cuTensor (same version, per-arch archive: linux-x86_64 or linux-sbsa)
ARG CUTENSOR_INSTALL_PREFIX=/usr/local/cutensor
ARG CUTENSOR_VERSION=2.2.0.0
RUN nv_arch=$(cat /tmp/nv_arch) && \
    cutensor_archive="libcutensor-linux-${nv_arch}-${CUTENSOR_VERSION}-archive.tar.xz" && \
    wget "https://developer.download.nvidia.com/compute/cutensor/redist/libcutensor/linux-${nv_arch}/${cutensor_archive}" \
    && mkdir -p "${CUTENSOR_INSTALL_PREFIX}" \
    && tar xf "${cutensor_archive}" --strip-components 1 -C "${CUTENSOR_INSTALL_PREFIX}" \
    && rm -rf "${cutensor_archive}"

# --- cuda-quantum: build prerequisites ---

# cuda-quantum 0.16.0 requires cmake>=4.0 and nanobind (python/cudaq bindings
# have moved off pybind11-only); ninja/auditwheel unchanged.
RUN pip install --no-cache-dir "cmake>=4.0" "nanobind>=2.12.0,<3" ninja auditwheel

# System build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    gfortran \
    libtool \
    automake \
    patchelf \
    && rm -rf /var/lib/apt/lists/*

# Clone cuda-quantum with LLVM submodule (submodule needed for LLVM build from source).
# Pinned to the 0.16.0 release tag on NVIDIA's own repo (previously built from
# a personal fork — compared it against upstream: it was 841 commits behind
# with one commit that only touched NVIDIA's own CI dev-container files, none
# of which this Dockerfile's build path uses, so nothing is lost by dropping it).
RUN git clone --recurse-submodules --branch 0.16.0 https://github.com/NVIDIA/cuda-quantum.git /opt/cuda-quantum

WORKDIR /opt/cuda-quantum

# Zlib 1.3.1 (static) — needed by LLVM linker, OpenSSL, CURL, AWS SDK
ENV ZLIB_INSTALL_PREFIX=/usr/local/zlib
RUN ZLIB_VERSION=1.3.1 && \
    wget https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz && \
    tar xzf zlib-${ZLIB_VERSION}.tar.gz && cd zlib-${ZLIB_VERSION} && \
    CFLAGS="-fPIC" ./configure --prefix=${ZLIB_INSTALL_PREFIX} --static && make -j$(nproc) && make install && \
    cd contrib/minizip && autoreconf --install && \
    CFLAGS="-fPIC" ./configure --prefix=${ZLIB_INSTALL_PREFIX} --disable-shared && make -j$(nproc) && make install && \
    cd /opt/cuda-quantum && rm -rf zlib-${ZLIB_VERSION} zlib-${ZLIB_VERSION}.tar.gz

# LLVM (from git submodule) — main compiler infrastructure for cuda-quantum (~30-60 min build)
ENV LLVM_INSTALL_PREFIX=/opt/llvm
ENV PYBIND11_INSTALL_PREFIX=/usr/local/pybind11
# Pass -j explicitly so the LLVM ninja build uses every core on the build node.
RUN bash scripts/build_llvm.sh -v -j $(nproc)

# BLAS 3.11.0 (static) — needed for certain optimizers
ENV BLAS_INSTALL_PREFIX=/usr/local/blas
RUN BLAS_VERSION=3.11.0 && \
    wget http://www.netlib.org/blas/blas-${BLAS_VERSION}.tgz && \
    tar xzf blas-${BLAS_VERSION}.tgz && cd BLAS-3.11.0 && \
    make -j$(nproc) FC=gfortran && \
    mkdir -p ${BLAS_INSTALL_PREFIX} && mv blas_*.a ${BLAS_INSTALL_PREFIX}/libblas.a && \
    cd /opt/cuda-quantum && rm -rf BLAS-3.11.0 blas-${BLAS_VERSION}.tgz

# OpenSSL 3.5.1 (static) — needed for CURL and AWS SDK
# Builds its own Perl (5.38.2) to avoid platform-specific module gaps
ENV OPENSSL_INSTALL_PREFIX=/usr/local/openssl
RUN OPENSSL_VERSION=3.5.1 && PERL_VERSION=5.38.2 && \
    BUILDDIR=$(mktemp -d) && cd ${BUILDDIR} && \
    wget https://www.cpan.org/src/5.0/perl-${PERL_VERSION}.tar.gz && \
    tar xzf perl-${PERL_VERSION}.tar.gz && cd perl-${PERL_VERSION} && \
    ./Configure -des -Dprefix=${BUILDDIR}/perl5 && make -j$(nproc) && make install && \
    cd ${BUILDDIR} && \
    wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz && \
    tar xf openssl-${OPENSSL_VERSION}.tar.gz && cd openssl-${OPENSSL_VERSION} && \
    CFLAGS="-fPIC" CXXFLAGS="-fPIC" \
    ${BUILDDIR}/perl5/bin/perl Configure no-shared \
        --prefix=${OPENSSL_INSTALL_PREFIX} zlib \
        --with-zlib-include=${ZLIB_INSTALL_PREFIX}/include \
        --with-zlib-lib=${ZLIB_INSTALL_PREFIX}/lib && \
    make -j$(nproc) && make install_sw && \
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
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
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

# QRMI 0.12.0 (pre-built binary) — needed for the Pasqal QRMI connector.
# Only ships an el8-x86_64 build at this pinned version, and cuda-quantum's
# own build (pyproject.toml.cu12) only enables the Pasqal connector on linux
# x86_64 anyway (CUDAQ_ENABLE_PASQAL_QRMI_CONNECTOR is OFF on every other
# platform) — so skip it entirely on arm64 rather than failing to find an
# archive that wouldn't be linked in regardless.
ENV QRMI_INSTALL_PREFIX=/usr/local/qrmi
RUN if [ "$(cat /tmp/nv_arch)" = "x86_64" ]; then \
    QRMI_VERSION=0.12.0 && \
    QRMI_ARCHIVE=libqrmi-${QRMI_VERSION}-el8-x86_64.tar.gz && \
    EXPECTED_SHA256=2986150d4f55e1f6566bef16d9fb3897ca04dd7eaa681865f7ef244f298a6746 && \
    wget https://github.com/qiskit-community/qrmi/releases/download/v${QRMI_VERSION}/${QRMI_ARCHIVE} && \
    computed=$(sha256sum ${QRMI_ARCHIVE} | awk '{print $1}') && \
    [ "$computed" = "$EXPECTED_SHA256" ] || (echo "SHA256 mismatch for QRMI!" && exit 1) && \
    mkdir -p ${QRMI_INSTALL_PREFIX}/include ${QRMI_INSTALL_PREFIX}/lib64 && \
    tar xzf ${QRMI_ARCHIVE} && \
    cp libqrmi-${QRMI_VERSION}/qrmi.h ${QRMI_INSTALL_PREFIX}/include/ && \
    cp libqrmi-${QRMI_VERSION}/libqrmi.so ${QRMI_INSTALL_PREFIX}/lib64/ && \
    rm -rf ${QRMI_ARCHIVE} libqrmi-${QRMI_VERSION}; \
    fi

# cuQuantum 26.01.0.4 — GPU-accelerated quantum simulation backends
# (same version ships for both linux-x86_64 and linux-sbsa)
ENV CUQUANTUM_INSTALL_PREFIX=/opt/nvidia/cuquantum
RUN CUQUANTUM_VERSION=26.01.0.4 && \
    nv_arch=$(cat /tmp/nv_arch) && \
    cuquantum_archive=cuquantum-linux-${nv_arch}-${CUQUANTUM_VERSION}_cuda12-archive.tar.xz && \
    wget https://developer.download.nvidia.com/compute/cuquantum/redist/cuquantum/linux-${nv_arch}/${cuquantum_archive} && \
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
#   - Point the hard-coded lld search path (-B/usr/local/llvm/bin) at our LLVM_INSTALL_PREFIX
RUN sed -i \
    's/cmake\.verbose = false/cmake.verbose = true/' pyproject.toml.cu12 && \
    sed -i \
    's/"-DCUDAQ_ENABLE_PASQAL_QRMI_CONNECTOR=OFF"/"-DCUDAQ_ENABLE_PASQAL_QRMI_CONNECTOR=OFF",\n    "-DCMAKE_COMPILE_WARNING_AS_ERROR=OFF"/' pyproject.toml.cu12 && \
    sed -i \
    "s/'cupy-cuda12x ~= 13.6.0;/'cupy-cuda12x >= 13.6.0;/" pyproject.toml.cu12 && \
    sed -i "s|-B/usr/local/llvm/bin|-B${LLVM_INSTALL_PREFIX}/bin|g" pyproject.toml.cu12 && \
    ! grep -q '/usr/local/llvm' pyproject.toml.cu12

# cudaq-synth (cudaq/lib/Synthesis) needs GMP: FindGMP requires the shared libgmp.so
# plus gmp.h. Kept as its own layer here so earlier cached layers stay valid.
RUN apt-get update && apt-get install -y --no-install-recommends libgmp-dev && \
    rm -rf /var/lib/apt/lists/*

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

# Informational check (never fails the build — just surfaces it in the build
# log): cudaq's MPI comm plugin (runtime/cudaq/distributed/builtin) is only
# built when CMake's find_package(MPI) succeeds, and links against whatever
# MPI it finds at build time. That must be this image's own MPICH (from the
# base image) — not some bundled OpenMPI — otherwise cudaq::mpi calls would
# be silently wrong (or crash) on a Slingshot/InfiniBand cluster that swaps
# in the host's own MPICH-ABI-compatible libmpi at job launch. If this says
# "not found", search by hand before relying on cudaq's MPI support.
RUN plugin=$(find /opt /usr -name 'libcudaq-comm-plugin*.so' 2>/dev/null | head -1); \
    if [ -n "$plugin" ]; then \
        echo "MPI comm plugin: $plugin"; ldd "$plugin" | grep -i mpi || true; \
    else \
        echo "WARNING: cudaq MPI comm plugin not found under /opt or /usr — check manually" >&2; \
    fi

WORKDIR /opt
RUN git clone https://github.com/rr637/QC-AFQMC.git

# Build and install cudaqx from source
# CUDAQ cmake configs come from the pip wheel install location
ENV CUDAQ_DIR=/opt/basic/lib/python3.12/site-packages/lib/cmake/cudaq
ENV CUDAQX_INSTALL_PREFIX=/opt/nvidia/cudaqx

# cudaqx was renamed to cudaq-qec upstream; pin 0.8.1, whose .cudaq_version
# pins a cuda-quantum commit 4 commits ahead of our 0.16.0 pin above — the
# closest matched pair of releases. Local path kept as /opt/cudaqx since the
# cmake variable names (CUDAQX_*) and install layout are unchanged by the rename.
RUN git clone --branch 0.8.1 https://github.com/NVIDIA/cudaq-qec.git /opt/cudaqx

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

# The nv-qldpc-decoder (GPU BP-OSD) plugin is closed source — it ships only as
# a binary inside NVIDIA's cudaq-qec-cu12 wheel, so the source build above
# never produces it (and e.g. the SC25 tutorial's Hour3 decoding example hard-
# fails without it). Lift it out of the matching 0.8.1 wheel into the plugin
# dir decoder.cpp scans (<dir of libcudaq-qec-decoders.so>/decoder-plugins).
# Its only cudaq dependency is libcudaq-qec-decoders.so via RUNPATH $ORIGIN/..,
# which the source build above provides at the same release.
RUN nv_arch=$(cat /tmp/nv_arch) && \
    case "${nv_arch}" in \
      x86_64) whl_arch=x86_64;  EXPECTED_SHA256=bdc613cf7fb11f74c30bc3c4c04ec7ce91079be95770187c53e6ec6ee2e3af9d ;; \
      sbsa)   whl_arch=aarch64; EXPECTED_SHA256=dd5814cb0cb0ecfc135c751186617231158b56cc7d96b4a763b6f6f010604f88 ;; \
    esac && \
    BUILDDIR=$(mktemp -d) && cd ${BUILDDIR} && \
    pip download --no-deps --only-binary=:all: --python-version 3.12 \
        --platform manylinux_2_28_${whl_arch} cudaq-qec-cu12==0.8.1 && \
    whl=$(ls cudaq_qec_cu12-0.8.1-cp312-*.whl) && \
    computed=$(sha256sum ${whl} | awk '{print $1}') && \
    [ "$computed" = "$EXPECTED_SHA256" ] || (echo "SHA256 mismatch for cudaq-qec wheel!" && exit 1) && \
    python3 -m zipfile -e ${whl} wheel && \
    mkdir -p /opt/nvidia/cudaqx/lib/decoder-plugins && \
    install -m 755 wheel/cudaq_qec/lib/decoder-plugins/libcudaq-qec-nv-qldpc-decoder.so \
        /opt/nvidia/cudaqx/lib/decoder-plugins/ && \
    if ldd /opt/nvidia/cudaqx/lib/decoder-plugins/libcudaq-qec-nv-qldpc-decoder.so | grep 'not found'; then exit 1; fi && \
    cd / && rm -rf ${BUILDDIR}

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
RUN pip install "ipie @ git+https://github.com/rr637/ipie.git@develop"
RUN pip install --upgrade "jax[cuda12]"
