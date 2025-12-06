#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include <stdio.h>
#include <fstream>
#include <stdlib.h>
#include <stdint.h>
#include <iostream>
#include <chrono>
#include <set>
#include <string.h> 

#include "Worker.cuh"

#include "lib/Int.h"
#include "lib/Math.cuh"
#include "lib/util.h"
#include "lib/SECP256k1.h"

#include "bloom_filter.hpp"
#include "lib/V/VBase58.h"

#include "lib/ctpl/ctpl_stl.h"

Secp256K1* secp;

using namespace std;

bool readArgs(int argc, char** argv);
void prepareAlphabet();
bool checkDevice();
void processCandidate(Int& toTest);
void processCandidateThread(int id, uint32_t bit0, uint32_t bit1, uint32_t bit2, uint32_t bit3, uint32_t bit4, uint32_t bit5, uint32_t bit6, uint32_t bit7);
bool read_file(const std::string& file_name);
void incrementBase58(int count, int* key);
void printSpeed(double speed);
void printSpeed(double speed, double speedCorrect);
void saveStatus();
cudaError_t prepareCuda();
cudaError_t processCuda();
cudaError_t processCudaRandom();

int DEVICE_NR = 0;
unsigned int BLOCK_THREADS = 0;
unsigned int BLOCK_NUMBER = 0;
unsigned int THREAD_STEPS = 1;

char ALPHABET[LONG_ALPHABET_LEN];

string fileResult = "result.txt";
string fileStatus = "fileStatus.txt";
string fileInput = "";
int fileStatusInterval = 60;

const int KEY_LENGTH = 21; // <-- Reverted to original value
int KEY_START_IX[KEY_LENGTH];
string KEY_START = "";
uint64_t outputSize;

bloom_parameters parameters;
bloom_filter filter;
bloom_filter filterR160;

set<string>addresses;
vector<uint64_t> vectorX;
vector<uint64_t> vectorY;
vector<vector<unsigned char>> addressR160;

bool addressesLoaded = false;
bool randomMode = false;
//ctpl::thread_pool pool(std::thread::hardware_concurrency() / 2);
ctpl::thread_pool pool(1);

int main(int argc, char** argv)
{
    prepareAlphabet();
    parameters.false_positive_probability = 0.00000001;
    parameters.projected_element_count = 5000;
    parameters.compute_optimal_parameters();
    filter = bloom_filter(parameters);
    filterR160 = bloom_filter(parameters);

    readArgs(argc, argv); // This function will now handle -h and exit if found.

    if (!addressesLoaded) {
        fprintf(stderr, "Lis of addresses not loaded! use -i <filename>\n");
        return -2;
    }

    if (!checkDevice()) {
        return -1;
    }

    printf("number of blocks : %d\n", BLOCK_NUMBER);
    printf("number of threads: %d\n", BLOCK_THREADS);
    //printf("number of checks per thread: %d\n", THREAD_STEPS);
    //printf("number of CPU threads: %d\n", pool.size());

    secp = new Secp256K1();
    secp->Init();
   
    cudaError_t cudaStatus = prepareCuda();
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "Device prepare failed: %s\n", cudaGetErrorString(cudaStatus));
        return 1;
    }

    auto time = std::chrono::system_clock::now();
    std::time_t s_time = std::chrono::system_clock::to_time_t(time);
    std::cout << "Work started at " << std::ctime(&s_time);

    if (randomMode){        
        pool.resize(std::thread::hardware_concurrency());
        printf("RANDOM mode (bulk size: %d)\n", BLOCK_NUMBER*BLOCK_THREADS);
        cudaStatus = processCudaRandom();
    }
    else {
        pool.resize(std::thread::hardware_concurrency() / 2);
        printf("Starting key: %s\n", KEY_START.c_str());
        cudaStatus = processCuda();
    }

    cudaStatus = cudaDeviceReset();
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "Device reset failed!");
        return 1;
    }
    
    return 0;
}

bool checkDevice() {
    cudaError_t cudaStatus = cudaSetDevice(DEVICE_NR);
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "device %d failed!", DEVICE_NR);
        return false;
    }
    else {
        cudaDeviceProp props;
        cudaStatus = cudaGetDeviceProperties(&props, DEVICE_NR);
        printf("Using   device   : %d \n", DEVICE_NR);
        printf("%s (%2d procs)\n", props.name, props.multiProcessorCount);
        //printf("maxThreadsPerBlock: %2d\n\n", props.maxThreadsPerBlock);
        if (BLOCK_NUMBER == 0) {
            BLOCK_NUMBER = props.multiProcessorCount * 8;
        }
        if (BLOCK_THREADS == 0) {
            BLOCK_THREADS = props.maxThreadsPerBlock / 8;
        }
        outputSize = (uint64_t) BLOCK_NUMBER * BLOCK_THREADS * THREAD_STEPS;

    }
    return true;
}

