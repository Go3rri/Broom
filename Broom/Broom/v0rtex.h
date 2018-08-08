#import "common.h"

#include <mach/mach.h>
#include <stdint.h>

typedef kern_return_t (*v0rtex_cb_t)(task_t tfp0, kptr_t kbase, void *cb_data);

kern_return_t v0rtex(offsets_t *off, v0rtex_cb_t callback, void *cb_data);
