from mpi4py import MPI
import sys

# Get the world communicator
comm = MPI.COMM_WORLD
# Get the rank of the current process
rank = comm.Get_rank()
# Get the total number of processes
size = comm.Get_size()
# Get the name of the processor (node)
name = MPI.Get_processor_name()

# Print identifying information from each process
sys.stdout.write(f"Hello World! I am process {rank} of {size} on {name}.\n")