cudaError_t prepareCuda() {
    cudaError_t cudaStatus;
    unsigned int* buffAlphabet = new unsigned int[LONG_ALPHABET_LEN];
    for (int i = 0; i < LONG_ALPHABET_LEN; i++) {
        buffAlphabet[i] = ALPHABET[i];
    }
    cudaStatus = loadAlphabet(buffAlphabet);
    if (cudaStatus != cudaSuccess) {
        fprintf(stderr, "kernel launch failed: %s\n", cudaGetErrorString(cudaStatus));
    }   
    // Kept original behavior, no delete here.
    return cudaStatus;
}



cudaError_t processCudaRandom() {
    cudaError_t cudaStatus;

    // --- 所有变量的声明和初始化，全部移到函数开头 ---
    // 确保所有局部变量在任何 goto Error; 之前完成声明和可能的初始化
    uint32_t outputSize8 = outputSize * 8; // 声明并初始化
    unsigned int* buffDeviceResult = new unsigned int[outputSize8]; // 声明并初始化
    unsigned int* dev_buffDeviceResult = new unsigned int[outputSize8]; // 声明并初始化
    curandState_t* states = nullptr; // 声明并初始化为 nullptr，以防 cudaMalloc 失败

    // 以下变量来自 processCuda()，用于顺序模式的密钥管理
    int buffStart[KEY_LENGTH]; // 栈上数组，其声明在函数入口即完成
    int *dev_buffStart = nullptr; // 声明并初始化为 nullptr

    // 以下是收集结果的缓冲区，从 processCuda() 借用
    //int COLLECTOR_SIZE = BLOCK_NUMBER; // 声明并初始化
    int COLLECTOR_SIZE8 = BLOCK_NUMBER * 8; // 声明并初始化

    unsigned int* buffResult = new unsigned int[COLLECTOR_SIZE8]; // 声明并初始化
    unsigned int* dev_buffResult = nullptr; // 声明并初始化为 nullptr
    bool* buffCollectorWork = new bool[1]; // 声明并初始化
    bool* dev_buffCollectorWork = nullptr; // 声明并初始化为 nullptr

    // 计时器和计数器，声明并初始化
    uint64_t counter = 0;
    uint64_t foundCount = 0;
    std::chrono::steady_clock::time_point beginCountHashrate = std::chrono::steady_clock::now();
    std::chrono::steady_clock::time_point beginCountStatus = std::chrono::steady_clock::now();

    // 控制随机跳跃的频率
    const int JUMP_BATCHES_COUNT = 1000; // const 变量可以在声明时直接初始化
    int batches_since_last_jump = JUMP_BATCHES_COUNT; // 声明并初始化

    // --- 初始主机端缓冲区设置 ---
    for (int i = 0; i < outputSize8; i++) {
        buffDeviceResult[i] = 0;
    }
    for (int i = 0; i < COLLECTOR_SIZE8; i++) {
        buffResult[i] = 0;
    }
    buffCollectorWork[0] = false;

    // --- CUDA 内存分配和初始数据拷贝 ---
    // 现在这些 CUDA 调用和 goto Error; 都在变量初始化之后了
    cudaStatus = cudaMalloc((void**)&dev_buffDeviceResult, outputSize8 * sizeof(unsigned int));
    if (cudaStatus != cudaSuccess) { fprintf(stderr, "cudaMalloc dev_buffDeviceResult failed: %s\n", cudaGetErrorString(cudaStatus)); goto Error; }
    cudaStatus = cudaMemcpyAsync(dev_buffDeviceResult, buffDeviceResult, outputSize8 * sizeof(unsigned int), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) { fprintf(stderr, "cudaMemcpyAsync dev_buffDeviceResult failed: %s\n", cudaGetErrorString(cudaStatus)); goto Error; }

    cudaStatus = cudaMalloc((void**)&states, outputSize * sizeof(curandState_t));
    if (cudaStatus != cudaSuccess) { fprintf(stderr, "cudaMalloc states failed: %s\n", cudaGetErrorString(cudaStatus)); goto Error; }
    initRandomStates <<<BLOCK_NUMBER, BLOCK_THREADS>>> (time(0), states);
    cudaStatus = cudaGetLastError();
    if (cudaStatus != cudaSuccess) { fprintf(stderr, "initRandomStates launch failed: %s\n", cudaGetErrorString(cudaStatus)); goto Error; }

    cudaStatus = cudaMalloc((void**)&dev_buffResult, COLLECTOR_SIZE8 * sizeof(unsigned int));
    if (cudaStatus != cudaSuccess) { fprintf(stderr, "cudaMalloc dev_buffResult failed: %s\n", cudaGetErrorString(cudaStatus)); goto Error; }
    cudaStatus = cudaMemcpy(dev_buffResult, buffResult, COLLECTOR_SIZE8 * sizeof(unsigned int), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) { fprintf(stderr, "cudaMemcpy dev_buffResult failed: %s\n", cudaGetErrorString(cudaStatus)); goto Error; }

    cudaStatus = cudaMalloc((void**)&dev_buffCollectorWork, 1 * sizeof(bool));
    if (cudaStatus != cudaSuccess) { fprintf(stderr, "cudaMalloc dev_buffCollectorWork failed: %s\n", cudaGetErrorString(cudaStatus)); goto Error; }
    cudaStatus = cudaMemcpy(dev_buffCollectorWork, buffCollectorWork, 1 * sizeof(bool), cudaMemcpyHostToDevice);
    if (cudaStatus != cudaSuccess) { fprintf(stderr, "cudaMemcpy dev_buffCollectorWork failed: %s\n", cudaGetErrorString(cudaStatus)); goto Error; }

    cudaStatus = cudaMalloc((void**)&dev_buffStart, KEY_LENGTH * sizeof(int));
    if (cudaStatus != cudaSuccess) { fprintf(stderr, "cudaMalloc dev_buffStart failed: %s\n", cudaGetErrorString(cudaStatus)); goto Error; }

    // 主要的循环
    while (true) {
        // --- 随机跳跃部分：生成新的随机起点 ---
        if (batches_since_last_jump >= JUMP_BATCHES_COUNT) {
            // 通过 GPU 生成一个随机私钥的 Base58 索引，作为新的 KEY_START_IX
            // 这需要一个专门的 CUDA 内核，或者简单地利用 curand 生成 256 位随机数
            // 最简单的实现（但不完全是 GPU 随机生成私钥，而是生成随机索引）
            // 注意：这种方式生成的“私钥”并不一定完全覆盖 2^256 空间，
            // 只是在 Base58 编码的索引上随机跳跃。
            for (int i = 0; i < KEY_LENGTH; ++i) {
                // 使用 CPU 的 rand() 函数，或者更安全的随机数生成器
                // 对于加密货币搜索，如果需要密码学强度随机数，应使用专门的库
                KEY_START_IX[i] = rand() % LONG_ALPHABET_LEN; 
            }
            batches_since_last_jump = 0; // 重置计数器
        }

        // --- 顺序搜索部分：从当前 KEY_START_IX 开始，计算一个批次 ---
        for (int i = 0; i < KEY_LENGTH; i++) {
            buffStart[i] = KEY_START_IX[i];
        }
        cudaStatus = cudaMemcpy(dev_buffStart, buffStart, KEY_LENGTH * sizeof(int), cudaMemcpyHostToDevice);
        if (cudaStatus != cudaSuccess) { fprintf(stderr, "cudaMemcpy dev_buffStart failed: %s\n", cudaGetErrorString(cudaStatus)); goto Error; }

        kernelMinikeys <<<BLOCK_NUMBER, BLOCK_THREADS >>> (dev_buffDeviceResult, dev_buffCollectorWork, dev_buffStart, THREAD_STEPS);
        cudaStatus = cudaGetLastError();
        if (cudaStatus != cudaSuccess) { fprintf(stderr, "kernelMinikeys launch failed: %s\n", cudaGetErrorString(cudaStatus)); goto Error; }
        cudaStatus = cudaDeviceSynchronize();
        if (cudaStatus != cudaSuccess) { fprintf(stderr, "cudaDeviceSynchronize returned error code %d!\n", cudaStatus); goto Error; }

        // --- 结果收集与处理 (与 processCuda() 类似) ---
        // 这里的 anyResult 逻辑是为了检查是否有结果需要收集。
        // 原 processCuda 这里的 anyResult 依赖 buffCollectorWork[0]，
        // 但你之前注释掉了 Host-Device 的拷贝和异步拷贝，
        // 这里我保持原来的 anyResult=true 简化处理，即总是尝试收集
        bool anyResult = true; 
        if (anyResult) {
            for (int i = 0; i < COLLECTOR_SIZE8; i++) {
                buffResult[i] = 0;
            }
            cudaStatus = cudaMemcpy(dev_buffResult, buffResult, COLLECTOR_SIZE8 * sizeof(unsigned int), cudaMemcpyHostToDevice);
            if (cudaStatus != cudaSuccess) { fprintf(stderr, "cudaMemcpy dev_buffResult for reset failed: %s\n", cudaGetErrorString(cudaStatus)); goto Error; }
        }
        while (anyResult) {
            resultCollector <<<BLOCK_NUMBER, 1 >>> (dev_buffDeviceResult, dev_buffResult, THREAD_STEPS * BLOCK_THREADS);
            vectorX.clear(); // 这些 clear 可以在循环外，或由线程池处理
            vectorY.clear();            
            cudaStatus = cudaGetLastError();
            if (cudaStatus != cudaSuccess) { fprintf(stderr, "resultCollector launch failed: %s\n", cudaGetErrorString(cudaStatus)); goto Error; }
            cudaStatus = cudaDeviceSynchronize();
            if (cudaStatus != cudaSuccess) { fprintf(stderr, "cudaDeviceSynchronize returned error code %d after resultCollector!\n", cudaStatus); goto Error; }            
            cudaStatus = cudaMemcpy(buffResult, dev_buffResult, COLLECTOR_SIZE8 * sizeof(unsigned int), cudaMemcpyDeviceToHost);
            if (cudaStatus != cudaSuccess) { fprintf(stderr, "cudaMemcpy buffResult failed: %s\n", cudaGetErrorString(cudaStatus)); goto Error; }

            anyResult = false; // 假设本轮没有更多结果，除非在循环中找到
            for (int resultIx = 0; resultIx < COLLECTOR_SIZE8;) {
                // 检查是否是非零结果 (假设 0x0 或 0xFFFFFFFF 是特殊标志)
                if ((buffResult[resultIx] != 0x0 && buffResult[resultIx] != 0xFFFFFFFF) || buffResult[resultIx + 1] != 0x0 || buffResult[resultIx + 2] != 0x0 || buffResult[resultIx + 3] != 0x0 ||
                    buffResult[resultIx + 4] != 0x0 || buffResult[resultIx + 5] != 0x0 || buffResult[resultIx + 6] != 0x0 || buffResult[resultIx + 7] != 0x0) {                    
                    
                    uint32_t bitsToSet[8];
                    for (int b = 0; b < 8; b++) {
                        bitsToSet[7 - b] = buffResult[resultIx + b];
                    }
                    pool.push(processCandidateThread, bitsToSet[0], bitsToSet[1], bitsToSet[2], bitsToSet[3], bitsToSet[4], bitsToSet[5], bitsToSet[6], bitsToSet[7]);
                    
                    anyResult = true; // 发现结果，可能还有更多批次
                    foundCount++;
                }
                resultIx += 8;                
            }            
        }

        // --- 更新 KEY_START_IX 和计数器 ---
        incrementBase58(outputSize, KEY_START_IX); // 递增 KEY_START_IX 以准备下一个顺序批次
        counter += outputSize;
        batches_since_last_jump++; // 增加已处理的批次计数

        // --- 速度和状态报告 (与 processCuda() 相同) ---
        int64_t tHash = std::chrono::duration_cast<std::chrono::seconds>(std::chrono::steady_clock::now() - beginCountHashrate).count();
        int64_t tStatus = std::chrono::duration_cast<std::chrono::seconds>(std::chrono::steady_clock::now() - beginCountStatus).count();
        if (tHash > 5) { // 每 5 秒报告一次速度
            double speed = (double)((double)counter / tHash) / 1000000.0;
            double speedCorrect = (double)((double)foundCount / tHash) / 1000000.0;
            printSpeed(speed, speedCorrect);
            counter = 0;
            foundCount = 0;
            beginCountHashrate = std::chrono::steady_clock::now();
            while (!pool.isQueueEmpty()) {
                std::this_thread::sleep_for(std::chrono::milliseconds(2)); // 这里使用 2ms，而不是 50ms
            }
            pool.clear_queue(); // 清空 CPU 线程池队列
        }
        if (tStatus > fileStatusInterval) {
            saveStatus(); // 保存状态，记录当前 KEY_START_IX
            beginCountStatus = std::chrono::steady_clock::now();
        }
    }

Error: // 错误处理和资源清理
    // 确保所有动态分配的内存都被释放
    if (dev_buffResult) cudaFree(dev_buffResult);
    if (dev_buffDeviceResult) cudaFree(dev_buffDeviceResult);
    if (dev_buffStart) cudaFree(dev_buffStart);
    if (dev_buffCollectorWork) cudaFree(dev_buffCollectorWork);
    if (states) cudaFree(states);
    
    // 释放主机端内存
    delete [] buffDeviceResult;
    delete [] buffResult;
    delete [] buffCollectorWork;
    return cudaStatus;
}

