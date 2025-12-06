// Worker.cu


#include "Worker.cuh"

__device__ __constant__ unsigned int ALPHABET[LONG_ALPHABET_LEN];

__global__ void resultCollector(unsigned int* buffResult, unsigned int* buffCombinedResult, const uint64_t threadsInBlockNumberOfChecks) {	
	int64_t start = 8 * blockIdx.x;
	if (buffCombinedResult[start] == 0xFFFFFFFF) {
		return;
	}
	int64_t tIx = blockIdx.x * blockDim.x;
	for (int i = start; i < start + 8; i++) {
		buffCombinedResult[i] = 0x0;
	}
	for (uint64_t i = 0, resultIx = tIx * threadsInBlockNumberOfChecks * 8; i < threadsInBlockNumberOfChecks; i++, resultIx += 8) {
		if (buffResult[resultIx] != 0x0 || buffResult[resultIx + 1] != 0x0 || buffResult[resultIx + 2] != 0x0 || buffResult[resultIx + 3] != 0x0 ||
			buffResult[resultIx + 4] != 0x0 || buffResult[resultIx + 5] != 0x0 || buffResult[resultIx + 6] != 0x0 || buffResult[resultIx + 7] != 0x0) {
			for (int z = start, r = resultIx, c = 0; c < 8; z++, r++, c++) {
				buffCombinedResult[z] = buffResult[r];
				buffResult[r] = 0x0;
			}
			return;
		}
	}
	buffCombinedResult[start] = 0xFFFFFFFF;
}

/*__global__ void resultCollector(unsigned int* buffResult, unsigned int* buffCombinedResult, const uint64_t threadsInBlockNumberOfChecks) {
	int64_t tIx = blockIdx.x * blockDim.x;
	int64_t start = 8 * blockIdx.x;
	for (int i = start; i < start + 8; i++) {
		buffCombinedResult[i] = 0x0;
	}
	for (uint64_t i = 0, resultIx = tIx * threadsInBlockNumberOfChecks * 8; i < threadsInBlockNumberOfChecks; i++, resultIx+=8) {
		if (buffResult[resultIx]!=0x0 || buffResult[resultIx+1] != 0x0 || buffResult[resultIx + 2] != 0x0 || buffResult[resultIx + 3] != 0x0 ||
			buffResult[resultIx+4] != 0x0 || buffResult[resultIx + 5] != 0x0 || buffResult[resultIx +6] != 0x0 || buffResult[resultIx +7] != 0x0) {
			for (int i = start, r= resultIx, c=0; c < 8; i++, r++, c++) {
				buffCombinedResult[i] = buffResult[r];
				buffResult[r] = 0x0;
			}
			return;
		}
		//resultIx += 8;
	}
}*/

__global__ void kernelMinikeys(unsigned int* buffResult, bool* buffCollectorWork, int* const __restrict__ buffStart, const int threadNumberOfChecks) {
	beu32 d_hash[8];
	int64_t tIx = (threadIdx.x + (int64_t)blockIdx.x * blockDim.x)/* * threadNumberOfChecks*/;
	int key[21];
	for (int i = 0; i < 21; i++) {
		key[i] = buffStart[i];
	}
	addBase58(tIx, key);
	//int tries = 0;
	if (checkSha256(key, d_hash)) {
		calculateSha256(key, d_hash);
		//buffCollectorWork[0] = true;
		for (int64_t i = tIx * 8, h = 0; h < 8; i++, h++) {
			buffResult[i] = d_hash[h];
		}
	}
	/*while (tries < threadNumberOfChecks) {
		if (checkSha256(key, d_hash)) {
			calculateSha256(key, d_hash);
			buffCollectorWork[0] = true;
			for (int64_t i = tIx * 8 + (tries*8), h = 0; h < 8; i++, h++) {
				buffResult[i] = d_hash[h];
			}
		}
		addBase58(1, key);
		tries++;
	}*/
}

__global__ void kernelMinikeysRandom(unsigned int* buffResult, curandState_t* states) {
	beu32 d_hash[8];
	int64_t tIx = (threadIdx.x + (int64_t)blockIdx.x * blockDim.x);
	int key[21];
	for (int i = 0; i < 21; i++) {
		key[i] = curand(&states[tIx]) % LONG_ALPHABET_LEN;
	}
	while (true) {
		if (checkSha256(key, d_hash)) {
			calculateSha256(key, d_hash);
			for (int64_t i = tIx * 8, h = 0; h < 8; i++, h++) {
				buffResult[i] = d_hash[h];
			}
			return;
		}
		addBase58(1, key);
	}	
}

__global__ void initRandomStates(unsigned int seed, curandState_t* states) {
	int64_t tIx = (threadIdx.x + (int64_t)blockIdx.x * blockDim.x);
	curand_init(seed, 		tIx,		0,		&states[tIx]);
}

