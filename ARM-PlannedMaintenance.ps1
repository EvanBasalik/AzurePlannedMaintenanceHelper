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
#ListARMVMMetaData -SubscriptionArray $
#
#.EXAMPLE
#Takes the array and get various pieces of VM data plus converts any dynamic private IPs to static private IPs
#$subs=@("YourSubsHere")
#ListARMVMMetaData -SubscriptionArray $subs -ConvertDynamicPrivateIPstoStatic
#
#.EXAMPLE
#Takes the array and get various pieces of VM data
#ListARMVMMetaData -SubscriptionArray $subs
#
#.EXAMPLE
#Gets all the subs to which you have access
#$subs = Get-AzureRmSubscription
#ListARMVMMetaData -SubscriptionArray $subs[0..2]
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
function ListARMVMMetaData (
    [parameter(Mandatory=$true)][string[]]$SubscriptionArray,
    [parameter(Mandatory=$false)][switch]$SingleFileOutput,
    [parameter(Mandatory=$false)][switch]$ConvertDynamicPrivateIPstoStatic
    ) 
{

    #check if we need to log in
    $context =  Get-AzureRmContext
    if ($context.Environment -eq $null) {
        Login-AzureRmAccount
    }

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
        Select-AzureRmSubscription -SubscriptionId $subId
        $subscription = Get-AzureRmSubscription -SubscriptionId $subId
        $subName = $subscription.Name
        Write-Output "Evaluating subscription $subName - $subId"
        
            $rgList= Get-AzureRmResourceGroup 
        
            for ($rgIdx=0; $rgIdx -lt $rgList.Length ; $rgIdx++)
            {
                $rg = $rgList[$rgIdx]
                Write-Output "Evaluating resource group $($rg.ResourceGroupName)"    
                $vmList = Get-AzureRMVM -ResourceGroupName $rg.ResourceGroupName 
                $avsets = Get-AzureRmAvailabilitySet -ResourceGroupName $rg.ResourceGroupName
                
                for ($vmIdx=0; $vmIdx -lt $vmList.Length ; $vmIdx++)
                {

                    ##object to hold the VM properties
                    $newVM = New-Object psobject

                    $newVM | Add-Member -MemberType NoteProperty -Name "SubscriptionName" -Value $subscription.Name
                    $newVM | Add-Member -MemberType NoteProperty -Name "SubscriptionId" -Value $subscription.Id

                    $vm = $vmList[$vmIdx]
                    $newVM | Add-Member -MemberType NoteProperty -Name "Name" -Value $vm.Name

                    $vmStatus = Get-AzureRMVM -ResourceGroupName $rg.ResourceGroupName -Name $vm.Name -Status
                    $vmMetaData = Get-AzureRMVM -ResourceGroupName $rg.ResourceGroupName -Name $vm.Name
                    Write-Output "Evaluating VM: $($vmStatus.Name)"

                    ##Get the image name
                    Write-Host "Getting image information" -ForegroundColor Yellow
                    $newVM | Add-Member -MemberType NoteProperty -Name "ImagePublisher" -Value $vmMetaData.StorageProfile.ImageReference.Publisher
                    $newVM | Add-Member -MemberType NoteProperty -Name "ImageSKU" -Value $vmMetaData.StorageProfile.ImageReference.Sku

                    Write-Host "Getting disk type" -ForegroundColor Yellow
                    if ($vmMetaData.storageprofile.OsDisk.ManagedDisk -ne $null) 
                    {
                        $newVM | Add-Member -MemberType NoteProperty -Name "IsManagedDisk" -Value $true
                    }
                    else {
                        $newVM | Add-Member -MemberType NoteProperty -Name "IsManagedDisk" -Value $false
                    }

                    ##Get the NIC information
                    ##First, loop through all the NICs
                    Write-Host "Getting NIC and IPConfig information" -ForegroundColor Yellow
                    $niccount=0
                    foreach ($nic in $vmMetaData.NetworkProfile.NetworkInterfaces) {
                        $niccounter +=1
                        $nicinternal=Get-AzureRmNetworkInterface -ResourceGroupName $rg.ResourceGroupName -Name $nic.id.Split("/")[$nic.id.Split("/").Length-1]
                        $newVM | Add-Member -MemberType NoteProperty -Name "NIC$($niccounter)Name" -Value $nicinternal.Name
                        
                        ##Now, for each NIC, loop through the ipconfigs
                        $ipconfigcounter=0
                        foreach ($ipconfig in $nicinternal.IpConfigurations) {
                            $ipconfigcounter +=1
                            $newVM | Add-Member -MemberType NoteProperty -Name "ipconfig$($ipconfigcounter)Name" -Value $ipconfig.Name
                            $newVM | Add-Member -MemberType NoteProperty -Name "ipconfig$($ipconfigcounter)IPAllocationType" -Value $ipconfig.PrivateIpAllocationMethod
                            $newVM | Add-Member -MemberType NoteProperty -Name "ipconfig$($ipconfigcounter)PrivateIPAddress" -Value $ipconfig.PrivateIpAddress

                            #if PrivateIpAllocationMethod=Dynamic and $ConvertDynamicPrivateIPstoStatic=$true
                            #then convert to Static
                            if ($ipconfig.PrivateIpAllocationMethod -eq "Dynamic")
                            {
                                Write-Host "$($ipconfig.Name) for $($nicinternal.Name) is Dynamic" -ForegroundColor Red
                                if ($ConvertDynamicPrivateIPstoStatic) {
                                    ConvertPrivateIPConfigtoStatic -NICName $nicinternal.Name -NICResourceGroup $nicinternal.ResourceGroupName -ipconfigIdx $nicinternal.IpConfigurations.IndexOf($ipconfig)
                                }
                            }
                        }
                    }

                    #start av set check
                    Write-Host "Checking Availability Sets" -ForegroundColor Yellow
                    $avsetReferenceFound = $false

                    foreach($avset in $avsets){
                        $vmavset = $avset.VirtualMachinesReferences | Where-Object {$_.Id -eq $vm.Id}
                        if($vmavset -ne $null){
                            $newVM | Add-Member -MemberType NoteProperty -Name "InAvailabilitySet" -Value $true
                            $newVM | Add-Member -MemberType NoteProperty -Name "AvailabilitySetName" -Value $avset.Name
                            $avsetReferenceFound = $true
                            break
                        }
                    }

                    if($avsetReferenceFound -eq $false){
                        $newVM | Add-Member -MemberType NoteProperty -Name "InAvailabilitySet" -Value $false
                        $newVM | Add-Member -MemberType NoteProperty -Name "AvailabilitySetName" -Value ''
                    }

                    $avsetReferenceFound = $false
                    #end av set check

                    #check for sql match
                    if($vm.Name -match 'sql' -or $vmMetadata.StorageProfile.ImageReference.Publisher -match 'sql' -or $vm.Name -match 'db'){
                        $newVM | Add-Member -MemberType NoteProperty -Name 'PotentialSQLMatch' -Value $true
                    }
                    else{
                        $newVM | Add-Member -MemberType NoteProperty -Name 'PotentialSQLMatch' -Value $false
                    }
                    #end check for sql match

                    #maintenance properties
                    Write-Host "Checking Maintenance status" -ForegroundColor Yellow
                    if ($vmStatus.MaintenanceRedeployStatus -ne $null){
                        $newVM | Add-Member -MemberType NoteProperty -Name 'IsCustomerInitiatedMaintenanceAllowed' -Value $vmStatus.MaintenanceRedeployStatus.IsCustomerInitiatedMaintenanceAllowed
                        $newVM | Add-Member -MemberType NoteProperty -Name 'PreMaintenanceWindowStartTime' -Value $vmStatus.MaintenanceRedeployStatus.PreMaintenanceWindowStartTime
                        $newVM | Add-Member -MemberType NoteProperty -Name 'PreMaintenanceWindowEndTime' -Value $vmStatus.MaintenanceRedeployStatus.PreMaintenanceWindowEndTime
                        $newVM | Add-Member -MemberType NoteProperty -Name 'MaintenanceWindowStartTime' -Value $vmStatus.MaintenanceRedeployStatus.MaintenanceWindowStartTime
                        $newVM | Add-Member -MemberType NoteProperty -Name 'MaintenanceWindowEndTime' -Value $vmStatus.MaintenanceRedeployStatus.MaintenanceWindowEndTime
                        $newVM | Add-Member -MemberType NoteProperty -Name 'LastOperationResultCode' -Value $vmStatus.MaintenanceRedeployStatus.LastOperationResultCode
                    }
                    else{
                        $newVM | Add-Member -MemberType NoteProperty -Name 'IsCustomerInitiatedMaintenanceAllowed' -Value "N/A - VM is likely deallocated"
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
                    $VMCSV = $directory + "\" + "AllSubscriptions-$($dt).csv"
                }
                else {
                    $VMCSV = $directory + "\" + $subscription.Name + '-' + $subscription.Id + "-$($dt).csv"
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

##############################
#.SYNOPSIS
#Converts a file consisting of a list of subscriptions (one per line) into a comma-separated list
#
#.PARAMETER inputFile
#File that contains the list of subscriptions (one per line)
#
#.EXAMPLE
#CommaSubs -inputFile MySubscriptionList
#
#.NOTES
#Most outputs of Azure subscriptions list them once per line, but most cmdlets want an array
##############################
function CommaSubs (
    [parameter(Mandatory=$true)][string]$inputFile)
    {
    $sublist = Get-Content -Path $inputFile
    for ($i = 0; $i -lt $sublist.Count-1; $i++) {
        $fulllist += $sublist[$i]
        $fulllist += ","
    }
    
    ##need to do the last one without a comma at the end
    $fulllist += $sublist[$sublist.Count-1]
    $fulllist |Out-File merged.txt -Force
}

##############################
#.SYNOPSIS
#Converts the specified ipconfiguration from dynamic to static
#
#.PARAMETER NICName
#Name of the NIC which has the ipconfiguration which needs to be converted to static
#
#.PARAMETER NICResourceGroup
#Resource group of the NIC which has the ipconfiguration which needs to be converted to static
#
#.PARAMETER ipconfigIdx
#In the arrary of ipconfigs for the NIC, the index of the one to be converted
#
#.EXAMPLE
#ConvertPrivateIPConfigtoStatic -NICName myNIC -NICResourceGroup MyResourceGroup -ipconfigIdx 0 (most NICs will have one ipconfg)
#
##############################
function ConvertPrivateIPConfigtoStatic (
    [parameter(Mandatory=$true)][string]$NICName,
    [parameter(Mandatory=$true)][string]$NICResourceGroup,
    [parameter(Mandatory=$true)][int]$ipconfigIdx
    ) 
{
    Write-Host "Converting $($NICName) to Static" -ForegroundColor Yellow
    $nic = Get-AzureRmNetworkInterface -ResourceGroupName $NICResourceGroup -Name $NICName
    $nic.IpConfigurations[$ipconfigIdx].PrivateIpAllocationMethod = "Static"
    Set-AzureRmNetworkInterface -NetworkInterface $nic 
    Write-Host "Converted $($NICName) to Static" -ForegroundColor Green
}

#MySubs.txt is a list of subs, one per line
[array]$subs=Get-Content -Path "MySubs.txt"
ListARMVMMetaData -SubscriptionArray $subs -SingleFileOutput