cudaError_t processCuda() {
    cudaError_t cudaStatus;
    int buffStart[KEY_LENGTH];
    int *dev_buffStart; // 仅声明
    uint32_t outputSize8 = outputSize * 8;
    //int COLLECTOR_SIZE = BLOCK_NUMBER;
    int COLLECTOR_SIZE8 = BLOCK_NUMBER * 8;

    unsigned int* buffDeviceResult = new unsigned int[outputSize8];
    unsigned int* dev_buffDeviceResult = new unsigned int[outputSize8];

    // === 新增/移动的声明，解决 goto 问题 ===
    unsigned int* buffResult; // 仅声明
    unsigned int* dev_buffResult; // 仅声明

    bool* buffCollectorWork; // 仅声明
    bool* dev_buffCollectorWork; // 仅声明

    uint64_t counter;
    uint64_t foundCount;
    std::chrono::steady_clock::time_point beginCountHashrate;
    std::chrono::steady_clock::time_point beginCountStatus;

    Int toTest; // <--- **重要：同样从 `Int toTest = new Int();` 变为 `Int toTest;`**
                 // 注意：`toTest` 是对象，`buffStart` 是栈数组，它们的生命周期和 `new` 的指针变量不同。

    for (int i = 0; i < outputSize * 8; i++) {
        buffDeviceResult[i] = 0;
    }
    cudaStatus = cudaMalloc((void**)&dev_buffDeviceResult, outputSize8 * sizeof(unsigned int));
    cudaStatus = cudaMemcpyAsync(dev_buffDeviceResult, buffDeviceResult, outputSize8 * sizeof(unsigned int), cudaMemcpyHostToDevice);     
    
    // === 变量的实际初始化（保留在原位） ===
    buffResult = new unsigned int[COLLECTOR_SIZE8];
    dev_buffResult = new unsigned int[COLLECTOR_SIZE8];
    cudaStatus = cudaMalloc((void**)&dev_buffResult, COLLECTOR_SIZE8 * sizeof(unsigned int));
    cudaStatus = cudaMemcpy(dev_buffResult, buffResult, COLLECTOR_SIZE8 * sizeof(unsigned int), cudaMemcpyHostToDevice);

    buffCollectorWork = new bool[1];
    buffCollectorWork[0] = false;
    dev_buffCollectorWork = new bool[1];
    cudaStatus = cudaMalloc((void**)&dev_buffCollectorWork, 1 * sizeof(bool));
    cudaStatus = cudaMemcpy(dev_buffCollectorWork, buffCollectorWork, 1 * sizeof(bool), cudaMemcpyHostToDevice);

    cudaStatus = cudaMalloc((void**)&dev_buffStart, KEY_LENGTH * sizeof(int));

    counter = 0;
    foundCount = 0;
    beginCountHashrate = std::chrono::steady_clock::now();
    beginCountStatus = std::chrono::steady_clock::now();

    toTest.bits[8] = 0x0;
    toTest.bits[9] = 0x0;

    while (true) {
        for (int i = 0; i < KEY_LENGTH; i++) {
            buffStart[i] = KEY_START_IX[i];
        }
        cudaStatus = cudaMemcpy(dev_buffStart, buffStart, KEY_LENGTH * sizeof(int), cudaMemcpyHostToDevice);
        kernelMinikeys <<<BLOCK_NUMBER, BLOCK_THREADS >>> (dev_buffDeviceResult, dev_buffCollectorWork, dev_buffStart, THREAD_STEPS);

        cudaStatus = cudaGetLastError();
        if (cudaStatus != cudaSuccess) {
            fprintf(stderr, "kernel launch failed: %s\n", cudaGetErrorString(cudaStatus));
            goto Error;
        }
        cudaStatus = cudaDeviceSynchronize();
        if (cudaStatus != cudaSuccess) {
            fprintf(stderr, "cudaDeviceSynchronize returned error code %d after launching kernel!\n", cudaStatus);
            goto Error;
        }

        bool anyResult = true;
        /*cudaStatus = cudaMemcpy(buffCollectorWork, dev_buffCollectorWork, 1 * sizeof(bool), cudaMemcpyDeviceToHost);
        bool anyResult = buffCollectorWork[0];
        buffCollectorWork[0] = false;
        cudaStatus = cudaMemcpyAsync(dev_buffCollectorWork, buffCollectorWork, 1 * sizeof(bool), cudaMemcpyHostToDevice);
        */
        
        if (anyResult) {
            for (int i = 0; i < COLLECTOR_SIZE8; i++) {
                buffResult[i] = 0;
            }
            cudaStatus = cudaMemcpy(dev_buffResult, buffResult, COLLECTOR_SIZE8 * sizeof(unsigned int), cudaMemcpyHostToDevice);
        }
        while (anyResult) {
            resultCollector << <BLOCK_NUMBER, 1 >> > (dev_buffDeviceResult, dev_buffResult, THREAD_STEPS * BLOCK_THREADS);
            vectorX.clear();
            vectorY.clear();            
            cudaStatus = cudaGetLastError();
            if (cudaStatus != cudaSuccess) {
                fprintf(stderr, "kernel launch failed: %s\n", cudaGetErrorString(cudaStatus));
                goto Error;
            }
            cudaStatus = cudaDeviceSynchronize();
            if (cudaStatus != cudaSuccess) {
                fprintf(stderr, "cudaDeviceSynchronize returned error code %d after launching kernel!\n", cudaStatus);
                goto Error;
            }            
            cudaStatus = cudaMemcpy(buffResult, dev_buffResult, COLLECTOR_SIZE8 * sizeof(unsigned int), cudaMemcpyDeviceToHost);
            if (cudaStatus != cudaSuccess) {
                fprintf(stderr, "cudaMemcpy failed!");
                goto Error;
            }
            anyResult = false;                                    
            for (int resultIx = 0; resultIx < COLLECTOR_SIZE8;) {
                if ((buffResult[resultIx] != 0x0&& buffResult[resultIx] != 0xFFFFFFFF) || buffResult[resultIx + 1] != 0x0 || buffResult[resultIx + 2] != 0x0 || buffResult[resultIx + 3] != 0x0 ||
                    buffResult[resultIx + 4] != 0x0 || buffResult[resultIx + 5] != 0x0 || buffResult[resultIx + 6] != 0x0 || buffResult[resultIx + 7] != 0x0) {                    
                    /*for (int b = 0; b < 8; b++) {
                        toTest.bits[7-b] = buffResult[resultIx + b];
                    }
                                    
                    processCandidate(toTest);*/
                    
                    uint32_t bitsToSet[8];
                    for (int b = 0; b < 8; b++) {
                        bitsToSet[7 - b] = buffResult[resultIx + b];
                    }
                    pool.push(processCandidateThread, bitsToSet[0], bitsToSet[1], bitsToSet[2], bitsToSet[3], bitsToSet[4], bitsToSet[5], bitsToSet[6], bitsToSet[7]);
                    
                    anyResult = true;
                    foundCount++;
                }
                resultIx += 8;                
            }            
        }

        incrementBase58(outputSize, KEY_START_IX);
        counter += outputSize;
        int64_t tHash = std::chrono::duration_cast<std::chrono::seconds>(std::chrono::steady_clock::now() - beginCountHashrate).count();
        int64_t tStatus = std::chrono::duration_cast<std::chrono::seconds>(std::chrono::steady_clock::now() - beginCountStatus).count();
        if (tHash > 5) {
            double speed = (double)((double)counter / tHash) / 1000000.0;
            double speedCorrect = (double)((double)foundCount / tHash) / 1000000.0;
            printSpeed(speed, speedCorrect);
            counter = 0;
            foundCount = 0;
            beginCountHashrate = std::chrono::steady_clock::now();
            while (!pool.isQueueEmpty()) {
                std::this_thread::sleep_for(std::chrono::milliseconds(2));
            }
            pool.clear_queue();
        }
        if (tStatus > fileStatusInterval) {
            saveStatus();
            beginCountStatus = std::chrono::steady_clock::now();
        }
    }
Error:
    cudaFree(dev_buffResult);
    cudaFree(dev_buffDeviceResult);
    cudaFree(dev_buffStart);
    cudaFree(dev_buffCollectorWork);
    // 同样，对于 new 分配的 buffDeviceResult 和 buffResult，需要 delete []
    delete [] buffDeviceResult; // 增加这行
    delete [] buffResult; // 增加这行
    return cudaStatus;
}

