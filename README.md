# WindowsServerPatch

Server Patching Script
</br>
Functions: WriteLog, Start-ServerPatching</br>
Author: James Auchterlonie</br>
Version: 1.0</br>
Last Modified: 12/04/18 3:30PM</br>
</br>
Summary: </br>
    This Function utilises the SCCM WMI module to install patches that are currently in an available state. </br>
</br>
Usage: </br>
    Patch server with no reboot - Start-ServerPatching -Server <Server Name> -LogFile <LogFile></br>
    Patch server and restart - Start-ServerPatching -Server <Server Name> -LogFile <LogFile> -postPatchingAction 1</br>
    Patch server and shutdown - Start-ServerPatching -Server <Server Name> -LogFile <LogFile> -postPatchingAction 2</br>
</br>
Changelog:</br>
    0.1 - Basic WMI to get and complete server patches</br>
    0.2 - Control logic for patching</br>
    0.3 - Replaced Write-Host with Logging Function</br>
    0.4 - Included logic to handle shutdowns/restarts/errors</br>
    1.0 - Basic Version Completed</br>
</br>
Return Values: </br>
    Complete - Patches completed, not rebooted/shutdown</br>
    NoPatches - WMI advised no patches queued</br>
    Error - Error with patching</br>
    Timeout - Took over 1 hour, </br>
    Restart - Server has been restarted</br>
    Shutdown - Server has been shutdown</br>
    ServerNotFound - Server connection checks failed</br>
    Usage info - Basic details to use command.</br>
