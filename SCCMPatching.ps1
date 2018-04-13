﻿#Simple logging function
Function WriteLog{
    Param(
        [String]$StringInput,
        [String]$LogFile
    )
    $LogTime = Get-Date
    $StringToWrite = $LogTime.ToString() + ": "+ $StringInput
    Add-Content $LogFile -value $StringToWrite
    Write-Host $StringInput
}#End of Function
    
Function Start-ServerPatching {
    <#
    .SYNOPSIS
        This Function utilises the SCCM WMI module to install patches that are currently in an available state. 

    .DESCRIPTION
        Start-ServerPatching
        Author: James Auchterlonie
        Version: 1.2
        Last Modified: 12/04/18 3:30PM

        Changelog:
        0.1 - Basic WMI to get and complete server patches
        0.2 - Control logic for patching
        0.3 - Replaced Write-Host with Logging Function
        0.4 - Included logic to handle shutdowns/restarts/errors
        1.0 - Basic Version Completed
        1.1 - Updated ugly switch with neater hashtable logic
        1.2 - Updated initialisation to hanfle lack of WMI connectivity
        1.3 - Added help file

    .OUTPUTS
        Complete - Patches completed, not rebooted/shutdown
        NoPatches - WMI advised no patches queued
        Error - Error with patching
        Timeout - Took over 1 hour, 
        Restart - Server has been restarted
        Shutdown - Server has been shutdown
        ServerNotFound - Server connection checks failed
        Usage info - Basic details to use command.
        RemoteWMINotAvailable - Unable to access server using WMI


    .PARAMETER Server
        The server hostname to be patched
    .Parameter LogFile
        A specific file to provide output to, by default the script will output to C:\Temp\patching<datetime>.log
    .Parameter postPatchingAction 
        Can be set to Reboot\shutdown to complete a shutdown or restart post patching. By default, server is left on with patches pending next reboot

    .Example 
    #Patch server with no reboot
    Start-ServerPatching -Server <Server Name> -LogFile <LogFile>
    .Example
    #Patch server and restart
    Start-ServerPatching -Server <Server Name> -LogFile <LogFile> -postPatchingAction Restart
    .Example
    #Patch server and shutdown
    Start-ServerPatching -Server <Server Name> -LogFile <LogFile> -postPatchingAction Shutdown


    #>
    [cmdletbinding()]
    Param(
        [Parameter(Position=0,mandatory=$true)]
        [string]$Server,
        [Parameter(Position=1,mandatory=$false)]
        [string]$LogFile,
        [Parameter(Position=2,mandatory=$false)]
        [string]$postPatchingAction
    )
    Process{
    #declare hashtable for possible patch statuses
    $PatchStatus = @{}
    $PatchStatus.add(1,"is available, but has not been activated")
    $PatchStatus.add(2,"has been submitted for evaluation")
    $PatchStatus.add(3,"is currently being detected") 
    $PatchStatus.add(4,"is completing pre download") 
    $PatchStatus.add(5,"is downloading") 
    $PatchStatus.add(6,"is awaiting install") 
    $PatchStatus.add(7,"is installing" )
    $PatchStatus.add(8,"is pending soft reboot") 
    $PatchStatus.add(9,"is pending hard reboot") 
    $PatchStatus.add(10,"is Waiting for reboot") 
    $PatchStatus.add(11,"is Verifying completion")
    $PatchStatus.add(12,"is installed") 
    $PatchStatus.add(13,"is in an Error State") 
    $PatchStatus.add(14,"is waiting for a service window") 
    $PatchStatus.add(15,"is waiting user logon") 
    $PatchStatus.add(16,"is waiting user logoff") 
    $PatchStatus.add(17,"is waiting user job logon") 
    $PatchStatus.add(18,"is waiting user reconnect") 
    $PatchStatus.add(19,"is pending user logoff") 
    $PatchStatus.add(20,"is pending an update") 
    $PatchStatus.add(21,"is waiting a retry")
    $PatchStatus.add(22,"is waiting presmodeoff")
    $PatchStatus.add(23,"is waiting for orchestration")
    
    #check for logfile, generate if not specified. 
    if(!($LogFile)){$LogFile = "c:\Temp\PowershellServerPatching.Log"} 
    #Output basic details to logfile
    WriteLog -StringInput "SCCM Patching Script" -LogFile $LogFile
    WriteLog -StringInput "Patching initiated by user: $env:USERNAME" -LogFile $LogFile 
    WriteLog -StringInput "Initiating Server: $env:COMPUTERNAME" -LogFile $LogFile
    WriteLog -StringInput "Script Version: 1.0" -LogFile $LogFile
    WriteLog -StringInput "Server to be patched: $Server" -LogFile $LogFile
    #check for servername, exit if not provided. 
    if($server){
        if(!(Test-Connection $Server -ErrorAction SilentlyContinue)){
            WriteLog -StringInput "Unable see server" -LogFile $LogFile
            return "ServerNotFound"
        }else{
            try{
                WriteLog -StringInput "Checking WMI" -LogFile $LogFile
                [System.Management.ManagementObject[]] $CMMissingUpdates = @(GWMI -ComputerName $server -query "SELECT * FROM CCM_SoftwareUpdate WHERE ComplianceState = '0'" -namespace "ROOT\ccm\ClientSDK" -ErrorAction Stop)<#End Get update count.#>
            }catch{
                WriteLog -StringInput "Unable to connect to server using WMI" -LogFile $LogFile
                Return "RemoteWMINotAvailable"
            }
        }
    }else{
        return "Usage: Start-ServerPatching -Server <Hostname> -LogFile <LogPath>"
    }



    # Get the number of missing updates
    $updates = $CMMissingUpdates.count
    WriteLog -StringInput "The number of missing updates is $updates" -LogFile $LogFile
    foreach($patch in $CMMissingUpdates){
        WriteLog -StringInput "Patchno KB$($patch.ArticleID)" -LogFile $LogFile
    }

    $finishTime = [DateTime]::Now.AddHours(1)
    $failedPatchAttempts = 0
    #if updates are available, install them.
    If ($updates) {
        $CMInstallMissingUpdates = (GWMI -ComputerName $server -Namespace "root\ccm\clientsdk" -Class "CCM_SoftwareUpdatesManager" -List).InstallUpdates($CMMissingUpdates)
        WriteLog -StringInput "Patching Initiated" -LogFile $LogFile
        #not ready for reboot
        $reboot = 0 
        #Wait for all updates to be ready, and reboot once complete.
        While($reboot -ne 1){
            $counter++
            #get status of updates
            $readyforreboot = 1
            #complete a check for each patch that was found earlier, change readyforreboot status to 0 if not ready or 2 if errors found
            foreach($patch in $CMMissingUpdates){
                $patchno = $patch | select -ExpandProperty ArticleID
                $query = "SELECT * FROM CCM_SoftwareUpdate WHERE ArticleID = '$patchno'"
                WriteLog -StringInput "KB$patchno being evaluated" -LogFile $LogFile
                $wmiresult = (GWMI -ComputerName $server -query $query -namespace "ROOT\ccm\ClientSDK")
                WriteLog -StringInput "WMI result is: $wmiresult" -LogFile $LogFile
                #check on WMI result and previous reboot status, if reboot is 0 ignore code. Go back to line 83 
                if(($wmiresult) -and ($readyforreboot -eq 1)){
                    #Setup exit behaviour based off: https://msdn.microsoft.com/library/jj155450.aspx  
                    WriteLog -StringInput "WMI status for this patch is: $($wmiresult.EvaluationState)" -LogFile $LogFile
                    switch($($wmiresult.EvaluationState)){
                        {($_ -eq 8) -or ($_ -eq 9) -or ($_ -eq 10)-or ($_ -eq 12)}{
                            #ready for reboot  or installed
                            WriteLog -StringInput "KB$patchno $($PatchStatus[[int]$_])" -LogFile $LogFile
                        }{($_ -eq 1) -or ($_ -eq 2)}{
                            #1+2 is patches not initialised
                            WriteLog -StringInput "KB$patchno $($PatchStatus[[int]$_])" -LogFile $LogFile
                            $CMInstallMissingUpdates = (GWMI -ComputerName $server -Namespace "root\ccm\clientsdk" -Class "CCM_SoftwareUpdatesManager" -List).InstallUpdates($CMMissingUpdates)        
                            $readyforreboot = 0
                        }{$_ -eq 13}{
                            #13 is patch in error
                            WriteLog -StringInput "KB$patchno $($PatchStatus[[int]$_])" -LogFile $LogFile
                            $CMInstallMissingUpdates = (GWMI -ComputerName $server -Namespace "root\ccm\clientsdk" -Class "CCM_SoftwareUpdatesManager" -List).InstallUpdates($CMMissingUpdates)
                            $failedPatchAttempts ++
                            if($failedPatchAttempts -ge 5){
                                $readyforreboot=2
                            }else{
                                $readyforreboot=0
                            }
                        }default{
                            WriteLog -StringInput "KB$patchno $($PatchStatus[[int]$_])" -LogFile $LogFile
                            $readyforreboot = 0
                        }  
                    }    
                }     
            }
            $currenttime = [DateTime]::Now
            #if all patches are good, reboot. Check for long running patching.
            if($readyforreboot -eq 1){
                $reboot = 1    
            }elseif($currenttime -ge $finishTime){
                WriteLog -StringInput "Patching took too long on this server" -LogFile $LogFile
                Return "TimeOut"
            }elseif($readyforreboot -eq 2){  
                Return "Error"
            }else{
                Start-Sleep -seconds 120   
            }  
        }
        WriteLog -StringInput "Patching is in desired state" -LogFile $LogFile
        }Else{
           WriteLog -StringInput "There are no missing updates." -LogFile $LogFile
           Return "NoPatches"
        }
        switch($postPatchingAction){
            {[String]$_.toUpper() -eq "RESTART"}{
                WriteLog -StringInput "Initiating Server Restart" -LogFile $LogFile
                Restart-Computer -ComputerName $Server -Confirm:$false
                Return "Restart"
            }{[String]$_.toUpper() -eq "SHUTDOWN"}{
                WriteLog -StringInput "Initiating Server Shutdown" -LogFile $LogFile
                Stop-Computer -ComputerName $Server -Confirm:$false
                return "Shutdown"
            }default{
                Return "Complete"
            }
        }    
    }#End of Process    
}#End of Function