void processCandidateThread(int id, uint32_t bit0, uint32_t bit1, uint32_t bit2, uint32_t bit3, uint32_t bit4, uint32_t bit5, uint32_t bit6, uint32_t bit7) {
    Int* toTest;
    toTest = new Int();
    toTest->bits[9] = 0x0;    toTest->bits[8] = 0x0;
    toTest->bits[7] = bit7;   toTest->bits[6] = bit6;
    toTest->bits[5] = bit5;   toTest->bits[4] = bit4;
    toTest->bits[3] = bit3;   toTest->bits[2] = bit2;
    toTest->bits[1] = bit1;   toTest->bits[0] = bit0;
    char rmdhash[21], address[50];
    //?
    Point publickey = secp->ComputePublicKey(toTest);
    secp->GetHash160(P2PKH, false, publickey, (unsigned char*)rmdhash);    
    std::string hashString(reinterpret_cast<char*>(rmdhash), 20);
    if (filterR160.contains(hashString)) {
        addressToBase58(rmdhash, address);
        string a = address;
        if (filter.contains(a) && addresses.find(a) != addresses.end()) {
            FILE* keys;
            string fileName = a;
            fileName.append("_");
            fileName.append(fileResult);
            printf("\nfound: %s - %s\n", address, toTest->GetBase16().c_str());
            keys = fopen(fileName.c_str(), "a+");
            fprintf(keys, "%s\n", address);
            fprintf(keys, "%s\n\n", toTest->GetBase16().c_str());
            fclose(keys);
        }
        a.clear();
    }
    publickey.Clear();
    publickey.~Point();
    hashString.clear();
    delete toTest;
}

