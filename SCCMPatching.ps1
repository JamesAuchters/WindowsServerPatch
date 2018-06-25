#Variable Declaration

#declare hashtable for possible patch statuses
#exit codes taken from: https://msdn.microsoft.com/library/jj155450.aspx
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

$LogFile = ""

Function Add-Log{
    <# 
        .SYNOPSIS
            Takes a string input and flags to write logs and information to screen
        .PARAMETER StringInput 
            Data to be written to screen and log. Timestamp is auto generated.
        .PARAMETER Action
            An Int code that defines the type of output.
            1=Error
            2=Warning
            3=PauseforInput
        .Parameter File
            Location to write log to. 
        .EXAMPLE
            Add-Log -StringInput "Example" -File C:\Example.log
            Writes a normal log to file and screen
        .EXAMPLE 
            Add-Log -StringInput "Example" -Action 1 -File C:\Example.log
            Writes a warning log to file and screen
    #>
    Param(
        [Parameter(mandatory=$true)]
        [String]$StringInput,
        [Parameter(mandatory=$true)]
        [String]$File,
        [Parameter(mandatory=$false)]
        [int]$Action
    )
    Begin{
        $LogTime = Get-Date
        $StringToWrite = $LogTime + ": "+ $StringInput
        $continue = ''
    }
    Process{
        Switch($Action){
            1{
                $StringToWrite = $LogTime + ": ERROR: " + $StringInput
                Add-Content -Path $File -Value $StringToWrite
                Write-Host $StringInput -ForegroundColor Red
            }2{
                $StringToWrite = $LogTime + ": WARNING: " + $StringInput
                Add-Content -Path $File -Value $StringToWrite
                Write-Host $StringInput -ForegroundColor Yellow 
            }3{
                while($continue.ToUpper() -ne 'Y'){
                    Write-Host $StringToWrite
                    Add-Content -Path $File -Value $StringToWrite
                    $continue = Read-Host "Would you like to continue? (Y/N)"
                    if($continue.ToUpper() -eq "Y"){
                        Add-Content -Path $File -Value "$env:USERNAME has elected to continue."
                    }elseif($continue.ToUpper() -eq "N"){
                        Add-Content -Path $File -Value "$env:USERNAME has elected to stop"
                    }else{
                        Write-Host "Please enter Y or N."
                    }
                }
            }Default{
                Add-Content -Path $File -Value $StringToWrite
                Write-Host $StringInput
            }
        }
    }#End of Process  
}#End of Function

