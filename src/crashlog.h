#ifndef __CRASHLOG_H__
#define __CRASHLOG_H__

// Copies log() output to a file players can send in (Download/samp_log.txt, or the game's
// own files folder) and records where the game was when it crashes.
void CrashLog_Init();
void CrashLog_Write(const char* line);

#endif
