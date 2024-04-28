.. cyt_docs documentation master file, created by
   sphinx-quickstart on Mon Apr 15 23:25:28 2024.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

Welcome to Coyote's documentation!
====================================

**An OS for FPGAs**
------------------------------------

.. figure:: ../../img/cyt_ov_light.png

**Coyote** is a framework that offers operating system abstractions and a variety of shared networking (*RDMA*, *TCP/IP*), memory (*DRAM*, *HBM*)
and accelerator (*GPU*) services for modern heterogeneous platforms with *FPGAs*, targeting data centers and cloud environments.

.. toctree::
   :maxdepth: 2
   :caption: Quick Start

   quickstart/index

.. toctree::
   :maxdepth: 2
   :caption: Deploying Coyote in HACC

   hacc/index

.. toctree::
   :maxdepth: 2
   :caption: System Architecture

   system/static/index
   system/dynamic/index
   system/application/index
   system/vms/index

.. toctree::
   :maxdepth: 2
   :caption: Developer Guide

   developer/index

.. toctree::
   :maxdepth: 2
   :caption: Additional Info

   addinfo/index

Indices and tables
==================

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`
