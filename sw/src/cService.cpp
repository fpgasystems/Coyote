#include "cService.hpp"

namespace fpga {

cService* cService::cservice = nullptr;

// ======-------------------------------------------------------------------------------
// Ctor, dtor
// ======-------------------------------------------------------------------------------

/**
 * @brief Constructor
 * 
 * @param vfid
 */
cService::cService(string name, bool remote, int32_t vfid, csDev dev, void (*uisr)(int), bool priority, bool reorder) 
    : remote(remote), vfid(vfid), dev(dev), uisr(uisr), cSched(vfid, dev, priority, reorder)  {
    // ID
    service_id = ("coyote-daemon-vfid-" + std::to_string(vfid) + "-" + name).c_str();
    socket_name = ("/tmp/coyote-daemon-vfid-" + std::to_string(vfid) + "-" + name).c_str();
}

// ======-------------------------------------------------------------------------------
// Sig handler
// ======-------------------------------------------------------------------------------

void cService::sigHandler(int signum) {
    cservice->myHandler(signum);
}

void cService::myHandler(int signum) {
    if(signum == SIGTERM) {
        syslog(LOG_NOTICE, "SIGTERM received\n");//cService::getPid());
        unlink(socket_name.c_str());

        run_req = false;
        run_rsp = false;
        thread_req.join();
        thread_rsp.join();

        //kill(getpid(), SIGTERM);
        syslog(LOG_NOTICE, "Exiting");
        closelog();
        exit(EXIT_SUCCESS);
    } else {
        syslog(LOG_NOTICE, "Signal %d not handled", signum);
    }
}

// ======-------------------------------------------------------------------------------
// Init
// ======-------------------------------------------------------------------------------

/**
 * @brief Initialize the daemon service
 * 
 */
void cService::daemonInit() {
    // Fork
    DBG3("Forking...");
    pid = fork();
    if(pid < 0 ) 
        exit(EXIT_FAILURE);
    if(pid > 0 ) 
        exit(EXIT_SUCCESS);

    // Sid
    if(setsid() < 0) 
        exit(EXIT_FAILURE);

    // Signal handler
    signal(SIGTERM, cService::sigHandler);
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
    openlog(service_id.c_str(), LOG_NOWAIT | LOG_PID, LOG_USER);
    syslog(LOG_NOTICE, "Successfully started %s", service_id.c_str());

    // Close fd
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);
}

/**
 * @brief Initialize listening socket
 * 
 */
void cService::socketInit() {
    syslog(LOG_NOTICE, "Socket initialization");

    sockfd = -1;
    struct sockaddr_un server;
    socklen_t len;

    if((sockfd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
        syslog(LOG_ERR, "Error creating a server socket");
        exit(EXIT_FAILURE);
    }

    server.sun_family = AF_UNIX;
    strcpy(server.sun_path, socket_name.c_str());
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

/**
 * @brief Accept connections
 * 
 */
void cService::acceptConnectionLocal() {
    sockaddr_un client;
    socklen_t len = sizeof(client); 
    int connfd;
    char recv_buf[recvBuffSize];
    int n;
    pid_t rpid;
    int fid;

    if((connfd = accept(sockfd, (struct sockaddr *)&client, &len)) != -1) {
        syslog(LOG_NOTICE, "Connection accepted, connfd: %d", connfd);

        if(n = read(connfd, recv_buf, sizeof(pid_t)) == sizeof(pid_t)) {
            memcpy(&rpid, recv_buf, sizeof(pid_t));
            syslog(LOG_NOTICE, "Registered pid: %d", rpid);
        } else {
            syslog(LOG_ERR, "Registration failed, connfd: %d, received: %d", connfd, n);
        }

        if(n = read(connfd, recv_buf, sizeof(int)) == sizeof(int)) {
            memcpy(&fid, recv_buf, sizeof(int));
            syslog(LOG_NOTICE, "Function id: %d", fid);
        } else {
            syslog(LOG_ERR, "Registration failed, connfd: %d, received: %d", connfd, n);
        }

        functions[fid]->registerClientThread(connfd, vfid, rpid, dev, uisr);
    }

    nanosleep((const struct timespec[]){{0, sleepIntervalDaemon}}, NULL);
}

/**
 * @brief Main run service
 * 
 */
void cService::start() {
    // Init daemon
    daemonInit();

    // Run scheduler
    if(isReconfigurable()) runSched();

    // Init socket
    socketInit();
    
    // Init threads
    syslog(LOG_NOTICE, "Thread initialization");

    thread_req = std::thread(&cService::processRequests, this);
    thread_rsp = std::thread(&cService::processResponses, this);

    // Main
    while(1) {
        if(!remote)
            acceptConnectionLocal();
    }
}

// ======-------------------------------------------------------------------------------
// Threads
// ======-------------------------------------------------------------------------------

void cService::processRequests() {
    run_req = true;

    syslog(LOG_NOTICE, "Starting thread");

    while(run_req) {
        for (auto i = functions.begin(); i != functions.end(); i++) {
            i->second->requestRecv();
        }

        nanosleep((const struct timespec[]){{0, sleepIntervalRequests}}, NULL);
    }
}

void cService::processResponses() {
    run_rsp = true;
    
    while(run_rsp) {
        for (auto i = functions.begin(); i != functions.end(); i++) {
            i->second->responseSend();
        }

        nanosleep((const struct timespec[]){{0, sleepIntervalCompletion}}, NULL);
    }
}

// ======-------------------------------------------------------------------------------
// Functions
// ======-------------------------------------------------------------------------------
void cService::addFunction(int32_t fid, std::unique_ptr<bFunc> f) {
    if(functions.find(fid) == functions.end()) {
        functions.emplace(fid,std::move(f));
    }
}

}