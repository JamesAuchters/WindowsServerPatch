﻿#Variable Declaration
$PatchStatus = @{}#declare hashtable for possible patch statuses
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

$clusterNodes = @{}

$LogFile = ""

#Simple logging function
Function WriteLog{
    <# 

    #>
    Param(
        [Parameter(mandatory=$true)]
        [String]$StringInput,
        [Parameter(mandatory=$true)]
        [String]$File,
        [Parameter(mandatory=$false)]
        [int]$Action
        #TODO: Update with Warning and Error Flags
    )
    Begin{
        $LogTime = Get-Date
    }
    Process{
        #CONTINUE HERE: Setting up writelog action for different error types. 
        #Allows removal of Pauseforinput and sets up different diplays for error/warning.
        if($Action -eq 1){
            $continue = ''
            while($continue.ToUpper() -ne 'Y'){
                Add-Content -Path $File -Value $StringToWrite
                $continue = Read-Host "Would you like to continue? (Y/N)"
                if($continue.ToUpper() -eq "Y"){
                    
                }elseif($continue.ToUpper() -eq "N"){
                    
                    return "Cancelled"
                }else{
                    Write-Host "Please enter Y or N."
                }
            }
        }Else{
            $StringToWrite = $LogTime.ToString() + ": "+ $StringInput
            Add-Content -Path $File -Value $StringToWrite
            Write-Host $StringInput
        }
    }#End of Process  
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
            1.4 - Updated local logfile with global logfile

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
            Start-ServerPatching -Server <Server Name> -Log <LogFile>
        .Example
            #Patch server and restart
            Start-ServerPatching -Server <Server Name> -Log <LogFile> -postPatchingAction Restart
        .Example
            #Patch server and shutdown
            Start-ServerPatching -Server <Server Name> -Log <LogFile> -postPatchingAction Shutdown
    #>
    [cmdletbinding()]
    Param(
        [Parameter(Position=0,mandatory=$true)]
        [string]$Server,
        [Parameter(Position=1,mandatory=$false)]
        [string]$Log,
        [Parameter(Position=2,mandatory=$false)]
        [string]$postPatchingAction
    )#End of Param
    Begin{
        #TODO: Work out usage of the global logfile within this function.
        if(!($Log)){$global:LogFile = "c:\Temp\ComplexPowershell.Log"}else{$Global:LogFile=$Log}
        #Output basic details to logfile
        WriteLog -StringInput "SCCM Patching Script" -File $global:LogFile
        WriteLog -StringInput "Patching initiated by user: $env:USERNAME" -File $global:LogFile 
        WriteLog -StringInput "Initiating Server: $env:COMPUTERNAME" -File $global:LogFile
        WriteLog -StringInput "Script Version: 1.0" -File $global:LogFile
        WriteLog -StringInput "Server to be patched: $Server" -File $global:LogFile
        #check for servername, exit if not provided. 
        if($server){
            if(!(Test-Connection $Server -ErrorAction SilentlyContinue)){
                WriteLog -StringInput "Unable see server" -File $global:LogFile
                return "ServerNotFound"
            }else{
                try{
                    WriteLog -StringInput "Checking WMI" -File $global:LogFile
                    [System.Management.ManagementObject[]] $CMMissingUpdates = @(Get-WmiObject -ComputerName $server -query "SELECT * FROM CCM_SoftwareUpdate WHERE ComplianceState = '0'" -namespace "ROOT\ccm\ClientSDK" -ErrorAction Stop)<#End Get update count.#>
                }catch{
                    WriteLog -StringInput "Unable to connect to server using WMI" -File $global:LogFile
                    Return "RemoteWMINotAvailable"
                }
            }
        }else{
            return "Usage: Start-ServerPatching -Server <Hostname> -Log <LogPath>"
        }
    }#End of Begin
    Process{
        # Get the number of missing updates
        $updates = $CMMissingUpdates.count
        WriteLog -StringInput "The number of missing updates is $updates" -File $global:LogFile
        foreach($patch in $CMMissingUpdates){
        WriteLog -StringInput "Patchno KB$($patch.ArticleID)" -File $global:LogFile
        }

        $finishTime = [DateTime]::Now.AddHours(1)
        $failedPatchAttempts = 0
        #if updates are available, install them.
        If ($updates) {
            $CMInstallMissingUpdates = (Get-WmiObject -ComputerName $server -Namespace "root\ccm\clientsdk" -Class "CCM_SoftwareUpdatesManager" -List).InstallUpdates($CMMissingUpdates)
            WriteLog -StringInput "Patching Initiated" -File $global:LogFile
            #not ready for reboot
            $reboot = 0 
            #Wait for all updates to be ready, and reboot once complete.
            While($reboot -ne 1){
                $counter++
                #get status of updates
                $readyforreboot = 1
                #complete a check for each patch that was found earlier, change readyforreboot status to 0 if not ready or 2 if errors found
                foreach($patch in $CMMissingUpdates){
                    $patchno = $patch | Select-Object -ExpandProperty ArticleID
                    $query = "SELECT * FROM CCM_SoftwareUpdate WHERE ArticleID = '$patchno'"
                    WriteLog -StringInput "KB$patchno being evaluated" -File $global:LogFile
                    $wmiresult = (Get-WmiObject -ComputerName $server -query $query -namespace "ROOT\ccm\ClientSDK")
                    WriteLog -StringInput "WMI result is: $wmiresult" -File $global:LogFile
                    #check on WMI result and previous reboot status, if reboot is 0 ignore code. Go back to line 83 
                    if(($wmiresult) -and ($readyforreboot -eq 1)){
                        #Setup exit behaviour based off: https://msdn.microsoft.com/library/jj155450.aspx  
                        WriteLog -StringInput "WMI status for this patch is: $($wmiresult.EvaluationState)" -File $global:LogFile
                        switch($($wmiresult.EvaluationState)){
                            {($_ -eq 8) -or ($_ -eq 9) -or ($_ -eq 10)-or ($_ -eq 12)}{
                                #ready for reboot  or installed
                                WriteLog -StringInput "KB$patchno $($global:PatchStatus[[int]$_])" -File $global:LogFile
                            }{($_ -eq 1) -or ($_ -eq 2)}{
                                #1+2 is patches not initialised
                                WriteLog -StringInput "KB$patchno $($global:PatchStatus[[int]$_])" -File $global:LogFile
                                $CMInstallMissingUpdates = (Get-WmiObject -ComputerName $server -Namespace "root\ccm\clientsdk" -Class "CCM_SoftwareUpdatesManager" -List).InstallUpdates($CMMissingUpdates)        
                                $readyforreboot = 0
                            }{$_ -eq 13}{
                                #13 is patch in error
                                WriteLog -StringInput "KB$patchno $($global:PatchStatus[[int]$_])" -File $global:LogFile
                                $CMInstallMissingUpdates = (Get-WmiObject -ComputerName $server -Namespace "root\ccm\clientsdk" -Class "CCM_SoftwareUpdatesManager" -List).InstallUpdates($CMMissingUpdates)
                                $failedPatchAttempts ++
                                if($failedPatchAttempts -ge 5){
                                    $readyforreboot=2
                                }else{
                                    $readyforreboot=0
                                }
                            }default{
                                WriteLog -StringInput "KB$patchno $($global:PatchStatus[[int]$_])" -File $global:LogFile
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
                    WriteLog -StringInput "Patching took too long on this server" -File $global:LogFile
                    Return "TimeOut"
                }elseif($readyforreboot -eq 2){  
                    Return "Error"
                }else{
                    Start-Sleep -seconds 120   
                }  
            }
            WriteLog -StringInput "Patching is in desired state" -File $global:LogFile
        }Else{
            WriteLog -StringInput "There are no missing updates." -File $global:LogFile
            Return "NoPatches"
        }
        switch($postPatchingAction){
            {[String]$_.toUpper() -eq "RESTART"}{
                WriteLog -StringInput "Initiating Server Restart" -File $global:LogFile
                Restart-Computer -ComputerName $Server -Confirm:$false
                Return "Restart"
            }{[String]$_.toUpper() -eq "SHUTDOWN"}{
                WriteLog -StringInput "Initiating Server Shutdown" -File $global:LogFile
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
    )#End of Param
    Begin{
    }#End of Begin
    Process{
        if($server){
            if(!(Test-Connection $Server -ErrorAction SilentlyContinue)){
                WriteLog -StringInput "Unable see server" -File $global:LogFile
                return "ServerNotFound"
            }else{
                try{
                    WriteLog -StringInput "Checking WMI" -File $global:LogFile
                    [System.Management.ManagementObject[]] $CMUpdates = @(Get-WmiObject -ComputerName $server -query "SELECT * FROM CCM_SoftwareUpdate WHERE ComplianceState = '0'" -namespace "ROOT\ccm\ClientSDK" -ErrorAction Stop)<#End Get update count.#>
                }catch{
                    WriteLog -StringInput "Unable to connect to server using WMI" -File $global:LogFile
                    Return "RemoteWMINotAvailable"
                }
            }
        }else{
            return "Usage: Start-ServerPatching -Server <Hostname> -File <LogPath>"
        }
        if($CMUpdates){
            foreach($patch in $CMUpdates){
                $patchno = $patch | Select-Object -ExpandProperty ArticleID
                $query = "SELECT * FROM CCM_SoftwareUpdate WHERE ArticleID = '$patchno'"
                $wmiresult = (Get-WmiObject -ComputerName $server -query $query -namespace "ROOT\ccm\ClientSDK")
                if($wmiresult){
                    "KB$patchno $($global:PatchStatus[[int]$wmiresult.EvaluationState])"          
                }
            }
        }
    }#End of Process 
}#End of Function

Function Start-ServiceXML{
    <#
        .SYNOPSIS
            Takes a Child XML node from Start-ServerXML and completes specified action against server
        .PARAMETER Service
            The XML node that define actions for the service:
            <Service Type="Service" Name="vmtools" Action="Stop/Start"></Service>
        .PARAMETER Server
            The hostname of the server that the service is on.
        .EXAMPLE
            start-serviceXML -service $($XML.ChildNode) -server hostname
        .NOTES
            This function makes use of the $global:LogFile, there is no error handling for a missing declaration
    #>
    [cmdletbinding()]
    Param(
        [Parameter(Position=0,mandatory=$true)]
        [Xml.XmlElement[]]$Service,
        [Parameter(Position=1,mandatory=$true)]
        [string]$Server
    )#End of Param
    Begin{
        #TODO: XML validation.
    }#End of Begin
    Process{
        #Test for existence of service on server
        if($ServerService = Get-Service -ComputerName $Server -Name $($Service.name)){
            #Perform action based on XML specification
            if(($Service.Action).toUpper() -eq "STOP"){
                WriteLog -StringInput "Stopping service $($Service.name) on server $Server" -File $global:LogFile
                Stop-Service -InputObject $ServerService -Verbose -Force #TODO: Add Error Handling
                WriteLog -StringInput "Service Stopped" -File $global:LogFile
            }elseif($($Service.Action).toUpper() -eq "START"){
                WriteLog -StringInput "Starting service $($Service.name) on server $Server" -File $global:LogFile
                Start-Service -InputObject $ServerService -Verbose #TODO: Add Error Handling
                WriteLog -StringInput "Service Started" -File $global:LogFile    
            }else{
                WriteLog -StringInput "ERROR: Service tag has been incorrectly defined within XML file. Please define an action of STOP/START" -File $global:LogFile
            }
        }else{
            WriteLog -StringInput "WARNING: Service not found on server" -File $global:LogFile
        }
    }#End of Process
}#End of Function

Function Start-ServerXML{
    <#
        .SYNOPSIS
            Takes a child XML element from Start-ComplexPatch or Start-ClusterXML
            Completes action specified, and handles child XML nodes using Start-ServiceXML
            Makes use of Start-ServerPatching to complete any defined patching actions.
        
        .PARAMETER ServerXML
            The XML node that defines the server Below is an example XML node:
            <Server Type="Server" HostName="Server2" Action="Patch" Flags="">
                <Service Type="Service" Name="vmtools" Action="Stop/Start"></Service> 
            </Server>

            HostName - is used to specify the server that is being acted on.
            Action - is used to specify what is to be completed by the function
                Possible Values:
                Patch
                Shutdown
                Restart
                Start
                None

            Flags - is used to define options used by start-serverpatch when action is set to patch. Refer to the documentation for a full option list.
            
        .EXAMPLE
            start-serverXML -Device $($XML.ChildNode)

        .NOTES
            This function makes use of the $global:LogFile, there is no error handling for a missing declaration
    #>
    [cmdletbinding()]
    Param(
        [Parameter(Position=0,mandatory=$true)]
        [Xml.XmlElement[]]$ServerXML
    )#End of Param
    Begin{
        #TODO: Check for VMWare/HYPERV Module.
    }#End of Begin
    Process{
        #check if services need to be handled.
        if(($ServerXML.ChildNodes).count -gt 0){
            WriteLog -StringInput "Services have been Found" -File $global:LogFile
            #foreach service that is found, perform action.
            foreach($Service in $ServerXML.ChildNodes){
                #pass node to function which holds service handling logic.
                Write-host "Start-S
                erviceXML -Service $Service -Server $($Device.name)"
            }
        }else{
            WriteLog -StringInput "No Services found for this server." -File $global:LogFile
        }
        #Now that services have been handled, complete action assigned to this server.
        Switch($($ServerXML.Action).toUpper()){
            "PATCH"{
                $flags = "-Servername $($ServerXML.HostName) $($ServerXML.flags)"
                WriteLog -StringInput "Running Patching command: Start-ServerPatching $flags" -File $global:LogFile
                $return = Start-ServerPatching $flags
                Switch($return.toUpper){
                    "COMPLETE"{
                        WriteLog -StringInput "Start-ServerPatching has returned successfully" -File $global:LogFile
                    }"NOPATCHES"{
                        WriteLog -StringInput "Start-ServerPatching has advised no patches available." -File $global:LogFile
                    }"ERROR"{
                        WriteLog -StringInput "ERROR: Start-ServerPatching has failed patching for server: $($ServerXML.HostName)" -File $global:LogFile
                        PauseForInput
                    }"TIMEOUT"{
                        WriteLog -StringInput "WARNING: Start-ServerPatching has ran over the allocated time: $($ServerXML.HostName)" -File $global:LogFile
                        PauseForInput
                    }"SERVERNOTFOUND"{
                        WriteLog -StringInput "Start-ServerPatching is unable to locate the server: $($ServerXML.HostName)" -File $global:LogFile
                        PauseForInput
                    }"REMOTEWMINOTAVAILABLE"{
                        WriteLog -StringInput "Start-ServerPatching is unable to connect to WMI for server: $($ServerXML.HostName)" -File $global:LogFile
                        PauseForInput
                    }"SHUTDOWN"{
                        WriteLog -StringInput "$($ServerXML.HostName) has been shutdown by Start-ServerPatching" -File $global:LogFile
                    }"RESTART"{
                        WriteLog -StringInput "$($ServerXML.HostName) has been restarted by Start-ServerPatching" -File $global:LogFile
                    }
                }
            }
            "SHUTDOWN"{
                WriteLog -StringInput "Completing Shutdown for: $($ServerXML.HostName)" -File $global:LogFile
                Stop-Computer -ComputerName $ServerXML.HostName -Confirm:$false
            }
            "RESTART"{
                WriteLog -StringInput "Completing Restart for: $($ServerXML.HostName)" -File $global:LogFile
                Restart-Computer -ComputerName $Server -Confirm:$false
            }
            "START"{
                WriteLog -StringInput "Attempting startup of $($ServerXML.HostName)" -File $global:LogFile
                #TODO: Use HyperV/VMWare Module
                #TODO: Start-server -server $($device.HostName) -File $global:LogFile
            }
            "NONE"{
                WriteLog -StringInput "WARNING: No action has been specified for server: $($ServerXML.HostName)" -File $global:LogFile
            }
        }
    }#End of Process 
}#End of Function

Function Start-ClusterXML{
    <#
        .SYNOPSIS
            Takes a child XML element from Start-ComplexPatch and handles cluster failovers.
            Any child nodes that are found as servers and passes these through to Start-ServerXML
        .PARAMETER Cluster
            The XML node that defines the server Below is an example XML node:
            <Cluster Type="Cluster" FinalActiveNode="Node1" ClusterName="Cluster1" ResourceName="SQLGroup">
                <Server Type="Server" HostName="Node1" Action="Patch" Flags="-postpatchingaction shutdown -logfile c:\users\auchterj-admin\desktop\example.log">
                </Server>
                <Server Type="Server" HostName="Node2" Action="Patch" Flags="-postpatchingaction shutdown -logfile c:\users\auchterj-admin\desktop\example.log">
                </Server>
            </Cluster>

            Within the XML Node the variables are:
            FinalActiveNode - used to specify the final location of the cluster resource.
            Clustername - The name of the cluster
            ResourceName - The name of the cluster resource that will require failover.
        .EXAMPLE
            start-ClusterXML -Cluster $($XML.ChildNode)
        .NOTES
            This function makes use of the $global:LogFile, there is no error handling for a missing declaration
    #>
    [cmdletbinding()]
    Param(
        [Parameter(Position=0,mandatory=$true)]
        [Xml.XmlElement[]]$Cluster
    )#End of Param 
    Begin{
    }#End of Begin
    Process{
        #get a list of nodes
        Get-Cluster -Name "$($Cluster.ClusterName)" | Get-ClusterNode | ForEach-Object{
            $clusterNodes.Add("$($_.Name)","No Actions Completed.")
        }
        #get the active node for the specified resource.
        $ClusterOwner = Get-Cluster -Name $($Cluster.ClusterrName) | Get-ClusterGroup -Name $($Cluster.ResourceName) | Select-Object -ExpandProperty OwnerNode 
        foreach($Server in $Cluster.ChildNodes){
            #Am I working with a cluster node?
            if($clusterNodes.Contains($($Server.HostName))){
                WriteLog -StringInput "$($Server.HostName) is in specified cluster" -Log $Global:Logfile
                #Am I the host node?
                if($Server.HostName -eq $ClusterOwner){
                    #Move cluster off this node for reboots to occur.
                    Try{
                        'Move-ClusterGroup -Name $($Device.ResourceName) -ErrorAction Stop'
                        $ClusterOwner = Get-Cluster -Name $($Device.ClusterName) | Get-ClusterGroup -Name $($Device.ResourceName) | Select-Object -ExpandProperty OwnerNode 
                    }catch{
                        $formatstring = "{0} : {1}`n{2}`n" +
                        "    + CategoryInfo          : {3}`n" +
                        "    + FullyQualifiedErrorId : {4}`n"
                        $fields = $_.InvocationInfo.MyCommand.Name,
                        $_.ErrorDetails.Message,
                        $_.InvocationInfo.PositionMessage,
                        $_.CategoryInfo.ToString(),
                        $_.FullyQualifiedErrorId
                        $DumpError = $formatstring -f $fields
                        WriteLog -StringInput $DumpError -log $Global:Logfile
                        PauseforInput
                    }
                }else{
                    'Start-ServerXML $Server'
                }
                $clusterNodes."$($Server.HostName)" = "XML Action Carried Out"
            }else{
                #XML Declared wrong. Not accounting for numbnuts.
                WriteLog -StringInput "WARNING: $($Server.HostName) Not in Cluster, no actions have been carried out." -log $Global:Logfile
            }
        }
        #Now that loop has moved through all servers, move the server back to the desired node. 
        Try{
            Move-ClusterGroup -Name $($Cluster.ResourceName) -Node $Cluster.FinalActiveNode -ErrorAction Stop
        }catch{
            $formatstring = "{0} : {1}`n{2}`n" +
            "    + CategoryInfo          : {3}`n" +
            "    + FullyQualifiedErrorId : {4}`n"
            $fields = $_.InvocationInfo.MyCommand.Name,
            $_.ErrorDetails.Message,
            $_.InvocationInfo.PositionMessage,
            $_.CategoryInfo.ToString(),
            $_.FullyQualifiedErrorId
            $DumpError = $formatstring -f $fields
            WriteLog -StringInput $DumpError -log $Global:Logfile
            PauseforInput -StringInput ""
        }
        #TODO: Add dump of completed cluster node actions to the log.
    }#End of Process                                                                         
}#End of Function

Function Start-XMLPatch{
    <#
        .SYNOPSIS
            This Function takes XML files to complete complex patching sequences.

        .DESCRIPTION
            Start-ServerPatching
            Author: James Auchterlonie
            Version: 0.1
            Last Modified: 09/06/18 7PM

            Changelog:
            0.1 - 
        .OUTPUTS
            Complete - Patches completed for all servers
            Error - Error with patching
            MissingModule - Missing a required module for execution.
        .PARAMETER XMLFile
            The XML file dictating which servers are to be patched.
        .Parameter LogFile
            A specific file to provide output to, by default the script will output to C:\Temp\ComplexPatching<datetime>.log
        .Example 
            #Patch multiple servers as defined in XML file.
            Start-ComplexPatch -XMLFile C:\Example.xml -File C:\Example.log
    #>
    [cmdletbinding()]
    Param(
        [Parameter(Position=0,mandatory=$true)]
        [string]$XMLFile,
        [Parameter(Position=1,mandatory=$false)]
        [string]$Log,
        [Parameter(Position=1,mandatory=$false)]
        [string]$virtualHost
        #TODO: Add a full auto flag - No warning prompts or error pauses.
    )#End of Param
    Begin{
        [XML]$PatchData= get-content -Path $XMLFile
        if(!($Log)){$global:LogFile = "c:\Temp\ComplexPowershellPatching.Log"}else{$Global:LogFile=$log}
        
        #TODO: Import-Module HyperV
        #TODO: Import-Module VMware.PowerCLI
        #TODO: Check for connection to Virtual host if specified.

        #Clustering Module for required work.
        If(Get-Module -ListAvailable FailoverClusters){
            If(!(Get-module FailoverClusters)) {
                try{
                    Import-Module FailoverClusters -ErrorAction Stop
                }catch{
                    WriteLog -StringInput "Failed to import module FailoverClusters" -File $global:LogFile
                    return "MissingModule"
                }    
            }else{
                WriteLog -StringInput "FailoverClusters is already loaded." -File $global:LogFile
            }
        }else{
            WriteLog -StringInput "Failed to find module FailoverClusters" -File $global:LogFile
            return "MissingModule"
        }
    }#End of Begin
    Process{
        Foreach($PatchingGroup in $PatchData.Patching.Group){
            WriteLog -StringInput "Processing Group $($PatchingGroup.name)" -File $global:LogFile
            #Foreach server/cluster. If server detected, $Device variable used to identify the server, if Cluster $Node is used to identify the server.
            foreach($XMLNode in $PatchingGroup.ChildNodes){
               if($XMLNode.Type -eq "Cluster"){
                    WriteLog -StringInput "Cluster has been found. ClusterName: $($XMLNode.ClusterName)" -File $global:LogFile
                    WriteLog -StringInput "Passing XML through to Start-ClusterXML" -File $global:LogFile
                    Start-ClusterXML -Cluster $XMLNode
               }elseif($XMLNode.Type -eq "Server"){
                    WriteLog -StringInput "XML Server Found. Hostname: $($XMLNode.name)" -File $global:LogFile
                    WriteLog -StringInput "Passing XML through to Start-ServerXML" -File $global:LogFile
                    Start-ServerXML -ServerXML $XMLNode
               }
            }
        }
    }#End of Process 
}#End of Function