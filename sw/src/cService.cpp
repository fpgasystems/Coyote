#include "cService.hpp"

namespace fpga {

/**
 * @brief Constructor
 * 
 * @param vfid
 */
void cService::cService(int32_t vfid) 
{
    // ID
    this->vfid = vfid;
    service_id = "coyote-daemon-vfid-" + vfid;
}

/**
 * @brief Signal handler 
 * 
 * @param signum : Kill signal
 */
static void sig_handler(int signum)
{   
    if(signum == SIGTERM) {
        syslog(LOG_NOTICE, "SIGTERM sent to %d\n", (int)pid);
        unlink(socketName);

        delete thread_req;
        //delete thread_rsp;
        //delete csched;

        kill(pid, SIGTERM);
        syslog(LOG_NOTICE, "Exiting");
        closelog();
        exit(EXIT_SUCCESS);
    } else {
        syslog(LOG_NOTICE, "Signal %d not handled", signum);
    }
}

/**
 * @brief Initialize the daemon service
 * 
 */
void cService::daemon_init()
{
    // Fork
    pid = fork();
    if(pid < 0 ) 
        exit(EXIT_FAILURE);
    if(pid > 0 ) 
        exit(EXIT_SUCCESS);

    // Sid
    if(setsid() < 0) 
        exit(EXIT_FAILURE);

    // Signal handler
    signal(SIGTERM, sig_handler);
    signal(SIGCHLD, SIG_IGN);
    signal(SIGHUP, SIG_IGN);

    // Fork
    pid = fork();
    if(pid < 0 ) 
        exit(EXIT_FAILURE);
    if(pid > 0 ) 
        exit(EXIT_SUCCESS);

    // Permissions
    umask(0);

    // Cd
    if((chdir("/")) < 0) {
        exit(EXIT_FAILURE);
    }

    // Syslog
    openlog(service_id, LOG_NOWAIT | LOG_PID, LOG_USER);
    syslog(LOG_NOTICE, "Successfully started %s", service_id);

    // Close fd
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);
}

/**
 * @brief Initialize listening socket
 * 
 */
void cService::socket_init() 
{
    syslog(LOG_NOTICE, "Socket initialization");

    sockfd = -1;
    struct sockaddr_un server;
    socklen_t len;

    if((sockfd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
        syslog(LOG_ERR, "Error creating a server socket");
        exit(EXIT_FAILURE);
    }

    server.sun_family = AF_UNIX;
    strcpy(server.sun_path, "/tmp/" + service_id);
    unlink(server.sun_path);
    len = strlen(server.sun_path) + sizeof(server.sun_family);
    
    if(bind(sockfd, (struct sockaddr *)&server, len) == -1) {
        syslog(LOG_ERR, "Error bind()");
        exit(EXIT_FAILURE);
    }

    if(listen(sockfd, maxNumClients) == -1) {
        syslog(LOG_ERR, "Error listen()");
        exit(EXIT_FAILURE);
    }
}

void cService::threads_init(void (*f_req)(), void (*f_rsp)()) 
{
    syslog(LOG_NOTICE, "Thread initialization");

    thread_req = new threadType(&f_req);
    thread_rsp = new threadType(&f_rsp);
}

}