void processCandidate(Int &toTest) {    
    char rmdhash[21], address[50];
    Point publickey = secp->ComputePublicKey(&toTest);
    /*vectorX.push_back(publickey.x.bits64[0]);
    vectorY.push_back(publickey.y.bits64[0]);
    vectorX.push_back(publickey.x.bits64[1]);
    vectorY.push_back(publickey.y.bits64[1]);
    vectorX.push_back(publickey.x.bits64[2]);
    vectorY.push_back(publickey.y.bits64[2]);
    vectorX.push_back(publickey.x.bits64[3]);
    vectorY.push_back(publickey.y.bits64[3]);
    vectorX.push_back(publickey.x.bits64[4]);
    vectorY.push_back(publickey.y.bits64[4]);*/
    secp->GetHash160(P2PKH, false, publickey, (unsigned char*)rmdhash);
    std::string hashString(reinterpret_cast< char*>(rmdhash),20);
    if (filterR160.contains(hashString)) {
        addressToBase58(rmdhash, address);
        string a = address;
        if (filter.contains(a) && addresses.find(a) != addresses.end()) {
            FILE* keys;
            printf("\nfound: %s - %s\n", address, toTest.GetBase16().c_str());
            keys = fopen(fileResult.c_str(), "a+");
            fprintf(keys, "%s\n", address);
            fprintf(keys, "%s\n\n", toTest.GetBase16().c_str());
            fclose(keys);
        }
    }
    /*bool match = true;
    for (int i=0; i<addressR160.size(); i++){
        vector<unsigned char> v = addressR160.at(i);
        match = true;
        for (int j = 0; match && j < v.size(); j++) {
            if (v.at(j) != (unsigned char)rmdhash[j]) {
                match = false;
            }
        }
        if (match) {
            break;
        }
    }
    if (match) {
        addressToBase58(rmdhash, address);
        string a = address;
        if (filter.contains(a)) {
            printf("found: %s - %s\n", address, toTest.GetBase16().c_str());
            keys = fopen(fileResult.c_str(), "a+");
            fprintf(keys, "%s\n", address);
            fprintf(keys, "%s\n\n", toTest.GetBase16().c_str());
            fclose(keys);
        }
    } */   
}

