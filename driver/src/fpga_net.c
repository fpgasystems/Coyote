/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  */

#include "fpga_net.h"

// ======-------------------------------------------------------------------------------
//
// FPGA network functions - Exposes Coyote as a proper NIC to the system 
//
// ======-------------------------------------------------------------------------------

// Function for opening the new FPGA-NIC
static int fpga_net_open(struct net_device *dev)
{
    struct fpga_dev *fpga = netdev_priv(dev);

    // Initialize the TX lock and start the queue 
    spin_lock_init(&fpga->tx_lock);
    netif_start_queue(dev);

    pr_info("fpga_net: device %s opened\n", dev->name);
    return 0;
}

// Function for stopping the FPGA-NIC 
static int fpga_net_stop(struct net_device *dev)
{
    struct fpga_dev *fpga = netdev_priv(dev);

    // Stop the queue 
    netif_stop_queue(dev);

    pr_info("fpga_net: device %s closed\n", dev->name);
    return 0;
}

// Function for transmitting packets
static netdev_tx_t fpga_net_xmit(struct sk_buff *skb, struct net_device *dev)
{
    struct fpga_dev *fpga = netdev_priv(dev);

    // Increment the counter for outgoing packets and bytes for pushed out packets 
    dev->stats.tx_packets++;
    dev->stats.tx_bytes += skb->len;

    // TO BE IMPLEMENTED: PUSH PACKET TO FPGA FOR TRANSMISSION

    // Free the socket buffer
    dev_kfree_skb(skb);
    return NETDEV_TX_OK; // Return that everything is ok
}

// Struct that points to all the functions of the FPGA-NIC in the driver 
static const struct net_device_ops fpga_netdev_ops = {
    .ndo_open = fpga_net_open,
    .ndo_stop = fpga_net_stop,
    .ndo_start_xmit = fpga_net_xmit,
}; 

// --------------------------------------------
// Public API for registering the new FPGA-NIC
// --------------------------------------------

// Register the FPGA-NIC
int fpga_net_register(struct fpga_dev *fpga)
{
    int ret_val;

    // Allocate the net device structure
    fpga->ndev = alloc_etherdev(sizeof(struct fpga_dev));
    if (!fpga->ndev) {
        pr_err("fpga_net: could not allocate net device\n");
        return -ENOMEM;
    }

    struct fpga_dev *priv = netdev_priv(fpga->ndev);
    *priv = *fpga;        // copy existing FPGA struct
    priv->ndev = fpga->ndev; // ensure back-pointer to net_device

    // Set the device operations
    fpga->ndev->netdev_ops = &fpga_netdev_ops;

    // Set the MAC address (for simplicity, using a fixed MAC address here)
    eth_hw_addr_random(fpga->ndev); // Random MAC address for demonstration

    // Register the network device
    ret_val = register_netdev(fpga->ndev);
    if (ret_val) {
        pr_err("fpga_net: could not register net device\n");
        free_netdev(fpga->ndev);
        return ret_val;
    }

    pr_info("fpga_net: device %s registered with MAC %pM\n", fpga->ndev->name, fpga->ndev->dev_addr);
    return 0;
}

// Unregister the FPGA-NIC
void fpga_net_unregister(struct fpga_dev *fpga)
{
    if (fpga->ndev) {
        unregister_netdev(fpga->ndev);
        free_netdev(fpga->ndev);
        pr_info("fpga_net: device unregistered\n");
    } else {
        return; 
    }
}