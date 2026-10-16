#!/bin/bash
# Build and push one image from this repo on a Perlmutter compute node.
#
#   build_perlmutter.sh <context-dir> <tag> [podman-hpc build args...]
#   e.g. build_perlmutter.sh Base/GPU docker.io/nersc/base_gpu:26.10-amd64
#        build_perlmutter.sh Cudaq docker.io/nersc/cudaq:26.10-amd64 \
#            --build-arg BASE_IMAGE=docker.io/nersc/base_gpu:26.10-amd64
#
# Run it inside an allocation (srun under salloc, or sbatch --wrap); build_perlmutter_hedged.sh does
# that for you. podman-hpc image storage is node-local and disappears with the job, so the build and
# push have to happen in the same job, and login nodes (30 GiB cap) run out of memory on MPICH/LLVM.
#
# Optional environment:
#   COMMIT=<rev>         build from a `git archive` snapshot of <context-dir> at <rev> (default HEAD),
#                        so later commits or local edits don't change a running build
#   CACHE=<registry/repo> registry layer cache (--cache-to/--cache-from); a rebuild after a failure
#                        then resumes near the failing step instead of from scratch
#   AUTHFILE=<path>      registry credentials (default ~/.config/containers/auth.json)
#   PUSH_LOCK=<dir>      only push if `mkdir <dir>` succeeds (atomic on the shared filesystem), so one
#                        of several hedged builds pushes; the lock is released if the push fails
#   CANCEL_JOB=<name>    after a successful push, scancel your job with this name (the other hedge)
set -uo pipefail
CONTEXT=${1:?context dir}; TAG=${2:?image tag}; shift 2
REPO=$(git -C "$(dirname "$(readlink -f "$0")")" rev-parse --show-toplevel)
COMMIT=${COMMIT:-HEAD}
AUTHFILE=${AUTHFILE:-$HOME/.config/containers/auth.json}

SNAP=$(mktemp -d)
git -C "$REPO" archive "$COMMIT" "$CONTEXT" | tar -x -C "$SNAP" || { echo "=== SNAPSHOT FAILED ==="; exit 1; }
cd "$SNAP"
echo "=== host $(hostname) job ${SLURM_JOB_ID:-?} $CONTEXT @ $(git -C "$REPO" rev-parse --short "$COMMIT") -> $TAG $(date) ==="

CACHE_ARGS=()
[ -n "${CACHE:-}" ] && CACHE_ARGS=(--authfile "$AUTHFILE" --layers --cache-to "$CACHE" --cache-from "$CACHE")
# Pin to 128 CPUs so make -j$(nproc) / ninja don't start 256 jobs and exhaust the node's memory.
# Raise nproc: a low limit makes parallel builds (e.g. libfabric) fail fork() with EAGAIN.
podman-hpc build --platform linux/amd64 --ulimit nproc=65536:65536 --cpuset-cpus=0-127 \
  "${CACHE_ARGS[@]}" "$@" -t "$TAG" -f "$CONTEXT/Dockerfile" --progress=plain "$CONTEXT" \
  || { echo "=== BUILD FAILED $(date) ==="; exit 1; }
echo "=== BUILD OK $(date) ==="

if [ -n "${PUSH_LOCK:-}" ]; then
  mkdir "$PUSH_LOCK" 2>/dev/null || { echo "=== PUSH SKIPPED: another job holds $PUSH_LOCK $(date) ==="; exit 0; }
  echo "${SLURM_JOB_ID:-?} $(hostname)" > "$PUSH_LOCK/owner"
fi
if podman-hpc push --authfile "$AUTHFILE" "$TAG"; then
  echo "=== PUSH OK $(date) ==="
  [ -n "${CANCEL_JOB:-}" ] && scancel -u "$USER" -n "$CANCEL_JOB" && echo "=== cancelled other hedge ($CANCEL_JOB) ==="
else
  [ -n "${PUSH_LOCK:-}" ] && rm -rf "$PUSH_LOCK"  # let another hedge push instead
  echo "=== PUSH FAILED $(date) ==="; exit 2
fi
