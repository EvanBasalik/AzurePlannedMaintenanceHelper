##############################
#.SYNOPSIS
#Given one or more subscriptions, iterates through all the IaaS VMs in the subscription
#and pull various pieces of metadata from which it creates a CSV for easy analysis
#
#.PARAMETER SubscriptionArray
#Comma-separated list of subscriptions
#
#.PARAMETER ConvertDynamicPrivateIPstoStatic
#If passed, converts any detected dynamic private IPs into static private IPs
#
#.EXAMPLE
#MySubs.txt is a list of subs, one per line
#[array]$subs=Get-Content -Path "MySubs.txt"
#ListASMVMMetaData -SubscriptionArray $
#
#.EXAMPLE
#Takes the array and get various pieces of VM data plus converts any dynamic private IPs to static private IPs
#$subs=@("YourSubsHere")
#ListASMVMMetaData -SubscriptionArray $subs -ConvertDynamicPrivateIPstoStatic
#
#.EXAMPLE
#Takes the array and get various pieces of VM data
#ListASMVMMetaData -SubscriptionArray $subs
#
#.EXAMPLE
#Gets all the subs to which you have access
#$subs = Get-AzureRmSubscription
#ListASMVMMetaData -SubscriptionArray $subs[0..2]
#
#.NOTES
#Sample scripts are not supported under any Microsoft standard support program or service. 
#The sample scripts are provided AS IS without warranty of any kind. Microsoft disclaims all 
#implied warranties including, without limitation, any implied warranties of merchantability
#or of fitness for a particular purpose. The entire risk arising out of the use or performance
#of the sample scripts and documentation remains with you. In no event shall Microsoft, its 
#authors, or anyone else involved in the creation, production, or delivery of the scripts be 
#liable for any damages whatsoever (including, without limitation, damages for loss of business
#profits, business interruption, loss of business information, or other pecuniary loss) arising
#out of the use of or inability to use the sample scripts or documentation, even if Microsoft 
#has been advised of the possibility of such damages.
##############################
function ListASMVMMetaData (
    [parameter(Mandatory=$true)][string[]]$SubscriptionArray,
    [parameter(Mandatory=$false)][switch]$SingleFileOutput,
    [parameter(Mandatory=$false)][switch]$ConvertDynamicPrivateIPstoStatic
    ) 
{

    #check if we need to log in
    #need to find an easy was to mimic Get-AzureRMContext for ASM
    Add-AzureAccount

    ##define array to hold the evaluated VMs
    [array]$VMs = @()
    $today=Get-Date
    #$VMCSV = "VMData - $($today.Month)-$($today.Day)-$($today.Hour)$($today.Minute)$($today.Second).csv"
    $directory = 'C:\AzurePlannedMaintenance\'
    
    #generate directory for maintenance output
    If(!(test-path $directory)){
        New-Item -ItemType Directory -Force -Path $directory
    }

    foreach ($sub in $SubscriptionArray) 
    {
        $subId = $null
        if($sub.Id -ne $null){
            $subId = $sub.Id
        }
        else{
            $subId = $sub
        }
        
        Write-Output ""
        Select-AzureSubscription -SubscriptionId $subId
        $subscription = Get-AzureSubscription -SubscriptionId $subId
        $subName = $subscription.Name
        Write-Output "Evaluating subscription $subName - $subId"
        
            $serviceList= Get-AzureVM | Group-Object -Property ServiceName 

            for ($svIdx=0; $svIdx -lt $serviceList.Length ; $svIdx++)
            {
                $sv = $serviceList[$svIdx]
                Write-Output "Evaluating cloud service $($sv.Name)"    
                $vmList = Get-AzureVM -ServiceName $sv.Name
                
                for ($vmIdx=0; $vmIdx -lt $vmList.Length ; $vmIdx++)
                {

                    ##object to hold the VM properties
                    $newVM = New-Object psobject

                    $newVM | Add-Member -MemberType NoteProperty -Name "SubscriptionName" -Value $subscription.Name
                    $newVM | Add-Member -MemberType NoteProperty -Name "SubscriptionId" -Value $subscription.Id

                    $vm = $vmList[$vmIdx]
                    $newVM | Add-Member -MemberType NoteProperty -Name "Name" -Value $vm.Name
                    $newVM | Add-Member -MemberType NoteProperty -Name "Service" -Value $sv.Name

                    $vmMetaData = Get-AzureVM -ServiceName $sv.Name -Name $vm.Name
                    Write-Output "Evaluating VM: $($vmMetaData.Name)"

                    ##Get the image name
                    Write-Host "Getting image information" -ForegroundColor Yellow
                    $newVM | Add-Member -MemberType NoteProperty -Name "ImagePublisher" -Value $vmMetaData.VM.OSVirtualHardDisk.OS
                    #split location
                    $split=$vmMetaData.VM.OSVirtualHardDisk.SourceImageName.IndexOf("__")+2
                    $newVM | Add-Member -MemberType NoteProperty -Name "ImageOS" -Value $vmMetaData.VM.OSVirtualHardDisk.SourceImageName.Substring($split,$vmMetaData.VM.OSVirtualHardDisk.SourceImageName.length-$split).Replace(".vhd","")

                    ##Get the IP address
                    ##First, loop through all the NICs
                    Write-Host "Getting IP address information" -ForegroundColor Yellow
                    $newVM | Add-Member -MemberType NoteProperty -Name "PrivateIPAddress" -Value  $vmmetadata.IpAddress
                    $newVM | Add-Member -MemberType NoteProperty -Name "IPAllocationType" -Value ""

                    #call out PIPs b/c there is no way to make them static
                    if ($vmMetaData.PublicIPAddress -ne $null) {
                        Write-Host "WARNING! $($vmmetadata.Name) has a PIP. There is no way to do a STOP and preserve it"
                        $newVM | Add-Member -MemberType NoteProperty -Name "HasPIP" -Value $true
                        $newVM | Add-Member -MemberType NoteProperty -Name "PIP" -Value $vmmetadata.PublicIPAddress
                    }

                    #start av set check
                    Write-Host "Checking Availability Sets" -ForegroundColor Yellow
                    if($vmmetadata.AvailabilitySetName -ne $null){
                        $newVM | Add-Member -MemberType NoteProperty -Name "InAvailabilitySet" -Value $true
                        $newVM | Add-Member -MemberType NoteProperty -Name "AvailabilitySetName" -Value $vmmetadata.AvailabilitySetName
                    }
                    else {
                        $newVM | Add-Member -MemberType NoteProperty -Name "AvailabilitySetName" -Value ''
                    }

                    #check for sql match
                    if($vm.Name -match 'sql' -or $newVM.ImageOS -match 'sql' -or $vm.Name -match 'db'){
                        $newVM | Add-Member -MemberType NoteProperty -Name 'PotentialSQLMatch' -Value $true
                    }
                    else{
                        $newVM | Add-Member -MemberType NoteProperty -Name 'PotentialSQLMatch' -Value $false
                    }
                    #end check for sql match

                    #maintenance properties
                    Write-Host "Checking Maintenance status" -ForegroundColor Yellow
                    if ($vm.MaintenanceStatus -ne $null){
                        $newVM | Add-Member -MemberType NoteProperty -Name 'IsCustomerInitiatedMaintenanceAllowed' -Value $vmStatus.MaintenanceStatus.IsCustomerInitiatedMaintenanceAllowed
                        $newVM | Add-Member -MemberType NoteProperty -Name 'PreMaintenanceWindowStartTime' -Value $vmStatus.MaintenanceStatus.PreMaintenanceWindowStartTime
                        $newVM | Add-Member -MemberType NoteProperty -Name 'PreMaintenanceWindowEndTime' -Value $vmStatus.MaintenanceStatus.PreMaintenanceWindowEndTime
                        $newVM | Add-Member -MemberType NoteProperty -Name 'MaintenanceWindowStartTime' -Value $vmStatus.MaintenanceStatus.MaintenanceWindowStartTime
                        $newVM | Add-Member -MemberType NoteProperty -Name 'MaintenanceWindowEndTime' -Value $vmStatus.MaintenanceStatus.MaintenanceWindowEndTime
                        $newVM | Add-Member -MemberType NoteProperty -Name 'LastOperationResultCode' -Value $vmStatus.MaintenanceStatus.LastOperationResultCode
                    }
                    else{
                        $newVM | Add-Member -MemberType NoteProperty -Name 'IsCustomerInitiatedMaintenanceAllowed' -Value "VM doesn't need maintenance"
                    }
                    #end maintenance properties

                    $VMs += $newVM

                    ##Write-Output "Status $($vmStatus)"
                    ##Write-Output "Status $($vmMetaData)"          
                  }
            }

            try {
                $dt="$($today.Month)-$($today.Day)-$($today.Hour)$($today.Minute)$($today.Second)"
                if ($SingleFileOutput) {
                    $VMCSV = $directory + "AllSubscriptions-$($dt).csv"
                }
                else {
                    $VMCSV = $directory + $subscription.Name + '-' + $subscription.Id + "-$($dt).csv"
                }
                ##export the updates for VM information
                Write-Host "Exporting VM data to CSV" 
                $VMs | Export-Csv $VMCSV -notypeinformation -Append
                Write-Host "Exported VM data to $($VMCSV)" -ForegroundColor Green
            }
            catch {
                Write-Host "Unable to export CSV" -ForegroundColor Red
                Exit
            }

            $VMs = @()
    }
}


[array]$subs=Get-Content -Path "MySubs.txt"
ListASMVMMetaData -SubscriptionArray $subs -SingleFileOutput