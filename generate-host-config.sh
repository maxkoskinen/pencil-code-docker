#!/bin/bash
# generate-host-config.sh
# Generates a container-optimized Pencil Code host config file.
# Run during docker build.

set -e

ARCH=$(dpkg --print-architecture)
if [ "$ARCH" = "amd64" ]; then
    LIBDIR="/usr/lib/x86_64-linux-gnu"
elif [ "$ARCH" = "arm64" ]; then
    LIBDIR="/usr/lib/aarch64-linux-gnu"
else
    LIBDIR="/usr/lib"
fi

HDF5_INC=$(find /usr/include -path "*/hdf5/openmpi" -type d 2>/dev/null | head -1)
if [ -z "$HDF5_INC" ]; then HDF5_INC="/usr/include/hdf5/openmpi"; fi

mkdir -p "${PENCIL_HOME}/config/hosts/docker"

cat > "${PENCIL_HOME}/config/hosts/docker/docker-container.conf" << 'EOF'
# Container-optimized Pencil Code host config
# Generated at image build time

%include compilers/GNU-GCC_MPI

%section Makefile

    # Compiler optimizations
    FFLAGS += -O3
    CFLAGS += -O3

    # Larger stack allocation for big arrays
    FFLAGS += -fmax-stack-var-size=512000 -fno-stack-arrays

    # FFTW3 support
    LD_FFTW3 = -lfftw3 -lfftw3f -lfftw3_mpi -lfftw3f_mpi

    # Double precision flags (used when FFLAGS_DOUBLE is requested)
    FFLAGS_DOUBLE = -fdefault-real-8 -fdefault-double-8

%endsection Makefile

%section runtime

    mpiexec = mpiexec
    mpiexec_opts2 = --oversubscribe

%endsection runtime
EOF

# Append HDF5 paths (these use shell variables so can't be in the quoted heredoc)
sed -i "/LD_FFTW3/a\\
\\n    # HDF5 support (parallel, via OpenMPI)\\n    FFLAGS += -I${HDF5_INC}\\n    LD_MPI = -lhdf5_openmpi -lhdf5_openmpi_fortran" \
    "${PENCIL_HOME}/config/hosts/docker/docker-container.conf"

echo "Generated host config for ${ARCH} (libs: ${LIBDIR}, hdf5: ${HDF5_INC})"
