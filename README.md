# WindowsServerPatch
Server Patching Script

Start-ServerPatching
Author: James Auchterlonie
Version: 1.0
Last Modified: 12/04/18 3:30PM

Summary: 
    This Function utilises the SCCM WMI module to install patches that are currently in an available state. 
Usage: 
    Patch server with no reboot - Start-ServerPatching -Server <Server Name> -LogFile <LogFile>
    Patch server and restart - Start-ServerPatching -Server <Server Name> -LogFile <LogFile> -postPatchingAction 1
    Patch server and shutdown - Start-ServerPatching -Server <Server Name> -LogFile <LogFile> -postPatchingAction 2
Changelog:
    0.1 - Basic WMI to get and complete server patches
    0.2 - Control logic for patching
    0.3 - Replaced Write-Host with Logging Function
    0.4 - Included logic to handle shutdowns/restarts/errors
    1.0 - Basic Version Completed
Return Values: 
    Complete - Patches completed, not rebooted/shutdown
    NoPatches - WMI advised no patches queued
    Error - Error with patching
    Timeout - Took over 1 hour, 
    Restart - Server has been restarted
    Shutdown - Server has been shutdown
    ServerNotFound - Server connection checks failed
    Usage info - Basic details to use command.
