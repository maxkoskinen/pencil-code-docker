# =============================================================================
# Pencil Code — Self-contained Docker Image (CPU + GPU)
# =============================================================================
#
# Build:
#   docker build -t pencil-code .                                  # CPU (default)
#   docker build -t pencil-code:gpu --build-arg VARIANT=gpu .      # GPU (CUDA)
#
# Run:
#   docker run --rm pencil-code conv-slab                          # CPU
#   docker run --rm --gpus all pencil-code:gpu conv-slab           # GPU
#   docker run --rm pencil-code list                               # list samples
#   docker run --rm -it pencil-code bash                           # shell
#   docker run --rm -v ./my-sim:/simulation pencil-code            # custom sim
#
# =============================================================================

# ---- Multi-stage base selection ----
ARG VARIANT=cpu
FROM ubuntu:24.04 AS base-cpu
FROM nvidia/cuda:12.6.0-devel-ubuntu24.04 AS base-gpu
FROM base-${VARIANT} AS final

LABEL maintainer="your-team@example.com"
LABEL description="Pencil Code — self-contained MHD simulation environment"
LABEL variant="${VARIANT}"

ENV DEBIAN_FRONTEND=noninteractive

# Save variant for runtime detection
ARG VARIANT=cpu
ENV PENCIL_VARIANT=${VARIANT}

# -----------------------------------------------------------------------------
# 1. System dependencies
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Compilers
    gcc \
    gfortran \
    g++ \
    make \
    cmake \
    # MPI
    openmpi-bin \
    libopenmpi-dev \
    # Math / science libraries
    libfftw3-dev \
    libfftw3-mpi-dev \
    libgsl-dev \
    libhdf5-openmpi-dev \
    hdf5-tools \
    # Python runtime + pip
    python3 \
    python3-pip \
    python3-tk \
    # IDL-compatible post-processing
    gnudatalanguage \
    python3-gdl \
    # Graphics / X11
    libxrender1 \
    x11-apps \
    # Tools used by pencil scripts
    git \
    csh \
    perl \
    bc \
    vim \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Python packages
RUN pip3 install --break-system-packages \
    numpy scipy matplotlib h5py \
    pencil \
    setuptools astropy Cython \
    dill pexpect tqdm f90nml pandas \
    lazy_loader pyvista flatdict

# -----------------------------------------------------------------------------
# 2. Clone Pencil Code source
# -----------------------------------------------------------------------------
# CPU: shallow clone (fast, small)
# GPU: full clone with Astaroth submodule
RUN if [ "${PENCIL_VARIANT}" = "gpu" ]; then \
        git clone --recurse-submodules https://github.com/pencil-code/pencil-code.git /opt/pencil-code && \
        cd /opt/pencil-code/src/astaroth/submodule && git checkout develop; \
    else \
        git clone --depth 1 https://github.com/pencil-code/pencil-code.git /opt/pencil-code; \
    fi

# -----------------------------------------------------------------------------
# 3. Environment variables
# -----------------------------------------------------------------------------
ENV PENCIL_HOME=/opt/pencil-code
ENV PATH="${PENCIL_HOME}/bin:${PENCIL_HOME}/utils:${PATH}"
ENV PYTHONPATH="${PENCIL_HOME}/python:${PYTHONPATH}"

# MPI: allow running as root in containers
ENV OMPI_ALLOW_RUN_AS_ROOT=1
ENV OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

# MPI: allow oversubscribing
ENV OMPI_MCA_rmaps_base_oversubscribe=1

# Set default build flags based on variant
# Default build flags are set in entrypoint.sh based on PENCIL_VARIANT

# IDL/GDL alias support
RUN echo 'alias idl=gdl' >> /etc/bash.bashrc && \
    echo 'source $PENCIL_HOME/sourceme.sh' >> /etc/bash.bashrc

# -----------------------------------------------------------------------------
# 4. Container-optimized host config
# -----------------------------------------------------------------------------
COPY generate-host-config.sh /tmp/generate-host-config.sh
RUN chmod +x /tmp/generate-host-config.sh && \
    /tmp/generate-host-config.sh && \
    rm /tmp/generate-host-config.sh

# -----------------------------------------------------------------------------
# 5. Bundle all samples
# -----------------------------------------------------------------------------
RUN cp -r ${PENCIL_HOME}/samples /opt/samples

# Simulation working directory
RUN mkdir -p /simulation
WORKDIR /simulation

# -----------------------------------------------------------------------------
# 6. Entrypoint
# -----------------------------------------------------------------------------
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
