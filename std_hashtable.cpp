#include <iostream>
#include <limits.h>
#include <stdlib.h>
#include <ctime>
#include <vector>
#include <sstream>
#include <string>
#include <string>
#include <unordered_map>

using namespace std;

typedef std::unordered_map<int, int, std::hash<int>> hash_t;

int* stdBatchGet(hash_t hash, int* keys, int numKeys)
{
	int* retValues = new int[numKeys];
	if(retValues == NULL) {
		return NULL;
	}
	
	for(int i=0; i<numKeys; i++){
		retValues[i] = hash.find(keys[i])->second;
	}
	
	return retValues;
}

/******************************************/

#define HASH_INIT unordered_map<int, int> hash
#define HASH_RESERVE(size) hash.reserve(size)

#define HASH_INSERT(key, value) hash[key] = value
#define HASH_BATCH_INSERT(keys, values, numKeys) for(int i=0; i<numKeys; i++){ hash[ keys[i] ] = values[i]; }

#define HASH_GET(key) hash.find(key)->second
#define HASH_BATCH_GET(keys, numKeys) stdBatchGet(hash, keys, numKeys)

#define HASH_LOAD_FACTOR hash.load_factor()

#define HASH_DELETE(key) hash.erase(key)

#include "test_map.cpp"
