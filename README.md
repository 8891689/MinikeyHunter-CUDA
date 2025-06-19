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
./minikey -i test.txt -d 0 -s S888888888888888888888

./minikey -i Sminikey_Address.txt
[INFO] Loaded 4907 addresses into Bloom filters and set.
[INFO] Reading status file: status.txt
[INFO] Mode: Preset order of S-Key indexes (S888888888888888888888, index 0).
[INFO] Using Device 0: NVIDIA GeForce GT 1030 (3 SMs)
[INFO] Grid: 96 blocks, 256 threads/block
[INFO] Work started at Thu Jun 19 14:11:52 2025
[INFO] SEQUENTIAL (Indexed) mode starting from S888888888888888888888 (index 0).
[INFO] Speed: 196.64 MKey/s | Probe: 3.81 M | Task: S8888888888888889gc4Ac              ^C

```


5. Use GPU 1 for random search with custom number of blocks and threads, preferably with default dynamic allocation:
```
./minikey -i test.txt -r -d 1 -b 256 -t 512

./minikey -i Sminikey_Address.txt -r
[INFO] Loaded 4907 addresses into Bloom filters and set.
[INFO] Reading status file: status.txt
[INFO] Mode: Random S-Key generation (GPU internal).
[INFO] Using Device 0: NVIDIA GeForce GT 1030 (3 SMs)
[INFO] Grid: 96 blocks, 256 threads/block
[INFO] Work started at Thu Jun 19 13:27:35 2025
[INFO] Mixed (random jump order) mode enabled.
[INFO] Random jumps per batch: 100000000
[INFO] Detecting cache area: 500000
[INFO] Speed: 616.40 MKey/s | Probe: 1.94 G | Task: S5WpiwaNxVcGBDDrYTvnGk
```

6. Execute from the beginning and you can experiment with it as a verification.
```
./minikey -i test.txt -s S111111111111111111111
[INFO] Loaded 10 addresses into Bloom filters and set.
[INFO] Reading status file: status.txt
[INFO] Incremental mode: From S-Key(S111111111111111111111) 
[INFO] Using Device 0: NVIDIA GeForce GT 1030 (3 SMs)
[INFO] Grid: 96 blocks, 256 threads/block
[INFO] Work started at Thu Jun 19 14:11:27 2025


Address: 1Kf9HN3ssoSWpXEfvZmL1KukDZB7g5RE3r (Uncompressed)
Privkey: 920E3A05397C69450BEB8E76CC6B870610831F7FD52E073E17B47C127A0C57F7
HASH160: cca8fbf5e9c0d0b7281d6bfe1ff86352be3f0fbe

Address: 1MaTZNiSp41fT31USu9R9gtnueCmwxSikL (Compressed)
Privkey: 920E3A05397C69450BEB8E76CC6B870610831F7FD52E073E17B47C127A0C57F701
HASH160: e1b6697d29889233826243d1888dd4bbb1155ba7


Address: 1LnGAaZrP9bFdQ5df3LXqranGVS189azro (Uncompressed)
Privkey: F380202B0D6838959A129541374E76C50ECBB40958043C4779FEAA7EC78DE59A
HASH160: d8f9c4747c949af7f7a866e730358d74180c44fb

Address: 1MdDaPrdffkv6kLs2hrh3wdYEGZb3JLetC (Compressed)
Privkey: F380202B0D6838959A129541374E76C50ECBB40958043C4779FEAA7EC78DE59A01
HASH160: e23bfcee95e58f8f82f98849bacaf2971e02156a


Address: 1BcRHK9VTxXXNhsgNpS1PQYK8zfMu84pXh (Uncompressed)
Privkey: 11B27EF4C6C4C4A176EA63A68FD02D065FDEF51BD36942AD1B80AF20355A6E49
HASH160: 746415e1861bf44c684e17f2f51cb6a314250968

Address: 17WaZgkVi7F2pWfPitPpA9tpz9MrHT4aZT (Compressed)
Privkey: 11B27EF4C6C4C4A176EA63A68FD02D065FDEF51BD36942AD1B80AF20355A6E4901
HASH160: 4768d5c456996ce98f433635b52b0e323702e7d3


Address: 1KJ5c9B6WQFbSMwteuCQCUx9jFtL9k99te (Uncompressed)
Privkey: 65EFF5D87851EB5161F0E7BBD2C3731E1A3480B494AAF16A9BC22BACE26EE45
HASH160: c8ad2e24fc660ab4a0ae250350ade893a0cffc87

Address: 1KsJHZ3BusNuSubPErV5nGw8iL76xgbYN (Compressed)
Privkey: 65EFF5D87851EB5161F0E7BBD2C3731E1A3480B494AAF16A9BC22BACE26EE4501
HASH160: 03917957490a58638ed89256773e9e6718fe71c7


Address: 1DpvL6FtuiQcp3FHiP56koeNmajChwG21Q (Uncompressed)
Privkey: FF2818908FB70993AA3B017F4FE92A7AD13D142BE5451A77F287BA74FC206543
HASH160: 8cb1939831b8ed2a7fcee8bfd83b8eef436af58d
[INFO] Speed: 185.95 MKey/s | Probe: 9.16 M | Task: S1111111111111114aETV9              ^C

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