__device__ void calculateSha256(int* key, beu32* d_hash) {
	sha256Kernel(d_hash,
		(((int)'S' << 24) & 0xff000000) | ((ALPHABET[key[0]] << 16) & 0x00ff0000) | ((ALPHABET[key[1]] << 8) & 0x0000ff00) | ((ALPHABET[key[2]]) & 0x000000ff),
		((ALPHABET[key[3]] << 24) & 0xff000000) | ((ALPHABET[key[4]] << 16) & 0x00ff0000) | ((ALPHABET[key[5]] << 8) & 0x0000ff00) | ((ALPHABET[key[6]]) & 0x000000ff),
		((ALPHABET[key[7]] << 24) & 0xff000000) | ((ALPHABET[key[8]] << 16) & 0x00ff0000) | ((ALPHABET[key[9]] << 8) & 0x0000ff00) | ((ALPHABET[key[10]]) & 0x000000ff),
		((ALPHABET[key[11]] << 24) & 0xff000000) | ((ALPHABET[key[12]] << 16) & 0x00ff0000) | ((ALPHABET[key[13]] << 8) & 0x0000ff00) | ((ALPHABET[key[14]]) & 0x000000ff),
		((ALPHABET[key[15]] << 24) & 0xff000000) | ((ALPHABET[key[16]] << 16) & 0x00ff0000) | ((ALPHABET[key[17]] << 8) & 0x0000ff00) | ((ALPHABET[key[18]]) & 0x000000ff),
		((ALPHABET[key[19]] << 24) & 0xff000000) | ((ALPHABET[key[20]] << 16) & 0x00ff0000) | 0x00008000,
		0x00000000,
		0x00000000,
		0x00000000,
		0x00000000,
		0x00000000,
		0x00000000,
		0x00000000,
		0x00000000,
		0x00000000,
		0x000000b0);
}

__device__ bool checkSha256(int* key, beu32* d_hash) {
	sha256Kernel(d_hash,
		(((int)'S' << 24) & 0xff000000) | ((ALPHABET[key[0]] << 16) & 0x00ff0000) | ((ALPHABET[key[1]] << 8) & 0x0000ff00) | ((ALPHABET[key[2]]) & 0x000000ff),
		((ALPHABET[key[3]] << 24) & 0xff000000) | ((ALPHABET[key[4]] << 16) & 0x00ff0000) | ((ALPHABET[key[5]] << 8) & 0x0000ff00) | ((ALPHABET[key[6]]) & 0x000000ff),
		((ALPHABET[key[7]] << 24) & 0xff000000) | ((ALPHABET[key[8]] << 16) & 0x00ff0000) | ((ALPHABET[key[9]] << 8) & 0x0000ff00) | ((ALPHABET[key[10]]) & 0x000000ff),
		((ALPHABET[key[11]] << 24) & 0xff000000) | ((ALPHABET[key[12]] << 16) & 0x00ff0000) | ((ALPHABET[key[13]] << 8) & 0x0000ff00) | ((ALPHABET[key[14]]) & 0x000000ff),
		((ALPHABET[key[15]] << 24) & 0xff000000) | ((ALPHABET[key[16]] << 16) & 0x00ff0000) | ((ALPHABET[key[17]] << 8) & 0x0000ff00) | ((ALPHABET[key[18]]) & 0x000000ff),
		((ALPHABET[key[19]] << 24) & 0xff000000) | ((ALPHABET[key[20]] << 16) & 0x00ff0000) | (('?' << 8) & 0x0000ff00) | 0x00000080,
	0x00000000,
	0x00000000,
	0x00000000,
	0x00000000,
	0x00000000,
	0x00000000,
	0x00000000,
	0x00000000,
	0x00000000,
	0x000000b8);
	return (d_hash[0] & 0xff000000) == 0x00;
}

__device__ void addBase58(int count, int* key) {	
	for (int c = 0; c < count; c++) {
		int i = 20;
		do {
			key[i] = (key[i] + 1) % LONG_ALPHABET_LEN;
		} while (key[i--] == 0 && i >= 0);
	}
}

cudaError_t loadAlphabet(unsigned int* _alphabet) {
	return cudaMemcpyToSymbol(ALPHABET, _alphabet, LONG_ALPHABET_LEN * sizeof(unsigned int));
}

__device__ void sha256Kernel(beu32* const hash, C16(COMMA, EMPTY)) {
#undef  H
#define H(i,alpha,magic)  beu32 hout##i;

	H8(EMPTY, EMPTY);

#undef  C
#define C(i)              c##i

#undef  H
#define H(i,alpha,magic)  &hout##i

	sha256_chunk0(C16(COMMA, EMPTY), H8(COMMA, EMPTY));

	//
	// SAVE H'S FOR NOW JUST SO NVCC DOESN'T OPTIMIZE EVERYTHING AWAY
	//
#undef  H
#define H(i,alpha,magic)  hash[i] = hout##i;

	H8(EMPTY, EMPTY);
}