void prepareAlphabet() {
    string a = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    for (int i = 0; i < LONG_ALPHABET_LEN; i++) {
        ALPHABET[i] = a.at(i);
    }
}

bool readArgs(int argc, char** argv) {
    int a = 1;
    while (a < argc) {
        // --- ADDED: Handle -h or --help argument ---
        if (strcmp(argv[a], "-h") == 0 || strcmp(argv[a], "--help") == 0) {
            printf("Usage: %s [options]\n", argv[0]);
            printf("\nOptions:\n");
            printf("  -h, --help     Show this help message and exit.\n");
            printf("  -r        Enable random key search mode (generates random private keys).\n");
            printf("  -d <device_nr> Specify GPU device number (e.g., 0). Default is 0.\n");
            printf("  -t <threads>   Number of threads per CUDA block. Default is based on device properties.\n");
            printf("  -b <blocks>    Number of CUDA blocks. Default is based on device properties.\n");
            printf("  -i <file>  Path to a file containing target Bitcoin addresses (one per line, Base58).\n");
            printf("  -s <key>  Starting Base58 key for sequential search (e.g., S8888888888888888). Mutually exclusive with -r.\n");
            printf("\nExamples:\n");
            printf("  %s -i addresses.txt -d 0 -b 128 -t 1024 -s S8888888888888888\n", argv[0]);
            printf("  %s -i addresses.txt -r -d 0\n", argv[0]);
            exit(0); // Exit after showing help
        }
        // --- Original argument parsing logic ---
        if (strcmp(argv[a], "-r") == 0) {
            randomMode = true;
        }
        if (strcmp(argv[a], "-d") == 0) {
            a++;
            DEVICE_NR = strtol(argv[a], NULL, 10);
        }
        else if (strcmp(argv[a], "-t") == 0) {
            a++;
            BLOCK_THREADS = strtol(argv[a], NULL, 10);
        }
        else if (strcmp(argv[a], "-b") == 0) {
            a++;
            BLOCK_NUMBER = strtol(argv[a], NULL, 10);
        }
        else if (strcmp(argv[a], "-i") == 0) {
            a++;
            fileInput = string(argv[a]);
            read_file(fileInput);
        }
        else if (strcmp(argv[a], "-s") == 0) {
            a++;
            KEY_START= string(argv[a]);
            // Reverted to original padding logic based on KEY_LENGTH+1
            while (KEY_START.length() < KEY_LENGTH+1) {
                KEY_START.append("1");
            }
            // Reverted to original parsing loop based on KEY_LENGTH+1 and starting from i=1
            for (int i = 1, ix=0; i < KEY_LENGTH+1; i++, ix++) {
                for (int c = 0; c < 58; c++) {
                    if (ALPHABET[c] == KEY_START.at(i)) {
                        KEY_START_IX[ix] = c;
                        break;
                    }
                }
            }            
        }
        a++;
    }
    return true;
}



