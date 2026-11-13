/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#ifndef _COYOTE_BINARY_RUNNER_HPP_
#define _COYOTE_BINARY_RUNNER_HPP_

#include <fcntl.h>
#include <unistd.h>
#include <sys/wait.h>
#include <cerrno>
#include <cstring>
#include <filesystem>
#include <string>

#include <coyote/Common.hpp>

namespace coyote {

/**
 * Runs a prebuilt simulation binary, e.g. the Verilator build of tb_user from sim/vl/build.sh,
 * in place of Vivado. The binary writes its stdout and stderr to <build_dir>/sim/coyote_vl.log.
 * cThread selects this runner when the COYOTE_SIM_BIN environment variable is set.
 */
class BinaryRunner {
    pid_t pid = -1;

public:
    /**
     * Starts the binary. Returns 0 on success, -1 if the binary is not executable or fork failed.
     */
    int start(const std::string &binary, const std::filesystem::path &sim_dir) {
        if (access(binary.c_str(), X_OK) != 0) {
            ERROR("Simulation binary '" << binary << "' is not executable: " << strerror(errno))
            return -1;
        }
        auto log_path = sim_dir / "coyote_vl.log";

        pid = fork();
        if (pid < 0) {
            ERROR(strerror(errno))
            return -1;
        }

        if (pid == 0) { // Child: redirect output to the log, exec the binary
            int log_fd = open(log_path.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (log_fd >= 0) {
                dup2(log_fd, STDOUT_FILENO);
                dup2(log_fd, STDERR_FILENO);
                close(log_fd);
            }
            execl(binary.c_str(), binary.c_str(), (char *) NULL);
            perror("exec of the simulation binary failed");
            _exit(127);
        }

        DEBUG("Started simulation binary " << binary << " (pid " << pid << "), output in " << log_path)
        return 0;
    }

    /**
     * Waits until the binary exits. Returns 0 when it exited with code 0, -1 otherwise.
     */
    int wait() {
        int status = 0;
        if (waitpid(pid, &status, 0) < 0) {
            ERROR(strerror(errno))
            return -1;
        }
        pid = -1;

        if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
            DEBUG("Simulation binary exited with code 0")
            return 0;
        }
        if (WIFEXITED(status)) {
            ERROR("Simulation binary exited with code " << WEXITSTATUS(status) << ", see coyote_vl.log")
        } else if (WIFSIGNALED(status)) {
            ERROR("Simulation binary was killed by signal " << WTERMSIG(status))
        }
        return -1;
    }
};

}

#endif
