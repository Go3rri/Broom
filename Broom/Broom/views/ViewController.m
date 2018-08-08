//
//  ViewController.m
//  Broom
//
//  Created by Ben Sparkes on 08/08/2018.
//  Copyright © 2018 Ben Sparkes. All rights reserved.
//

#import "ViewController.h"

#include "amfi.h"
#include "kernel.h"
#include "offsetfinder.h"
#include "patchfinder64.h"
#include "root-rw.h"
#include "untar.h"
#include "utils.h"
#include "v0rtex.h"

#include <dlfcn.h>
#include <sys/stat.h>

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UIButton *goButton;
@property (weak, nonatomic) IBOutlet UILabel *versionLabel;
@end

@implementation ViewController

NSString *Version = @"Broom: v1.0.0 - by PsychoTea, w/ thanks to saurik";
BOOL allowedToRun = TRUE;

offsets_t offsets;

task_t   kernel_task;
uint64_t kernel_base;
uint64_t kernel_slide;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.versionLabel setText:Version];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        int waitTime;
        while ((waitTime = 90 - uptime()) > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.goButton setTitle:[NSString stringWithFormat:@"wait: %ds", waitTime] forState:UIControlStateNormal];
            });
            allowedToRun = FALSE;
            sleep(1);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.goButton setTitle:@"go" forState:UIControlStateNormal];
        });
        allowedToRun = TRUE;
    });
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)goButtonPressed:(UIButton *)button {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [self makeShitHappen];
    });
}

- (void)makeShitHappen {
    int ret;
    kern_return_t kret;
    
    if (allowedToRun == FALSE) return;
    
    allowedToRun = FALSE;
    [self.goButton setAlpha:0.7];
    
    [self updateStatus:@"running..."];
    
    // grab offsets via liboffsetfinder64
    // this is retarded
    offsets_t *offs = get_offsets();
    offsets = *offs;
    
    [self updateStatus:@"grabbed offsets"];
    
    // suspend app
    suspend_all_threads();
    
    // run v0rtex
    kret = v0rtex(&offsets, &v0rtex_callback, NULL);
    
    // resume app
    resume_all_threads();
    
    if (kret != KERN_SUCCESS) {
        [self updateStatus:@"v0rtex failed, rebooting..."];
        sleep(3);
        restart_device();
        return;
    }
    
    [self updateStatus:@"v0rtex success!"];
    
    // initialize patchfinder64 & amfi stuff
    init_patchfinder(NULL, kernel_base);
    init_amfi();
    
    // initialize kernel.m stuff
    uint64_t kernel_task_addr = rk64(offs->kernel_task + kernel_slide);
    uint64_t kern_proc = rk64(kernel_task_addr + offs->task_bsd_info);
    setup_kernel_tools(kernel_task, kern_proc);
    
    [self updateStatus:@"initialized patchfinders, etc"];
    
    // remount '/' as r/w
    NSOperatingSystemVersion osVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    int pre103 = osVersion.minorVersion < 3 ? 1 : 0;
    ret = mount_root(kernel_slide, offs->root_vnode, pre103);
    
    if (ret != 0) {
        [self updateStatus:@"failed to remount disk0s1s1: %d", ret];
        return;
    }
    
    fclose(fopen("/.broom_test_file", "w"));
    if (access("/.broom_test_file", F_OK) != 0) {
        [self updateStatus:@"failed to remount disk0s1s1"];
        return;
    }
    unlink("/.broom_test_file");
    
    execprog("/sbin/mount", NULL);
    
    [self updateStatus:@"remounted successfully"];
    
    ret = chdir("/Applications");
    if (ret != 0) {
        [self updateStatus:@"failed to change dir to /Applications"];
        return;
    }
    
    // TODO: sanity checks
    const char *eraser_tar_path = bundled_file("eraser.tar");
    if (strlen(eraser_tar_path) < 5) {
        [self updateStatus:@"failed to get eraser.tar file"];
        return;
    }
    
    FILE *fd = fopen(eraser_tar_path, "r");
    if (fd == NULL) {
        [self updateStatus:@"failed to open eraser.tar file"];
        return;
    }
    
    // Extrct tar & close the handle
    untar(fd, "/Applications");
    fclose(fd);
    
#define ERASER_MAIN "/Applications/Eraser.app/Eraser"
#define ERASER_LIB  "/Applications/Eraser.app/Eraser.dylib"
    
    // give +s bit & root:wheel to Eraser.app/Eraser
    inject_trust(ERASER_MAIN);
    inject_trust(ERASER_LIB);
    
    chmod(ERASER_MAIN, 6755);
    chmod(ERASER_LIB, 0755);
    
    chown(ERASER_MAIN, 0, 0);
    chown(ERASER_LIB, 0, 0);
    
    // Eraser fix
    mkdir("/var/stash", 0755);
    
    [self updateStatus:@"done!"];
    
    // TODO: automatically launch app?
    // run uicache
    
    // Credit to @insidegui on GitHub
    
    // I'm using dlopen to avoid having to link directly to SpringBoardServices
    void *spbsHandle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_GLOBAL);
    
    if (!spbsHandle) {
        printf("ERROR: Failed to get SpringBoardServices handle:\n%s\n", dlerror());
        return;
    }
    
    CFStringRef identifier = CFStringCreateWithCString(kCFAllocatorDefault, "com.saurik.Eraser", kCFStringEncodingUTF8);
    if (!identifier) {
        printf("ERROR: Unable to parse bundle identifier\n");
        return;
    }
    
    int(*SBSLaunchApplicationWithIdentifier)(CFStringRef identifier, bool flag) = dlsym(spbsHandle, "SBSLaunchApplicationWithIdentifier");
    
    int result = SBSLaunchApplicationWithIdentifier(identifier, FALSE);
    
    dlclose(spbsHandle);
    
    if (result != 0) {
        printf("Launch failed. Error code %d\n", result);
        return;
    }
}

kern_return_t v0rtex_callback(task_t tfp0, kptr_t kbase, void *cb_data) {
    kernel_task = tfp0;
    kernel_base = kbase;
    kernel_slide = kernel_base - offsets.base;
    
    return KERN_SUCCESS;
}

- (void)updateStatus:(NSString *)text, ... {
    va_list args;
    va_start(args, text);
    
    text = [[NSString alloc] initWithFormat:text arguments:args];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.goButton setTitle:text forState:UIControlStateNormal];
    });

    NSLog(@"%@", text);

    va_end(args);
}

@end
