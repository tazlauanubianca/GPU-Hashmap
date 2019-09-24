#include <iostream>
#include <limits.h>
#include <stdlib.h>
#include <ctime>
#include <sstream>
#include <string>

#include "gpu_hashtable.hpp"

#define BLOCKSIZE 1024

typedef struct {
	int key;
	int value;
} Pair;

typedef struct {
	int *size;
	int *numElem;
	Pair *pairs;
} HashTable;

HashTable hashTable;

/* INIT HASH
 */
GpuHashTable::GpuHashTable(int size) {
	cudaMalloc(&hashTable.size, sizeof(int));
	cudaMalloc(&hashTable.pairs, size * sizeof(Pair));
	cudaMalloc(&hashTable.numElem, sizeof(int));

	cudaMemset(hashTable.numElem, 0, sizeof(int));
	cudaMemset(hashTable.pairs, 0, size * sizeof(Pair));
	cudaMemcpy(hashTable.size, &size, sizeof(int), cudaMemcpyHostToDevice);	
}

/* DESTROY HASH
 */
GpuHashTable::~GpuHashTable() {
	cudaFree(hashTable.pairs);
	cudaFree(hashTable.size);
	cudaFree(hashTable.numElem);
}

__global__ void resize(Pair *newPairs, Pair *oldPairs, int *size, int *numElem, int *oldSize) {
	int keyToInsert = blockIdx.x * blockDim.x + threadIdx.x;
	if (keyToInsert >= *oldSize)
		return;

	int key = oldPairs[keyToInsert].key;
	if (key == 0)
		return;

	int position = hash1(key, *size);
	int index = position;
	int free = 0;

	/* Search for an empty position. */
	while (atomicCAS(&(newPairs[index].key), free, key) != 0) {
		index++;
		if (index == (*size))
			index = 0;
	}

	atomicAdd(numElem, 1);
	newPairs[index].value = oldPairs[keyToInsert].value;
}

/* RESHAPE HASH
 */
void GpuHashTable::reshape(int numBucketsReshape) {
	Pair *devicePairs;
	int hostOldSize;
	int *deviceOldSize;

	cudaMalloc(&deviceOldSize, sizeof(int));
	cudaMalloc(&devicePairs, numBucketsReshape * sizeof(Pair));

	cudaMemcpy(deviceOldSize, hashTable.size, sizeof(int), cudaMemcpyDeviceToDevice);
	cudaMemcpy(&hostOldSize, hashTable.size, sizeof(int), cudaMemcpyDeviceToHost);

	cudaMemset(hashTable.numElem, 0, sizeof(int));
	cudaMemcpy(hashTable.size, &numBucketsReshape, sizeof(int), cudaMemcpyHostToDevice);	

	/* Compute number of blocks */
	int blockNum = hostOldSize / BLOCKSIZE;
	if (blockNum * BLOCKSIZE < hostOldSize)
		blockNum++;

	resize<<<blockNum, BLOCKSIZE>>>(devicePairs, hashTable.pairs,
			hashTable.size, hashTable.numElem, deviceOldSize);

	cudaDeviceSynchronize();

	cudaFree(hashTable.pairs);
	hashTable.pairs = devicePairs;
}

__global__ void insert(int *keys, int *values, Pair *pairs, int *size,
		int *numElem, int *result, int numKeys) {
	/* Get position in HashTable for inertion */
	int keyToInsert = blockIdx.x * blockDim.x + threadIdx.x;
	if (keyToInsert >= numKeys)
		return;

	if (keys[keyToInsert] <= 0 || values[keyToInsert] <= 0)
		return;

	int position = hash1(keys[keyToInsert], *size);
	int key = keys[keyToInsert];
	int index = position;
	int free = 0;

	/* Check for an empty space in the HashTable */
	while(1) {
		if (pairs[index].key == key) 
			break;

		if (atomicCAS(&(pairs[index].key), free, key) == 0) {
			atomicAdd(result, 1);
			atomicAdd(numElem, 1);
			break;
		}

		index++;
		if (index == (*size))
			index = 0;
	}

	pairs[index].value = values[keyToInsert];
}

/* INSERT BATCH
 */
