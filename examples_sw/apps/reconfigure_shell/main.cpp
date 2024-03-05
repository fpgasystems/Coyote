#include <iostream>
#include <string>
#include <malloc.h>
#include <time.h> 
#include <sys/time.h>  
#include <chrono>
#include <fstream>
#include <fcntl.h>
#include <unistd.h>
#include <iomanip>
#ifdef EN_AVX
#include <x86intrin.h>
#endif
#include <signal.h> 
#include <boost/program_options.hpp>


#include "cRnfg.hpp"

using namespace std;
using namespace std::chrono;
using namespace fpga;

/**
 * @brief Loopback example
 * 
 */
int main(int argc, char *argv[])  
{
    // ---------------------------------------------------------------
    // Args 
    // ---------------------------------------------------------------

    boost::program_options::options_description programDescription("Options:");
    programDescription.add_options()
        ("bpath,b", boost::program_options::value<string>(), "Bitstream path (.bin)");
    
    boost::program_options::variables_map commandLineArgs;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, programDescription), commandLineArgs);
    boost::program_options::notify(commandLineArgs);

    try {
        string b_path;

        if(commandLineArgs.count("bpath") == 0) 
            throw std::runtime_error("ERR:   Bitstream path not provided!\n");
        else
            b_path = commandLineArgs["bpath"].as<string>();
    

        // Reconfigure
        cRnfg crnfg;

        std::cout << "Reconfiguring the shell ... " << std::endl;
        std::cout << "Shell path: " << b_path << std::endl;
        
        auto begin_time = std::chrono::high_resolution_clock::now();
        
        crnfg.shellReconfigure(b_path);

        auto end_time = std::chrono::high_resolution_clock::now();
        double time = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - begin_time).count();
        
        std::cout << "Shell loaded, elapsed time: " << time << " ms" << std::endl;

    }
    catch( const std::exception & ex ) {
        std::cerr << std::endl << ex.what() << std::endl;
    }
    
    return EXIT_SUCCESS;
}
