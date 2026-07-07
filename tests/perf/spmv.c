// Sparse matrix multiply + residual computaiton with b vector after computation
// The matrix is represented in CSR format and is blocked to improve cache locality
//
// After computing the result of A*x, we compute |b - x|, the residual 

#include "spmv_matrix.h"

#define BLOCK_SIZE 128

static unsigned int out[NUM_ROWS];       // 32-bit SpMV output
static unsigned int blockbuf[BLOCK_SIZE];
static unsigned int residual[NUM_ROWS];  // 32-bit residuals


int main(void)
{
    for (unsigned int i = 0; i < NUM_ROWS; i++)
        out[i] = 0;

    // Stage 1: CSR SpMV
    unsigned int r = 0;

    while (r < NUM_ROWS) {
        unsigned int rmax = r + BLOCK_SIZE;
        if (rmax > NUM_ROWS)
            rmax = NUM_ROWS;

        for (unsigned int i = 0; i < BLOCK_SIZE; i++)
            blockbuf[i] = 0;

        for (unsigned int rr = r; rr < rmax; rr++) {

            unsigned int sum = 0;

            unsigned int start = row_ptr[rr];
            unsigned int end   = row_ptr[rr + 1];

            for (unsigned int i = start; i < end; i++) {

                unsigned int c = (unsigned int)col_idx[i];    
                unsigned int v = (unsigned int)values[i];   

                unsigned int base = (unsigned int)vec[c];

                unsigned int prod = base * v;
                
                // Indirection!!!!
                unsigned int c2 = (c ^ rr) % NUM_ROWS;
                unsigned int extra = (unsigned int)vec[c2];

                // Interesting math?? 
                prod ^= (extra << 1);
                prod += (rr & 31);
                prod ^= (i & 15);

                sum += prod;
            }

            blockbuf[rr - r] = sum;
        }

        for (unsigned int i = r; i < rmax; i++)
            out[i] = blockbuf[i - r];

        r = rmax;
    }

    // Stage 2: Residual computation
    unsigned int norm = 0;

    for (unsigned int i = 0; i < NUM_ROWS; i++) {

        unsigned int bi = (unsigned int)b[i];
        unsigned int yi = out[i];

        unsigned int diff = (bi > yi) ? (bi - yi) : (yi - bi);

        // More ALU mixing to stress scoreboard / OoO
        diff ^= (i << 1);
        diff += (i & 7);

        residual[i] = diff;
        norm += diff;
    }

    return (int)norm;
}
