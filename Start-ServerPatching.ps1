<# 
Start-ServerPatching
Author: James Auchterlonie
Version: 0.2
Last Modified: 12/04/18
Summary: This Function utilises the SCCM WMI module to install patches that are currently in an available state. 
Usage: Start-ServerPatching -Server <DC1>
Changelog:
0.1 - Basic WMI to get and complete server patches
0.2 - Control logic for patching
#>



Function Start-ServerPatching {
[cmdletbinding()]
Param(
    [string]$Server
) 
}

# End of Parameters
Process {
    $Server = "" 

    # Get the number of missing updates
    [System.Management.ManagementObject[]] $CMMissingUpdates = @(GWMI -ComputerName $server -query "SELECT * FROM CCM_SoftwareUpdate WHERE ComplianceState = '0'" -namespace "ROOT\ccm\ClientSDK") #End Get update count.
    $result.UpdateCountBefore = "The number of missing updates is $($CMMissingUpdates.count)"
    $updates = $CMMissingUpdates.count

    If ($updates) {
       #Install the missing updates.
       $CMInstallMissingUpdates = (GWMI -ComputerName $server -Namespace "root\ccm\clientsdk" -Class "CCM_SoftwareUpdatesManager" -List).InstallUpdates($CMMissingUpdates)
       Write-Host "Patching Initiated"
    } Else {
       $result.UpdateCountAfter = "There are no missing updates."
    }

    $reboot = 0

    #Wait for all updates to be ready, and reboot once complete.
    While($reboot -ne 1){
        #get status of updates
        $readyforreboot = 1
        foreach($patch in $CMMissingUpdates){
            $patchno = $patch | select -ExpandProperty ArticleID
            $query = "SELECT * FROM CCM_SoftwareUpdate WHERE ArticleID = '$patchno'"
            $wmiresult = (GWMI -ComputerName $server -query $query -namespace "ROOT\ccm\ClientSDK")
            #check on previous reboot status
            if($readyforreboot -eq 1){
                #if patch is not in desired state, do not reboot
                if(($wmiresult.EvaluationState -ne 9 -or 8 -or 12)){
                    $readyforreboot = 0
                }else{
                 
                }
                #Setup WMI behaviour based off: https://msdn.microsoft.com/library/jj155450.aspx
                Switch(@($wmiresult.EvaluationState)){
                    1{}
                    2{}
                    3{}
                    4{}
                    5{}
                    6{}
                    7{}
                    8{}
                    9{}
                    10{}
                    11{}
                    12{}
                    13{}
                    14{}
                    15{}
                    16{}
                    17{}
                    18{}
                    19{}
                    20{}
                    21{}
                    22{}
                    23{}
                    default{}
                }

            }       
        }
        #if all patches are good, reboot. Check for long running patching. 
        if($readyforreboot -eq 1){
            $reboot = 1
        }elseif($timeelapsed -gt "1:00:00"){
    
        }elseif($readyforreboot -eq 2){
            #exit with an error number. 
            exit 2
        }
    }
}