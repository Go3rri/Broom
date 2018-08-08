//
//  utils.m
//  Broom
//
//  Created by Ben Sparkes on 08/08/2018.
//  Copyright © 2018 Ben Sparkes. All rights reserved.
//

#import <Foundation/Foundation.h>

#include <sys/sysctl.h>

#include "iokit.h"

// credits to tihmstar
void restart_device() {
    // open user client
    CFMutableDictionaryRef matching = IOServiceMatching("IOSurfaceRoot");
    io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, matching);
    io_connect_t connect = 0;
    IOServiceOpen(service, mach_task_self(), 0, &connect);
    
    // add notification port with same refcon multiple times
    mach_port_t port = 0;
    mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port);
    uint64_t references;
    uint64_t input[3] = {0};
    input[1] = 1234;  // keep refcon the same value
    while (1) {
        IOConnectCallAsyncStructMethod(connect, 17, port, &references, 1, input, sizeof(input), NULL, NULL);
    }
}

// credits to tihmstar
double uptime() {
    struct timeval boottime;
    size_t len = sizeof(boottime);
    int mib[2] = { CTL_KERN, KERN_BOOTTIME };
    if (sysctl(mib, 2, &boottime, &len, NULL, 0) < 0) {
        return -1.0;
    }
    
    time_t bsec = boottime.tv_sec, csec = time(NULL);
    
    return difftime(csec, bsec);
}

// credits to tihmstar
void suspend_all_threads() {
    thread_act_t other_thread, current_thread;
    unsigned int thread_count;
    thread_act_array_t thread_list;
    
    current_thread = mach_thread_self();
    int result = task_threads(mach_task_self(), &thread_list, &thread_count);
    if (result == -1) {
        exit(1);
    }
    if (!result && thread_count) {
        for (unsigned int i = 0; i < thread_count; ++i) {
            other_thread = thread_list[i];
            if (other_thread != current_thread) {
                int kr = thread_suspend(other_thread);
                if (kr != KERN_SUCCESS) {
                    mach_error("thread_suspend:", kr);
                    exit(1);
                }
            }
        }
    }
}

// credits to tihmstar
void resume_all_threads() {
    thread_act_t other_thread, current_thread;
    unsigned int thread_count;
    thread_act_array_t thread_list;
    
    current_thread = mach_thread_self();
    int result = task_threads(mach_task_self(), &thread_list, &thread_count);
    if (!result && thread_count) {
        for (unsigned int i = 0; i < thread_count; ++i) {
            other_thread = thread_list[i];
            if (other_thread != current_thread) {
                int kr = thread_resume(other_thread);
                if (kr != KERN_SUCCESS) {
                    mach_error("thread_suspend:", kr);
                }
            }
        }
    }
}

#include <sys/spawn.h>

// creds to stek29 on this one
int execprog(const char *prog, const char* args[]) {
    if (args == NULL) {
        args = (const char **)&(const char*[]){ prog, NULL };
    }
    
    const char *logfile = [NSString stringWithFormat:@"/tmp/%@-%lu",
                           [[NSMutableString stringWithUTF8String:prog] stringByReplacingOccurrencesOfString:@"/" withString:@"_"],
                           time(NULL)].UTF8String;
    
    NSString *prog_args = @"";
    for (const char **arg = args; *arg != NULL; ++arg) {
        prog_args = [prog_args stringByAppendingString:[NSString stringWithFormat:@"%s ", *arg]];
    }
    NSLog(@"[execprog] Spawning [ %@ ] to logfile [ %s ]", prog_args, logfile);
    
    int rv;
    posix_spawn_file_actions_t child_fd_actions;
    if ((rv = posix_spawn_file_actions_init (&child_fd_actions))) {
        perror ("posix_spawn_file_actions_init");
        return rv;
    }
    if ((rv = posix_spawn_file_actions_addopen (&child_fd_actions, STDOUT_FILENO, logfile,
                                                O_WRONLY | O_CREAT | O_TRUNC, 0666))) {
        perror ("posix_spawn_file_actions_addopen");
        return rv;
    }
    if ((rv = posix_spawn_file_actions_adddup2 (&child_fd_actions, STDOUT_FILENO, STDERR_FILENO))) {
        perror ("posix_spawn_file_actions_adddup2");
        return rv;
    }
    
    pid_t pd;
    if ((rv = posix_spawn(&pd, prog, &child_fd_actions, NULL, (char**)args, NULL))) {
        printf("posix_spawn error: %d (%s)\n", rv, strerror(rv));
        return rv;
    }
    
    NSLog(@"[execprog] Process spawned with pid %d", pd);
    
    int ret, status;
    do {
        ret = waitpid(pd, &status, 0);
        if (ret > 0) {
            NSLog(@"'%s' exited with %d (sig %d)\n", prog, WEXITSTATUS(status), WTERMSIG(status));
        } else if (errno != EINTR) {
            NSLog(@"waitpid error %d: %s\n", ret, strerror(errno));
        }
    } while (ret < 0 && errno == EINTR);
    
    char buf[65] = {0};
    int fd = open(logfile, O_RDONLY);
    if (fd == -1) {
        perror("open logfile");
        return 1;
    }
    
    NSLog(@"contents of %s:", logfile);
    NSLog(@"-------------------------");
    while (read(fd, buf, sizeof(buf) - 1) == sizeof(buf) - 1) {
        NSLog(@"%s", buf);
    }
    NSLog(@"-------------------------");
    
    close(fd);
    remove(logfile);
    return (int8_t)WEXITSTATUS(status);
}
