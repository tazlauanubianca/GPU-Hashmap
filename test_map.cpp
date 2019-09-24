#include <inttypes.h>
#include <sys/types.h>
#include <time.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <vector>
#include <algorithm>
#include <random>
#include <fstream>
#include <iostream>
#include <chrono>
#include <array>
#include <errno.h>

#define	KEY_INVALID		0
#define DIE(assertion, call_description) \
	do {	\
		if (assertion) {	\
		fprintf(stderr, "(%s, %d): ",	\
		__FILE__, __LINE__);	\
		perror(call_description);	\
		exit(errno);	\
	}	\
} while (0)

using namespace std;

void fillRandom(vector<int> &vecKeys, vector<int> &vecValues, int numEntries) {
	vecKeys.reserve(numEntries);
	vecValues.reserve(numEntries);
	
	int interval = (numeric_limits<int>::max() / numEntries) - 1;
	default_random_engine generator;
	uniform_int_distribution<int> distribution(1, interval);

	for(int i = 0; i < numEntries; i++) {
		vecKeys.push_back(interval * i + distribution(generator));
		vecValues.push_back(interval * i + distribution(generator));
	}
	
	random_shuffle(vecKeys.begin(), vecKeys.end());
	random_shuffle(vecValues.begin(), vecValues.end());
}

int main(int argc, char **argv)
{
	clock_t begin;
	double elapsedTime;
	
	int numKeys = 0;
	int numChunks = 0;
	vector<int> vecKeys;
	vector<int> vecValues;
	int *valuesGot = NULL;
	
	DIE(argc != 3, 
		"ERR, args num, call ./bin test_numKeys test_numChunks");
	
	numKeys = stoll(argv[1]);
	DIE((numKeys < 1) || (numKeys >= numeric_limits<int>::max()),
		"ERR, numKeys should be greater or equal to 1 and less than maxint");
	
	numChunks = stoll(argv[2]);
	DIE((numChunks < 1) || (numChunks >= numKeys), 
		"ERR, numChunks should be greater or equal to 1");
	
	fillRandom(vecKeys, vecValues, numKeys);
	
	HASH_INIT;
	
	int chunkSize = numKeys / numChunks;
	HASH_RESERVE(chunkSize);
	
	// perform INSERT and test performance
	for(int chunkStart = 0; chunkStart < numKeys; chunkStart += chunkSize) {
		
		int* keysStart = &vecKeys[chunkStart];
		int* valuesStart = &vecValues[chunkStart];
		
		begin = clock();
		// insert stage

		HASH_BATCH_INSERT(keysStart, valuesStart, chunkSize);
		elapsedTime = double(clock() - begin) / CLOCKS_PER_SEC;
		
		cout << "HASH_BATCH_INSERT, " << chunkSize
		<< ", " << chunkSize / elapsedTime / 1000000
		<< ", " << 100.f * HASH_LOAD_FACTOR << endl;
	}
	
	// perform INSERT for update validation
	int chunkSizeUpdate = min(256, numKeys);
	for(int chunkStart = 0; chunkStart < chunkSizeUpdate; chunkStart++) {
		vecValues[chunkStart] += 1111111 + chunkStart;
	}
	int *keyPtr = &vecKeys[0];
	int *vecPtr = &vecValues[0];
	HASH_BATCH_INSERT(keyPtr, vecPtr, chunkSizeUpdate);
	
	// perform GET and test performance
	for(int chunkStart = 0; chunkStart < numKeys; chunkStart += chunkSize) {
		
		int* keysStart = &vecKeys[chunkStart];

		begin = clock();
		// get stage
		valuesGot = HASH_BATCH_GET(keysStart, chunkSize);
		elapsedTime = double(clock() - begin) / CLOCKS_PER_SEC;
		
		cout << "HASH_BATCH_GET, " << chunkSize
		<< ", " << chunkSize / elapsedTime / 1000000
		<< ", " << 100.f * HASH_LOAD_FACTOR << endl;
	
		DIE(valuesGot == NULL, "ERR, ptr valuesCheck cannot be NULL");
		
		int mistmatches = 0;
		for(int i = 0; i < chunkSize; i++) {
			if(vecValues[chunkStart + i] != valuesGot[i]) {
				mistmatches++;
				if(mistmatches < 32) {
					cout << "Expected " << vecValues[chunkStart + i]
					<< ", but got " << valuesGot[i] << " for key:" << keysStart[i] << endl;
				}
			}
		}
		
		if(mistmatches > 0) {
			cout << "ERR, mistmatches: " << mistmatches << " / " << numKeys << endl;
			exit(1);
		}
	}

	return 0;
}

