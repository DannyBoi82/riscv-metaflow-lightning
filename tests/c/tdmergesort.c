/* Based on wikipedia pseudocode */

#define SIZE 140

//  Left source half is A[ iBegin:iMiddle-1].
// Right source half is A[iMiddle:iEnd-1   ].
// Result is            B[ iBegin:iEnd-1   ].
void TopDownMerge(int A[], int iBegin, int iMiddle, int iEnd, int B[])
{
  int i = iBegin, j = iMiddle;
  int k;

  // While there are elements in the left or right runs...
  for (k = iBegin; k < iEnd; k++) {
    // If left run head exists and is <= existing right run head.
    if (i < iMiddle && (j >= iEnd || A[i] <= A[j])) {
      B[k] = A[i];
      i = i + 1;
    } else {
      B[k] = A[j];
      j = j + 1;
    }
  }
}

void CopyArray(int A[], int iBegin, int iEnd, int B[])
{
  int k;
  for (k = iBegin; k < iEnd; k++)
    B[k] = A[k];
}

void TopDownMergeSort(int A[], int B[], int n);

// Split A[] into 2 runs, sort both runs into B[], merge both runs from B[] to A[]
// iBegin is inclusive; iEnd is exclusive (A[iEnd] is not in the set).
void TopDownSplitMerge(int B[], int iBegin, int iEnd, int A[])
{
  if (iEnd - iBegin <= 1)                     // if run size == 1
    return;                                 //   consider it sorted
  // split the run longer than 1 item into halves
  int iMiddle = (iEnd + iBegin) / 2;              // iMiddle = mid point
  // recursively sort both runs from array A[] into B[]
  TopDownSplitMerge(A, iBegin,  iMiddle, B);  // sort the left  run
  TopDownSplitMerge(A, iMiddle,    iEnd, B);  // sort the right run
  // merge the resulting runs from array B[] into A[]
  TopDownMerge(B, iBegin, iMiddle, iEnd, A);
}

// Array A[] has the items to sort; array B[] is a work array.
void TopDownMergeSort(int A[], int B[], int n)
{
  CopyArray(A, 0, n, B);           // one time copy of A[] to B[]
  TopDownSplitMerge(B, 0, n, A);   // sort data from B[] into A[]
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

  TopDownMergeSort(array, scratch, SIZE);

  sum=0;
  for(i=0; i<SIZE; i++) {
    int bits=((unsigned int) sum)>>31;
    sum<<=1;
    sum|=bits;
    sum^=array[i];
  }

  return sum;
}
