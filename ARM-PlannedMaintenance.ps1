function ListARMVMMetaData (
    [parameter(Mandatory=$true)][string[]]$SubscriptionArray) 
{

    Login-AzureRmAccount

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
                    $newVM | Add-Member -MemberType NoteProperty -Name "ImagePublisher" -Value $vmMetaData.StorageProfile.ImageReference.Publisher
                    $newVM | Add-Member -MemberType NoteProperty -Name "ImageSKU" -Value $vmMetaData.StorageProfile.ImageReference.Sku

                    if ($vmMetaData.storageprofile.OsDisk.ManagedDisk -ne $null) 
                    {
                        $newVM | Add-Member -MemberType NoteProperty -Name "IsManagedDisk" -Value $true
                    }
                    else {
                        $newVM | Add-Member -MemberType NoteProperty -Name "IsManagedDisk" -Value $false
                    }

                    ##Get the NIC information
                    ##First, loop through all the NICs
                    $niccount=0
                    foreach ($nic in $vmMetaData.NetworkProfile.NetworkInterfaces) {
                        $niccounter +=1
                        $nic=Get-AzureRmNetworkInterface -ResourceGroupName $rg.ResourceGroupName -Name $vmMetaData.NetworkProfile.NetworkInterfaces
                        $newVM | Add-Member -MemberType NoteProperty -Name "NICName$($niccounter)" -Value $nic.id.Split("/")[$nic.id.Split("/").Length-1]
                        
                        ##Now, for each NIC, loop through the ipconfigs
                        $ipconfigcounter=0
                        foreach ($ipconfig in $nic.IpConfigurations) {
                            $ipconfigcounter +=1
                            $newVM | Add-Member -MemberType NoteProperty -Name "ipconfigName$($ipconfigcounter)" -Value $ipconfig.Name
                            $newVM | Add-Member -MemberType NoteProperty -Name "IPAllocationType" -Value $ipconfig.PrivateIpAllocationMethod
                        }
                    }
  
                    $newVM | Add-Member -MemberType NoteProperty -Name "InternalIPType" -Value $vmMetaData.StorageProfile.ImageReference.Sku
                    foreach($ipconfig in $nic.IpConfigurations){write-host $ipconfig.name}

                    #start av set check
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
                   
                    if ($vmStatus.MaintenanceRedeployStatus -ne $null){
                        $newVM | Add-Member -MemberType NoteProperty -Name 'IsCustomerInitiatedMaintenanceAllowed' -Value $vmStatus.MaintenanceRedeployStatus.IsCustomerInitiatedMaintenanceAllowed
                        $newVM | Add-Member -MemberType NoteProperty -Name 'PreMaintenanceWindowStartTime' -Value $vmStatus.MaintenanceRedeployStatus.PreMaintenanceWindowStartTime
                        $newVM | Add-Member -MemberType NoteProperty -Name 'PreMaintenanceWindowEndTime' -Value $vmStatus.MaintenanceRedeployStatus.PreMaintenanceWindowEndTime
                        $newVM | Add-Member -MemberType NoteProperty -Name 'MaintenanceWindowStartTime' -Value $vmStatus.MaintenanceRedeployStatus.MaintenanceWindowStartTime
                        $newVM | Add-Member -MemberType NoteProperty -Name 'MaintenanceWindowEndTime' -Value $vmStatus.MaintenanceRedeployStatus.MaintenanceWindowEndTime
                        $newVM | Add-Member -MemberType NoteProperty -Name 'LastOperationResultCode' -Value $vmStatus.MaintenanceRedeployStatus.LastOperationResultCode
                    }
                    else{
                        $newVM | Add-Member -MemberType NoteProperty -Name 'IsCustomerInitiatedMaintenanceAllowed' "N/A - Rerun Jan 2 2018"
                        $newVM | Add-Member -MemberType NoteProperty -Name 'PreMaintenanceWindowStartTime' -Value $vmStatus.MaintenanceRedeployStatus.PreMaintenanceWindowStartTime
                        $newVM | Add-Member -MemberType NoteProperty -Name 'PreMaintenanceWindowEndTime' -Value $vmStatus.MaintenanceRedeployStatus.PreMaintenanceWindowEndTime
                        $newVM | Add-Member -MemberType NoteProperty -Name 'MaintenanceWindowStartTime' -Value $vmStatus.MaintenanceRedeployStatus.MaintenanceWindowStartTime
                        $newVM | Add-Member -MemberType NoteProperty -Name 'MaintenanceWindowEndTime' -Value $vmStatus.MaintenanceRedeployStatus.MaintenanceWindowEndTime
                        $newVM | Add-Member -MemberType NoteProperty -Name 'LastOperationResultCode' -Value $vmStatus.MaintenanceRedeployStatus.LastOperationResultCode
                    }
                    #end maintenance properties


                    $VMs += $newVM

                    ##Write-Output "Status $($vmStatus)"
                    ##Write-Output "Status $($vmMetaData)"          
                  }
            }

            try {
                $VMCSV = $directory + "\" + $subscription.Name + '-' + $subscription.Id + ".csv"
                ##export the updates for VM information
                Write-Host "Exporting VMs to CSV" 
                if (Test-Path -Path $VMCSV)
                {
                    Remove-Item $VMCSV
                }
                $VMs | Export-Csv $VMCSV -notypeinformation
                Write-Host "Exported topic updates to $($VMCSV)" -ForegroundColor Green
            }
            catch {
                Write-Host "Unable to export CSV" -ForegroundColor Red
                Exit
            }

            $VMs = @()
    }
}

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

#Login-AzureRmAccount

#pull specific subs by subscription id in array format - comma separate values
$subs=@("27b2ee0a-4093-4253-95b5-c595487ad66f")
ListARMVMMetaData -SubscriptionArray $subs

#pull subs based on what you have access to with optional array range parameter
#$subs = Get-AzureRmSubscription
#ListARMVMMetaData -SubscriptionArray $subs[0..2]

#CommaSubs "ListofMySubsOnePerLine.txt"

