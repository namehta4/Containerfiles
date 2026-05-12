import subprocess, os, glob, socket, ctypes

rank       = int(os.environ.get('SLURM_PROCID', 0))
local_rank = int(os.environ.get('SLURM_LOCALID', 0))
hostname   = socket.gethostname()

prefix = f"[rank {rank:02d} | {hostname} | local {local_rank}]"

# --- nvidia-smi for this rank's assigned GPU ---
result = subprocess.run(
    ['nvidia-smi', '--query-gpu=index,name,memory.total,temperature.gpu',
     '--format=csv,noheader'],
    capture_output=True, text=True
)
gpu_lines = result.stdout.strip().splitlines()
gpu_info  = gpu_lines[local_rank] if local_rank < len(gpu_lines) else "(not found)"
print(f"{prefix} GPU: {gpu_info}")

# --- CUDA device count via ctypes ---
for lib in ['libcuda.so.1', 'libcuda.so']:
    try:
        libcuda = ctypes.cdll.LoadLibrary(lib)
        count   = ctypes.c_int(0)
        ret     = libcuda.cuInit(0)
        if ret == 0:
            libcuda.cuDeviceGetCount(ctypes.byref(count))
            print(f"{prefix} cuDeviceGetCount: {count.value}")
        else:
            print(f"{prefix} cuInit returned {ret}")
        break
    except Exception as e:
        print(f"{prefix} {lib}: {e}")

# --- /dev/nvidia* devices (rank 0 per node only to avoid duplicate output) ---
if local_rank == 0:
    devs = sorted(glob.glob('/dev/nvidia[0-9]*'))
    print(f"{prefix} /dev/nvidia[0-9]* devices: {devs}")
