/* Based on wikipedia pseudocode */

#define SIZE 75

#define SWAP(a,b) {int temp=(a); (a)=(b); (b)=temp;}

void selectionSort(int a[], int aLength) {
  /* a[0] to a[aLength-1] is the array to sort */
  int i,j;
  
  /* advance the position through the entire array */
  /*   (could do i < aLength-1 because single element is also min element) */
  for (i = 0; i < aLength-1; i++) {
    /* find the min element in the unsorted a[i .. aLength-1] */

    /* assume the min is the first element */
    int jMin = i;
    /* test against elements after i to find the smallest */
    for (j = i+1; j < aLength; j++) {
      /* if this element is less, then it is the new minimum */
      if (a[j] < a[jMin]) {
	/* found new minimum; remember its index */
	jMin = j;
      }
    }
    
    if (jMin != i) {
      SWAP(a[i],a[jMin]);
    }
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

  selectionSort(array, SIZE);

  sum=0;
  for(i=0; i<SIZE; i++) {
    int bits=((unsigned int) sum)>>31;
    sum<<=1;
    sum|=bits;
    sum^=array[i];
  }

  return sum;
}
