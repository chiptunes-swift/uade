GetWB0bject equ -30
PutWBObject equ -36
GetIcon equ -42
Putlcon equ -48
FreeFreeList equ -54
FreeWBObject equ -60
AllocWBObject equ -66
AddFreeList equ -72
* struct DiskObject *GetDiskObject(char *);  D0 = (A0);
GetDiskObject equ -78
PutDiskObject equ -84
* void FreeDiskObject(struct DiskObject *); (A0)
FreeDiskObject equ -90
* char *FindToolType(char **list, char *key) where "list" e.g. ["FILETYPE=text"]; D0 = (A0, A1)
FindToolType equ -96
MatchToolValue equ -102
BumpRevision equ -108

ICONENTRIES equ 18