bool read_file(const std::string& file_name) {
    std::ifstream stream(file_name.c_str());

    if (!stream)
    {
        std::cout << "Error: Failed to open file '" << file_name << "'" << std::endl;
        return false;
    }
    std::string buffer;

    while (std::getline(stream, buffer))
    {        
        filter.insert(buffer);
        addresses.insert(buffer);
        std::vector<unsigned char> r160;
        if (DecodeBase58(buffer, r160)) {
            std::vector<unsigned char> address160;
            for (int i = 1; i <= 20; i++) {
                address160.push_back(r160.at(i));
            }
            std::string s(address160.begin(), address160.end());
            addressR160.push_back(address160);
            filterR160.insert(s);
        }
    }
    printf("Loaded addresses : %d\n", filter.element_count());
    addressesLoaded = true;
    return true; 
}

void incrementBase58(int count, int* key) {    
    for (int c = 0; c < count; c++) {
        int i = 20; // Reverted to original index (KEY_LENGTH - 1) which is 21 - 1 = 20.
        do {
            key[i] = (key[i] + 1) % LONG_ALPHABET_LEN;
        } while (key[i--] == 0 && i >= 0);
    }
}

// This helper function builds the current key string from the global KEY_START_IX array.
string getCurrentKeyAsString() {
    string key = "";
    for (int i = 0; i < KEY_LENGTH; i++) {
        key += ALPHABET[KEY_START_IX[i]];
    }
    return key;
}

