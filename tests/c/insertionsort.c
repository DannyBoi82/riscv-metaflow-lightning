/* Based on wikipedia pseudocode */

#define SIZE 95

#define SWAP(a,b) {int temp=(a); (a)=(b); (b)=temp;}
 
void insertionSort(int A[], int n) {
  int i = 1;
  
  while (i < n) {
    int j = i;
    
    while ((j > 0) && (A[j-1] > A[j])) {
      SWAP(A[j],A[j-1]);
      j = j - 1;
    }
    i = i + 1;
  }
}

int array[SIZE];

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

  insertionSort(array, SIZE);

  sum=0;
  for(i=0; i<SIZE; i++) {
    int bits=((unsigned int) sum)>>31;
    sum<<=1;
    sum|=bits;
    sum^=array[i];
  }

  return sum;
}
