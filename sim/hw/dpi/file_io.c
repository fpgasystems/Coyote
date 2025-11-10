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

#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <poll.h>

/**
 * Opens the file at the provided path for non-blocking reads.
 * Returns an integer file descriptor, or -1 if the file
 * could not be opened.
 */
int open_pipe_for_non_blocking_reads(const char* path)
{
    // Open the file (the open call itself is also non-blocking)
    int fd = open(path, O_RDONLY | O_NONBLOCK);
    if (fd == -1) {
        perror("Error opening file");
        return -1;
    }

    // Wait for the file to have some input
    // Otherwise, the next read will result in a EOF immediately
    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = POLLIN;

    // Blocking call!
    int result = poll(&pfd, 1, -1);
    if (result > 0) {
        return fd;
    } else {
        perror("Polling till file is ready failed");
        return -1;
    }
}

/**
 * Tries to read one byte from the given file descriptor.
 * The descriptor should be created using 'open_pipe_for_non_blocking_reads'.
 * @retval The value that was read when reading was successful
 * @retval -1 if the EOF has been reached
 * @retval -2 if the read would have caused the file to block
 * @retval -3 if a unknown error occurred
 */ 
short int try_read_byte_from_file(int fd) {

    // Try to perform the read
    unsigned char result;
    ssize_t bytes_read = read(fd, &result, 1);
    
    // Check the return values
    if (bytes_read > 0) {
        // Success
        return result;
    } else if (bytes_read == 0) {
        // EOF
        return -1;
    } else if (bytes_read == -1){
        if (errno == EAGAIN) {
            // File would block
            return -2;
        } else {
            // Unexpected error
            return -3;
        }
    }
}

/**
 * Closes the file that was opened using
 * 'open_pipe_for_non_blocking_reads'
 */
void close_file(int fd) {
    int success = close(fd);
    if (success != 0) {
        perror("Error closing file");
    }
}