Function Start-ServerPatching {
    <#
        .SYNOPSIS
            This Function utilises the SCCM WMI module to install patches that are currently in an available state. 
            
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
        if(!($Log) -or ($global:LogFile -eq "")){$global:LogFile = "c:\Temp\ComplexPowershell.Log"}else{$Global:LogFile=$Log}
        #Output basic details to logfile
        Add-Log -StringInput "SCCM Patching Script" -File $global:LogFile
        Add-Log -StringInput "Patching initiated by user: $env:USERNAME" -File $global:LogFile 
        Add-Log -StringInput "Initiating Server: $env:COMPUTERNAME" -File $global:LogFile
        Add-Log -StringInput "Script Version: 1.0" -File $global:LogFile
        Add-Log -StringInput "Server to be patched: $Server" -File $global:LogFile
        #check for servername, exit if not provided. 
        if($server){
            if(!(Test-Connection $Server -ErrorAction SilentlyContinue)){
                Add-Log -StringInput "Unable see server" -File $global:LogFile
                return "ServerNotFound"
            }else{
                try{
                    Add-Log -StringInput "Checking WMI" -File $global:LogFile
                    [System.Management.ManagementObject[]] $CMMissingUpdates = @(Get-WmiObject -ComputerName $server -query "SELECT * FROM CCM_SoftwareUpdate WHERE ComplianceState = '0'" -namespace "ROOT\ccm\ClientSDK" -ErrorAction Stop)<#End Get update count.#>
                }catch{
                    Add-Log -StringInput "Unable to connect to server using WMI" -File $global:LogFile
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
        Add-Log -StringInput "The number of missing updates is $updates" -File $global:LogFile
        foreach($patch in $CMMissingUpdates){
        Add-Log -StringInput "Patchno KB$($patch.ArticleID)" -File $global:LogFile
        }

        $finishTime = [DateTime]::Now.AddHours(1)
        $failedPatchAttempts = 0
        #if updates are available, install them.
        If ($updates) {
            $CMInstallMissingUpdates = (Get-WmiObject -ComputerName $server -Namespace "root\ccm\clientsdk" -Class "CCM_SoftwareUpdatesManager" -List).InstallUpdates($CMMissingUpdates)
            Add-Log -StringInput "Patching Initiated" -File $global:LogFile
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
                    Add-Log -StringInput "KB$patchno being evaluated" -File $global:LogFile
                    $wmiresult = (Get-WmiObject -ComputerName $server -query $query -namespace "ROOT\ccm\ClientSDK")
                    Add-Log -StringInput "WMI result is: $wmiresult" -File $global:LogFile
                    #check on WMI result and previous reboot status, if reboot is 0 ignore code. Go back to line 83 
                    if(($wmiresult) -and ($readyforreboot -eq 1)){
                        #Setup exit behaviour based off status codes.
                        Add-Log -StringInput "WMI status for this patch is: $($wmiresult.EvaluationState)" -File $global:LogFile
                        switch($($wmiresult.EvaluationState)){
                            {($_ -eq 8) -or ($_ -eq 9) -or ($_ -eq 10)-or ($_ -eq 12)}{
                                #ready for reboot  or installed
                                Add-Log -StringInput "KB$patchno $($global:PatchStatus[[int]$_])" -File $global:LogFile
                            }{($_ -eq 1) -or ($_ -eq 2)}{
                                #1+2 is patches not initialised
                                Add-Log -StringInput "KB$patchno $($global:PatchStatus[[int]$_])" -File $global:LogFile
                                $CMInstallMissingUpdates = (Get-WmiObject -ComputerName $server -Namespace "root\ccm\clientsdk" -Class "CCM_SoftwareUpdatesManager" -List).InstallUpdates($CMMissingUpdates)        
                                $readyforreboot = 0
                            }{$_ -eq 13}{
                                #13 is patch in error
                                Add-Log -StringInput "KB$patchno $($global:PatchStatus[[int]$_])" -File $global:LogFile
                                $CMInstallMissingUpdates = (Get-WmiObject -ComputerName $server -Namespace "root\ccm\clientsdk" -Class "CCM_SoftwareUpdatesManager" -List).InstallUpdates($CMMissingUpdates)
                                $failedPatchAttempts ++
                                if($failedPatchAttempts -ge 5){
                                    $readyforreboot=2
                                }else{
                                    $readyforreboot=0
                                }
                            }default{
                                Add-Log -StringInput "KB$patchno $($global:PatchStatus[[int]$_])" -File $global:LogFile
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
                    Add-Log -StringInput "Patching took too long on this server" -File $global:LogFile
                    Return "TimeOut"
                }elseif($readyforreboot -eq 2){  
                    Return "Error"
                }else{
                    Start-Sleep -seconds 120   
                }  
            }
            Add-Log -StringInput "Patching is in desired state" -File $global:LogFile
        }Else{
            Add-Log -StringInput "There are no missing updates." -File $global:LogFile
            Return "NoPatches"
        }
        switch($postPatchingAction){
            {[String]$_.toUpper() -eq "RESTART"}{
                Add-Log -StringInput "Initiating Server Restart" -File $global:LogFile
                Restart-Computer -ComputerName $Server -Confirm:$false
                Return "Restart"
            }{[String]$_.toUpper() -eq "SHUTDOWN"}{
                Add-Log -StringInput "Initiating Server Shutdown" -File $global:LogFile
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
                Add-Log -StringInput "Unable see server" -File $global:LogFile
                return "ServerNotFound"
            }else{
                try{
                    Add-Log -StringInput "Checking WMI" -File $global:LogFile
                    [System.Management.ManagementObject[]] $CMUpdates = @(Get-WmiObject -ComputerName $server -query "SELECT * FROM CCM_SoftwareUpdate WHERE ComplianceState = '0'" -namespace "ROOT\ccm\ClientSDK" -ErrorAction Stop)<#End Get update count.#>
                }catch{
                    Add-Log -StringInput "Unable to connect to server using WMI" -File $global:LogFile
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
            Start-ServiceXML -service $($XML.ChildNode) -server hostname
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
                Add-Log -StringInput "Stopping service $($Service.name) on server $Server" -File $global:LogFile
                Stop-Service -InputObject $ServerService -Verbose -Force #TODO: Add Error Handling
                Add-Log -StringInput "Service Stopped" -File $global:LogFile
            }elseif($($Service.Action).toUpper() -eq "START"){
                Add-Log -StringInput "Starting service $($Service.name) on server $Server" -File $global:LogFile
                Start-Service -InputObject $ServerService -Verbose #TODO: Add Error Handling
                Add-Log -StringInput "Service Started" -File $global:LogFile    
            }else{
                Add-Log -StringInput "Service tag has been incorrectly defined within XML file. Please define an action of STOP/START" -File $global:LogFile -Action 1
            }
        }else{
            Add-Log -StringInput "Service not found on server" -File $global:LogFile -Action 2
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
            Start-ServerXML -Device $($XML.ChildNode)

        .NOTES
            This function makes use of the $global:LogFile, there is no error handling for a missing declaration
    #>
    [cmdletbinding()]
    Param(
        [Parameter(Position=0,mandatory=$true)]
        [Xml.XmlElement[]]$ServerXML
    )#End of Param
    Begin{
        #TODO: XML validation.
    }#End of Begin
    Process{
        #check if services need to be handled.
        if(($ServerXML.ChildNodes).count -gt 0){
            Add-Log -StringInput "Services have been Found" -File $global:LogFile
            #foreach service that is found, perform action.
            foreach($Service in $ServerXML.ChildNodes){
                #pass node to function which holds service handling logic.
                Start-ServiceXML -Service $Service -Server $($Device.name)
            }
        }else{
            Add-Log -StringInput "No Services found for this server." -File $global:LogFile
        }
        #Now that services have been handled, complete action assigned to this server.
        Switch($($ServerXML.Action).toUpper()){
            "PATCH"{
                $flags = "-Servername $($ServerXML.HostName) $($ServerXML.flags)"
                Add-Log -StringInput "Running Patching command: Start-ServerPatching $flags" -File $global:LogFile
                $return = Start-ServerPatching $flags
                Switch($return.toUpper()){
                    "COMPLETE"{
                        Add-Log -StringInput "Start-ServerPatching has returned successfully" -File $global:LogFile
                    }"NOPATCHES"{
                        Add-Log -StringInput "Start-ServerPatching has advised no patches available." -File $global:LogFile
                    }"ERROR"{
                        Add-Log -StringInput "Start-ServerPatching has failed patching for server: $($ServerXML.HostName)" -File $global:LogFile -Action 1
                        Add-Log -StringInput "" -Action 3 -File $global:LogFile
                    }"TIMEOUT"{
                        Add-Log -StringInput "Start-ServerPatching has ran over the allocated time: $($ServerXML.HostName)" -File $global:LogFile -Action 2
                        Add-Log -StringInput "" -Action 3 -File $global:LogFile
                    }"SERVERNOTFOUND"{
                        Add-Log -StringInput "Start-ServerPatching is unable to locate the server: $($ServerXML.HostName)" -File $global:LogFile
                        Add-Log -StringInput "" -Action 3 -File $global:LogFile
                    }"REMOTEWMINOTAVAILABLE"{
                        Add-Log -StringInput "Start-ServerPatching is unable to connect to WMI for server: $($ServerXML.HostName)" -File $global:LogFile
                        Add-Log -StringInput "" -Action 3 -File $global:LogFile
                    }"SHUTDOWN"{
                        Add-Log -StringInput "$($ServerXML.HostName) has been shutdown by Start-ServerPatching" -File $global:LogFile
                    }"RESTART"{
                        Add-Log -StringInput "$($ServerXML.HostName) has been restarted by Start-ServerPatching" -File $global:LogFile
                    }
                }
            }
            "SHUTDOWN"{
                Add-Log -StringInput "Completing Shutdown for: $($ServerXML.HostName)" -File $global:LogFile
                Stop-Computer -ComputerName $ServerXML.HostName -Confirm:$false
            }
            "RESTART"{
                Add-Log -StringInput "Completing Restart for: $($ServerXML.HostName)" -File $global:LogFile
                Restart-Computer -ComputerName $Server -Confirm:$false
            }
            "START"{
                Add-Log -StringInput "Attempting startup of $($ServerXML.HostName)" -File $global:LogFile
                if($($ServerXML.Type).toUpper() -eq "PHYSICAL"){
                    Add-Log -StringInput "Pausing for physical server power on. Please connect to required management interfaces manually." -File $global:LogFile -Action 3
                    #TODO: Add support for physical servers. Figure out some way to connect to iLo, IDRAC, UCS Manager  
                }else{
                    Add-Log -StringInput "Starting Server: $($ServerXML.HostName)" -File $global:LogFile
                    Get-VM $($ServerXML.HostName) | Start-VM -Confirm:$false
                    while ((get-service -name "Winmgmt" -computer $($ServerXML.HostName)).status -ne "Running"){
                        Add-Log "Waiting for server to come online"; 
                        start-sleep -s 1; 
                    }
                }
            }
            "NONE"{
                Add-Log -StringInput "No action has been specified for server: $($ServerXML.HostName)" -File $global:LogFile -Action 2
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
            Start-ClusterXML -Cluster $($XML.ChildNode)
        .NOTES
            This function makes use of the $global:LogFile, there is no error handling for a missing declaration
    #>
    [cmdletbinding()]
    Param(
        [Parameter(Position=0,mandatory=$true)]
        [Xml.XmlElement[]]$Cluster
    )#End of Param 
    Begin{
        $clusterNodes = @{}
        #TODO: XML validation.
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
                Add-Log -StringInput "$($Server.HostName) is in specified cluster" -File $Global:Logfile
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
                        Add-Log -StringInput $DumpError -File $Global:Logfile -Action 1
                        Add-Log -StringInput "" -File $Global:Logfile -Action 3
                    }
                }else{
                    'Start-ServerXML $Server'
                }
                $clusterNodes."$($Server.HostName)" = "XML Action Carried Out"
            }else{
                #XML Declared wrong. Not accounting for numbnuts.
                Add-Log -StringInput "$($Server.HostName) Not in Cluster, no actions have been carried out." -File $Global:Logfile -Action 2
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
            Add-Log -StringInput $DumpError -File $Global:Logfile -Action 1
            Add-Log -StringInput "" -File $Global:Logfile -Action 3
        }
        Add-Log -StringInput "Summary for actions completed against cluster: $($Cluster.Name)" -File $Global:Logfile
        foreach ($Node in $clusterNodes.GetEnumerator()) {
            Add-Log "$($Node.Name): $($Node.Value)" -File $Global:Logfile
        }
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
            Error - problem with patching
            MissingModule - Missing a required module for execution.
            NoVirtualHost - Unable to connect to management services
        .PARAMETER XMLFile
            The XML file dictating which servers are to be patched.
        .PARAMETER LogFile
            A specific file to provide output to, by default the script will output to C:\Temp\ComplexPatching<datetime>.log
        .PARAMETER virtualType
            Specify whether to load VMWare or HyperV Module for virtual server support.
        .PARAMETER virtualHost 
            Specify the Virtual management interface to connect to.
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
        [Parameter(Position=2,mandatory=$false)]
        [string]$virtualType,
        [Parameter(Position=3,mandatory=$false)]
        [string]$virtualHost
        #TODO: Add a full auto flag - No warning prompts or error pauses.
    )#End of Param
    Begin{
        [XML]$PatchData= get-content -Path $XMLFile
        if(!($Log) -or ($global:LogFile = "")){$global:LogFile = "c:\Temp\ComplexPowershellPatching.Log"}else{$Global:LogFile=$log}
        
        switch ($virtualType.ToUpper()){
            "HYPERV"{
                #TODO: Import-Module HyperV
            }
            "VMWARE"{
                #VMWare vCentre module required for startup/shutdown
                If(Get-Module -ListAvailable vmware.vimautomation.core){
                    If(!(Get-module vmware.vimautomation.core)) {
                        try{
                            Import-Module vmware.vimautomation.core -ErrorAction Stop
                        }catch{
                            Add-Log -StringInput "Failed to import module vmware.vimautomation.core" -File $global:LogFile -Action 1
                            return "MissingModule"
                        }    
                    }else{
                        Add-Log -StringInput "vmware.vimautomation.core is already loaded." -File $global:LogFile
                    }
                }else{
                    Add-Log -StringInput "Failed to find module vmware.vimautomation.core" -File $global:LogFile -Action 1
                    return "MissingModule"
                }
                try{
                    Connect-VIServer -Server $virtualHost -ErrorAction Stop
                }catch{
                    Add-Log "Unable to connect to Virtual Infrastructure Management Server" -File $global:LogFile -Action 1
                    return "NoVirtualHost"
                }
            }
            Default{
                Add-Log "WARNING: No virtual Server specified. Assuming all servers are physical and may require intervention." -File $global:LogFile -Action 2
            }
        }
        #Clustering Module for required work.
        If(Get-Module -ListAvailable FailoverClusters){
            If(!(Get-module FailoverClusters)) {
                try{
                    Import-Module FailoverClusters -ErrorAction Stop
                }catch{
                    Add-Log -StringInput "Failed to import module FailoverClusters" -File $global:LogFile -Action 1
                    return "MissingModule"
                }    
            }else{
                Add-Log -StringInput "FailoverClusters is already loaded." -File $global:LogFile
            }
        }else{
            Add-Log -StringInput "Failed to find module FailoverClusters" -File $global:LogFile -Action 1
            return "MissingModule"
        }
    }#End of Begin
    Process{
        Foreach($PatchingGroup in $PatchData.Patching.Group){
            Add-Log -StringInput "Processing Group $($PatchingGroup.name)" -File $global:LogFile
            #Foreach server/cluster. If server detected, $Device variable used to identify the server, if Cluster $Node is used to identify the server.
            foreach($XMLNode in $PatchingGroup.ChildNodes){
               if($XMLNode.Type -eq "Cluster"){
                    Add-Log -StringInput "Cluster has been found. ClusterName: $($XMLNode.ClusterName)" -File $global:LogFile
                    Add-Log -StringInput "Passing XML through to Start-ClusterXML" -File $global:LogFile
                    Start-ClusterXML -Cluster $XMLNode
               }elseif($XMLNode.Type -eq "Server"){
                    Add-Log -StringInput "XML Server Found. Hostname: $($XMLNode.name)" -File $global:LogFile
                    Add-Log -StringInput "Passing XML through to Start-ServerXML" -File $global:LogFile
                    Start-ServerXML -ServerXML $XMLNode
               }
            }
        }
    }#End of Process 
}#End of Function