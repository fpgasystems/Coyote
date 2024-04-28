
HACC Cluster
====================================

The Heterogeneous Accelerated Compute Clusters (HACC) program is a special initiative to support novel research in adaptive compute acceleration for high performance computing (HPC). 
The scope of the program is broad and encompasses systems, architecture, tools and applications. You can check out HACC in more details at: `amd-haccs <https://www.amd-haccs.io/>`_.

.. figure:: images/infrastructure.png

The ETH Zurich cluster consists of eighteen servers one for development and seventeen for deployment. 
Four deployment servers host a mix of Alveo U250, Alveo U280 and VCK5000, ten servers host Alveo U55C, whereas, three other server (heterogeneous boxes) host a mix of accelerators: 4x AMD Instinct™ MI210 Accelerator, 2x VCK5000 and 2x Alveo U55C.
There are also additionally other 4 servers with 4x Alveo U50 cards.

In terms of networking communication, each Alveo cards has two 100 Gbps interfaces, both of them are connected to a switch.

.. note:: Within the cluster Coyote can run on all Alveo data center cards. 

For a more detailed look at how ETHZ-HACC is organized you can check out the following link: `ETHZ-HACC <https://github.com/fpgasystems/hacc/blob/main/docs/infrastructure.md#infrastructure>`_.

SGRT - Systems Group RunTime
====================================

Systems Group RunTime (SGRT) is a versatile RunTime software ready to be used on any AMD-compatible heterogeneous cluster.

SGRT includes a command-line interpreter (CLI) and an API, both utilizing an intuitive device index to improve user workflow. 
The CLI simplifies infrastructure setup, validation, and device configuration, while the API streamlines accelerated application development, allowing users to focus on their primary objectives.

Using Coyote with SGRT
------------------------

The SGRT provides a range of functions which can be used to quickly deploy Coyote on the HACC cluster.

To load the initial static Coyote image the following command can be used: 

.. code-block:: 

    sgutil program vivado -d <device_id>

This will load the default bitstream obtained with the `static` example present in ``examples_hw``. 
This static layer will thus be the same no matter where the bitstream is built and the shell layers can be swapped on the fly. 

The above command will also handle the hot-plug protocol which rescannes the interconnect, thus no additional warm reboots are necessary, 

The SGRT provides additional helper features that you can use, like validation and building scripts.
