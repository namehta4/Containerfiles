#!/bin/bash
# Build and push an image on Perlmutter CPU nodes as two hedged jobs: a regular-QOS batch job and an
# interactive-QOS allocation, whichever starts first. The first to finish building takes a push lock,
# pushes, and cancels the other.
#
#   ACCOUNT=<account> build_perlmutter_hedged.sh <context-dir> <tag> [podman-hpc build args...]
#   e.g. ACCOUNT=nstaff CACHE=docker.io/<user>/cudaq-buildcache \
#        setsid nohup ./build_perlmutter_hedged.sh Cudaq docker.io/nersc/cudaq:26.10-amd64 \
#            --build-arg BASE_IMAGE=docker.io/nersc/base_gpu:26.10-amd64 > hedge.log 2>&1 &
#
# salloc blocks until the interactive build ends, so run this under setsid nohup to survive logout.
# The snapshot commit is resolved now, so both hedges build the same source.
#
# Optional environment: LOG_DIR (default $PWD), NAME (job-name prefix, default <context>-build),
# BATCH_TIME (default 12:00:00), INT_TIME (default 04:00:00), plus COMMIT, CACHE and AUTHFILE as in
# build_perlmutter.sh. Logs: $LOG_DIR/$NAME.{batch,interactive}.log; lock: $LOG_DIR/$NAME.push.lock.
set -uo pipefail
CONTEXT=${1:?context dir}; TAG=${2:?image tag}; shift 2
: "${ACCOUNT:?set ACCOUNT to your NERSC project}"
HERE=$(dirname "$(readlink -f "$0")")
REPO=$(git -C "$HERE" rev-parse --show-toplevel)
export COMMIT=$(git -C "$REPO" rev-parse "${COMMIT:-HEAD}")
LOG_DIR=$(readlink -f "${LOG_DIR:-$PWD}")
NAME=${NAME:-$(echo "$CONTEXT" | tr '/A-Z' '-a-z')-build}
export PUSH_LOCK=$LOG_DIR/$NAME.push.lock
[ -e "$PUSH_LOCK" ] && { echo "$PUSH_LOCK exists (an earlier push?); remove it to rebuild"; exit 1; }

BUILD="$HERE/build_perlmutter.sh $CONTEXT $TAG $(printf '%q ' "$@")"
echo "$(date) $CONTEXT @ ${COMMIT:0:7} -> $TAG: launching hedges $NAME-batch / $NAME-int"
CANCEL_JOB=$NAME-int sbatch -A "$ACCOUNT" -J "$NAME-batch" -N1 -C cpu -q regular -t "${BATCH_TIME:-12:00:00}" \
  -o "$LOG_DIR/$NAME.batch.log" --export=ALL --wrap "$BUILD"
CANCEL_JOB=$NAME-batch salloc -A "$ACCOUNT" -J "$NAME-int" -N1 -C cpu -q interactive -t "${INT_TIME:-04:00:00}" \
  srun --cpu-bind=none bash -c "$BUILD" > "$LOG_DIR/$NAME.interactive.log" 2>&1
echo "$(date) interactive hedge exited"
