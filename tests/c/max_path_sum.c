#include "data_arrays.h"

#define INT_MIN (-2147483648)

// Memoization table, initialized with -1 to indicate uncomputed values
static int memo[ROWS][COLS];

// Returns the maximum path sum from (0,0) to (r,c)
int max_path_sum(int r, int c) {
    if (r < 0 || c < 0) return INT_MIN; // Out of bounds
    if (r == 0 && c == 0) return grid[0][0]; // Base case: starting position
    if (memo[r][c] != -1) return memo[r][c]; // Return cached result if available

    // Recurrence: Maximum of coming from the left or from above
    int from_left = max_path_sum(r, c - 1);
    int from_top = max_path_sum(r - 1, c);

    memo[r][c] = grid[r][c] + (from_left > from_top ? from_left : from_top);
    return memo[r][c];
}

void initialize_memo() {
    for (int i = 0; i < ROWS; i++)
        for (int j = 0; j < COLS; j++)
            memo[i][j] = -1;
}

int main() {
    initialize_memo();
    int result = max_path_sum(ROWS - 1, COLS - 1);
    
    return result;
}
          

