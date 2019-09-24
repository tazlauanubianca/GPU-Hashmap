# GPU Hashmap Implementation

## I. Description
The project wants to implement a parallel HashMap used by CUDA.
The basic functionalities that the HashMap will support are those of insert and get.

The way it is implemented is linear probing, so after calculating the hash (key), it will try to insert the pair to the repository position in HashMap, and if it is busy it will look for the first free value after it. As an optimization, then
when get is done to get a value, after calculating that value, the key will be searched in the HashMap, and the search will cease when a free space has been found or the key we are looking for is found.

## II. Implementation
The insert, get and reshape functions will each use a kernel that will perform the respective operations in parallel. To keep the key pairs, value, I kept a vector in the device, all the operations being performed on it. For the hash function, we used a hash function already existing in the header.
For the insert function, first check if there is enough space in the hash map and check if the density of the positions already occupied in the hash map is greater than 0.8, in these cases the hash map size will double.
The insert kernel will insert only one element. It will search from the position indicated by the hash function, the first free position, or if the key is already inserted. If the key already exists, its value will be updated, and if it does not exist it will be inserted.
The reshape kernel will take an old key pair, value, and insert it into the new hash map.
The get kernel will search for a single key and add the value found in the vector.
I used a HashMap structure that keeps in VRAM a vector of Pair structures (key value pairs), the total size of the vector and the number of stored elements.
in the respective vector.

## III. Way of ussage
For use, the appropriate headers must be inserted.

## IV. Testing mode
For testing I used the HP tail (hp-sl.q) and CUDA 7.5.
