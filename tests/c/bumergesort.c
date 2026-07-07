/* Based on wikipedia pseudocode */

#define SIZE 130

//  Left run is A[iLeft :iRight-1].
// Right run is A[iRight:iEnd-1  ].
void BottomUpMerge(int A[], int iLeft, int iRight, int iEnd, int B[])
{
  int i = iLeft, j = iRight;
  int k;

  // While there are elements in the left or right runs...
  for (k = iLeft; k < iEnd; k++) {
    // If left run head exists and is <= existing right run head.
    if (i < iRight && (j >= iEnd || A[i] <= A[j])) {
      B[k] = A[i];
      i = i + 1;
    } else {
      B[k] = A[j];
      j = j + 1;    
    }
  } 
}

void CopyArray(int B[], int A[], int n)
{
  int i;
  for (i = 0; i < n; i++)
    A[i] = B[i];
}

#define min(a,b) ((a)<(b)?(a):(b))

// array A[] has the items to sort; array B[] is a work array
void BottomUpMergeSort(int A[], int B[], int n)
{
  int width;

  // Each 1-element run in A is already "sorted".
  // Make successively longer sorted runs of length 2, 4, 8, 16... until the whole array is sorted.
  for (width = 1; width < n; width = 2 * width)
    {
      int i;

      // Array A is full of runs of length width.
      for (i = 0; i < n; i = i + 2 * width)
        {
	  // Merge two runs: A[i:i+width-1] and A[i+width:i+2*width-1] to B[]
	  // or copy A[i:n-1] to B[] ( if (i+width >= n) )
	  BottomUpMerge(A, i, min(i+width, n), min(i+2*width, n), B);
        }
      // Now work array B is full of runs of length 2*width.
      // Copy array B to array A for the next iteration.
      // A more efficient implementation would swap the roles of A and B.
      CopyArray(B, A, n);
      // Now array A is full of runs of length 2*width.
    }
}

int array[SIZE];
int scratch[SIZE];

int main() {
  int i;
  int sum=0;

  /*
    for(i=0; i<SIZE; i++) {
    array[i]=SIZE-i;
    }
  */

  for(i=0; i<SIZE; i++) {
#define SHIFT 17
    int bits=((unsigned int) sum)>>SHIFT;
    sum<<=(32-SHIFT);
    sum|=bits;
    sum^=(31*(SIZE-i));
    array[i]=sum;
  }

  BottomUpMergeSort(array, scratch, SIZE);

  sum=0;
  for(i=0; i<SIZE; i++) {
    int bits=((unsigned int) sum)>>31;
    sum<<=1;
    sum|=bits;
    sum^=array[i];
  }

  return sum;
}
