/* Based on wikipedia pseudocode */

#define SIZE 240

#define SWAP(a,b) {int temp=(a); (a)=(b); (b)=temp;}

// Divides array into two partitions
int partition(int A[], int lo, int hi) {
  int pivot=A[hi]; // Choose the last element as the pivot

  // Temporary pivot index
  int i = lo - 1;

  int j;
  for( j=lo; j<hi; j++) {
    // If the current element is less than or equal to the pivot
    if (A[j] <= pivot) {
      // Move the temporary pivot index forward
      i = i + 1;

      // Swap the current element with the element at the temporary pivot index
      SWAP(A[i],A[j]);
    }
  }   
   
  // Move the pivot element to the correct pivot position (between the smaller and larger elements)
  i = i + 1;
  SWAP(A[i],A[hi]);
  
  return i; // the pivot index
}

// Sorts a (portion of an) array, divides it into partitions, then sorts those
void quickSort(int A[], int lo, int hi) {

  // Ensure indices are in correct order
  if ((lo >= hi) || (lo < 0)) return;
  
  // Partition array and get the pivot index
  int p= partition(A, lo, hi);
      
  // Sort the two partitions
  quickSort(A, lo, p - 1); // Left side of pivot
  quickSort(A, p + 1, hi); // Right side of pivot
}

int array[SIZE];

int main() {
  int i;
  int sum=0;

  for(i=0; i<SIZE; i++) {
#define SHIFT 17
    int bits=((unsigned int) sum)>>SHIFT;
    sum<<=(32-SHIFT);
    sum|=bits;
    sum^=(31*(SIZE-i));
    array[i]=sum;
  }

  quickSort(array, 0, SIZE-1);

  sum=0;
  for(i=0; i<SIZE; i++) {
    int bits=((unsigned int) sum)>>31;
    sum<<=1;
    sum|=bits;
    sum^=array[i];
  }

  return sum;
}
