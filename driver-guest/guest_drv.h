#ifndef __GUEST_DRV_H__
#define __GUEST_DRV_H__

#include "guest_dev.h"
#include "guest_pci.h"

/*
* Main functions
*/
static int __init guest_init(void);
static void __exit guest_exit(void);

#endif