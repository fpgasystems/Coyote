#include "cService.hpp"

namespace fpga {

cService* cService::cservice = nullptr;

// ======-------------------------------------------------------------------------------
// Ctor, dtor
// ======-------------------------------------------------------------------------------

/**
 * @brief Constructor for the cService object, protected to keep singleton-status 
 * 
 * @param vfid
 */
cService::cService(string name, bool remote, int32_t vfid, uint32_t dev, void (*uisr)(int), uint16_t port, bool priority, bool reorder) 
    : remote(remote), vfid(vfid), dev(dev), uisr(uisr), port(port), cSched(vfid, dev, priority, reorder)  {
    // ID - create both a service-ID and a socket-name for communication 
    service_id = ("coyote-daemon-vfid-" + std::to_string(vfid) + "-" + name).c_str();
    socket_name = ("/tmp/coyote-daemon-vfid-" + std::to_string(vfid) + "-" + name).c_str();

    # ifdef VERBOSE
        std::cout << "cService: Instantiated a cService with the service-ID " << service_id << " and the socket-name " << socket_name << std::endl; 
    # endif
}

// ======-------------------------------------------------------------------------------
// Sig handler
// ======-------------------------------------------------------------------------------

// Set the signum-handler based on the given signum-number (basically can only handle SIGTERM)
void cService::sigHandler(int signum) {
    cservice->myHandler(signum);
}

// Can handle signum-calls (only SIGTERM supported as of now)
void cService::myHandler(int signum) {
    # ifdef VERBOSE
        std::cout << "cService: Called a signal handler with the signal " << signum << std::endl; 
    # endif

    // Handle termination signals 
    if(signum == SIGTERM) {
        # ifdef VERBOSE
            std::cout << "cService: Received a SIGTERM." << signum << std::endl; 
        # endif

        syslog(LOG_NOTICE, "SIGTERM received\n");//cService::getPid());

        // Unlink the socket 
        unlink(socket_name.c_str());

        //kill(getpid(), SIGTERM);
        syslog(LOG_NOTICE, "Exiting");
        closelog();

        // Exit the daemon with success-code
        exit(EXIT_SUCCESS);
    } else {
        # ifdef VERBOSE
            std::cout << "cService: Received a signal that can't be handled here." << signum << std::endl; 
        # endif
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
    # ifdef VERBOSE
        std::cout << "cService: Init a daemon for background handling." << std::endl; 
    # endif

    // Fork: Create a new child-process, check success by the created PID 
    DBG3("Forking...");
    pid = fork();
    if(pid < 0 ) 
        exit(EXIT_FAILURE);
    if(pid > 0 ) 
        exit(EXIT_SUCCESS);

    // Sid - create a new session, of which the process is now the session-leader
    if(setsid() < 0) 
        exit(EXIT_FAILURE);

    // Signal handler
    signal(SIGTERM, cService::sigHandler); // set up the custom handler for a SIGTERM signal 
    signal(SIGCHLD, SIG_IGN); // ignore the SIGCHLD command to prevent the creation of zombie processes 
    signal(SIGHUP, SIG_IGN); // ignore the SIGHUP command so that the process keeps running even if the terminal is killed

    // Fork again. The new process is not a session leader and has no controlling terminal 
    pid = fork();
    if(pid < 0 ) 
        exit(EXIT_FAILURE);
    if(pid > 0 ) 
        exit(EXIT_SUCCESS);

    // Permissions - the daemon can create files with any required permission 
    umask(0);

    // Cd: Change directory to the working directory to avoid locking any directory 
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
    # ifdef VERBOSE
        std::cout << "cService: Called socketInit() to initialize sockets for communication." << std::endl; 
    # endif

    syslog(LOG_NOTICE, "Socket initialization");

    sockfd = -1;

    // In case remote is set to true, initialize a network socket for network communication 
    if(remote) {
        # ifdef VERBOSE
            std::cout << "cService: Open a remote socket for network-communication." << std::endl; 
        # endif

        struct sockaddr_in server;

        // Create the socket and check if it's successful
        sockfd = ::socket(AF_INET, SOCK_STREAM, 0);
        if (sockfd == -1) 
            throw std::runtime_error("Could not create a socket");

        // Select network and adress for connection 
        server.sin_family = AF_INET;
        server.sin_addr.s_addr = INADDR_ANY;
        server.sin_port = htons(port);

        // Try to connect the socket 
        if (::bind(sockfd, (struct sockaddr*)&server, sizeof(server)) < 0)
            throw std::runtime_error("Could not bind a socket");

        if (sockfd < 0 )
            throw std::runtime_error("Could not listen to a port: " + to_string(port));
    } else {
        # ifdef VERBOSE
            std::cout << "cService: Open a local socket for Inter-Process-communication." << std::endl; 
        # endif

        // Create a local socket for Inter-Process Communication 
        struct sockaddr_un server;
        socklen_t len;

        // Check for successful creation of the IPC-socket 
        if((sockfd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
            syslog(LOG_ERR, "Error creating a server socket");
            exit(EXIT_FAILURE);
        }

        // Try to bind the socket to remote side for network-based exchange 
        server.sun_family = AF_UNIX;
        strcpy(server.sun_path, socket_name.c_str());
        unlink(server.sun_path);
        len = strlen(server.sun_path) + sizeof(server.sun_family);
        
        if(bind(sockfd, (struct sockaddr *)&server, len) == -1) {
            syslog(LOG_ERR, "Error bind()");
            exit(EXIT_FAILURE);
        }
    }

    // Try to listen to the network socket 
    if(listen(sockfd, maxNumClients) == -1) {
        syslog(LOG_ERR, "Error listen()");
        exit(EXIT_FAILURE);
    }
}

/**
 * @brief Accept connections
 * 
 */

// Accept a local connection (I guess that's a IPC - inter-process communication)
void cService::acceptConnectionLocal() {
    sockaddr_un client;
    socklen_t len = sizeof(client); 
    int connfd;
    char recv_buf[recvBuffSize];
    int n;
    pid_t rpid;
    int fid;

    # ifdef VERBOSE
        std::cout << "cService: Accept an incoming local connection for IPC." << std::endl; 
    # endif

    // Try to accept an incoming connection 
    if((connfd = accept(sockfd, (struct sockaddr *)&client, &len)) != -1) {
        syslog(LOG_NOTICE, "Connection accepted local, connfd: %d", connfd);

        // Read rpid (registered process ID)
        if((n = read(connfd, recv_buf, sizeof(pid_t))) == sizeof(pid_t)) {
            memcpy(&rpid, recv_buf, sizeof(pid_t));
            syslog(LOG_NOTICE, "Registered pid: %d", rpid);
        } else {
            ::close(connfd);
            syslog(LOG_ERR, "Registration failed, connfd: %d, received: %d", connfd, n);
            exit(EXIT_FAILURE);
        }

        # ifdef VERBOSE
            std::cout << " - cService: Read incoming rpid " << rpid << std::endl; 
        # endif

        // Read fid (function ID)
        if((n = read(connfd, recv_buf, sizeof(int))) == sizeof(int)) {
            memcpy(&fid, recv_buf, sizeof(int));
            syslog(LOG_NOTICE, "Function id: %d", fid);
        } else {
            ::close(connfd);
            syslog(LOG_ERR, "Registration failed, connfd: %d, received: %d", connfd, n);
            exit(EXIT_FAILURE);
        }

        # ifdef VERBOSE
            std::cout << " - cService: Read incoming fid " << fid << std::endl; 
        # endif

        // Create a new client thread for the function in the function-struct 
        functions[fid]->registerClientThread(connfd, vfid, rpid, dev, this, uisr);

        # ifdef VERBOSE
            std::cout << " - cService: Register a new client thread in the functions-struct." << std::endl; 
        # endif
    }

    std::this_thread::sleep_for(std::chrono::nanoseconds(sleepIntervalDaemon));
}

// Accept a remote connection (that's probably for RDMA-usecase to exchange the QP)
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

    # ifdef VERBOSE
        std::cout << "cService: Accept an incoming remote connection for network communication." << std::endl; 
    # endif

    // Try to accept the incoming connection 
    if((connfd = ::accept(sockfd, NULL, 0)) != -1) {
        syslog(LOG_NOTICE, "Connection accepted remote, connfd: %d", connfd);

        // Read fid
        if((n = ::read(connfd, recv_buf, sizeof(int32_t))) == sizeof(int32_t)) {
            memcpy(&fid, recv_buf, sizeof(int32_t));
            syslog(LOG_NOTICE, "Function id: %d", fid);
        } else {
            ::close(connfd);
            syslog(LOG_ERR, "Registration failed, connfd: %d, received: %d", connfd, n);
            exit(EXIT_FAILURE);
        }

        # ifdef VERBOSE
            std::cout << " - cService: Read function ID " << fid << std::endl; 
        # endif

        // Read remote queue pair
        if ((n = ::read(connfd, recv_buf, sizeof(ibvQ))) == sizeof(ibvQ)) {
            memcpy(&r_qp, recv_buf, sizeof(ibvQ));
            syslog(LOG_NOTICE, "Read remote queue");
        } else {
            ::close(connfd);
            syslog(LOG_ERR, "Could not read a remote queue %d", n);
            exit(EXIT_FAILURE);
        }

        # ifdef VERBOSE
            std::cout << " - cService: Read remote QP" << std::endl; 
        # endif
        
        // Get a cThread from the function registered in the func-struct
        cthread = functions[fid]->registerClientThread(connfd, vfid, getpid(), dev, this, uisr);

        # ifdef VERBOSE
            std::cout << " - cService: Register a client thread in the functions-struct." << std::endl; 
        # endif

        cthread->getQpair()->remote = r_qp; // store the received remote QP 
        cthread->getMem({CoyoteAlloc::HPF, r_qp.size, true}); // Allocate memory for receiving data for RDMA 

        # ifdef VERBOSE
            std::cout << " - cService: Send the local QP to the remote side." << std::endl; 
        # endif

        // Send local queue pair to the remote side 
        if (::write(connfd, &cthread->getQpair()->local, sizeof(ibvQ)) != sizeof(ibvQ))  {
            ::close(connfd);
            syslog(LOG_ERR, "Could not write a local queue");
            exit(EXIT_FAILURE);
        }

        # ifdef VERBOSE
            std::cout << " - cService: Write QPs into configuration space and perform an ARP-lookup." << std::endl; 
        # endif

        // Write context and connection to the config-space of Coyote 
        cthread->writeQpContext(port);
        // ARP lookup
        cthread->doArpLookup(cthread->getQpair()->remote.ip_addr);

    } else {
        syslog(LOG_ERR, "Accept failed");
    }

    std::this_thread::sleep_for(std::chrono::nanoseconds(sleepIntervalDaemon));
}

/**
 * @brief Main run service for the daemon 
 * 
 */
void cService::start() {
    # ifdef VERBOSE
        std::cout << "cService: Called start() to kick of a scheduler-thread." << std::endl; 
    # endif

    // Init daemon
    daemonInit();

    // Run scheduler - creates a scheduler-thread which waits for incoming requests 
    if(isReconfigurable()) runSched();

    // Init socket
    socketInit();
    
    // Init threads
    syslog(LOG_NOTICE, "Thread initialization");

    // Iterate over entries in the func-struct and start all of these functions 
    // Going back to the definition of func-start(): Starting a clean-up-thread? 
    for (auto it = functions.begin(); it != functions.end(); it++) {
        it->second->start();
    }

    // Main - exchange of QP or local connection, depending on remote-setting 
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

// Place an additional function in the func-struct if the function ID doesn't already exist
void cService::addFunction(int32_t fid, std::unique_ptr<bFunc> f) {
    # ifdef VERBOSE
        std::cout << "cService: Called addFunction() to add a function in the functions-struct." << std::endl; 
    # endif
    if(functions.find(fid) == functions.end()) {
        functions.emplace(fid,std::move(f));
    }
}

}