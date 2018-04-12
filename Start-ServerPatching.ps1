<# 
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
#>

#Simple logging function
Function WriteLog{
    Param(
        [String]$StringInput,
        [String]$LogFile
    )
    $LogTime = Get-Date
    $StringToWrite = $LogTime.ToString() + ": "+ $StringInput
    Add-Content $LogFile -value $StringToWrite
}
    
Function Start-ServerPatching {
    [cmdletbinding()]
    Param(
        [string]$Server,
        [string]$LogFile,
        [int]$postPatchingAction
    )
    #check for logfile, generate if not specified. 
    if($LogFile){
    }else{$LogTime = Get-Date; $LogFile = "c:\Temp\Patching$LogTime.Log"}
    #check for servername, exit if not provided. 
    if($server){
        if(!(Test-Connection $Server -ErrorAction SilentlyContinue)){
            return "ServerNotFound"
        }
    }else{
        return "Usage: Start-ServerPatching -Server <Hostname> -LogFile <LogPath>"
    }

    #Output basic details to logfile
    WriteLog -StringInput "SCCM Patching Script" -LogFile $LogFile
    WriteLog -StringInput "Patching initiated by user: $env:USERNAME" -LogFile $LogFile 
    WriteLog -StringInput "Initiating Server: $env:COMPUTERNAME" -LogFile $LogFile
    WriteLog -StringInput "Script Version: 0.3" -LogFile $LogFile
    WriteLog -StringInput "Server to be patched: $Server" -LogFile $LogFile


    # Get the number of missing updates
    [System.Management.ManagementObject[]] $CMMissingUpdates = @(GWMI -ComputerName $server -query "SELECT * FROM CCM_SoftwareUpdate WHERE ComplianceState = '0'" -namespace "ROOT\ccm\ClientSDK") #End Get update count.
    $updates = $CMMissingUpdates.count
    WriteLog -StringInput "The number of missing updates is $updates" -LogFile $LogFile
    $finishTime = [DateTime]::Now.AddHours(1)

    #if updates are available, install them.
    If ($updates) {
        $CMInstallMissingUpdates = (GWMI -ComputerName $server -Namespace "root\ccm\clientsdk" -Class "CCM_SoftwareUpdatesManager" -List).InstallUpdates($CMMissingUpdates)
        WriteLog -StringInput "Patching Initiated" -LogFile $LogFile
        
        #not ready for reboot
        $reboot = 0
        
        #Wait for all updates to be ready, and reboot once complete.
        While($reboot -ne 1){
            #get status of updates
            $readyforreboot = 1
            #complete a check for each patch that was found earlier, change readyforreboot status to 0 if not ready or 2 if errors found
            foreach($patch in $CMMissingUpdates){
                $patchno = $patch | select -ExpandProperty ArticleID
                $query = "SELECT * FROM CCM_SoftwareUpdate WHERE ArticleID = '$patchno'"
                $wmiresult = (GWMI -ComputerName $server -query $query -namespace "ROOT\ccm\ClientSDK")
                #check on previous reboot status, if 0 ignore code. Go back to line TODO: while line. 
                if($readyforreboot -eq 1){
                    #Setup exit behaviour based off: https://msdn.microsoft.com/library/jj155450.aspx
                    Switch($($wmiresult.EvaluationState)){
                        1{
                            #for some reason patching isn't started, start it.
                            WriteLog -StringInput "KB$patchNo is available, but has not been activated" -LogFile $LogFile
                            $CMInstallMissingUpdates = (GWMI -ComputerName $server -Namespace "root\ccm\clientsdk" -Class "CCM_SoftwareUpdatesManager" -List).InstallUpdates($CMMissingUpdates)
                        }2{
                            #for some reason patching isn't started, start it.
                            WriteLog -StringInput "KB$patchNo has been submitted for evaluation" -LogFile $LogFile
                            $CMInstallMissingUpdates = (GWMI -ComputerName $server -Namespace "root\ccm\clientsdk" -Class "CCM_SoftwareUpdatesManager" -List).InstallUpdates($CMMissingUpdates)
                        }3{
                            WriteLog -StringInput "KB$patchNo is currently being detected " -LogFile $LogFile
                            $readyforreboot = 0
                        }4{
                            WriteLog -StringInput "KB$patchNo is completing pre download " -LogFile $LogFile
                            $readyforreboot = 0
                        }
                        5{
                            WriteLog -StringInput "KB$patchNo is downloading" -LogFile $LogFile
                            $readyforreboot = 0
                        }6{
                            WriteLog -StringInput "KB$patchNo is awaiting install" -LogFile $LogFile
                             $CMInstallMissingUpdates = (GWMI -ComputerName $server -Namespace "root\ccm\clientsdk" -Class "CCM_SoftwareUpdatesManager" -List).InstallUpdates($CMMissingUpdates)
                            $readyforreboot = 0
                        }7{
                            WriteLog -StringInput "KB$patchNo is installing" -LogFile $LogFile
                            $readyforreboot = 0
                        }8{
                            WriteLog -StringInput "KB$patchNo is pending soft reboot" -LogFile $LogFile
                        }9{
                            WriteLog -StringInput "KB$patchNo is pending hard reboot" -LogFile $LogFile
                        }10{
                            WriteLog -StringInput "KB$patchNo is Waiting for reboot" -LogFile $LogFile
                        }11{
                            WriteLog -StringInput "KB$patchNo is Verifying completion" -LogFile $LogFile
                            $readyforreboot = 0
                        }12{
                            WriteLog -StringInput "KB$patchNo is installed" -LogFile $LogFile
                        }13{
                            WriteLog -StringInput "KB$patchNo is in an Error State" -LogFile $LogFile
                            WriteLog -StringInput "$patch" -LogFile $LogFile
                            $readyforreboot = 2
                        }14{
                            WriteLog -StringInput "KB$patchNo is waiting for a service window" -LogFile $LogFile
                            $readyforreboot = 0
                        }15{
                            WriteLog -StringInput "KB$patchNo is waiting user logon" -LogFile $LogFile
                            $readyforreboot = 0
                        }16{
                            WriteLog -StringInput "KB$patchNo is waiting user logoff" -LogFile $LogFile
                            $readyforreboot = 0
                        }17{
                            WriteLog -StringInput "KB$patchNo is waiting user job logon" -LogFile $LogFile
                            $readyforreboot = 0
                        }18{
                            WriteLog -StringInput "KB$patchNo is waiting user reconnect" -LogFile $LogFile
                            $readyforreboot = 0
                        }19{
                            WriteLog -StringInput "KB$patchNo is pending user logoff" -LogFile $LogFile
                            $readyforreboot = 0
                        }20{
                            WriteLog -StringInput "KB$patchNo is pending an update" -LogFile $LogFile
                            $readyforreboot = 0
                        }21{
                            WriteLog -StringInput "KB$patchNo is waiting a retry" -LogFile $LogFile
                            $readyforreboot = 0
                        }22{
                            WriteLog -StringInput "KB$patchNo is waiting presmodeoff" -LogFile $LogFile
                            $readyforreboot = 0
                        }23{
                            WriteLog -StringInput "KB$patchNo is waiting for orchestration" -LogFile $LogFile
                            $readyforreboot = 0
                        }default{
                            WriteLog -StringInput "Default entered" -LogFile $LogFile
                            $readyforreboot = 0
                        }
                    }
                }      
            }
            $currenttime = [DateTime]::Now
            #if all patches are good, reboot. Check for long running patching. 
            if($readyforreboot -eq 1){
                $reboot = 1
                WriteLog -StringInput "Patching is in desired state" -LogFile $LogFile
                switch($postPatchingAction){
                    1{
                        WriteLog -StringInput "Initiating Server Restart" -LogFile $LogFile
                        Restart-Computer -ComputerName $Server -Confirm:false
                        Return "Restart"
                    }2{
                        WriteLog -StringInput "Initiating Server Shutdown" -LogFile $LogFile
                        Stop-Computer -ComputerName $Server -Confirm:false
                        return "Shutdown"
                    }default{
                        Return "Complete"
                    }
                }    
            }elseif($currenttime -ge $finishTime){
                WriteLog -StringInput "Patching took too long on this server" -LogFile $LogFile
                Return "TimeOut"
            }elseif($readyforreboot -eq 2){  
                Return "Error"
            }
            Start-Sleep -seconds 120
        }
    }Else{
       WriteLog -StringInput "There are no missing updates." -LogFile $LogFile
       Return "NoPatches"
    }   
}