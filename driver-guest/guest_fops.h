#ifndef __GUEST_FOPS_H__
#define __GUEST_FOPS_H__

#include "guest_dev.h"
#include "guest_mm.h"

int guest_open(struct inode* inode, struct file *f);
int guest_release(struct inode *inode, struct file *f);
long guest_ioctl(struct file *f, unsigned int cmd, unsigned long arg);
int guest_mmap(struct file *f, struct vm_area_struct *vma);

#endif