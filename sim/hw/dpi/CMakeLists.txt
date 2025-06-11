# List of c files to compile and link for the testbench
set(DPI_FILES
    file_io.c
)

set(WORKING_DIR "${CMAKE_BINARY_DIR}/sim")

# First, make sure the directory exists!
add_custom_target(sim_dpi_dir
    COMMAND ${CMAKE_COMMAND} -E make_directory ${WORKING_DIR}
)

# Then do the compilation

# Prefix each file with current source directory
list(TRANSFORM DPI_FILES PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")

# Convert to space-separated string
string(JOIN " " FILES_STRING ${DPI_FILES})

add_custom_target(sim_dpi_c   
    COMMAND ${XSC_BINARY} --compile ${FILES_STRING}
    COMMAND ${XSC_BINARY} --shared --output ${SIM_DPI_LIB_NAME}
    WORKING_DIRECTORY ${WORKING_DIR}
)
add_dependencies(sim_dpi_c sim_dpi_dir)