#include "ag_runtime.h"

void ag_runtime_init(ag_runtime *runtime) {
    if (runtime != 0) runtime->running = 1;
}

void ag_runtime_shutdown(ag_runtime *runtime) {
    if (runtime != 0) runtime->running = 0;
}