bool GpuHashTable::insertBatch(int *keys, int* values, int numKeys) {
	int *deviceResult, *deviceKeys, *deviceValues;
	int *hostResult;
	bool returnValue = false;

	int *hostNumElem = (int *)malloc(sizeof(int));
	cudaMemcpy(hostNumElem, hashTable.numElem, sizeof(int), cudaMemcpyDeviceToHost);

	int *hostSize = (int *)malloc(sizeof(int));
	cudaMemcpy(hostSize, hashTable.size, sizeof(int), cudaMemcpyDeviceToHost);

	/* Check if size is big enough */
	int oldSize = (*hostSize);
	while ((numKeys + (*hostNumElem)) > (*hostSize)) {
		(*hostSize) *= 2;
	}

	/* Check for hashtable density */
	if ((*hostNumElem) + numKeys > 0) { 
		if ((((float)((*hostNumElem) + numKeys) / (*hostSize)) > 0.8f) 
			&& ((*hostSize) * 2 < 0x7FFFFFFF)) {
			(*hostSize) *= 2;
		}
	}

	if (oldSize != (*hostSize))
		reshape((*hostSize));

	hostResult = (int *) malloc(sizeof(int));
	*hostResult = 0;

	cudaMalloc(&deviceKeys, numKeys * sizeof(int));
	cudaMalloc(&deviceValues, numKeys * sizeof(int));
	cudaMalloc(&deviceResult, sizeof(int));

	cudaMemcpy(deviceKeys, keys, numKeys * sizeof(int), cudaMemcpyHostToDevice);
	cudaMemcpy(deviceValues, values, numKeys * sizeof(int), cudaMemcpyHostToDevice);
	cudaMemcpy(deviceResult, hostResult, sizeof(int), cudaMemcpyHostToDevice);

	/* Compute number of blocks */
	int blockNum = numKeys / BLOCKSIZE;
	if (blockNum * BLOCKSIZE < numKeys)
		blockNum++;

	insert<<<blockNum, BLOCKSIZE>>>(deviceKeys, deviceValues, hashTable.pairs, 
					hashTable.size, hashTable.numElem, deviceResult, numKeys);
	
	cudaDeviceSynchronize();

	cudaFree(deviceResult);
	cudaFree(deviceKeys);
	cudaFree(deviceValues);
	free(hostResult);

	return returnValue;
}

__global__ void get(int *keys, int *values, Pair *pairs, int *size, int numKeys) {
	/* Get position in HashTable for inertion */
	int keyToGet = blockIdx.x * blockDim.x + threadIdx.x;
	if (keyToGet >= numKeys)
		return;

	int position = hash1(keys[keyToGet], *size);
	int key = keys[keyToGet];
	int index = position;
	int free = 0;
	int round = 0;

	/* Check for an empty space in the HashTable */
	while ((atomicCAS(&(pairs[index].key), key, key) != key) &&
		(atomicCAS(&(pairs[index].key), free, free) != free)) {
		index++;
		if (index == (*size))
			index = 0;

		if ((index == position) && (round == 1))
			return;

		round = 1;
	}

	values[keyToGet] = pairs[index].value;
}

/* GET BATCH
 */
int* GpuHashTable::getBatch(int* keys, int numKeys) {
	int *deviceKeys, *deviceValues;
	int *hostValues;

	hostValues = (int *) calloc(numKeys, sizeof(int));

	cudaMalloc(&deviceKeys, numKeys * sizeof(int));
	cudaMalloc(&deviceValues, numKeys * sizeof(int));
	cudaMemcpy(deviceKeys, keys, numKeys * sizeof(int), cudaMemcpyHostToDevice);

	/* Compute number of blocks */
	int blockNum = numKeys / BLOCKSIZE;
	if (blockNum * BLOCKSIZE < numKeys)
		blockNum++;

	get<<<blockNum, BLOCKSIZE>>>(deviceKeys, deviceValues, hashTable.pairs, 
					hashTable.size, numKeys);

	cudaDeviceSynchronize();
	cudaMemcpy(hostValues, deviceValues, sizeof(int) * numKeys, cudaMemcpyDeviceToHost);

	cudaFree(deviceKeys);
	cudaFree(deviceValues);

	return hostValues;
}

/* GET LOAD FACTOR
 * num elements / hash total slots elements
 */
float GpuHashTable::loadFactor() {
	int *numElem = (int *) malloc(sizeof(int));
	int *size = (int *) malloc(sizeof(int));

	cudaMemcpy(numElem, hashTable.numElem, sizeof(int), cudaMemcpyDeviceToHost);
	cudaMemcpy(size, hashTable.size, sizeof(int), cudaMemcpyDeviceToHost);

	float loadFactor = (float) *numElem / *size;

	return (float)loadFactor; // no larger than 1.0f = 100%
}

/*********************************************************/

#define HASH_INIT GpuHashTable GpuHashTable(1);
#define HASH_RESERVE(size) GpuHashTable.reshape(size);

#define HASH_BATCH_INSERT(keys, values, numKeys) GpuHashTable.insertBatch(keys, values, numKeys)
#define HASH_BATCH_GET(keys, numKeys) GpuHashTable.getBatch(keys, numKeys)

#define HASH_LOAD_FACTOR GpuHashTable.loadFactor()

#include "test_map.cpp"
