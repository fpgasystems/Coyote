#include <pty.h>
#include <stdio.h>
#include <unistd.h>
#include <cerrno>
#include <cstring>
#include <iostream>
#include <string>
#include <sys/wait.h>
#include <filesystem>

namespace fpga {

class VivadoRunner {
    const bool PRINT_LOGS;
    const std::string PROJ_NAME;
    const std::string SIM_DIR;

    int master;

    void waitTillReady() {
        const char *VIVADO = "Vivado% ";
        const int VIVADO_SIZE = 8;
        int match = 0;

        while (true) {
            char buf[1024];
            auto size = read(master, buf, 1024);
            buf[size] = '\0';
            if (PRINT_LOGS) {
                std::cout << buf;
            }
            
            if (size >= VIVADO_SIZE) {
                match = 0;
            }
            for (int i = match; i < VIVADO_SIZE; i++) {
                if (buf[size - (VIVADO_SIZE - i)] == VIVADO[match]) {
                    match++;
                } else {
                    match = 0;
                }
            }
            if (match == VIVADO_SIZE) {
                break;
            }
        }
    }

    void executeCommand(std::string command, bool do_wait = true) {
        command.append("\n");
        const char *test = command.c_str();
        write(master, test, command.size() + 1);
        if (do_wait) waitTillReady();
    }

public:
    VivadoRunner(const char *proj_name, const char *sim_dir, bool print_logs) : PRINT_LOGS(print_logs), PROJ_NAME(proj_name), SIM_DIR(sim_dir) {}

    ~VivadoRunner() {
        int status = 0;
        executeCommand("quit", false);
        wait(&status);
        std::cout << "Vivado exited with code " << status << "..." << std::endl;
        close(master);
    }

    int initialize() {
        if (system("which vivado > /dev/null 2>&1")) {
            std::cout << "Error: Executable 'vivado' is not available" << std::endl;
            return -1;
        }

        pid_t pid = forkpty(&master, nullptr, nullptr, nullptr);

        if(0 > pid) {
            std::cout << "Error: " << strerror(errno) << std::endl;
            return -1;
        }

        if (pid == 0) { // If this is the child process
            const char *argv[] = {"vivado", "-mode", "tcl", NULL};
            execvp(argv[0], const_cast<char *const *>(argv)); // Replace it with execution of Vivado
        }

        return 0;
    }

    void openProject() {
        waitTillReady();
        std::filesystem::path proj_path(SIM_DIR);
        proj_path /= PROJ_NAME + ".xpr";
        executeCommand("open_project " + proj_path.string());
    }

    void compileProject() {
        executeCommand("update_compile_order -fileset sources_1");
        executeCommand("check_syntax -fileset sources_1");
        executeCommand("set_property -name {xsim.simulate.runtime} -value {} -objects [get_filesets sim_1]");
        executeCommand("launch_simulation -simset [get_filesets sim_1] -step compile -noclean_dir -mode behavioral");
        executeCommand("launch_simulation -simset [get_filesets sim_1] -step elaborate -noclean_dir -mode behavioral");
        if (PRINT_LOGS) {
            executeCommand("launch_simulation -simset [get_filesets sim_1] -step simulate -noclean_dir -mode behavioral");
        } else {
            executeCommand("launch_simulation -simset [get_filesets sim_1] -step simulate -noclean_dir -mode behavioral > /dev/null");
        }
        
    }

    void runSimulation(std::string simulation_time = "-all") { // TODO
        std::filesystem::path vcd_path(SIM_DIR);
        vcd_path /= "sim_dump.vcd";
        executeCommand("restart");
        executeCommand("set_value -radix bin /tb_user/VAR_DUMP_ENABLED 0");
        executeCommand("open_vcd " + vcd_path.string());
        executeCommand("log_vcd /tb_user/inst_DUT/*");
        executeCommand("run " + simulation_time);
        executeCommand("close_vcd");
        executeCommand("close_sim");
    }
};

}
