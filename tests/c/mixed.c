/**
 * mixed.c
 *
 * Mixed behavior benchmark
 *
 * This benchmark excercises a diverse range of behavior drawn
 * from the targeted behaviors in fibi.c, fibm.c, fibr.c.
 *
 **/

// The Fibonacci number to compute.
#define N 9 
#define SCALE 10 


#define BUFSIZE 512

int buf[BUFSIZE];
int bufi=0;
	
int fibi0(int n) {

  if (n == 0) {
    return 0;
  } else if (n == 1) {
    return 1;
  }
  
  // Declare the variables for fib(n), fib(n-1), and fib(n-2).
  int fib_n2 = 0;
  int fib_n1 = 1;
  int fib_n = -1;
  int i;
  
  // Iteratively compute the nth Fibonacci number
  for (i = 2; i <= n; i++)     {
    fib_n = fib_n1 + fib_n2;
    fib_n2 = fib_n1;
    fib_n1 = fib_n;
  }

  //printf ("\ti%d %d\n", n, fib_n);

  bufi++; 
  buf[(bufi*11)%BUFSIZE]+=fib_n;
  return fib_n;
}

int fibi1(int n) {

  if (n == 0) {
    return 0;
  } else if (n == 1) {
    return 1;
  }
  
  // Declare the variables for fib(n), fib(n-1), and fib(n-2).
  int fib_n2 = 0;
  int fib_n1 = 1;
  int fib_n = -1;
  int i;
  
  // Iteratively compute the nth Fibonacci number
  for (i = 2; i <= n; i++)     {
    fib_n = fib_n1 + fib_n2;
    fib_n2 = fib_n1;
    fib_n1 = fib_n;
  }

  //printf ("\ti%d %d\n", n, fib_n);

  bufi++; 
  buf[(bufi*13)%BUFSIZE]+=fib_n;
  return fib_n;
}

int fibi2(int n) {

  if (n == 0) {
    return 0;
  } else if (n == 1) {
    return 1;
  }
  
  // Declare the variables for fib(n), fib(n-1), and fib(n-2).
  int fib_n2 = 0;
  int fib_n1 = 1;
  int fib_n = -1;
  int i;
  
  // Iteratively compute the nth Fibonacci number
  for (i = 2; i <= n; i++)     {
    fib_n = fib_n1 + fib_n2;
    fib_n2 = fib_n1;
    fib_n1 = fib_n;
  }

  //printf ("\ti%d %d\n", n, fib_n);

  bufi++; 
  buf[(bufi*17)%BUFSIZE]+=fib_n;
  return fib_n;
}

int fibi3(int n) {

  if (n == 0) {
    return 0;
  } else if (n == 1) {
    return 1;
  }
  
  // Declare the variables for fib(n), fib(n-1), and fib(n-2).
  int fib_n2 = 0;
  int fib_n1 = 1;
  int fib_n = -1;
  int i;
  
  // Iteratively compute the nth Fibonacci number
  for (i = 2; i <= n; i++)     {
    fib_n = fib_n1 + fib_n2;
    fib_n2 = fib_n1;
    fib_n1 = fib_n;
  }

  //printf ("\ti%d %d\n", n, fib_n);

  bufi++; 
  buf[(bufi*19)%BUFSIZE]+=fib_n;
  return fib_n;
}

int fibi(int n) {
  static int i=0;

  switch((i++)%4) {
  case 0: return fibi0(n);
  case 1: return fibi1(n);
  case 2: return fibi2(n);
  case 3: return fibi3(n);
  }

  return -100;
}

int fibm0(int n) {
  int i;
  static int fib_seq[N*SCALE+1];
  
  if (n>(N*SCALE)) {
    return -2;
  } else if (n == 0) {
    return 0;
  } else if (n == 1) {
    return 1;
  }
  
  // Declare the array to store the Fibonacci sequence of numbers.
  fib_seq[0] = 0;
  fib_seq[1] = 1;
  
  // Iteratively compute the nth Fibonacci number
  for (i = 2; i <= n; i++) {
    fib_seq[i] = fib_seq[i-1] + fib_seq[i-2];
  }

  for (i = 2; i <= n; i++) {
    if (fib_seq[i]!=(fib_seq[i-1] + fib_seq[i-2])) {
      return -3;
    }
  }
  
  //printf ("\tm%d %d\n", n, fib_seq[n]);

  bufi++; 
  buf[(bufi*23)%BUFSIZE]+=fib_seq[n];
  return fib_seq[n];
}

