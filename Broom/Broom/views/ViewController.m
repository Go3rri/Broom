//
//  ViewController.m
//  Broom
//
//  Created by Ben Sparkes on 08/08/2018.
//  Copyright © 2018 Ben Sparkes. All rights reserved.
//

#import "ViewController.h"

#include "kernel.h"
#include "offsetfinder.h"
#include "patchfinder64.h"
#include "root-rw.h"
#include "utils.h"
#include "v0rtex.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UIButton *goButton;
@end

@implementation ViewController

offsets_t *offsets = NULL;

task_t kernel_task;
uint64_t kernel_base;
uint64_t kernel_slide;

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)goButtonPressed:(UIButton *)button {
    kern_return_t kret;
    int ret;
    
    [self updateStatus:@"running..."];
    
    // grab offsets via liboffsetfinder64
    offsets = get_offsets();
    [self updateStatus:@"grabbed offsets"];
    
    // suspend app
    suspend_all_threads();
    
    // run v0rtex
    kret = v0rtex(offsets, &v0rtex_callback, NULL);
    
    if (kret != KERN_SUCCESS) {
        [self updateStatus:@"v0rtex failed, rebooting..."];
        sleep(3);
        restart_device();
        return;
    }
    
    resume_all_threads();
    
    [self updateStatus:@"v0rtex success!"];
    
    // initialize patchfinder64
    init_patchfinder(NULL, kernel_base);
    
    unsigned cmdline_offset;
    LOG("find_boot_args returned: %llx", find_boot_args(&cmdline_offset));
    LOG("cmdline offset: %d", cmdline_offset);
    
    // initialize kernel.m stuff
    uint64_t kernel_task_addr = rk64(offsets->kernel_task + kernel_slide);
    uint64_t kern_proc = rk64(kernel_task_addr + offsets->task_bsd_info);
    setup_kernel_tools(kernel_task, kern_proc);
    
    [self updateStatus:@"initialized patchfinders, etc"];
    
    // remount '/' as r/w
    NSOperatingSystemVersion osVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    int pre103 = osVersion.minorVersion < 3 ? 1 : 0;
    ret = mount_root(kernel_slide, offsets->root_vnode, pre103);
    
    if (ret != 0) {
        [self updateStatus:@"failed to remount disk0s1s1: %d", ret];
        return;
    }
    
    fclose(fopen("/.broom_test_file", "w"));
    if (access("/.broom_test_file", F_OK) != 0) {
        [self updateStatus:@"failed to remount disk0s1s1"];
        return;
    }
    
    execprog("/sbin/mount", NULL);
    
    [self updateStatus:@"remounted successfully"];
    
    // extract Eraser.app to /Applications
    
    
    // give +s bit & root:wheel to Eraser.app/Eraser
}

kern_return_t v0rtex_callback(task_t tfp0, kptr_t kbase, void *cb_data) {
    kernel_task = tfp0;
    kernel_base = kbase;
    kernel_slide = kernel_base - offsets->base;
    
    return KERN_SUCCESS;
}

- (void)updateStatus:(NSString *)text, ... {
    va_list args;
    va_start(args, text);
    
    text = [[NSString alloc] initWithFormat:text arguments:args];
    
    [self.goButton setTitle:text forState:UIControlStateNormal];
    NSLog(@"%@", text);

    va_end(args);
}

@end
