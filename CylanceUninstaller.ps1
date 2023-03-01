param (
    # Required for CLI, Optional for UI
    # Specify if the safemode is set to Yes/No. 
    #   Yes will allow you to test the script without making any system changes
    #   No will allow for deleting/modification of system.
    $safemode, 

    # Required for CLI, Optional for UI
    # Specify Yes if you have attempted to uninstall Protect at least once.
    $attempteduninstall
)

if ($safemode -eq "No") {
    $global:SkipPauseAfter10s = "Yes"
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$ScriptInfo = '
 *************************************************************************************************************************
 *  Support Script: Uninstall_Cleanup_EPP_EDR.ps1
 *  Created: 06/13/2022 by SDS
 *  Updated: 11/23/2022 by SDS
 *  Version: 2.9
 *  Tracked via: SDT00052661
 *  Description: Script to automate the windows cleanup of Cylance Protect and Cylance Optics - KB 66473
 *  
 *  Instructions for running script:
 *    1. Run the script with the safemode flag set to "yes" to see what the script will do without making any deletes/removes
 *    2. When ready to make changes, set the safemode flag set to "No"
 *    3. Run the script (as Administrator) to make the changes
 *       Set-ExecutionPolicy RemoteSigned
 *    4. Its likely you may need to reboot and re-run the script again
 *
 *  You may also run the script using NT AUTHORITY\SYSTEM using psexec (/k to .exe should be in single quotes)
 *    1. Start-Process -FilePath cmd.exe -Verb Runas -ArgumentList /k C:\PsExec.exe -i -s powershell.exe
 *    2. .\Uninstall_Cleanup_EPP_EDR.ps1
 * 
 * Switches:
 *   -safemode Yes/No (safemode Yes will not make any changes)
 *   -attempteduninstall Yes (suppress any warnings advising have you attempted to uninstall once)
 *
 * Example for unintended runs
 * Example: .\Uninstall_Cleanup_EPP_EDR.ps1 -safemode No -attempteduninstall Yes
 * Example: .\Uninstall_Cleanup_EPP_EDR.ps1 -safemode Yes -attempteduninstall Yes
 *
 *************************************************************************************************************************
'

function Check-Permissions {
    
    # Settings Varibales required for log folder creation and transscript logging
    $global:DateTime = ""
    $global:FolderName = ""
    $global:Folder = ""
    $global:dirPath = ""
    $global:DateTime = $(get-date -f yyyy-MM-dd_hh_mm);
    $global:FolderName = "Protect_Uninstall_Results";
    $global:Folder = $global:FolderName + "_" + $global:DateTime;
    $global:dirPath = $PSScriptRoot + "\" + $global:Folder
    try {
        New-Item -ItemType directory -Path $global:dirPath
        write-host ""
    }
    catch {
        write-Warning "Exception caught";
        write-Warning "$_";
        Exit 1;

    }

    write-host $ScriptInfo
    Start-Transcript -path $global:dirPath\Transcript_log.txt -Append #Start logging from this point
    write-host ""
    write-host ""
    write-host "Starting Script via: .\Uninstall_Cleanup_EPP_EDR.ps1 -safemode $safemode -attempteduninstall $attempteduninstall"
    write-host ""

    # Start of Check-Permissions
    Write-Host "Checking for elevated permissions..."
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
                [Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Warning "Insufficient permissions to run this script. Open the PowerShell console as an administrator and run this script again."
        write-host ""
        write-host ""
        Break
    }
    else {
        Write-Host "Script is running as administrator..." -ForegroundColor Green
        $whoami = ""
        $whoami = (whoami)
        Write-Host "User: $whoami"
        Write-Host ""
    }
} # End of Check-Permissions

function Check_DisableRegistryTools {
    if (Test-Path -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System") {
        $global:Originalkey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        $HiveAbr = $global:Originalkey.Substring(0, $global:Originalkey.IndexOf(':'))
        $Hivepath = $global:Originalkey.Substring($global:Originalkey.IndexOf('\') + 1)
        Write-Host ""
        Write-Host "Checking if DisableRegistryTools is enabled in the Registry"
        try { 
            $DisableRegistryTools = (Get-ItemProperty HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -ErrorAction Stop).DisableRegistryTools
        }
        catch {
            # Start catch
            write-Warning "Exception caught";
            write-Warning "$_";
        } # End catch
    
        If ( $DisableRegistryTools -eq 2) {
            Write-Host " 'DisableRegistryTools' is Enabled($DisableRegistryTools)" -fore Yellow
            Write-Host "Exiting Script as we cant make registry changes" -fore Red
            Exit 1;
        }
        else {
            Write-Host " 'DisableRegistryTools' is not Enabled";
        }
    }
    else {
        Write-Host " 'DisableRegistryTools' is not Enabled";
    }
} # End of check GPO DisableRegistryTools

function variables {
    # Start of Variables for script
    # This is where we will hold any Variables for the script
    $global:safemode = $safemode
    $KeyName = ""
    $MultiStringValue = ""
    $Registrykeys = ""
    $Result = ""
    $global:Continue = ""
    $global:KWildcard = ""
    $global:MultiStringName = ""
    $global:Originalkey = ""
    $global:RegOutputFile = ""
    $global:RegistryPath = ""
    $global:RemoveDelete_Value = ""
    $global:SafeExportName = ""
    $global:SafeFileName = ""
    $global:Servicevalue = ""
    $installed = ""

    if ($global:safemode -eq $null -or $global:safemode -eq '') {
        ###################################################################################################
        ###########################    THE ONLY VALUE YOU SHOULD CHANGE IS THIS ###########################
        ###################################################################################################
        
        $global:safemode = "No"; # Change this to "No" to make edits to the registry. "Yes" will allow the script to run but not change anything
        
        ###################################################################################################
        ###########################    THE ONLY VALUE YOU SHOULD CHANGE IS THIS ###########################
        ###################################################################################################

    }
    else {
        Write-Host "safemode was set via CLI to: $global:safemode"
    }
    
    if ($global:safemode -eq "Yes") {
        Write-Host "safemode is Enabled. No Changes will be made" -ForegroundColor Green
    }
    elseif ($global:safemode -eq "No") {
        Write-Warning "safemode is Disbaled. Changes will be made"
        if ($global:SkipPauseAfter10s -eq "Yes") {
            Write-Host "Pausing for 10s"
            Start-Sleep -Seconds 5
        }
        else {
            pause
        }
        
    }

    if ($global:AttemptedUninstall -eq $null -or $global:AttemptedUninstall -eq '') {
        Write-Host "attempteduninstall was not set via cli. Will prompt user"
    }
    else {
        Write-Host "AttemptedUninstall was set via CLI to: $global:AttemptedUninstall"
    }

    # NO NEED TO CHANGE THESE BUT ADDED FOR DEBUGGING
    $global:MultiStringName = "UpperFilters"; # UpperFilters is the name of the Multi-String Name
    $global:RemoveDelete_Value = "CyDevFlt"; # CyDevFlt is the name of the value to remove
    $global:RemoveDelete_Value2 = "CyDevFltV2"; # CyDevFlt is the name of the value to remove
    $global:RegistryPath = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\class";
    
} # End of Variables for script

function Check_Add/Remove {
    # Start check to see if EPP/EDR is installed
    if ($attempteduninstall -ne "Yes" ) {
        # Start we can skip this as cli has already stated they tried to uninstall 
        ## The following four lines only need to be declared once in your script.
        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Description."
        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Description."
        $cancel = New-Object System.Management.Automation.Host.ChoiceDescription "&Cancel", "Description."
        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no, $cancel)
        $software = ""
        $software = @(
            'Cylance OPTICS',
            'Cylance PROTECT',
            'Cylance Unified Agent'
            #'Cylance Platform' # Installed With DLP 1.0 | Persona 1.3
            #'CylanceGATEWAY' # Gateway 2.5
            #'CylanceAVERT' # DLP 1.0
            #'CylanceAVERT and Platform' # DLP 1.0
            #'BlackBerry Persona Agent' # Installed with Persona 1.3
        )

        $i = ""
        foreach ($i in $software) {
            # Start foreach loop
            $installed = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where { $_.DisplayName -eq $i }) -ne $null

            If (-Not $installed) {
                Write-Host "'$i' NOT is installed. Safe to continue";
                $global:Continue = "Yes";

            }
            else {
                Write-Host ""
                Write-Warning "'$i' is installed.";
                Write-Warning "Please ensure you have attempted to uninstall '$i' from Add/Remove programs before continuing";
    
                ## Use the following each time your want to prompt the use
                $title = "Found '$i' in Add/Remove" 
                $message = "Have you have attempted to uninstall '$i' via Add/Remove?"
                $result = $host.ui.PromptForChoice($title, $message, $options, 1)
                switch ($result) {
                    0 {
                        Write-Host "Yes"
                        $global:Continue = "Yes"
                    }1 {
                        Write-Host "No"
                        $global:Continue = "No"
                        exit 1
                        Stop-Transcript
                    }2 {
                        Write-Host "Cancel"
                        $global:Continue = "No"
                        exit 1
                        Stop-Transcript
                    }
                }

            } # End else
        } # End foreach loop
    }
    else {
        $global:Continue = "Yes";
    }# End we can skip this as cli has already stated they tried to uninstall
} # End check to see if Protect/Optics is installed

function modify-Self-Protection-Desktop {
    # Start We need to ensure that Self Protection is enabled and set to Local Admin
    # Ensure that the Cylance\Desktop Key exists
    if (Test-Path -Path "HKLM:\SOFTWARE\Cylance\Desktop") {
        $global:Originalkey = "HKLM:\SOFTWARE\Cylance\Desktop"
        $HiveAbr = $global:Originalkey.Substring(0, $global:Originalkey.IndexOf(':'))
        $Hivepath = $global:Originalkey.Substring($global:Originalkey.IndexOf('\') + 1)
        Write-Host ""
        Write-Host "Checking if SelfProtection Level is enabled in the Registry"
        # Within the Cylance\Desktop Key, check for SelfProtectionLevel DWORD
        try { 
            $SelfProtectionLevel = (Get-ItemProperty HKLM:\SOFTWARE\Cylance\Desktop -ErrorAction Stop).SelfProtectionLevel
        }
        catch {
            # Start catch
            write-Warning "Exception caught";
            write-Warning "$_";
        } # End catch

        If ( $SelfProtectionLevel -eq 0 -or $SelfProtectionLevel -eq 2) {
            Write-Host " 'SelfProtectionLevel' is Disabled($SelfProtectionLevel)";
            Write-Host "  Changing 'SelfProtectionLevel' to Enabled(1)";
            if ($global:safemode -eq "No") {
    
                Write-Host " Taking Ownership of $global:Originalkey"
                try {
                    Take-Permissions $HiveAbr $Hivepath
                }
                catch {
                    # Start catch
                    write-Warning "Exception caught";
                    write-Warning "$_";
                } # End catch

                try { 
                    #TODO: We need to restart service after this
                    Set-ItemProperty -Path "HKLM:\SOFTWARE\Cylance\Desktop" -Name "SelfProtectionLevel" -Value 1;
                    if ($LASTEXITCODE -eq 1) {
                        write-Warning "Exception caught";
                        exit 1
                        Stop-Transcript;
                    }
                }
                catch {
                    # Start catch
                    write-Warning "Exception caught";
                    write-Warning "$_";
                } # End catch
            }
            else {
                Write-Host " **** safemode: No changes have been made ****"
            } # End safemode Check
        }
        elseif ( $SelfProtectionLevel -eq 1) {
            Write-Host " 'SelfProtectionLevel' is Enabled(1)";
            # Local Administrators can make changes to the registry and services.
        }
        elseIf ( !$SelfProtectionLevel) {
            Write-Host ""	
            Write-Host " 'SelfProtectionLevel' is Missing";
            Write-Host "  Creating 'SelfProtectionLevel' with to Enabled(1)";
            if ($global:safemode -eq "No") {
                Write-Host " Taking Ownership of $global:Originalkey"
                try {
                    Take-Permissions $HiveAbr $Hivepath
                }
                catch {
                    # Start catch
                    write-Warning "Exception caught";
                    write-Warning "$_";
                } # End catch        
        
                try { 
                    #TODO: We need to restart the service after this call
                    New-ItemProperty -Path "HKLM:\SOFTWARE\Cylance\Desktop" -Name 'SelfProtectionLevel' -Value 1 -PropertyType DWord -ErrorAction Stop;
                }
                catch {
                    # Start catch
                    write-host "Exception caught";
                    write-host "$_";
                } # End catch
            }
            else {
                Write-Host " **** safemode: No changes have been made ****"
            } # End safemode Check
        }
        else {
            Write-Host "'SelfProtectionLevel' Unknown Error";
            Write-Host "SelfProtectionLevel: $SelfProtectionLevel"
        }

    }
    else {
        Write-host ""    
        Write-host "Path does not exist: HKLM:\SOFTWARE\Cylance\Desktop"
    } # End If Test-Path

} # End we need to ensure that Self Protection is enabled and set to Local Admin for Protect

function modify-Self-Protection-Optics {
    # Start We need to ensure that Self Protection is enabled and set to Local Admin
    # Ensure that the Cylance\Optics Key exists
    if (Test-Path -Path "HKLM:\SOFTWARE\Cylance\Optics") {
        $global:Originalkey = "HKLM:\SOFTWARE\Cylance\Optics"
        $HiveAbr = $global:Originalkey.Substring(0, $global:Originalkey.IndexOf(':'))
        $Hivepath = $global:Originalkey.Substring($global:Originalkey.IndexOf('\') + 1)
        Write-Host ""
        Write-Host "Checking if SelfProtection Level is enabled in the Registry"
        # Within the Cylance\Optics Key, check for SelfProtectionLevel DWORD
        try { 
            $SelfProtectionLevel = (Get-ItemProperty HKLM:\SOFTWARE\Cylance\Optics -ErrorAction Stop).SelfProtectionLevel
        }
        catch {
            # Start catch
            write-Warning "Exception caught";
            write-Warning "$_";
        } # End catch

        If ( $SelfProtectionLevel -eq 0 -or $SelfProtectionLevel -eq 2) {
            Write-Host " 'SelfProtectionLevel' is Disabled($SelfProtectionLevel)";
            Write-Host "  Changing 'SelfProtectionLevel' to Enabled(1)";
            if ($global:safemode -eq "No") {
    
                Write-Host " Taking Ownership of $global:Originalkey"
                try {
                    Take-Permissions $HiveAbr $Hivepath
                }
                catch {
                    # Start catch
                    write-Warning "Exception caught";
                    write-Warning "$_";
                } # End catch

                try { 
                    #TODO: We need to restart service after this
                    Set-ItemProperty -Path "HKLM:\SOFTWARE\Cylance\Optics" -Name "SelfProtectionLevel" -Value 1;
                    if ($LASTEXITCODE -eq 1) {
                        write-Warning "Exception caught";
                        exit 1
                        Stop-Transcript;
                    }
                }
                catch {
                    # Start catch
                    write-Warning "Exception caught";
                    write-Warning "$_";
                } # End catch
            }
            else {
                Write-Host " **** safemode: No changes have been made ****"
            } # End safemode Check
        }
        elseif ( $SelfProtectionLevel -eq 1) {
            Write-Host " 'SelfProtectionLevel' is Enabled(1)";
            # Local Administrators can make changes to the registry and services.
        }
        elseIf ( !$SelfProtectionLevel) {
            Write-Host ""	
            Write-Host " 'SelfProtectionLevel' is Missing";
            Write-Host "  Creating 'SelfProtectionLevel' with to Enabled(1)";
            if ($global:safemode -eq "No") {
                Write-Host " Taking Ownership of $global:Originalkey"
                try {
                    Take-Permissions $HiveAbr $Hivepath
                }
                catch {
                    # Start catch
                    write-Warning "Exception caught";
                    write-Warning "$_";
                } # End catch        
        
                try { 
                    #TODO: We need to restart the service after this call
                    New-ItemProperty -Path "HKLM:\SOFTWARE\Cylance\Optics" -Name 'SelfProtectionLevel' -Value 1 -PropertyType DWord -ErrorAction Stop;
                }
                catch {
                    # Start catch
                    write-host "Exception caught";
                    write-host "$_";
                } # End catch
            }
            else {
                Write-Host " **** safemode: No changes have been made ****"
            } # End safemode Check
        }
        else {
            Write-Host "'SelfProtectionLevel' Unknown Error";
            Write-Host "SelfProtectionLevel: $SelfProtectionLevel"
        }

    }
    else {
        Write-host ""    
        Write-host "Path does not exist: HKLM:\SOFTWARE\Cylance\Optics"
    } # End If Test-Path

} # End we need to ensure that Self Protection is enabled and set to Local Admin for optics

function modify-LastStateRestorePoint {
    # Start We need to ensure that Self Protection is enabled and set to Local Admin
    if (Test-Path -Path "HKLM:\SOFTWARE\Cylance\Desktop") {
        $global:Originalkey = "HKLM:\SOFTWARE\Cylance\Desktop"
        $HiveAbr = $global:Originalkey.Substring(0, $global:Originalkey.IndexOf(':'))
        $Hivepath = $global:Originalkey.Substring($global:Originalkey.IndexOf('\') + 1)
        Write-Host ""
        Write-Host "Checking if SelfProtection Level is enabled in the Registry"
        
        # Within the Cylance\Desktop Key, check for SelfProtectionLevel DWORD
        try { 
            $SelfProtectionLevel = (Get-ItemProperty $global:Originalkey).PSObject.Properties.Name -contains "LastStateRestorePoint"
        }
        catch {
            # Start catch
            write-Warning "Exception caught";
            write-Warning "$_";
        } # End catch

        if ($SelfProtectionLevel) {
            Write-host "Found Value: LastStateRestorePoint"

            if ($global:Continue -eq "Yes") {
                # Start of Continue check

                if ($global:safemode -eq "No") {
                    # Start of safemode check
                    Write-Host "Taking Ownership of HKLM:\SOFTWARE\Cylance\Desktop"
                    try {
                        Take-Permissions $HiveAbr $Hivepath
                    }
                    catch {
                        # Start catch
                        write-Warning "Exception caught";
                        write-Warning "$_";
                    } # End catch  
                
                    Write-Host "Deleting $global:SafeExportName"
                    try {
                        Remove-ItemProperty -Path HKLM:\SOFTWARE\Cylance\Desktop -Name LastStateRestorePoint -Force -Verbose -ErrorAction Stop
                        Write-Host " Successfully Deleted $global:SafeExportName"
                        Write-Host ""
                    }
                    catch {
                        # Start catch
                        write-Warning "    Exception caught";
                        write-Warning "    $_";
                        Write-Host ""
                    } # End catch

                }
                else {
                    Write-Host "    Key for Deletion/Modification: LastStateRestorePoint"
                    Write-Host " **** safemode: No changes have been made ****"
                    Write-Host ""
                } # End of safemode check
            }
            else {
                write-host "Global continue is prompt was set to 'No' or 'Cancel', Stopping script,"
            } # End If self protection
        }
        else {
            Write-host ""    
            Write-host "Path does not exist: HKLM:\SOFTWARE\Cylance\Desktop"
        } # End If Test-Path
    } # End we need to ensure that LastStateRestorePoint is deleted
} # End We need to ensure that Self Protection is enabled and set to Local Admin for Protect

function modify-Services {
    # Start We need to ensure that all existing services for Cylance are set to Disabled
    Write-Host ""
    Write-Host "Checking if all Cylance Services are disabled"
    $RegkeysHive = ""
    $RegkeysHive = @(
        'HKLM:\SYSTEM\CurrentControlSet\services\CyDevFlt' # Protect 2.x? Default Start(?)
        , 'HKLM:\SYSTEM\CurrentControlSet\services\CyDevFlt64' # Protect 3.0? Default Start(?)
        , 'HKLM:\SYSTEM\CurrentControlSet\services\CylanceDrv' # Protect 3.1 Default Start(0)
        , 'HKLM:\SYSTEM\CurrentControlSet\services\CylanceSvc' # Protect 3.1 Default Start(2)
        , 'HKLM:\SYSTEM\CurrentControlSet\services\CyProtectDrv'  
        , 'HKLM:\SYSTEM\CurrentControlSet\services\CyOptics' # Optics 3.2 Default Start(2)
        , 'HKLM:\SYSTEM\CurrentControlSet\services\CyOpticsDrv' # Optics 3.2 Default Start(1)
        , 'HKLM:\SYSTEM\CurrentControlSet\services\CyAgent' # DLP 1.0 Default Start(2) | Persona 1.3 Default Start(2) | Protect/Optics?
        #,'HKLM:\SYSTEM\CurrentControlSet\services\CyElamDrv' # Protect 3.1 Default Start(0)
        , 'HKLM:\SYSTEM\CurrentControlSet\services\CyDevFltV2' # Protect 3.1 Default Start(0)
        #,'HKLM:\SYSTEM\CurrentControlSet\services\BlackBerryGatewayCalloutDriver' # Gateway 2.5 Default Start(0)
        #,'HKLM:\SYSTEM\CurrentControlSet\services\BlackBerryGatewayService' # Gateway 2.5 Default Start(2)
    )

    $k = ""
    foreach ($k in $RegkeysHive) {
        # Start foreach loop
        $global:Originalkey = $k
        $global:SafeFileName = $k.replace(':', '_') # Replacing " with _ for supported filename
        $global:SafeFileName = $global:SafeFileName.replace('\', '_') # Replacing \ with _ for supported filename
        $global:SafeExportName = $k.replace(':', '') # Removing : to support exporting variable
        $HiveAbr = $global:Originalkey.Substring(0, $global:Originalkey.IndexOf(':'))
        $Hivepath = $global:Originalkey.Substring($global:Originalkey.IndexOf('\') + 1)


        if (Test-Path -Path $k) {
            # Start If loop
            try {
                $global:Servicevalue = (Get-ItemProperty $k -ErrorAction Stop).Start;
            }
            catch {
                write-Warning "Exception caught";
                write-Warning "$_";
            }

            If ( $global:Servicevalue -ne 4 ) {
                Write-Host ""
                Write-Host "Service $k is not disabled"
                Write-Host "  Current value: $global:Servicevalue"
                Write-Host "  Disabling the service via registry 'Disabled(4)'"
    
                if ($global:safemode -eq "No") {
                    Write-Host " Taking Ownership of $global:Originalkey"
                    try {
                        Take-Permissions $HiveAbr $Hivepath
                    }
                    catch {
                        # Start catch
                        write-Warning "Exception caught";
                        write-Warning "$_";
                    } # End catch    
    
                    try { 
                        Set-ItemProperty -Path $k -Name "Start" -Value 4;
                        $CheckValue = (Get-ItemProperty $k -ErrorAction Stop).Start;
                        if ($CheckValue -ne 4) {
                            write-Error "Disabling the service failed Current value: '$CheckValue'";
                        }

                    }
                    catch {
                        # Start catch
                        write-Warning "Exception caught";
                        write-Warning "$_";
                    } # End catch
                }
                else {
                    Write-Host "  **** safemode: No changes have been made ****"
                } # End safemode Check
            }

        } # End If loop

    } # End foreach loop
    #Write-Warning "Any changes to the services may require a reboot and re-run of the script"

} # End We need to ensure that all existing services for Cylance are set to Disabled

function Stop-Delete-Services {
    # Start try to stop services

    # We need to stop any service that may be running as well as the CylanceUI.exe however, depending on Self Protection, LastStateRestorePoint
    #  and the state of the endpoint, this may fail. If we see any errors we may need to reboot the endpoint and re-run the script.
    # TODO: Add a write-host to reboot

    if ($global:Continue -eq "Yes") {
        # Start of Continue check
        
        $Services = @(
            # Cylance Service
            'CylanceSvc',
            # Cylance Driver
            'CyProtectDrv',
            'CyDevFlt64',
            'CyAgent',
            # Optics
            'CyOptics'
        )
            
        foreach ($k in $Services) {
            # Start Foreach Service
            $service = Get-Service -Name $k -ErrorAction SilentlyContinue
            if ($service.Length -gt 0) {
                Write-Host "Service Exists: $k"
                if ($global:safemode -eq "No") {
                    # Start of safemode check
                    Write-Host "Stopping Service"
                    try {
                        # Start try to stop service
                        #Stop-Service -Name $k -ErrorAction stop -PassThru -Force
                        Stop-ServiceWithTimeout $k 30
                    }
                    catch {
                        Write-Warning "Exception caught";
                        Write-Warning "You may need to restart the endpoint and re-run the script"
                    } # End try to stop service
                    Write-Host "Removing Service"
                    sc.exe delete $k #-ErrorAction SilentlyContinue
                    if ( $LASTEXITCODE -eq 0 ) { 
                        Write-Host "Service was deleted successfully."
                    }
                    if ( $LASTEXITCODE -eq 5 ) { 
                        Write-Warning "Access Denied! Please reboot the endpoint and re-run the script."
                    }
                    if ( $LASTEXITCODE -eq 1072 ) { 
                        Write-Warning "Service is marked for deletion and will be removed during the next reboot."
                    }
                } # End of safemode check
                
            }
        } # End Foreach Service


        # Get CylanceUI process
        if ($global:safemode -eq "No") {
            # Start safemode check for CylanceUI
            $CylanceUI = Stop-Process -ProcessName "CylanceUI" -Force -ErrorAction SilentlyContinue
            if ($CylanceUI) {
                # try gracefully first
                $CylanceUI.CloseMainWindow()
                # kill after five seconds
                Start-Sleep 5
                if (!$CylanceUI.HasExited) {
                    $CylanceUI | Stop-Process -Force
                }
            }
            Remove-Variable CylanceUI
        } # End safemode check for CylanceUI
    }
    else {
        write-host "Global continue is prompt was set to 'No' or 'Cancel', Stopping script,"
    } # End Continue check
} # End try to stop services

function Backup_Reg_Keys {
    # Start Backup and Delete Registry keys
    # By default, only two hives are added to paths. we need to also add HKCR so we don't have to duplicate a lot of code
    $CheckHKCRHive = (Get-PSDrive -PSProvider Registry | Select-Object Name, Provider, Root | Where { $_.Name -eq "HKCR" -and $_.Root -eq "HKEY_CLASSES_ROOT" }) -ne $null;
    If ( !$CheckHKCRHive) {
        # Start If
        try {
            New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -ErrorAction Stop
        }
        catch {
            # Start catch
            write-host "$_";
            exit 1
            Stop-Transcript;
        } # End catch
    } # End If

    Write-host ""
    Write-host "Scanning Windows Registry 1of5..."
    # Search the registry for static folders to backup.
    $RegkeysHive = ""
    $RegkeysHive = @(
        'HKLM:\SOFTWARE\Cylance\Desktop',
        'HKLM:\SOFTWARE\Cylance\Optics',
        'HKLM:\SYSTEM\CurrentControlSet\services\CyDevFlt',
        'HKLM:\SYSTEM\CurrentControlSet\services\CyDevFltV2',
        'HKLM:\SYSTEM\CurrentControlSet\services\CyOpticsDrv',
        'HKLM:\SYSTEM\CurrentControlSet\services\CylanceDrv',
        'HKLM:\SYSTEM\CurrentControlSet\services\CyProtectDrv',
        'HKLM:\SYSTEM\CurrentControlSet\services\CyOptics',
        'HKLM:\SYSTEM\CurrentControlSet\services\CylanceSvc',
        'HKLM:\SYSTEM\CurrentControlSet\services\CyDevFlt64',
        'HKLM:\SYSTEM\CurrentControlSet\services\CyAgent',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\C5CF46E2682913A419B6D0A84E2B9245',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\EEEA7AC670DE2F343B7B624D338C49E8',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{2E64FC5C-9286-4A31-916B-0D8AE4B22954}',
        'HKCR:\Installer\Features\C5CF46E2682913A419B6D0A84E2B9245',
        'HKCR:\Installer\Products\C5CF46E2682913A419B6D0A84E2B9245',
        'HKCR:\Installer\Features\EEEA7AC670DE2F343B7B624D338C49E8',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DIFx\Services\CyProtectDrv',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DIFx\Services\CylanceDrv',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DIFx\Services\CylanceOpticsDrv',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DIFx\Services\CyOpticsDrv'
        'HKLM:\SOFTWARE\Microsoft\RADAR\HeapLeakDetection\DiagnosedApplications\CylanceSvc.exe',
        'HKLM:\SOFTWARE\Microsoft\Tracing\CylanceSvc_RASAPI32',
        'HKLM:\SOFTWARE\Microsoft\Tracing\CylanceSvc_RASMANCS',
        'HKLM:\SOFTWARE\Microsoft\Tracing\CyOptics_RASAPI32',
        'HKLM:\SOFTWARE\Microsoft\Tracing\CyOptics_RASMANCS',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DIFxApp\Components\{450500FA-75A8-44E8-BC01-734384C37067}',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DIFxApp\Components\{0F031C0D-153A-45EA-A827-C50D4D89FF3B}',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DIFxApp\Components\{72B70F45-0B32-5191-A610-8350D30001BD}',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\033832A116D21F144B962FF76D4884D3',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\050B5E1EB914B794D81D33D454BE5EDA',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\056F1F2DDE833B05FBCD73E2356DDD65',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\0B250EF44F86B284D91FACC3AEC02A6A',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\0EF15392547C50353BCFC3E00A3827FB',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\13A6247DBB6C4FE4EB7E8014BB12F85F',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\19A09EF58F343F153A382115133CB618',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\28EC0CF0E8B751959B4C48BD4B9F8799',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\517BD3DDC393FEB55A5C67E741B72E35',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\8384F56E243C82151BE8CB2C6460306A',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\00F6D629AD1DD634FAF344EBDEDA3B87',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\0158DE7CE6C322D4090A84BEE5E5B970',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\01944E0C4C36473479167EDE0E4B6918',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\01CE8C5C0853AD142853AC619D42CB2C',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\028975F5105D6B84EBC36597C86994D8',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\0359EAC03B1D14F4DA578FF2C7CC830B',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\0367243376916FD43A47FD078D55F8B1',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components\03F7CD04CCD14E7459C109AF0888D70F',
        'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\CylanceSvc',
        'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\CyAgent',
        'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\CyOptics',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\5E3ECEF636AC03A42AD963002F50F714',
        'HKLM:\SYSTEM\CurrentControlSet\services\CyElamDrv',
        'HKLM:\SYSTEM\ControlSet001\services\CyElamDrv'
    )

    # Perform iteration to create the same file in each folder
    $k = ""
    foreach ($k in $RegkeysHive) {
        # Start foreach loop
        $global:Originalkey = $k
        $global:SafeFileName = $k.replace(':', '_') # Replacing " with _ for supported filename
        $global:SafeFileName = $global:SafeFileName.replace('\', '_') # Replacing \ with _ for supported filename
        $global:SafeExportName = $k.replace(':', '') # Removing : to support exporting variable
        $HiveAbr = $global:Originalkey.Substring(0, $global:Originalkey.IndexOf(':')) # take only "HKLM" from the variable
        $Hivepath = $global:Originalkey.Substring($global:Originalkey.IndexOf('\') + 1) # Strip "HKLM:\" from the variable

        if (Test-Path -Path $k) {
            # Start If loop
            #$global:Continue = "Yes";
            $global:RegOutputFile = "";
            $global:RegOutputFile = $PSScriptRoot + "\" + $global:Folder + "\" + $global:SafeFileName + ".reg";
            try {
                reg export $global:SafeExportName $global:RegOutputFile /y | out-null;
                if ($LASTEXITCODE -eq 1) {
                    write-Warning "Exception caught";
                    exit 1
                    Stop-Transcript;
                }
                write-host "Exported $k successfully";
                Delete_Reg_Keys;
            }
            catch {
                write-Warning "Exception caught";
                write-host "$_";
            }
        } # End If loop
    } # End foreach loop


    
    <#
    Write-host ""
    Write-host "Scanning Windows Registry 2of5..."
    # Scanning the Uninstaller locations for the product GUID. We take this GUID and do a delete of the Keys
    $RegkeysHive = ""
    $RegkeysHive = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $RegkeysHiveDeletePaths = ""
    $RegkeysHiveDeletePaths = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCR:\Installer\Dependencies',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\TempPackages\C:\WINDOWS\Installer'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\Folders\C:\WINDOWS\Installer',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'
    )

    $l = ""
    foreach ($l in $RegkeysHive) {
        # Start foreach loop
        $global:Originalkey = $l
        $global:KWildcard1 = $l + "\*" # append \* for the search
        $HiveAbr = $global:Originalkey.Substring(0, $global:Originalkey.IndexOf(':'))
        $Hivepath = $global:Originalkey.Substring($global:Originalkey.IndexOf('\') + 1)

        #$SearchWord = "Cylance PROTECT";
        $SearchWord = ""
        $SearchWord = @(
            'Cylance PROTECT'
            #,'Cylance Platform' # Installed With DLP 1.0 | Persona 1.3
            , 'Cylance OPTICS'
            , 'Cylance PROTECT with OPTICS'
            , 'CylancePROTECT'
            , 'Cylance Unified Agent' # Installed with Protect + Optics Installer
            #,'Cylance Persona' # Installed with Persona 1.3
            #,'Cylance Persona Capability' # Installed with Persona 1.3
            #,'CylanceAVERT and Platform' # Installed with DLP 1.0
            #,'Cylance Agent' # Installed With DLP 1.0 | Persona 1.3
        )

        $m = ""
        foreach ($m in $SearchWord) {
            # Start foreach loop for SearchWord
            #Write-host "RegkeysHive: $l"
            #write-host "$global:KWildcard1"
            #Write-host "SearchWord: $m"
            $installed = (Get-ItemProperty $global:KWildcard1 | Where { $_.DisplayName -eq $m -or $_.ProductName -eq $m }) -ne $null;
            If ( $installed ) {
                Write-host ""
                #Write-host "Debug installed: $installed"
                #Write-host "Debug KWildcard 1: $global:KWildcard1"
                #Write-host "Debug m 1: $m"

                # Get the GUID for the installed Product
                $KeyName1 = (Get-ItemProperty $global:KWildcard1 | Where-Object { $_.DisplayName -eq $m -or $_.ProductName -eq $m }).PSChildName;
                #Write-host "Debug KeyName1: $KeyName1"
               
                #Write-host "Debug Originalkey1: $global:Originalkey"
                #Write-host "Debug KWildcard1: $global:KWildcard1"
                #Write-host "Debug HiveAbr1: $HiveAbr"
                #Write-host "Debug Hivepath1: $Hivepath"

                #Write-host "Debug FullWildCard 1: $global:FullWildCard1"
                $global:FullWildCard1 = $global:Originalkey + "\" + $KeyName1
                #Write-host "Debug FullWildCard 2: $global:FullWildCard1"

                $PathExists = (Get-ItemProperty $global:FullWildCard1 -ErrorAction SilentlyContinue) -ne $null;
                #Write-host "Debug PathExists: $PathExists"
                If ( $PathExists ) {
                    # Start If PathExists
                    Write-host "   Scanning for $m"
                    $n = $l + "\"
                    $global:Originalkey = $n
                    $global:SafeFileName1 = $n.replace(':', '_') # Replacing " with _ for supported filename  
                    $global:SafeFileName1 = $global:SafeFileName1.replace('\', '_') # Replacing \ with _ for supported filename
                    $global:SafeFileName1 = $global:SafeFileName1 + "_" + $KeyName1 # Appending porduct GUID from $KeyName1

                    $global:SafeExportName = $n.replace(':', '') # Removing : to support exporting variable
                    $global:SafeExportName = $global:SafeExportName + $KeyName1 #Appending porduct GUID from $KeyName1

                    $global:RegOutputFile1 = "";
                    $global:RegOutputFile1 = $PSScriptRoot + "\" + $global:Folder + "\" + $SafeFileName1 + ".reg";
                    $HiveAbr = $global:Originalkey.Substring(0, $global:Originalkey.IndexOf(':'))
                    $Hivepath = $global:Originalkey.Substring($global:Originalkey.IndexOf('\') + 1)
                                               
                    try {
                        reg export $global:SafeExportName $global:RegOutputFile1 /y | out-null;
                        if ($LASTEXITCODE -eq 1) {
                            write-Warning "Exception caught";
                            exit 1
                            Stop-Transcript;
                        }
                        write-host "Exported $global:FullWildCard1 successfully";
                        Delete_Reg_Keys;
                    }
                    catch {
                        # Start catch
                        write-Warning "Exception caught";
                        write-host "$_";
                    } # End catch

                    $o = ""
                    $p = ""
                    foreach ($o in $RegkeysHiveDeletePaths) {
                        # Start foreach RegkeysHiveDeletePaths
                        $p = $o + "\"
                        $global:Originalkey = $p
                        $global:Originalkey = $o + "\" + $KeyName
                        $global:SafeFileName = $p.replace(':', '_') # Replacing " with _ for supported filename  
                        $global:SafeFileName = $global:SafeFileName.replace('\', '_') # Replacing \ with _ for supported filename
                        $global:SafeFileName = $global:SafeFileName + "_" + $KeyName # Appending porduct GUID from $KeyName
                        $global:SafeExportName = $p.replace(':', '') # Removing : to support exporting variable
                        $global:SafeExportName = $global:SafeExportName + $KeyName #Appending porduct GUID from $KeyName
                        $global:RegOutputFile = "";
                        $global:RegOutputFile = $PSScriptRoot + "\" + $global:Folder + "\" + $SafeFileName + ".reg";
                        $HiveAbr = $global:Originalkey.Substring(0, $global:Originalkey.IndexOf(':'))
                        $Hivepath = $global:Originalkey.Substring($global:Originalkey.IndexOf('\') + 1)
                
                        $RegkeyPathExist = ""
                        $RegkeyPathExist = (Get-ItemProperty $global:Originalkey -ErrorAction SilentlyContinue) -ne $null;
                        If ( $RegkeyPathExist ) {
                            # Start If RegkeyPathExist
                            try {
                                reg export $global:SafeExportName $global:RegOutputFile /y | out-null;
                                if ($LASTEXITCODE -eq 1) {
                                    write-Warning "Exception caught";
                                    exit 1
                                    Stop-Transcript;
                                }
                                write-host "Exported $global:Originalkey successfully";
                                Delete_Reg_Keys;
                            }
                            catch {
                                # Start catch
                                write-Warning "Exception caught";
                                write-host "$_";
                            } # End catch
                        } # End If RegkeyPathExist
                    } # End foreach RegkeysHiveDeletePaths
                } # End If PathExists
            } # If installed
        } # foreach SearchWord
    }
#>


    Write-host ""
    Write-host "Scanning Windows Registry 3of5..."
    # Some regkeys does not have a static folder path, thus we need to search using keywords and build the path to backup.
    $RegkeysHive = ""
    $RegkeysHive = @(
        'HKCR:\Installer\Products'
        , 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        , 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        , 'HKCR:\Installer\Dependencies'
        , 'HKLM:\SOFTWARE\Classes\Installer\Dependencies'
        , 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DIFx\DriverStore'
        #, 'HKLM:\SOFTWARE\Microsoft\Security Center\Provider\Av'
    )

    $l = ""
    foreach ($l in $RegkeysHive) {
        # Start foreach loop
        $global:Originalkey = $l
        $global:KWildcard = $l + "\*" # append \* for the search
        $HiveAbr = $global:Originalkey.Substring(0, $global:Originalkey.IndexOf(':'))
        $Hivepath = $global:Originalkey.Substring($global:Originalkey.IndexOf('\') + 1)

        $SearchWord = ""
        $SearchWord = @(
            'Cylance PROTECT'
            #,'Cylance Platform' # Installed With DLP 1.0 | Persona 1.3
            , 'Cylance OPTICS'
            , 'Cylance PROTECT with OPTICS'
            , 'CylancePROTECT'
            , 'Cylance Unified Agent' # Installed with Protect + Optics Installer
            #,'Cylance Persona' # Installed with Persona 1.3
            #,'Cylance Persona Capability' # Installed with Persona 1.3
            #,'CylanceAVERT and Platform' # Installed with DLP 1.0
            #,'Cylance Agent' # Installed With DLP 1.0 | Persona 1.3
        )

        $m = ""
        foreach ($m in $SearchWord) {
            # Start foreach loop for SearchWord
            $installed = (Get-ItemProperty $global:KWildcard | Where { $_.DisplayName -eq $m -or $_.ProductName -eq $m }) -ne $null;

            If ( $installed ) {
                # Start if
                $KeyName = ""
                $Result = ""
                $KeyName = (Get-ItemProperty $global:KWildcard | Where-Object { $_.DisplayName -eq $m -or $_.ProductName -eq $m }).PSChildName;
                foreach ($Result in $KeyName) {
                    # Start Loop through multiple results if exist
                    $n = $l + "\" + $Result
                    $global:Originalkey = $n
                    $global:SafeFileName = $n.replace(':', '_') # Replacing " with _ for supported filename  
                    $global:SafeFileName = $global:SafeFileName.replace('\', '_') # Replacing \ with _ for supported filename
                    $global:SafeExportName = $n.replace(':', '') # Removing : to support exporting variable
                    $global:RegOutputFile = "";
                    $global:RegOutputFile = $PSScriptRoot + "\" + $global:Folder + "\" + $SafeFileName + ".reg";
                    $HiveAbr = $global:Originalkey.Substring(0, $global:Originalkey.IndexOf(':'))
                    $Hivepath = $global:Originalkey.Substring($global:Originalkey.IndexOf('\') + 1)

                    try {
                        reg export $global:SafeExportName $global:RegOutputFile /y | out-null;
                        if ($LASTEXITCODE -eq 1) {
                            write-Warning "Exception caught";
                            exit 1
                            Stop-Transcript;
                        }
                        write-host "Exported $k successfully";
                        Delete_Reg_Keys;
                    }
                    catch {
                        # Start catch
                        write-Warning "Exception caught";
                        write-host "$_";
                    } # End catch
                } # Start Loop through multiple results if exist
            } # End if
        } # End foreach loop for SearchWord
    } # End foreach loop

    
    Write-host ""
    Write-host "Scanning Windows Registry 4of5..."
    # Checking registry UpperFilters and LowerFilters that contain CyDevFlt for backup
    $RegkeysHive = ""
    $RegkeysHive = @(
        'HKLM:\SYSTEM\CurrentControlSet\Control\class'
    )

    $k = ""
    foreach ($k in $RegkeysHive) {
        # Start foreach loop
        $global:Originalkey = $k
        $global:KWildcard = $k + "\*" # append \* for the search

        $SearchWord = "CyDevFlt";
        $Result = (Get-ItemProperty $global:KWildcard | Where-Object { $_.UpperFilters -eq $SearchWord -or $_.LowerFilters -eq $SearchWord }).PSChildName;
        $key = ""
        foreach ($key in $Result) {
            # Start foreach loop
            #$key = $RegkeysHive + "\" + $key
            $key = "$RegkeysHive\$key"
            $global:SafeFileName = $key.replace(':', '_') # Replacing " with _ for supported filename  
            $global:SafeFileName = $global:SafeFileName.replace('\', '_') # Replacing \ with _ for supported filename
            $global:SafeExportName = $key.replace(':', '') # Removing : to support exporting variable
            $global:RegOutputFile = "";
            $global:RegOutputFile = $PSScriptRoot + "\" + $global:Folder + "\" + $SafeFileName + ".reg";

            try {
                reg export $global:SafeExportName $global:RegOutputFile /y | out-null;
                if ($LASTEXITCODE -eq 1) {
                    write-Warning "Exception caught";
                    exit 1
                    Stop-Transcript;
                }
                write-host "Exported $key successfully";
                # Do not call Delete_Reg_Keys here or it will blow away the usb drivers.;
            }
            catch {
                # Start catch
                write-Warning "Exception caught";
                write-Warning "$_";
            } # End catch

        } # End if

    } # End foreach loop


    Write-host ""
    Write-host "Scanning Windows Registry 5of5..."
    # Checking registry for CylanceMemDef*.dll
    $global:Originalkey = ""
    $global:KWildcard = ""
    $RegkeysHive = ""
    $RegkeysHive = @(
        'HKLM:\SOFTWARE\Classes\CLSID'
    )

    $k = ""
    foreach ($k in $RegkeysHive) {
        # Start foreach loop
        $global:Originalkey = $k
        $global:KWildcard = $k + "\*" # append \* for the search

        $key = ""
        $Result = ""
        $Result = (get-childitem -recurse $global:KWildcard | get-itemproperty | where { $_.'(Default)' -match 'CylanceMemDef.dll' -or $_.'(Default)' -match 'CylanceMemDef64.dll' }).PSParentPath;
        
        foreach ($key in $Result) {
            $key = $key -replace '^[^:]+::' # Remove everything beofre ::
            $key = $key.replace('HKEY_LOCAL_MACHINE', 'HKLM:') # replace HKEY_LOCAL_MACHINE to HKLM:
            $global:Originalkey = $key
            $HiveAbr = $global:Originalkey.Substring(0, $global:Originalkey.IndexOf(':'))
            $Hivepath = $global:Originalkey.Substring($global:Originalkey.IndexOf('\') + 1)

            $global:SafeFileName = $key.replace(':', '_') # Replacing " with _ for supported filename  
            $global:SafeFileName = $global:SafeFileName.replace('\', '_') # Replacing \ with _ for supported filename
            $global:SafeExportName = $key.replace(':', '') # Removing : to support exporting variable
            $global:RegOutputFile = "";
            $global:RegOutputFile = $PSScriptRoot + "\" + $global:Folder + "\" + $SafeFileName + ".reg";

            try {
                reg export $global:SafeExportName $global:RegOutputFile /y | out-null;
                if ($LASTEXITCODE -eq 1) {
                    write-Warning "Exception caught";
                    exit 1
                    Stop-Transcript;
                }
                write-host "Exported $key successfully";
                Delete_Reg_Keys;
            }
            catch {
                write-Warning "Exception caught";
                write-Warning "$_";
            }

        } # End if

    } # End foreach loop

} # End of all Backup_Reg_Keys

function Search_Reg_CyDevFlt {
    # Start of Search_Reg_CyDevFlt

    if ($global:Continue -eq "Yes") { 
        $RegFilterList = ""
        $RegFilterList = @('UpperFilters', 'LowerFilters')

        $f = ""
        foreach ($f in $RegFilterList) {
            # Start of foreach RegFilterList
            $global:MultiStringName = $f

            Write-Host ""
            #Write-Host "safemode Enabled: $global:safemode"
            Write-Host "RegKey Name: $global:MultiStringName" #UpperFilters or LowerFilters
            Write-Host "RegKey Value: $global:RemoveDelete_Value"
            Write-Host "RegKey Start Path: $global:RegistryPath"

            $Registrykeys = Get-ChildItem -Recurse -Path "Registry::$global:RegistryPath" -ErrorAction SilentlyContinue
            $Registrykeys | Select-Object -Property Name | ForEach-Object { #ForEach-Object Start
                $Path = $_.name
                $MultiStringValue = (Get-ItemProperty Registry::$Path -Name $global:MultiStringName -ErrorAction SilentlyContinue).$global:MultiStringName

                if ($MultiStringValue -like $global:RemoveDelete_Value) {
        
                    if ($MultiStringValue.length -eq '1') {
                        Write-Host ""
                        Write-Host "Single Value Found"
                        Write-Host "    Path: $path"
                        Write-Host "    Old Value: $MultiStringValue"
                        if ($global:safemode -eq 'No') {
                            Write-Host "    Removed $Path $global:MultiStringName"
                            Remove-ItemProperty Registry::$Path -Name $global:MultiStringName
                        }
                        else {
                            Write-Host "    **** safemode: No changes have been made ****"
                        }

                    }
                    elseif ($MultiStringValue.length -gt '1') {
                        Write-Host ""
                        Write-Host "Multi Value Found"
                        Write-Host "    Path: $path"
                        Write-Host "    Old Value: $MultiStringValue"
                        $NewMultiStringValue = $MultiStringValue | Where-Object { $_ -ne $global:RemoveDelete_Value }
                        #Remove CyDevFlt and print the new list
                        Write-Host "    New Value: $NewMultiStringValue"
                        if ($global:safemode -eq 'No') {
                            Write-Host "    Updated $Path $global:MultiStringName"
                            Set-ItemProperty Registry::$Path -Name $global:MultiStringName -Value $NewMultiStringValue
                        }
                        else {
                            Write-Host "    **** safemode: No changes have been made ****"
                        }
                    } #end elseif
                } # end if

            } #ForEach-Object End
        } # End of foreach RegFilterList
    }
    else {
        write-host "Cylance protect is listed as installed in Add/Remove. Stopping script"
    } # end if check for protect is installed
} # end remove CyDevFlt function

function Search_Reg_CyDevFltV2 {
    # Start of Search_Reg_CyDevFltV2

    if ($global:Continue -eq "Yes") { 
        $RegFilterList = ""
        $RegFilterList = @('UpperFilters', 'LowerFilters')

        $f = ""
        foreach ($f in $RegFilterList) {
            # Start of foreach RegFilterList
            $global:MultiStringName = $f

            Write-Host ""
            #Write-Host "safemode Enabled: $global:safemode"
            Write-Host "RegKey Name: $global:MultiStringName" #UpperFilters or LowerFilters
            Write-Host "RegKey Value: $global:RemoveDelete_Value2"
            Write-Host "RegKey Start Path: $global:RegistryPath"

            $Registrykeys = Get-ChildItem -Recurse -Path "Registry::$global:RegistryPath" -ErrorAction SilentlyContinue
            $Registrykeys | Select-Object -Property Name | ForEach-Object { #ForEach-Object Start
                $Path = $_.name
                $MultiStringValue = (Get-ItemProperty Registry::$Path -Name $global:MultiStringName -ErrorAction SilentlyContinue).$global:MultiStringName

                if ($MultiStringValue -like $global:RemoveDelete_Value2) {
        
                    if ($MultiStringValue.length -eq '1') {
                        Write-Host ""
                        Write-Host "Single Value Found"
                        Write-Host "    Path: $path"
                        Write-Host "    Old Value: $MultiStringValue"
                        if ($global:safemode -eq 'No') {
                            Write-Host "    Removed $Path $global:MultiStringName"
                            Remove-ItemProperty Registry::$Path -Name $global:MultiStringName
                        }
                        else {
                            Write-Host "    **** safemode: No changes have been made ****"
                        }

                    }
                    elseif ($MultiStringValue.length -gt '1') {
                        Write-Host ""
                        Write-Host "Multi Value Found"
                        Write-Host "    Path: $path"
                        Write-Host "    Old Value: $MultiStringValue"
                        $NewMultiStringValue = $MultiStringValue | Where-Object { $_ -ne $global:RemoveDelete_Value2 }
                        #Remove CyDevFltV2 and print the new list
                        Write-Host "    New Value: $NewMultiStringValue"
                        if ($global:safemode -eq 'No') {
                            Write-Host "    Updated $Path $global:MultiStringName"
                            Set-ItemProperty Registry::$Path -Name $global:MultiStringName -Value $NewMultiStringValue
                        }
                        else {
                            Write-Host "    **** safemode: No changes have been made ****"
                        }
                    } #end elseif
                } # end if

            } #ForEach-Object End
        } # End of foreach RegFilterList
    }
    else {
        write-host "Cylance protect is listed as installed in Add/Remove. Stopping script"
    } # end if check for protect is installed
} # end remove CyDevFltv2 function

function Delete_Reg_Keys {
    # Start of Delete_Reg_Keys

    if ($global:Continue -eq "Yes") {
        # Start of Continue check

        if ($global:safemode -eq "Yes") {
            # Start of safemode check
            Write-Host "    Key for Deletion/Modification: $global:SafeExportName"
            Write-Host " **** safemode: No changes have been made ****"
            Write-Host ""

        }
        else {
            Write-Host " Taking Ownership of $global:Originalkey"
            try {
                Take-Permissions $HiveAbr $Hivepath
            }
            catch {
                # Start catch
                write-Warning "Exception caught";
                write-Warning "$_";
            } # End catch  

            Write-Host "Deleting $global:SafeExportName"
            try {
                Remove-Item -Path $global:Originalkey -Force -Recurse -Verbose -ErrorAction Stop
                Write-Host " Successfully Deleted $global:SafeExportName"
                Write-Host ""
            }
            catch {
                # Start catch
                write-Warning "    Exception caught";
                write-Warning "    $_";
                Write-Host ""
            } # End catch
        } # End of safemode check

    }
    else {
        write-host "Global continue is prompt was set to 'No' or 'Cancel', Stopping script,"
    } # end of Continue check
} # End of Delete_Reg_Keys

function Take-Permissions {
    # Start Take over ownership and permissions on a registry hive
    # Developed for PowerShell v4.0

    # # group BULTIN\Users takes full control of key and all subkeys
    #Take-Permissions "HKLM" "SOFTWARE\test"

    # group Everyone takes full control of key and all subkeys
    #Take-Permissions "HKLM" "SOFTWARE\test" "S-1-1-0"

    # group Everyone takes full control of key WITHOUT subkeys
    #Take-Permissions "HKLM" "SOFTWARE\test" "S-1-1-0" $false

    param($rootKey, $key, [System.Security.Principal.SecurityIdentifier]$sid = 'S-1-5-32-545', $recurse = $true)

    switch -regex ($rootKey) {
        'HKCU|HKEY_CURRENT_USER' { $rootKey = 'CurrentUser' }
        'HKLM|HKEY_LOCAL_MACHINE' { $rootKey = 'LocalMachine' }
        'HKCR|HKEY_CLASSES_ROOT' { $rootKey = 'ClassesRoot' }
        'HKCC|HKEY_CURRENT_CONFIG' { $rootKey = 'CurrentConfig' }
        'HKU|HKEY_USERS' { $rootKey = 'Users' }
    }
 ### Step 1 - escalate current process's privilege
    # get SeTakeOwnership, SeBackup and SeRestore privileges before executes next lines, script needs Admin privilege
    $import = '[DllImport("ntdll.dll")] public static extern int RtlAdjustPrivilege(ulong a, bool b, bool c, ref bool d);'
    $ntdll = Add-Type -Member $import -Name NtDll -PassThru
    $privileges = @{ SeTakeOwnership = 9; SeBackup = 17; SeRestore = 18 }
    $i = ""
    foreach ($i in $privileges.Values) {
        $null = $ntdll::RtlAdjustPrivilege($i, 1, 0, [ref]0)
    }

    function Take-KeyPermissions {
        param($rootKey, $key, $sid, $recurse, $recurseLevel = 0)

        ### Step 2 - get ownerships of key - it works only for current key
        $regKey = [Microsoft.Win32.Registry]::$rootKey.OpenSubKey($key, 'ReadWriteSubTree', 'TakeOwnership')
        $acl = New-Object System.Security.AccessControl.RegistrySecurity
        $acl.SetOwner($sid)
        $regKey.SetAccessControl($acl)

        ### Step 3 - enable inheritance of permissions (not ownership) for current key from parent
        $acl.SetAccessRuleProtection($false, $false)
        $regKey.SetAccessControl($acl)

        ### Step 4 - only for top-level key, change permissions for current key and propagate it for subkeys
        # to enable propagations for subkeys, it needs to execute Steps 2-3 for each subkey (Step 5)
        if ($recurseLevel -eq 0) {
            $regKey = $regKey.OpenSubKey('', 'ReadWriteSubTree', 'ChangePermissions')
            $rule = New-Object System.Security.AccessControl.RegistryAccessRule($sid, 'FullControl', 'ContainerInherit', 'None', 'Allow')
            $acl.ResetAccessRule($rule)
            $regKey.SetAccessControl($acl)
        }

        ### Step 5 - recursively repeat steps 2-5 for subkeys
        if ($recurse) {
            foreach ($subKey in $regKey.OpenSubKey('').GetSubKeyNames()) {
                Take-KeyPermissions $rootKey ($key + '\' + $subKey) $sid $recurse ($recurseLevel + 1)
            }
        }
    }

    Take-KeyPermissions $rootKey $key $sid $recurse
} # End Take over ownership and permissions on a registry hive

function Take-Ownership-Permission-Individual-Files {
    # Start Take ownership of specific files
    
    # Retake ownership of the following files
    $FolderPaths1 = ""
    $FolderPaths1 = @(
        (${Env:SystemRoot} + "\System32\drivers\CyProtectDrv64.sys"),
        (${Env:SystemRoot} + "\System32\drivers\CylanceDrv64.sys"), # Added with Protect 3.1
        (${Env:SystemRoot} + "\System32\drivers\CyOpticsDrv.sys"), # Added with Optics 3.2
        (${Env:SystemRoot} + "\System32\drivers\CyDevFlt64.sys"), 
        (${Env:SystemRoot} + "\System32\drivers\CyDevFltV264.sys"), # Added with Protect 3.1
        (${Env:SystemRoot} + "\System32\drivers\CyElamDrv64.cat"), # Added with Protect 3.1
        (${Env:SystemRoot} + "\System32\drivers\CyElamDrv64.inf"), # Added with Protect 3.1
        (${Env:SystemRoot} + "\System32\drivers\CyElamDrv64.sys"), # Added with Protect 3.1
        (${Env:SystemRoot} + "\ELAMBKUP\CyElamDrv64.sys") # Added with Protect 3.1
    )
    Write-Host ""
    Write-Host "Assigning ownership to Administrator group for Individual Files"
    foreach ($path1 in $FolderPaths1) {
        if ($global:safemode -eq "Yes") {
            # Start safemode Check
            Write-Host " **** safemode: No changes have been made ****"
        }
        else {
            # Start safemode Check Else
            if (Test-Path -Path $path1) {
                # Start Test-Path
                try {
                    takeown /f "$path1" /A
                    if ($LASTEXITCODE -eq 1) {
                        write-Warning "Exception caught";
                    }
                }  
                catch {
                    # Start catch
                    write-Warning "Exception caught";
                    write-Warning "$_";
                } # End catch
            } # End Test-Path
        } # End safemode Check Else
    }
       
        
    # Retake Permissions of the following files/folders
    $FolderPaths2 = @(
        (${Env:SystemRoot} + "\System32\drivers\CyProtectDrv64.sys"),
        (${Env:SystemRoot} + "\System32\drivers\CylanceDrv64.sys"), # Added with Protect 3.1
        (${Env:SystemRoot} + "\System32\drivers\CyOpticsDrv.sys"), # Added with Optics 3.2
        (${Env:SystemRoot} + "\System32\drivers\CyOpticsDrv.bak"), # Added with Optics 3.2
        (${Env:SystemRoot} + "\System32\drivers\CyDevFlt64.sys"), 
        (${Env:SystemRoot} + "\System32\drivers\CyDevFltV264.sys"), # Added with Protect 3.1
        (${Env:SystemRoot} + "\System32\drivers\CyElamDrv64.cat"), # Added with Protect 3.1
        (${Env:SystemRoot} + "\System32\drivers\CyElamDrv64.inf"), # Added with Protect 3.1
        (${Env:SystemRoot} + "\System32\drivers\CyElamDrv64.sys"), # Added with Protect 3.1
        (${Env:SystemRoot} + "\ELAMBKUP\CyElamDrv64.sys") # Added with Protect 3.1
        (${Env:SystemRoot} + "\ELAMBKUP\CyElamDrv64.sys.bak") # Added with Protect 3.1
    )

    # Set PS variables for each of the icacls options
    $Grant = "/grant:r"
    #$Remove = "/remove"
    $replaceInherit = "/inheritance:e"
    $permission = ":(OI)(CI)(F)"
    $useraccount2 = "Administrators"
    
    Write-Host ""
    Write-Host "Assigning Full Control permissions to for Individual Files"
    foreach ($filepath1 in $FolderPaths2) {
        if ($global:safemode -eq "Yes") {
            # Start safemode Check
            Write-Host " **** safemode: No changes have been made ****"
        }
        else {
            # Start safemode Check Else
            if (Test-Path -Path $filepath1) {
                # Start Test-Path
                try {
                    Invoke-Expression -Command ('icacls $filepath1 $Grant "${useraccount2}${permission}" /Q /T')
                    Invoke-Expression -Command ('icacls $filepath1 $replaceInherit /Q /T') 
                    if ($LASTEXITCODE -eq 1) {
                        write-Warning "Exception caught";
                    }
                }  
                catch {
                    # Start catch
                    write-Warning "Exception caught";
                    write-Warning "$_";
                } # End catch
            } # End Test-Path
        } # End safemode Check Else
    }
              
} # End Take ownership and permissions on Individual system32 files

function Take-Ownership-Permission-Folder-Files {
    # Start Take ownership and permissions on files and folders
    
    # Retake ownership of the following files/folders
    $FolderPaths1 = ""
    $FolderPaths1 = @(
        'C:\Program Files\Cylance\Desktop'
        , 'C:\ProgramData\Cylance\Desktop'
        , 'C:\ProgramData\Cylance\Status'
        , 'C:\Program Files\Cylance\Optics'
        , 'C:\ProgramData\Cylance\Optics'

    )
    Write-Host ""
    Write-Host "Assigning ownership to Administrator group"
    foreach ($path1 in $FolderPaths1) {
        if ($global:safemode -eq "Yes") {
            # Start safemode Check
            Write-Host " **** safemode: No changes have been made ****"
        }
        else {
            # Start safemode Check Else
            if (Test-Path -Path $path1) {
                # Start Test-Path
                try {
                    takeown /f "$path1" /R /A /D Y
                    if ($LASTEXITCODE -eq 1) {
                        write-Warning "Exception caught";
                    }
                }  
                catch {
                    # Start catch
                    write-Warning "Exception caught";
                    write-Warning "$_";
                } # End catch
            } # End Test-Path
        } # End safemode Check Else
    }
       
        
    # Retake Permissions of the following files/folders
    $FolderPaths2 = ""
    $FolderPaths2 = @(
        'C:\Program Files\Cylance\Desktop'
        , 'C:\ProgramData\Cylance\Desktop'
        , 'C:\ProgramData\Cylance\Status'
        , 'C:\Program Files\Cylance\Optics'
        , 'C:\ProgramData\Cylance\Optics'
    )

    # Set PS variables for each of the icacls options
    $Grant = "/grant:r"
    #$Remove = "/remove"
    $replaceInherit = "/inheritance:e"
    $permission = ":(OI)(CI)(F)"
    $useraccount2 = "Administrators"
    
    Write-Host ""
    Write-Host "Assigning Full Control permissions to Files/Folders"
    foreach ($filepath1 in $FolderPaths2) {
        if ($global:safemode -eq "Yes") {
            # Start safemode Check
            Write-Host " **** safemode: No changes have been made ****"
        }
        else {
            # Start safemode Check Else
            if (Test-Path -Path $filepath1) {
                # Start Test-Path
                try {
                    Invoke-Expression -Command ('icacls $filepath1 $Grant "${useraccount2}${permission}" /Q /T')
                    Invoke-Expression -Command ('icacls $filepath1 $replaceInherit /Q /T') 
                    if ($LASTEXITCODE -eq 1) {
                        write-Warning "Exception caught";
                    }
                }  
                catch {
                    # Start catch
                    write-Warning "Exception caught";
                    write-Warning "$_";
                } # End catch
            } # End Test-Path
        } # End safemode Check Else
    }
              
} # End Take ownership and permissions on files and folders

function Delete-Files-n-Folders {
    # Start End Delete files and folders
    
    $FolderPaths3 = @(
    (${Env:LOCALAPPDATA} + "\Cylance\Desktop"),
    (${Env:Programfiles} + "\Cylance\Desktop"),
    (${Env:Programfiles} + "\Cylance\Optics"),
    (${Env:ProgramFiles(x86)} + "\Cylance\Desktop"),
    (${Env:ProgramFiles(x86)} + "\Cylance\Optics"),
    (${Env:ProgramData} + "\Cylance\Desktop"),
    (${Env:ProgramData} + "\Cylance\Optics"),
    (${Env:ProgramData} + "\Cylance\Status"),
    (${Env:ProgramData} + "\Microsoft\Windows\Start Menu\Programs\Cylance\Cylance PROTECT.lnk"),
    (${Env:ProgramData} + "\Microsoft\Windows\Start Menu\Programs\Startup\Cylance Desktop.lnk"),
        #(${Env:ProgramData} + "\Microsoft\Windows\Start Menu\Programs\Cylance"),
    (${Env:SystemRoot} + "\System32\DRVSTORE\CylanceDrv*"),
    (${Env:SystemRoot} + "\System32\DRVSTORE\CyProtect*"),
    (${Env:SystemRoot} + "\System32\DRVSTORE\CyOpticsDr*"),
    (${Env:SystemRoot} + "\System32\drivers\CyProtectDrv64.sys"),
    (${Env:SystemRoot} + "\System32\drivers\CylanceDrv64.sys"), # Added with Protect 3.1
    (${Env:SystemRoot} + "\System32\drivers\CyOpticsDrv.sys"), # Added with Optics 3.2
    (${Env:SystemRoot} + "\System32\drivers\CyDevFlt64.sys"), 
    (${Env:SystemRoot} + "\System32\drivers\CyDevFltV264.sys"), # Added with Protect 3.1
    (${Env:SystemRoot} + "\System32\drivers\CyElamDrv64.cat"), # Added with Protect 3.1
    (${Env:SystemRoot} + "\System32\drivers\CyElamDrv64.inf"), # Added with Protect 3.1
    (${Env:SystemRoot} + "\System32\drivers\CyElamDrv64.sys"), # Added with Protect 3.1
    (${Env:SystemRoot} + "\ELAMBKUP\CyElamDrv64.sys") # Added with Protect 3.1
    )

    Write-Host ""
    Write-Host "Removing Files and Folders"
    foreach ($filepath3 in $FolderPaths3) {
        if (Test-Path $filepath3) {
            # Start Test-Path
            if ($filepath3 -like '*ELAM*') {
                $global:OutputFile = "";
                # This grabs the folder path like C:\Windows\Folder
                $FolderOnly = (Split-Path -Path $filepath3)
                #Take the $FolderOnly and remove the C:\
                $FolderOnly = $FolderOnly.Replace("C:\", "")
                # Append everything together
                $global:OutputFile = $PSScriptRoot + "\" + $global:Folder + "\" + $FolderOnly;
                Write-Host ""
                Write-Host " Backing up $filepath3"
                try {
                    New-Item -ItemType Directory $global:OutputFile -Force
                    Copy-Item $filepath3 -Destination $global:OutputFile -Force
                }
                catch {
                    Write-Warning "Exception caught";
                    Write-Warning "$_";
                }
            }

            # This will test is the path/file exists from FolderPaths3. If so we will delete it.
            Write-Host ""
            Write-Host " Deleting $filepath3"
            # Delete the files if they exist
            if ($global:safemode -eq "No") {
                #Start of If safemode
                # Before we delete, check if it's a ELAM file
                if ($filepath3 -like '*Elam*') { 
                    #Write-Host "Found $filepath3, Checking if Regkey exist..."
                    if (Test-Path -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\CyElamDrv') {
                        Write-Warning "  ELAM Registry still exist. Skipping delete of file"
                    }
                    else {
                        #Write-Host "Did not found ELAM regkey, safe to continue"
                        try {
                            Remove-Item -Recurse -Force $filepath3 -ErrorAction Stop
                        }
                        catch {
                            Write-Warning "Exception caught";
                            Write-Warning "$_";
                            Write-Warning "You may need to restart the endpoint and manually delete or re-run the script";
                        }
                    }
                }
                else {
                    try {
                        Remove-Item -Recurse -Force $filepath3 -ErrorAction Stop
                    }
                    catch {
                        Write-Warning "Exception caught";
                        Write-Warning "$_";
                        Write-Warning "You may need to restart the endpoint and manually delete or re-run the script";
                    }
                } #End Else
            } # End of If safemode

            else {
                Write-Host " **** safemode: No changes have been made ****"
            }
            if ($LASTEXITCODE -eq 1) {
                write-host "Exception caught";
            }
        } # End Test-Path
    }
     

    $filepath4 = ""
    $FolderPaths4 = ""
    $FolderPaths4 = @(
    (${Env:LOCALAPPDATA} + "\Cylance"),
    (${Env:Programfiles} + "\Cylance"),
    (${Env:ProgramFiles(x86)} + "\Cylance"),
    (${Env:ProgramData} + "\Cylance")
    )

    foreach ($filepath4 in $FolderPaths4) {
        if (Test-Path $filepath4) {
            # Start test-Path check
            if ((Get-ChildItem $filepath4 | Measure-Object).Count -eq 0) {
                # Start if folder-check is empty
                # Start Test-Path
                Write-Host ""
                Write-Host " Deleting $filepath4"
                if ($global:safemode -eq "No") {
                    try {
                        Remove-Item -Recurse -Force $filepath4 -ErrorAction Stop
                    }
                    catch {
                        Write-Warning "Exception caught";
                        Write-Warning "$_";
                        Write-Warning "You may need to restart the endpoint and manually delete or re-run the script";
                    }
                }
                else {
                    Write-Host " **** safemode: No changes have been made ****"
                }
                if ($LASTEXITCODE -eq 1) {
                    write-host "Exception caught";
                }
            } # End if folder-check is empty
        } # End Test-Path check
       
    } # End Delete files and folders

} # Start End Delete files and folders

function Stop-ServiceWithTimeout ([string] $name, [int] $timeoutSeconds) {
    # Start Function to handle timeout on start service 
    # Creating this function to handle cases where the script waits on stoping forever
    $timespan = New-Object -TypeName System.Timespan -ArgumentList 0, 0, $timeoutSeconds
    $svc = Get-Service -Name $name
    if ($svc -eq $null) { return $false }
    if ($svc.Status -eq [ServiceProcess.ServiceControllerStatus]::Stopped) { return $true }
    $svc.Stop()
    try {
        $svc.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped, $timespan)
    }
    catch [ServiceProcess.TimeoutException] {
        Write-Verbose "Timeout stopping service $($svc.Name)"
        return $false
    }
    return $true
} # End Function to handle timeout on start service 

function ReEnable-Windows-Defender {
    # Windows Defender WdBoot is disabled when Protect is installed by the following values
    # Disabled
    # Group = _Early-launch
    # Start = 3
    # Enabled
    # Group = Early-launch
    # Start = 0

    # Ensure that the \SYSTEM\CurrentControlSet\Services\WdBoot Key exists
    if (Test-Path -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WdBoot") {
        $global:Originalkey = ""
        $HiveAbr = ""
        $Hivepath = ""
        $global:Originalkey = "HKLM:\SYSTEM\CurrentControlSet\Services\WdBoot"
        $HiveAbr = $global:Originalkey.Substring(0, $global:Originalkey.IndexOf(':'))
        $Hivepath = $global:Originalkey.Substring($global:Originalkey.IndexOf('\') + 1)
        Write-Host ""
        Write-Host "Checking if Early-Launch is Disabled in the Registry"
        # Within the \SYSTEM\CurrentControlSet\Services\WdBoot Key, check for Group = _Early-Launch
        try { 
            $WdEarlyLaunchGroup = (Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\WdBoot -ErrorAction Stop).Group
        }
        catch {
            # Start catch
            write-Warning "Exception caught";
            write-Warning "$_";
        } # End catch

        # Within the \SYSTEM\CurrentControlSet\Services\WdBoot Key, check for Start = 3            
        try { 
            $WdEarlyLaunchStart = (Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\WdBoot -ErrorAction Stop).Start
        }
        catch {
            # Start catch
            write-Warning "Exception caught";
            write-Warning "$_";
        } # End catch

        # Within the \SYSTEM\CurrentControlSet\Services\WdBoot Key, check for ImagePath          
        try { 
            $WdEarlyLaunchImagePath = (Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\WdBoot -ErrorAction Stop).ImagePath
        }
        catch {
            # Start catch
            write-Warning "Exception caught";
            write-Warning "$_";
        } # End catch

        If ( $WdEarlyLaunchGroup -like '*_Early-Launch*' ) {
            Write-Host " 'Windows Defender Early-Launch' is Disabled($WdEarlyLaunchGroup)";
            Write-Host "  Changing Windows Defender Early-Launch to Enabled(Early-Launch)";
            if ($global:safemode -eq "No") {
        
                # try to take ownership of the folder
                Write-Host " Taking Ownership of $global:Originalkey"
                try {
                    Take-Permissions $HiveAbr $Hivepath
                }
                catch {
                    # Start catch
                    write-Warning "Exception caught";
                    write-Warning "$_";
                } # End catch

                # try to re-enable Group from _Early-Launch to Early-Launch
                try { 
                    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WdBoot" -Name "Group" -Value "Early-Launch";
                    if ($LASTEXITCODE -eq 1) {
                        write-Warning "Exception caught";
                        exit 1
                        Stop-Transcript;
                    }
                }
                catch {
                    # Start catch
                    write-Warning "Exception caught";
                    write-Warning "$_";
                } # End catch

                If ( $WdEarlyLaunchStart -eq 3 ) {
                    Write-Host " 'Windows Defender Early-Launch' Service is Disabled($WdEarlyLaunchStart)";
                    Write-Host "  Changing Windows Defender Early-Launch to Enabled(0)";
                    # try to re-enable Start to 0
                    try { 
                        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WdBoot" -Name "Start" -Value 0;
                        if ($LASTEXITCODE -eq 1) {
                            write-Warning "Exception caught";
                            exit 1
                            Stop-Transcript;
                        }
                    }
                    catch {
                        # Start catch
                        write-Warning "Exception caught";
                        write-Warning "$_";
                    } # End catch
                }                

                If ( $WdEarlyLaunchImagePath -like '*\SystemRoot\system32\drivers\wd\WdBoot.sys*' ) {
                    Write-Host " 'Windows Defender Early-Launch' ImagePath($WdEarlyLaunchImagePath)";
                    Write-Host "  Changing Windows Defender ImagePath to system32\drivers\wd\WdBoot.sys";
                    # try to re-enable Start to 0
                    try { 
                        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WdBoot" -Name "ImagePath" -Value "system32\drivers\wd\WdBoot.sys";
                        if ($LASTEXITCODE -eq 1) {
                            write-Warning "Exception caught";
                            exit 1
                            Stop-Transcript;
                        }
                    }
                    catch {
                        # Start catch
                        write-Warning "Exception caught";
                        write-Warning "$_";
                    } # End catch
                }        

            }
            else {
                Write-Host " **** safemode: No changes have been made ****"
            } # End safemode Check
        }
        else {
            Write-Host " 'Windows Defender Early-Launch' is already Enabled($WdEarlyLaunchGroup)";
        }
    }
    else {
        Write-host ""    
        Write-host "Path does not exist: HKLM:\SYSTEM\CurrentControlSet\Services\WdBoot"
    } # End If Test-Path
    
 

} # End Function to check and reenable windows defender

Check-Permissions # call Check-Permissions
Check_DisableRegistryTools # call Check_DisableRegistryTools GPO
variables # Call the variables
Check_Add/Remove # Adding a install check for this script only
modify-Self-Protection-Desktop # We need to ensure that Self Protection is enabled and set to Local Admin
modify-Self-Protection-Optics # We need to ensure that Self Protection is enabled and set to Local Admin
modify-LastStateRestorePoint # We need to ensure that LastStateRestorePoint is deleted 
modify-Services # We need to ensure that all existing services for Cylance are set to Disabled
Stop-Delete-Services # We need to attempt to stop and delete the services
Backup_Reg_Keys # Do a backup on any reg keys that will be deleted
Search_Reg_CyDevFlt # Remove CyDevFlt entries from Registry
Search_Reg_CyDevFltV2 # Remove CyDevFltV2 entries from Registry
Take-Ownership-Permission-Individual-Files # Take ownership and permissions on Individual system32 Files
Take-Ownership-Permission-Folder-Files # Take ownership and permissions on folders and sub-files
Delete-Files-n-Folders #Delete files and folders
ReEnable-Windows-Defender # Re-enbale Windows Defender if its still marked disabled

write-host ""
try { Stop-Transcript } catch {} # Stop logging here
write-host ""
write-host ""
write-Warning "Script Finished. A restart and re-run the script may be required if any errors were seen above."