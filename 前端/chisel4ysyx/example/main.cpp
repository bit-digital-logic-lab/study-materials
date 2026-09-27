#include "Vtop.h"
#include "verilated.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

int main (int argc, char *argv[]) {
  VerilatedContext * contexp = new VerilatedContext;
  contexp->commandArgs(argc,argv);


  Vtop* top = new Vtop{contexp};

  while (1) {
  int a = rand() & 1;
  int b = rand() & 1;
  top->a = a;
  top->b = b;
  top->eval();
  printf("a = %d, b = %d, f = %d\n", a, b, top->c);
  assert(top->c == (a ^ b));
}
  return 0;
}