int fibm1(int n) {
  int i;
  static int fib_seq[N*SCALE+1];
  
  if (n>(N*SCALE)) {
    return -2;
  } else if (n == 0) {
    return 0;
  } else if (n == 1) {
    return 1;
  }
  
  // Declare the array to store the Fibonacci sequence of numbers.
  fib_seq[0] = 0;
  fib_seq[1] = 1;
  
  // Iteratively compute the nth Fibonacci number
  for (i = 2; i <= n; i++) {
    fib_seq[i] = fib_seq[i-1] + fib_seq[i-2];
  }

  for (i = 2; i <= n; i++) {
    if (fib_seq[i]!=(fib_seq[i-1] + fib_seq[i-2])) {
      return -3;
    }
  }
  
  //printf ("\tm%d %d\n", n, fib_seq[n]);

  bufi++; 
  buf[(bufi*29)%BUFSIZE]+=fib_seq[n];
  return fib_seq[n];
}

int fibm2(int n) {
  int i;
  static int fib_seq[N*SCALE+1];
  
  if (n>(N*SCALE)) {
    return -2;
  } else if (n == 0) {
    return 0;
  } else if (n == 1) {
    return 1;
  }
  
  // Declare the array to store the Fibonacci sequence of numbers.
  fib_seq[0] = 0;
  fib_seq[1] = 1;
  
  // Iteratively compute the nth Fibonacci number
  for (i = 2; i <= n; i++) {
    fib_seq[i] = fib_seq[i-1] + fib_seq[i-2];
  }

  for (i = 2; i <= n; i++) {
    if (fib_seq[i]!=(fib_seq[i-1] + fib_seq[i-2])) {
      return -3;
    }
  }
  
  //printf ("\tm%d %d\n", n, fib_seq[n]);

  bufi++; 
  buf[(bufi*31)%BUFSIZE]+=fib_seq[n];
  return fib_seq[n];
}

int fibm3(int n) {
  int i;
  static int fib_seq[N*SCALE+1];
  
  if (n>(N*SCALE)) {
    return -2;
  } else if (n == 0) {
    return 0;
  } else if (n == 1) {
    return 1;
  }
  
  // Declare the array to store the Fibonacci sequence of numbers.
  fib_seq[0] = 0;
  fib_seq[1] = 1;
  
  // Iteratively compute the nth Fibonacci number
  for (i = 2; i <= n; i++) {
    fib_seq[i] = fib_seq[i-1] + fib_seq[i-2];
  }

  for (i = 2; i <= n; i++) {
    if (fib_seq[i]!=(fib_seq[i-1] + fib_seq[i-2])) {
      return -3;
    }
  }
  
  //printf ("\tm%d %d\n", n, fib_seq[n]);

  bufi++; 
  buf[(bufi*37)%BUFSIZE]+=fib_seq[n];
  return fib_seq[n];
}

int fibm(int n) {
  static int i=0;

  switch((i++)%4) {
  case 0: return fibm0(n);
  case 1: return fibm1(n);
  case 2: return fibm2(n);
  case 3: return fibm3(n);
  }

  return -1000;
}

int fibr(int n)
{
  static int i=0;
  int fib_n;

  if (n>N) {
    return -4;
  } else if (n == 0) {
    return 0;
  } else if (n == 1) {
    return 1;
  }

  //printf ("%d\n", n);

  i+=7;
  switch((n+i)%8) {
  case 0: 
    fib_n=fibr(n-1) + fibr(n-2);
    break;
  case 1: 
    fib_n=fibr(n-1) + fibr(n-2);
    break;
  case 2: 
    fib_n=fibr(n-1) + fibr(n-2);
    break;
  case 3: 
    fib_n=fibr(n-1) + fibr(n-2);
    break;
  case 4: 
    fib_n=fibr(n-1) + fibr(n-2);
    break;
  case 5: 
    fib_n=fibr(n-1) + fibr(n-2);
    break;
  case 6: 
    fib_n=fibr(n-1) + fibr(n-2);
    break;
  case 7: 
    fib_n=fibr(n-1) + fibr(n-2);
    break;
  default:
    fib_n=-1;
  }

  if (n>=((5*N)/10)) {
    if (fibi(SCALE*n)!=fibm(SCALE*n)) {
      return -5;
    }
  }

  //printf ("\tr%d %d\n", n, fib_n);

  bufi+=fib_n;
  return fib_n;
}
  
int main() {
  int i;
  int r=0;

  for(i=0; i<BUFSIZE; i++) {
    buf[i]=-i;
  }

  fibr(N);

  for(i=0; i<BUFSIZE; i++) {
    r+=buf[i];
  }

  r+=bufi;
  return r;
}


