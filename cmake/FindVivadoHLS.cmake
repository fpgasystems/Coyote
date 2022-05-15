# Author:  Johannes de Fine Licht (johannes.definelicht@inf.ethz.ch)
# Created: October 2016
#
# To specify the path to the Vivado HLS installation, provide:
#   -DVIVADO_HLS_ROOT_DIR=<installation directory>
# If successful, this script defines:
#   VIVADO_HLS_FOUND
#   VIVADO_HLS_BINARY
#   VIVADO_HLS_INCLUDE_DIRS

cmake_minimum_required(VERSION 3.0)

find_path(VIVADO_HLS_PATH
  NAMES vivado_hls vitis_hls
  PATHS ${VIVADO_HLS_ROOT_DIR} ENV XILINX_VIVADO_HLS ENV XILINX_HLS
  PATH_SUFFIXES bin
)

if(NOT EXISTS ${VIVADO_HLS_PATH})

  message(WARNING "Vivado/Vitis HLS not found.")

else()

  get_filename_component(VIVADO_HLS_ROOT_DIR ${VIVADO_HLS_PATH} DIRECTORY)

  set(VIVADO_HLS_FOUND TRUE)
  set(VIVADO_HLS_INCLUDE_DIRS ${VIVADO_HLS_ROOT_DIR}/include/)
  if (EXISTS ${VIVADO_HLS_ROOT_DIR}/bin/vivado_hls)
    set(VIVADO_HLS_BINARY ${VIVADO_HLS_ROOT_DIR}/bin/vivado_hls)
    set(VITIS_HLS 0)
  else()
    set(VIVADO_HLS_BINARY ${VIVADO_HLS_ROOT_DIR}/bin/vitis_hls)
    set(VITIS_HLS 1)
  endif()
  message(STATUS "Found Vivado/Vitis HLS at ${VIVADO_HLS_ROOT_DIR}.")

endif()