Function Get-PatchStatus{
    <#
    .SYNOPSIS
    This Function utilises the SCCM WMI Module to get the status for patches available currently
    .SYNTAX 
    Get-PatchStatus -Server <Hostname>
    .PARAMETER Server
            The server hostname to be patched
    .OUTPUTS
        ServerNotFound - Server connection checks failed
        Usage info - Basic details to use command.
        RemoteWMINotAvailable - Unable to access server using WMI
        Patch details for available patches
    #>
    [cmdletbinding()]
    Param(
        [Parameter(Position=0,mandatory=$true)]
        [string]$Server
    )
    Process{
        #declare hashtable for possible patch statuses
        $PatchStatus = @{}
        $PatchStatus.add(1,"is available, but has not been activated")
        $PatchStatus.add(2,"has been submitted for evaluation")
        $PatchStatus.add(3,"is currently being detected") 
        $PatchStatus.add(4,"is completing pre download") 
        $PatchStatus.add(5,"is downloading") 
        $PatchStatus.add(6,"is awaiting install") 
        $PatchStatus.add(7,"is installing" )
        $PatchStatus.add(8,"is pending soft reboot") 
        $PatchStatus.add(9,"is pending hard reboot") 
        $PatchStatus.add(10,"is Waiting for reboot") 
        $PatchStatus.add(11,"is Verifying completion")
        $PatchStatus.add(12,"is installed") 
        $PatchStatus.add(13,"is in an Error State") 
        $PatchStatus.add(14,"is waiting for a service window") 
        $PatchStatus.add(15,"is waiting user logon") 
        $PatchStatus.add(16,"is waiting user logoff") 
        $PatchStatus.add(17,"is waiting user job logon") 
        $PatchStatus.add(18,"is waiting user reconnect") 
        $PatchStatus.add(19,"is pending user logoff") 
        $PatchStatus.add(20,"is pending an update") 
        $PatchStatus.add(21,"is waiting a retry")
        $PatchStatus.add(22,"is waiting presmodeoff")
        $PatchStatus.add(23,"is waiting for orchestration")

        if($server){
            if(!(Test-Connection $Server -ErrorAction SilentlyContinue)){
                WriteLog -StringInput "Unable see server" -LogFile $LogFile
                return "ServerNotFound"
            }else{
                try{
                    WriteLog -StringInput "Checking WMI" -LogFile $LogFile
                    [System.Management.ManagementObject[]] $CMUpdates = @(GWMI -ComputerName $server -query "SELECT * FROM CCM_SoftwareUpdate WHERE ComplianceState = '0'" -namespace "ROOT\ccm\ClientSDK" -ErrorAction Stop)<#End Get update count.#>
                }catch{
                    WriteLog -StringInput "Unable to connect to server using WMI" -LogFile $LogFile
                    Return "RemoteWMINotAvailable"
                }
            }
        }else{
            return "Usage: Start-ServerPatching -Server <Hostname> -LogFile <LogPath>"
        }
        if($CMUpdates){
            foreach($patch in $CMUpdates){
                            $patchno = $patch | select -ExpandProperty ArticleID
                            $query = "SELECT * FROM CCM_SoftwareUpdate WHERE ArticleID = '$patchno'"
                            $wmiresult = (GWMI -ComputerName $server -query $query -namespace "ROOT\ccm\ClientSDK")
                            if($wmiresult){
                                "KB$patchno $($PatchStatus[[int]$wmiresult.EvaluationState])"          
                            }
            }
        }
    }
}#End of Function