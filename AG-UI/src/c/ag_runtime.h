#ifndef AG_RUNTIME_H
#define AG_RUNTIME_H

typedef struct ag_runtime { int running; } ag_runtime;
void ag_runtime_init(ag_runtime *runtime);
void ag_runtime_shutdown(ag_runtime *runtime);

#endif
