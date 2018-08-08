//
//  utils.h
//  Broom
//
//  Created by Ben Sparkes on 08/08/2018.
//  Copyright © 2018 Ben Sparkes. All rights reserved.
//

#ifndef utils_h
#define utils_h

void restart_device(void);

double uptime(void);

void suspend_all_threads(void);
void resume_all_threads(void);

// creds to stek29 on this one
int execprog(const char *prog, const char *args[]);

#endif /* utils_h */
