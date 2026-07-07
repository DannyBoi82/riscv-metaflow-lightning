#include "data_arrays.h"

// These are hard coded to optimize the index calculations for your
// poor multiplier-less core
void transpose_17() {
    for (int i = 0; i < 17; i++) {
        for (int j = i+1; j < 17; j++) {
            int t0,t1;
            t0 = array_17x17[i][j];
            t1 = array_17x17[j][i];
            array_17x17[j][i] = t0;
            array_17x17[i][j] = t1;
        }
    }
}

void transpose_16() {
    for (int i = 0; i < 16; i++) {
        for (int j = i+1; j < 16; j++) {
            int t0,t1;
            t0 = array_16x16[i][j];
            t1 = array_16x16[j][i];
            array_16x16[j][i] = t0;
            array_16x16[i][j] = t1;
        }
    }
}

void transpose_14() {
    for (int i = 0; i < 14; i++) {
        for (int j = i+1; j < 14; j++) {
            int t0,t1;
            t0 = array_14x14[i][j];
            t1 = array_14x14[j][i];
            array_14x14[j][i] = t0;
            array_14x14[i][j] = t1;
        }
    }
}

int get_checksum(int *array, int size) {
    int checksum = 0;
    for (int i = 0; i < size; i++) {
        checksum += array[i] ^ i;
    }
    return checksum;
}

int main() {
    int checksum = 0;
    transpose_14();
    checksum ^= get_checksum(&array_14x14[0][0], 14 * 14) << 18;
    transpose_17();
    checksum ^= get_checksum(&array_17x17[0][0], 17 * 17) << 9;
    transpose_16();
    checksum ^= get_checksum(&array_16x16[0][0], 16 * 16);
    // checksum_space[0][0] = checksum;
    return checksum;
}