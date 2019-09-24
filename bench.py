import traceback
import re
import sys, os, subprocess, signal
from subprocess import STDOUT, check_output

programs = [
    #'std_hashtable',
    'gpu_hashtable',
]

testConfig = [
    {   "testName" : "T1",
        "numEntries" : 100000,
        "numChunks" : 1,
        "points" : 20,
        "tags" : {
            "HASH_BATCH_INSERT" : { "minThroughput" : 0, "minLoadFactor" : 40, "points" : 10 },
            "HASH_BATCH_GET" : { "minThroughput" : 1, "minLoadFactor" : 40, "points" : 10 },
        }
    },
    {   "testName" : "T2",
        "numEntries" : 2000000,
        "numChunks" : 1,
        "points" : 20,
        "tags" : {
            "HASH_BATCH_INSERT" : { "minThroughput" : 5, "minLoadFactor" : 40, "points" : 10 },
            "HASH_BATCH_GET" : { "minThroughput" : 5, "minLoadFactor" : 40, "points" : 10 },
        }
    },
    {   "testName" : "T3",
        "numEntries" : 4000000,
        "numChunks" : 5,
        "points" : 10,
        "tags" : {
            "HASH_BATCH_INSERT" : { "minThroughput" : 1, "minLoadFactor" : 40, "points" : 1 },
            "HASH_BATCH_GET" : { "minThroughput" : 15, "minLoadFactor" : 40, "points" : 1 },
        }
    },
    {   "testName" : "T4",
        "numEntries" : 10000000,
        "numChunks" : 1,
        "points" : 20,
        "tags" : {
            "HASH_BATCH_INSERT" : {"minThroughput" : 10, "minLoadFactor" : 40, "points" : 10 },
            "HASH_BATCH_GET" : { "minThroughput" : 20, "minLoadFactor" : 40, "points" : 10 },
        }
    },
    {   "testName" : "T5",
        "numEntries" : 10000000,
        "numChunks" : 5,
        "points" : 20,
        "tags" : {
            "HASH_BATCH_INSERT" : {"minThroughput" : 1, "minLoadFactor" : 50, "points" : 2 },
            "HASH_BATCH_GET" : { "minThroughput" : 25, "minLoadFactor" : 50, "points" : 2 },
        }
     },
]

outfile = open('output', 'w')

if len(sys.argv) > 1:
    benchtypes = sys.argv[1:]
else:
    benchtypes = ('0', '1')

nkeys = 100000
nchunks = 10

X_list_ops = []
Y_list_mops_per_second = []

#G, 0.12, 2.08333, 0.932411
for program in programs:
    programName = program

    hwMaxPoints = 0
    hwPoints = 0
    for testEntry in testConfig:
        
        try:
            output = subprocess.check_output(['./' + program, str(testEntry["numEntries"]), str(testEntry["numChunks"])])
            lines = str(output).split("\n")
            
            testName = testEntry["testName"]
            testPoints = 0
            testMaxPoints = testEntry["points"]
            hwMaxPoints += testMaxPoints
            
            testPoints = 0
            for line in lines:
                if not re.match("[HASH_BATCH_INSERT]+[HASH_BATCH_GET]+[ERR]+", line):
                    continue

                words = str(line).split(",")
                tagName = words[0]
                if tagName == "ERR":
                    testPoints = 0
                    print(line, " INVALIDATED")
                    break
                if tagName == "HASH_BATCH_INSERT" or tagName == "HASH_BATCH_GET":
                    hashThroughput = float(words[2])
                    loadFactor = float(words[3])
                    testReq = testEntry["tags"][tagName]
                    if (hashThroughput >= testReq["minThroughput"]) and (loadFactor >= testReq["minLoadFactor"]):
                        testPoints = testPoints + testReq["points"]
                        print(line, " OK")
                    else:
                        print(line, testReq, " FAIL")
            hwPoints = hwPoints + testPoints
            print("Test %s %d/%d\n" % (testName, testPoints, testMaxPoints) )
        except Exception:
            traceback.print_exc()
            print("Error with %s" % str(['./' + program, str(nkeys), str(nchunks)]))
            break
    print("\nTOTAL %s  %d/%d" % (program, hwPoints, hwMaxPoints) )
        