// MODIFY THIS FUNCTION
void saveStatus() {
    FILE* stat = fopen(fileStatus.c_str(), "w");
    auto time = std::chrono::system_clock::now();
    std::time_t s_time = std::chrono::system_clock::to_time_t(time);
    fprintf(stat, "%s\n", std::ctime(&s_time));
    
    // Use the new helper function to get the key
    string key = getCurrentKeyAsString();

    fprintf(stat, "refresh：S%s\n", key.c_str()); // Outputs with 'S' prefix
    fclose(stat);
}


// REPLACE THIS ENTIRE FUNCTION
void printSpeed(double speed, double speedCorrect) {
    std::string speedStr; std::string speedCorrectStr;
    if (speed < 0.01) {
        speedStr = "< 0.01 MKey/s";
    }
    else {
        if (speed < 1000) {
            speedStr = formatDouble("%.3f", speed) + " MKey/s";
        }
        else {
            speed /= 1000;
            if (speed < 1000) {
                speedStr = formatDouble("%.3f", speed) + " GKey/s";
            }
            else {
                speed /= 1000;
                speedStr = formatDouble("%.3f", speed) + " TKey/s";
            }
        }
    }
    // Original code had a bug here, it used 'speed' instead of 'speedCorrect'.
    // I've corrected it, but if you want the original behavior, change 'speedCorrect' back to 'speed'.
    if (speedCorrect < 0.000001) { // A more sensible threshold for found keys/s
        speedCorrectStr = "0.000 MKey/s";
    }
    else {
        if (speedCorrect < 1000) {
            speedCorrectStr = formatDouble("%.3f", speedCorrect) + " MKey/s";
        }
        else {
            speedCorrect /= 1000;
            if (speedCorrect < 1000) {
                speedCorrectStr = formatDouble("%.3f", speedCorrect) + " GKey/s";
            }
            else {
                speedCorrect /= 1000;
                speedCorrectStr = formatDouble("%.3f", speedCorrect) + " TKey/s";
            }
        }
    }

    // Get the current key using our new helper function
    string currentKey = getCurrentKeyAsString();

    // Print everything in one line
    printf("\rTotal: %s | Candidates: %s | Task: S%s ", speedStr.c_str(), speedCorrectStr.c_str(), currentKey.c_str());
    fflush(stdout);
}
void printSpeed(double speed) {
    std::string speedStr;
    if (speed < 0.01) {
        speedStr = "< 0.01 MKey/s";
    }
    else {
        if (speed < 1000) {
            speedStr = formatDouble("%.3f", speed) + " MKey/s";
        }
        else {
            speed /= 1000;
            if (speed < 1000) {
                speedStr = formatDouble("%.3f", speed) + " GKey/s";
            }
            else {
                speed /= 1000;
                speedStr = formatDouble("%.3f", speed) + " TKey/s";
            }
        }
    }
    printf("\r %s   ", speedStr.c_str()); 
    fflush(stdout);
}

/*test : S1111111111111111888LV
* found: 1DpvL6FtuiQcp3FHiP56koeNmajChwG21Q - FF2818908FB70993AA3B017F4FE92A7AD13D142BE5451A77F287BA74FC206543
* 
* test : S8888888888888888888H9
* found: 1LNTHdkFgvn6fhKyzgyDvkVoa4ShvJA5aH - 2587BF77DB81437D3DE0EB97301791217341F6886057AA796F67E74431E144A0
*/
