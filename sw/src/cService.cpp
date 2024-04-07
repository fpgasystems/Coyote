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
cService::cService(string name, bool remote, int32_t vfid, csDev dev, void (*uisr)(int), uint16_t port, bool priority, bool reorder) 
    : remote(remote), vfid(vfid), dev(dev), uisr(uisr), port(port), cSched(vfid, dev, priority, reorder)  {
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

    if(remote) {
        struct sockaddr_in server;

        sockfd = ::socket(AF_INET, SOCK_STREAM, 0);
        if (sockfd == -1) 
            throw std::runtime_error("Could not create a socket");

        server.sin_family = AF_INET;
        server.sin_addr.s_addr = INADDR_ANY;
        server.sin_port = htons(port);

        if (::bind(sockfd, (struct sockaddr*)&server, sizeof(server)) < 0)
            throw std::runtime_error("Could not bind a socket");

        if (sockfd < 0 )
            throw std::runtime_error("Could not listen to a port: " + to_string(port));
    } else {
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
        syslog(LOG_NOTICE, "Connection accepted local, connfd: %d", connfd);

        // Read rpid
        if(n = read(connfd, recv_buf, sizeof(pid_t)) == sizeof(pid_t)) {
            memcpy(&rpid, recv_buf, sizeof(pid_t));
            syslog(LOG_NOTICE, "Registered pid: %d", rpid);
        } else {
            ::close(connfd);
            syslog(LOG_ERR, "Registration failed, connfd: %d, received: %d", connfd, n);
            exit(EXIT_FAILURE);
        }

        // Read fid
        if(n = read(connfd, recv_buf, sizeof(int)) == sizeof(int)) {
            memcpy(&fid, recv_buf, sizeof(int));
            syslog(LOG_NOTICE, "Function id: %d", fid);
        } else {
            ::close(connfd);
            syslog(LOG_ERR, "Registration failed, connfd: %d, received: %d", connfd, n);
            exit(EXIT_FAILURE);
        }

        functions[fid]->registerClientThread(connfd, vfid, rpid, dev, this, uisr);
    }

    std::this_thread::sleep_for(std::chrono::nanoseconds(sleepIntervalDaemon));
}

void cService::acceptConnectionRemote() {
    uint32_t recv_qpid;
    uint8_t ack;
    uint32_t n;
    int connfd;
    struct sockaddr_in server;
    char recv_buf[recvBuffSize];
    memset(recv_buf, 0, recvBuffSize);
    int fid;
    ibvQ r_qp;
    bThread *cthread;

    if((connfd = ::accept(sockfd, NULL, 0)) != -1) {
        syslog(LOG_NOTICE, "Connection accepted remote, connfd: %d", connfd);

        // Read fid
        if(n = ::read(connfd, recv_buf, sizeof(int32_t)) == sizeof(int32_t)) {
            memcpy(&fid, recv_buf, sizeof(int32_t));
            syslog(LOG_NOTICE, "Function id: %d", fid);
        } else {
            ::close(connfd);
            syslog(LOG_ERR, "Registration failed, connfd: %d, received: %d", connfd, n);
            exit(EXIT_FAILURE);
        }

        // Read remote queue pair
        if (n = ::read(connfd, recv_buf, sizeof(ibvQ)) == sizeof(ibvQ)) {
            memcpy(&r_qp, recv_buf, sizeof(ibvQ));
            syslog(LOG_NOTICE, "Read remote queue");
        } else {
            ::close(connfd);
            syslog(LOG_ERR, "Could not read a remote queue %d", n);
            exit(EXIT_FAILURE);
        }
        
        cthread = functions[fid]->registerClientThread(connfd, vfid, getpid(), dev, this, uisr);
        cthread->getQpair()->remote = r_qp;
        cthread->getMem({CoyoteAlloc::HPF, r_qp.size, true});

        // Send local queue pair
        if (::write(connfd, &cthread->getQpair()->local, sizeof(ibvQ)) != sizeof(ibvQ))  {
            ::close(connfd);
            syslog(LOG_ERR, "Could not write a local queue");
            exit(EXIT_FAILURE);
        }

        // Write context and connection
        cthread->writeQpContext(port);
        // ARP lookup
        cthread->doArpLookup(cthread->getQpair()->remote.ip_addr);

    } else {
        syslog(LOG_ERR, "Accept failed");
    }

    std::this_thread::sleep_for(std::chrono::nanoseconds(sleepIntervalDaemon));
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

    for (auto it = functions.begin(); it != functions.end(); it++) {
        it->second->start();
    }

    // Main
    while(1) {
        if(!remote)
            acceptConnectionLocal();
        else
            acceptConnectionRemote();
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