/* Based on wikipedia pseudocode */

#define SIZE 80

#define SWAP(a,b) {int temp=(a); (a)=(b); (b)=temp;}

void bubbleSort(int A[], int n) {
  int swapped;

  do {
    int i;
    swapped=0;

    for(i=1; i<= (n - 1); i++) {
      if (A[i - 1] > A[i]) {
	SWAP(A[i],A[i-1]);
	swapped=1;
      }
    }
    n = n - 1;
  } while (swapped);
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

  bubbleSort(array, SIZE);

  sum=0;
  for(i=0; i<SIZE; i++) {
    int bits=((unsigned int) sum)>>31;
    sum<<=1;
    sum|=bits;
    sum^=array[i];
  }

  return sum;
}
