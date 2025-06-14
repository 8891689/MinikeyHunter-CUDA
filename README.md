# MinikeyHunter CUDA

# Project Overview

This is a high-performance mini-key Bitcoin address search tool that fully utilizes the powerful parallel computing capabilities of NVIDIA GPUs through CUDA technology. It is designed to find private keys corresponding to a given list of target Bitcoin addresses.


# How It Works

1. Initialization:
The program starts by reading an input file containing target Bitcoin addresses (in Base58 format).
These addresses and their corresponding HASH160 values are loaded into an in-memory std::set and two Bloom filters for fast lookups.
It initializes the secp256k1 elliptic curve cryptography library and sets up the CUDA environment.

2. GPU Search Loop:
The program enters an infinite loop, processing one batch of keys per iteration.
In Sequential Mode: The current starting key (KEY_START_IX) is copied to the GPU.

3. In Random Mode: 

A random number generator is initialized on the GPU, or the search periodically jumps to a new random starting point.
The kernelMinikeys CUDA kernel is launched. Each GPU thread, based on a starting point or a random seed, generates and tests a large number of private keys. This kernel performs the elliptic curve multiplication to derive public keys, which is the most computationally expensive part of the process.
If a GPU thread finds a potential match (likely via a preliminary hash check), it flags it or stores it in an intermediate results buffer.

# Result Collection and CPU Verification:

The resultCollector kernel is launched to scan the intermediate buffer and gather all marked potential hits into a smaller, compact buffer.
This compact buffer is copied from the GPU back to the CPU.The CPU's thread pool (ctpl::thread_pool) receives these candidate private keys.

1. Each CPU thread executes the processCandidateThread function:
a. It calculates the full chain: Public Key -> HASH160 -> Base58 Address.
b. It checks the HASH160 against the filterR160 Bloom filter. If it's not a potential match, the candidate is discarded.
c. If it passes, it checks the Base58 address against the filter Bloom filter and discards it if not found.
d. If both filters pass, a final, precise lookup is performed in the std::set to confirm a true match (eliminating any Bloom filter false positives).
e. If a match is confirmed, the found address and its corresponding private key (in hex format) are printed to the console and saved to a result file.

2. Progress Update:

In sequential mode, the starting key (KEY_START_IX) is incremented after each batch is processed.
The program periodically displays the current computation speed (in MKey/s, GKey/s, or TKey/s) and the current key range being processed.
The saveStatus() function is called at regular intervals to write the progress to a file.

# How to Use

Compilation / Building
You will need the NVIDIA CUDA Toolkit installed. Compile the project using the nvcc compiler:
```
make gpu=0 all
```
or
```
make gpu=0
```
Clean up and rebuild
```
make clean
```
# User Manual

1. Execution
```
./minikey -h
```
2. Command-Line Options:
```
-h, --help: Show this help message and exit.

-i <file>: (Required) Specify the input file containing target Bitcoin addresses (one per line).

-r: Enable Random Search Mode. If not specified, the default is sequential mode.

-s <start_key>: In sequential mode, specify a starting "Minikey" in Base58 format (e.g., -s S65iN5g6vbeT3pmnA1bFp6zT3).

-d <device_id>: Specify the GPU device ID to use (default is 0).

-b <blocks>: Set the number of CUDA blocks.

-t <threads>: Set the number of threads per CUDA block.
```
3. Examples:

4. Start a sequential search from a specific key, using GPU 0, preferably using the default dynamic allocation unless you have multiple graphics cards:
```
./minikey -i test.txt -d 0 -s S8888888888888888

./minikey -i test.txt -s S8888888888888888

Loaded addresses : 2
Using   device   : 0 
NVIDIA GeForce GT 1030 ( 3 procs)
number of blocks : 24
number of threads: 128
Work started at Sun Jun 15 05:09:54 2025
Starting key: S888888888888888811111
Total: 30.528 MKey/s | Candidates: 0.154 MKey/s | Task: S88888888888888886dMnF 
found: 1LNTHdkFgvn6fhKyzgyDvkVoa4ShvJA5aH - 2587BF77DB81437D3DE0EB97301791217341F6886057AA796F67E74431E144A0
Total: 30.447 MKey/s | Candidates: 0.144 MKey/s | Task: S88888888888888888WRWP ^C
```


5. Use GPU 1 for random search with custom number of blocks and threads, preferably with default dynamic allocation:
```
./minikey -i test.txt -r -d 1 -b 256 -t 512

./minikey -i test.txt -r
Loaded addresses : 2
Using   device   : 0 
NVIDIA GeForce GT 1030 ( 3 procs)
number of blocks : 24
number of threads: 128
Work started at Sun Jun 15 06:01:15 2025
RANDOM mode (bulk size: 3072)
Total: 30.302 MKey/s | Candidates: 0.124 MKey/s | Task: SpGtW4DpLTY9SJR7xRx1hj ^C
```

6. Execute from the beginning and you can experiment with it as a verification.
```
./minikey -i test.txt
Loaded addresses : 2
Using   device   : 0 
NVIDIA GeForce GT 1030 ( 3 procs)
number of blocks : 24
number of threads: 128
Work started at Sun Jun 15 05:13:45 2025
Starting key: 
Total: 30.140 MKey/s | Candidates: 0.034 MKey/s | Task: S11111111111111116cjFd 
found: 1DpvL6FtuiQcp3FHiP56koeNmajChwG21Q - FF2818908FB70993AA3B017F4FE92A7AD13D142BE5451A77F287BA74FC206543
Total: 30.594 MKey/s | Candidates: 0.024 MKey/s | Task: S11111111111111118ViQw ^C
```
This is not a free project. You need to buy the public key extractor to get the password. You can also buy it separately for the same price. It is the same as the membership plan. You only pay a one-time fee, compressed password, the same as other project passwords.

# Acknowledgements

Assisted by: gemini.

# Sponsorship
If this project is helpful to you, please consider sponsoring. Your support is greatly appreciated. Thank you!
```
BTC: bc1qt3nh2e6gjsfkfacnkglt5uqghzvlrr6jahyj2k
ETH: 0xD6503e5994bF46052338a9286Bc43bC1c3811Fa1
DOGE: DTszb9cPALbG9ESNJMFJt4ECqWGRCgucky
TRX: TAHUmjyzg7B3Nndv264zWYUhQ9HUmX4Xu4
```
# 📜 Disclaimer
This code is only for learning and understanding how it works.
Please ensure that the program is run in a safe environment and comply with local laws and regulations!
The developer is not responsible for any financial losses or legal liabilities caused by the use of this code.

