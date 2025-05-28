#ifndef __GUEST_MM_H__
#define __GUEST_MM_H__

#include "guest_dev.h"

int guest_put_all_user_pages(struct vfpga *d, int dirtied);
int guest_get_user_pages(struct vfpga *d, uint64_t start, size_t count, int32_t cpid, pid_t pid);
int guest_put_user_pages(struct vfpga *d, uint64_t vaddr, int32_t cpid, int dirtied);

#endif