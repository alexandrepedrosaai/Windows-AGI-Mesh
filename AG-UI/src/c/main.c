#include <stdio.h>
#include "ag_runtime.h"

int main(void) {
    ag_runtime runtime;
    ag_runtime_init(&runtime);
    puts("AG-UI native runtime started");
    ag_runtime_shutdown(&runtime);
    return 0;
}
