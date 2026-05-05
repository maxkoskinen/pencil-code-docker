#!/bin/bash
set -eo pipefail

# =============================================================================
# Pencil Code Container Entrypoint
# =============================================================================
#
# Usage:
#   docker run pencil-code                      # run default sample (conv-slab)
#   docker run pencil-code conv-slab            # run a named sample
#   docker run pencil-code helical-MHDturb      # run another sample
#   docker run pencil-code list                 # list all available samples
#   docker run pencil-code bash                 # interactive shell
#   docker run -v ./my-sim:/simulation pencil-code   # run custom simulation
#
# Environment variables:
#   PENCIL_BUILD_FLAGS  — flags for pc_build   (default: "-f GNU-GCC_MPI")
#   PENCIL_NCPUS        — MPI process count    (default: auto from cparam.local)
#   PENCIL_RUN_FLAGS    — extra flags for pc_run
#   PENCIL_SKIP_BUILD   — "1" to skip compilation
#   PENCIL_SKIP_START   — "1" to skip pc_start (restart from snapshot)
#
# =============================================================================

SAMPLES_DIR="/opt/samples"
SIM_DIR="/simulation"
ARG="${1:-}"

# ---- "list" command: show available samples ----
if [ "${ARG}" = "list" ]; then
    echo "Available samples:"
    echo ""
    for d in "${SAMPLES_DIR}"/*/; do
        name=$(basename "$d")
        if [ -f "${d}/start.in" ] || [ -d "${d}/src" ]; then
            echo "  ${name}"
        fi
    done
    echo ""
    echo "Run a sample:  docker run --rm pencil-code <sample-name>"
    exit 0
fi

# ---- "bash"/"sh" command: interactive shell ----
if [ "${ARG}" = "bash" ] || [ "${ARG}" = "sh" ]; then
    cd "${PENCIL_HOME}" && set +e && . ./sourceme.sh && set -e && cd "${SIM_DIR}"
    exec "${ARG}"
fi

# ---- Any other unknown command: pass through to exec ----
if [ -n "${ARG}" ] && [ ! -d "${SAMPLES_DIR}/${ARG}" ] && command -v "${ARG}" &>/dev/null; then
    cd "${PENCIL_HOME}" && set +e && . ./sourceme.sh && set -e && cd "${SIM_DIR}"
    exec "$@"
fi

echo "=============================================="
echo "  Pencil Code Container"
echo "  $(date -u)"
echo "=============================================="

# Source pencil environment
# sourceme.sh runs git-config commands that can return non-zero under set -e,
# so we temporarily allow failures during sourcing.
cd "${PENCIL_HOME}"
set +e
. ./sourceme.sh
set -e
cd "${SIM_DIR}"

# Defaults — build flags auto-select based on CPU/GPU variant
if [ -z "${PENCIL_BUILD_FLAGS:-}" ]; then
    if [ "${PENCIL_VARIANT:-cpu}" = "gpu" ]; then
        BUILD_FLAGS="-f GNU-GCC_GPU"
    else
        BUILD_FLAGS="-f GNU-GCC_MPI"
    fi
else
    BUILD_FLAGS="${PENCIL_BUILD_FLAGS}"
fi
NCPUS="${PENCIL_NCPUS:-auto}"
SKIP_BUILD="${PENCIL_SKIP_BUILD:-0}"
SKIP_START="${PENCIL_SKIP_START:-0}"

# ---- Auto-detect CMA (cross-memory attach) support ----
# CMA is faster but needs SYS_PTRACE. If unavailable, disable it to avoid
# "Read -1, errno = 1" spam. Use --cap-add=SYS_PTRACE for best performance.
if [ -z "${OMPI_MCA_btl_vader_single_copy_mechanism:-}" ]; then
    # Check CapEff bitmask in /proc — bit 19 is SYS_PTRACE (0x80000)
    cap_eff=$(grep -oP 'CapEff:\s+\K\S+' /proc/1/status 2>/dev/null || echo "")
    if [ -n "${cap_eff}" ]; then
        cap_dec=$(python3 -c "print(int('${cap_eff}', 16) & 0x80000)" 2>/dev/null || echo "1")
        if [ "${cap_dec}" = "0" ]; then
            export OMPI_MCA_btl_vader_single_copy_mechanism=none
            echo "CMA unavailable — disabled (add --cap-add=SYS_PTRACE for faster MPI)"
        fi
    fi
fi

# ---- Runtime optimizations ----
# Increase stack size for large Fortran arrays
ulimit -s unlimited 2>/dev/null || true

# Check /dev/shm size — MPI shared memory needs enough space
SHM_SIZE=$(df -m /dev/shm 2>/dev/null | awk 'NR==2{print $2}')
if [ -n "${SHM_SIZE}" ] && [ "${SHM_SIZE}" -lt 256 ]; then
    echo "WARNING: /dev/shm is only ${SHM_SIZE}MB. Use --shm-size=1g for large simulations."
fi

# Report container capabilities
echo ""
echo "Container environment:"
echo "  CPUs available:  $(nproc 2>/dev/null || echo unknown)"
echo "  Memory:          $(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || echo unknown)"
echo "  /dev/shm:        ${SHM_SIZE:-unknown}MB"
echo "  Architecture:    $(uname -m)"
echo "  Variant:         ${PENCIL_VARIANT:-cpu}"
echo "  Build flags:     ${BUILD_FLAGS}"
if [ "${OMPI_MCA_btl_vader_single_copy_mechanism:-}" = "none" ]; then
    echo "  MPI CMA:         disabled"
else
    echo "  MPI CMA:         enabled"
fi
if [ "${PENCIL_VARIANT:-cpu}" = "gpu" ]; then
    if command -v nvidia-smi &>/dev/null; then
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        GPU_MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)
        echo "  GPU:             ${GPU_NAME:-detected} (${GPU_MEM:-unknown})"
    else
        echo "  GPU:             NOT DETECTED — run with --gpus all"
    fi
fi

# ---- Decide what to run ----
# Priority:
#   1. If /simulation already has config files (mounted by user) → use those
#   2. If a sample name was passed as argument → load that sample
#   3. If nothing → load conv-slab as default

if [ -f "${SIM_DIR}/start.in" ] && [ -d "${SIM_DIR}/src" ]; then
    echo ""
    echo "Found simulation config in /simulation — using it."
elif [ -n "${ARG}" ]; then
    SAMPLE_PATH="${SAMPLES_DIR}/${ARG}"
    if [ ! -d "${SAMPLE_PATH}" ]; then
        echo "ERROR: Sample '${ARG}' not found."
        echo ""
        echo "Run 'docker run pencil-code list' to see available samples."
        exit 1
    fi
    if [ ! -f "${SAMPLE_PATH}/start.in" ]; then
        echo "ERROR: Sample '${ARG}' has no start.in — it may not be a runnable simulation."
        exit 1
    fi
    echo ""
    echo "Loading sample: ${ARG}"
    cp -r "${SAMPLE_PATH}"/* "${SIM_DIR}"/
else
    echo ""
    echo "No simulation config found and no sample specified."
    echo "Loading default sample: conv-slab"
    echo ""
    echo "Tip: run 'docker run pencil-code list' to see all available samples."
    cp -r "${SAMPLES_DIR}/conv-slab"/* "${SIM_DIR}"/
fi

# ---- Validate ----
if [ ! -f "src/Makefile.local" ] || [ ! -f "src/cparam.local" ]; then
    echo "ERROR: Missing src/Makefile.local or src/cparam.local"
    exit 1
fi
if [ ! -f "start.in" ] || [ ! -f "run.in" ]; then
    echo "ERROR: Missing start.in or run.in"
    exit 1
fi

# ---- Auto-detect NCPUS from cparam.local ----
if [ "${NCPUS}" = "auto" ]; then
    NCPUS=$(grep -oP 'ncpus=\K[0-9]+' src/cparam.local 2>/dev/null || echo "1")
    echo "Auto-detected ncpus=${NCPUS} from cparam.local"
fi

# ---- Create data directory ----
mkdir -p data

# ---- Setup source links ----
echo ""
echo "[1/4] Setting up source links (pc_setupsrc)..."
pc_setupsrc
echo "      Done."

# ---- Compile ----
if [ "${SKIP_BUILD}" = "1" ]; then
    echo ""
    echo "[2/4] Skipping compilation (PENCIL_SKIP_BUILD=1)"
else
    echo ""
    echo "[2/4] Compiling: pc_build ${BUILD_FLAGS}"
    pc_build ${BUILD_FLAGS}
    echo "      Compilation complete."
fi

# ---- Initialize ----
if [ "${SKIP_START}" = "1" ]; then
    echo ""
    echo "[3/4] Skipping initialization (PENCIL_SKIP_START=1)"
elif [ -f "data/proc0/var.dat" ]; then
    echo ""
    echo "[3/4] Found existing snapshot — skipping pc_start (restart mode)."
else
    echo ""
    echo "[3/4] Initializing simulation (pc_start)..."
    pc_start
    echo "      Initialization complete."
fi

# ---- Run ----
# pc_run reads ncpus from cparam.local and calls mpiexec automatically.
echo ""
echo "[4/4] Running simulation (${NCPUS} MPI processes)..."
pc_run ${PENCIL_RUN_FLAGS:-}

echo ""
echo "=============================================="
echo "  Simulation finished at $(date -u)"
echo "=============================================="
