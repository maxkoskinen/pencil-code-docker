# Pencil Code — Containerized

A self-contained Docker image for running [Pencil Code](https://github.com/pencil-code/pencil-code) MHD simulations. Build it, pick a sample (or mount your own), and run.

The image includes Ubuntu 24.04, gfortran, OpenMPI, FFTW3, HDF5, Python 3 with the `pencil` package, GDL, and all ~116 bundled samples.

## Build

```bash
docker build -t pencil-code .

# GPU variant (CUDA + Astaroth)
docker build -t pencil-code:gpu --build-arg VARIANT=gpu .
```

## Usage

```bash
# Run the default sample (conv-slab)
docker run --rm pencil-code

# Run a specific sample
docker run --rm pencil-code helical-MHDturb

# List all available samples
docker run --rm pencil-code list

# Interactive shell (full Pencil Code environment ready)
docker run --rm -it pencil-code bash

# GPU run
docker run --rm --gpus all pencil-code:gpu conv-slab
```

## Running your own simulation

Mount a directory containing `start.in`, `run.in`, and a `src/` folder with `Makefile.local` and `cparam.local` into `/simulation`. This always takes priority over any sample argument.

```bash
docker run --rm -v ./my-simulation:/simulation pencil-code
```

## Saving output

Simulation output goes to `/simulation/data/`. Mount a volume there to keep it:

```bash
docker run --rm -v ./output:/simulation/data pencil-code conv-slab
```

## Performance flags

For best MPI performance in a container, add these flags:

```bash
docker run --rm \
  --cap-add=SYS_PTRACE \
  --shm-size=1g \
  pencil-code conv-slab
```

| Flag | Why |
|---|---|
| `--cap-add=SYS_PTRACE` | Enables fast MPI shared-memory transport (CMA). Without it MPI falls back to a slower path. |
| `--shm-size=1g` | MPI uses `/dev/shm` for inter-process communication. The default 64 MB is too small for larger simulations. |

The entrypoint auto-detects CMA availability, sets unlimited stack size, enables MPI oversubscribe, and reads `ncpus` from `cparam.local` — so things work out of the box either way.

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `PENCIL_BUILD_FLAGS` | `-f GNU-GCC_MPI` | Flags passed to `pc_build` |
| `PENCIL_NCPUS` | `auto` | Number of MPI processes (auto-reads from `cparam.local`) |
| `PENCIL_RUN_FLAGS` | *(empty)* | Extra flags passed to `pc_run` |
| `PENCIL_SKIP_BUILD` | `0` | Set to `1` to skip compilation |
| `PENCIL_SKIP_START` | `0` | Set to `1` to skip `pc_start` (restart from snapshot) |

Examples:

```bash
# Non-MPI build
docker run --rm -e PENCIL_BUILD_FLAGS="-f GNU-GCC" pencil-code conv-slab

# Force 4 MPI processes
docker run --rm -e PENCIL_NCPUS=4 pencil-code conv-slab

# Restart from a previous snapshot (skip compile + init)
docker run --rm -e PENCIL_SKIP_BUILD=1 -e PENCIL_SKIP_START=1 \
  -v ./my-sim:/simulation pencil-code
```

## Priority logic

The entrypoint decides what to run in this order:

1. `/simulation` already has `start.in` + `src/` (user-mounted config) → use that
2. A sample name was passed as an argument → copy that sample and run it
3. Neither → fall back to `conv-slab`
