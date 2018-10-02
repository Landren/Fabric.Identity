# Import Fabric Install Utilities
$fabricInstallUtilities = ".\Fabric-Install-Utilities.psm1"
if (!(Test-Path $fabricInstallUtilities -PathType Leaf)) {
    Write-DosMessage -Level "Warning" -Message "Could not find fabric install utilities. Manually downloading and installing"
    Invoke-WebRequest -Uri https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/common/Fabric-Install-Utilities.psm1 -Headers @{"Cache-Control" = "no-cache"} -OutFile $fabricInstallUtilities
}
Import-Module -Name $fabricInstallUtilities -Force

# Import Dos Install Utilities
$minVersion = [System.Version]::new(1, 0, 164 , 0)
$dosInstallUtilities = Get-Childitem -Path ./**/DosInstallUtilities.psm1 -Recurse
if ($dosInstallUtilities.length -eq 0) {
    $installed = Get-Module -Name DosInstallUtilities
    if ($null -eq $installed) {
        $installed = Get-InstalledModule -Name DosInstallUtilities
    }

    if (($null -eq $installed) -or ($installed.Version.CompareTo($minVersion) -lt 0)) {
        Write-Host "Installing DosInstallUtilities from Powershell Gallery"
        Install-Module DosInstallUtilities -Scope CurrentUser -MinimumVersion 1.0.164.0 -Force
        Import-Module DosInstallUtilities -Force
    }
}
else {
    Write-Host "Installing DosInstallUtilities at $($dosInstallUtilities.FullName)"
    Import-Module -Name $dosInstallUtilities.FullName
}

function Get-FullyQualifiedInstallationZipFile([string] $zipPackage, [string] $workingDirectory){
    if((Test-Path $zipPackage))
    {
        $path = [System.IO.Path]::GetDirectoryName($zipPackage)
        if(!$path)
        {
            $zipPackage = [System.IO.Path]::Combine($workingDirectory, $zipPackage)
        }
        Write-DosMessage -Level "Information" -Message "ZipPackage: $zipPackage is present."
        return $zipPackage
    }else{
        Write-DosMessage -Level "Error" -Message "Could not find file or directory $zipPackage, please verify that the zipPackage configuration setting in install.config is the path to a valid zip file that exists."
        throw
    }
}

function Install-DotNetCoreIfNeeded([string] $version, [string] $downloadUrl){
    if(!(Test-PrerequisiteExact "*.NET Core*Windows Server Hosting*" $version))
    {    
        try{
            Write-DosMessage -Level "Information" -Message "Windows Server Hosting Bundle version $version not installed...installing version $version"        
            Invoke-WebRequest -Uri $downloadUrl -OutFile $env:Temp\bundle.exe
            Start-Process $env:Temp\bundle.exe -Wait -ArgumentList '/quiet /install'
            Restart-W3SVC
        }catch{
            Write-DosMessage -Level "Error" -Message "Could not install .NET Windows Server Hosting bundle. Please install the hosting bundle before proceeding. $downloadUrl"
            throw
        }
        try{
            Remove-Item $env:Temp\bundle.exe
        }catch{
            $e = $_.Exception
            Write-DosMessage -Level "Warning" -Message "Unable to remove temporary download file for server hosting bundle exe" 
            Write-DosMessage -Level "Warning" -Message  $e.Message
        }

    }else{
        Write-DosMessage -Level "Information" -Message  ".NET Core Windows Server Hosting Bundle (v$version) installed and meets expectations."
    }
}

function Get-IISWebSiteForInstall([string] $selectedSiteName, [string] $installConfigPath, [bool] $quiet){
    try{
        $sites = Get-ChildItem IIS:\Sites
        if($quiet -eq $true){
            $selectedSite = $sites | Where-Object { $_.Name -eq $selectedSiteName }
        }else{
            if($sites -is [array]){
                $sites |
                    ForEach-Object {New-Object PSCustomObject -Property @{
                        'Id'=$_.id;
                        'Name'=$_.name;
                        'Physical Path'=[System.Environment]::ExpandEnvironmentVariables($_.physicalPath);
                        'Bindings'=$_.bindings;
                    };} |
                    Format-Table Id,Name,'Physical Path',Bindings -AutoSize | Out-Host
                
                $attempts = 1
                do {
                    if($attempts -gt 10){
                        Write-DosMessage -Level "Error" -Message "An invalid website has been selected."
                        throw
                    }
                    $selectedSiteId = Read-Host "Select a web site by Id"
                    $selectedSite = $sites[$selectedSiteId - 1]
                    if([string]::IsNullOrEmpty($selectedSiteId)){
                        Write-DosMessage -Level "Information" -Message "You must select a web site."
                    }
                    if($null -eq $selectedSite){
                        Write-DosMessage -Level "Information" -Message "You must select a web site by id between 1 and $($sites.Count)."
                    }
                    $attempts++
                } while ([string]::IsNullOrEmpty($selectedSiteId) -or ($null -eq $selectedSite))
                
            }else{
                $selectedSite = $sites
            }
        }
        if($null -eq $selectedSite){
            throw "Could not find selected site."
        }
        if($selectedSite.Name){ Add-InstallationSetting "identity" "siteName" $selectedSite.Name $installConfigPath | Out-Null }

        return $selectedSite

    }catch{
        Write-DosMessage -Level "Error" -Message "Could not select a website."
        throw
    }
}

function New-SigningAndEncryptionCertificate([string] $subject, [string] $certStorelocation)
{
    $cert = New-SelfSignedCertificate -Type Custom -Subject $subject -KeyUsage DataEncipherment, DigitalSignature -KeyAlgorithm RSA -KeyLength 2048 -CertStoreLocation $certStoreLocation
    return $cert
}

function Get-Certificates([string] $primarySigningCertificateThumbprint, [string] $encryptionCertificateThumbprint, [string] $installConfigPath, [bool] $quiet){
    if(Test-ShouldShowCertMenu -primarySigningCertificateThumbprint $primarySigningCertificateThumbprint `
                                -encryptionCertificateThumbprint $encryptionCertificateThumbprint `
                                -quiet $quiet){
        try{
            $today = Get-Date
            $allCerts = Get-CertsFromLocation Cert:\LocalMachine\My
            $index = 1
            $attempts = 1
            $allCerts | 
                Where-Object { $_.NotAfter -ge $today -and $_.NotBefore -le $today } |
                ForEach-Object {New-Object PSCustomObject -Property @{
                'Index'=$index;
                'Subject'= $_.Subject; 
                'Name' = $_.FriendlyName; 
                'Thumbprint' = $_.Thumbprint; 
                'Expiration' = $_.NotAfter
                };
                $index ++} |
                Format-Table Index,Name,Subject,Expiration,Thumbprint  -AutoSize | Out-Host
            do {
                if($attempts -gt 10){
                    Write-DosMessage -Level "Error" -Message "An invalid certificate has been selected."
                    throw
                }
                $selectionNumber = Read-Host  "Select a signing and encryption certificate by Index"
                if([string]::IsNullOrEmpty($selectionNumber)){
                    Write-DosMessage -Level "Information" -Message "You must select a certificate so Fabric.Identity can sign access and identity tokens."
                }else{
                    $selectionNumberAsInt = [convert]::ToInt32($selectionNumber, 10)
                    if(($selectionNumberAsInt -gt  $allCerts.Count) -or ($selectionNumberAsInt -le 0)){
                        Write-DosMessage -Level "Information" -Message  "Please select a certificate with index between 1 and $($allCerts.Count)."
                    }
                }
                $attempts++
            } while ([string]::IsNullOrEmpty($selectionNumber) -or ($selectionNumberAsInt -gt $allCerts.Count) -or ($selectionNumberAsInt -le 0))

            $certThumbprint = Get-CertThumbprint $allCerts $selectionNumberAsInt
            
            if([string]::IsNullOrWhitespace($primarySigningCertificateThumbprint)){
                $primarySigningCertificateThumbprint = $certThumbprint -replace '[^a-zA-Z0-9]', ''
            }
    
            if ([string]::IsNullOrWhitespace($encryptionCertificateThumbprint)){
                $encryptionCertificateThumbprint = $certThumbprint -replace '[^a-zA-Z0-9]', ''
            }
    
        }catch{
            Write-DosMessage -Level "Error" -Message  "Could not set the certificate thumbprint. Error $($_.Exception.Message)"
            throw
        }
    }
    try{
        $signingCert = Get-Certificate ($primarySigningCertificateThumbprint -replace '[^a-zA-Z0-9]', '')
    }catch{
        Write-DosMessage -Level "Error" -Message  "Could not get signing certificate with thumbprint $primarySigningCertificateThumbprint. Please verify that the primarySigningCertificateThumbprint setting in install.config contains a valid thumbprint for a certificate in the Local Machine Personal store."
        throw $_.Exception
    }

    try{
        $encryptionCert = Get-Certificate ($encryptionCertificateThumbprint -replace '[^a-zA-Z0-9]', '')
    }catch{
        Write-DosMessage -Level "Error" -Message  "Could not get encryption certificate with thumbprint $encryptionCertificateThumbprint. Please verify that the encryptionCertificateThumbprint setting in install.config contains a valid thumbprint for a certificate in the Local Machine Personal store."
        throw $_.Exception
    }
    if($encryptionCert.Thumbprint){ Add-InstallationSetting "common" "encryptionCertificateThumbprint" $encryptionCert.Thumbprint $installConfigPath | Out-Null }
    if($encryptionCert.Thumbprint){ Add-InstallationSetting "identity" "encryptionCertificateThumbprint" $encryptionCert.Thumbprint $installConfigPath | Out-Null }
    if($signingCert.Thumbprint){ Add-InstallationSetting "identity" "primarySigningCertificateThumbprint" $signingCert.Thumbprint $installConfigPath | Out-Null }
    return @{SigningCertificate = $signingCert; EncryptionCertificate = $encryptionCert}
}

function Get-IISAppPoolUser([PSCredential] $credential, [string] $appName, [string] $storedIisUser, [string] $installConfigPath){
    if($credential){
        Confirm-Credentials -credential $credential
        $iisUser = "$($credential.GetNetworkCredential().Domain)\$($credential.GetNetworkCredential().UserName)"
    }
    elseif(Test-AppPoolExistsAndRunsAsUser -appPoolName $appName -userName $storedIisUser){
        $iisUser = $storedIisUser
    }
    else{
        if(![string]::IsNullOrEmpty($storedIisUser)){
            $userEnteredIisUser = Read-Host "Press Enter to accept the default IIS App Pool User '$($storedIisUser)' or enter a new App Pool User"
            if([string]::IsNullOrEmpty($userEnteredIisUser)){
                $userEnteredIisUser = $storedIisUser
            }
        }else{
            $userEnteredIisUser = Read-Host "Please enter a user account for the App Pool"
        }
    
        if(![string]::IsNullOrEmpty($userEnteredIisUser)){
        
            $iisUser = $userEnteredIisUser
            $userEnteredPassword = Read-Host "Enter the password for $iisUser" -AsSecureString
            $credential = Get-ConfirmedCredentials -iisUser $iisUser -userEnteredPassword $userEnteredPassword
            Write-DosMessage -Level "Information" -Message "Credentials are valid for user $iisUser"
        }else{
            Write-DosMessage -Level "Error" -Message "No user account was entered, please enter a valid user account."
            throw
        }
    }
    if($iisUser){ Add-InstallationSetting "identity" "iisUser" "$iisUser" $installConfigPath | Out-Null }
    return @{UserName = $iisUser; Credential = $credential}
}

function Get-ConfirmedCredentials([string] $iisUser, [SecureString] $userEnteredPassword){
    $credential = New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList $iisUser, $userEnteredPassword
    Confirm-Credentials -credential $credential
    return $credential
}

function Confirm-Credentials([PSCredential] $credential){
    [System.Reflection.Assembly]::LoadWithPartialName("System.DirectoryServices.AccountManagement") | Out-Null
    $ct = [System.DirectoryServices.AccountManagement.ContextType]::Domain
    $pc = New-Object System.DirectoryServices.AccountManagement.PrincipalContext -ArgumentList $ct,$credential.GetNetworkCredential().Domain
    Write-Host "Confirming credentials"
    $isValid = $pc.ValidateCredentials($credential.GetNetworkCredential().UserName, $credential.GetNetworkCredential().Password, [System.DirectoryServices.AccountManagement.ContextOptions]::Negotiate)
    if(!$isValid){
        Write-DosMessage -Level "Error" -Message "Incorrect credentials for $($credential.GetNetworkCredential().UserName)"
        throw
    }
}

function Add-PermissionToPrivateKey([string] $iisUser, [System.Security.Cryptography.X509Certificates.X509Certificate2] $signingCert, [string] $permission){
    try{
        $allowRule = New-Object security.accesscontrol.filesystemaccessrule $iisUser, $permission, allow
        $keyFolder = "c:\programdata\microsoft\crypto\rsa\machinekeys"

        $keyname = $signingCert.privatekey.cspkeycontainerinfo.uniquekeycontainername
        $keyPath = [io.path]::combine($keyFolder, $keyname)

        if ([io.file]::exists($keyPath))
        {        
            $acl = Get-Acl $keyPath
            $acl.AddAccessRule($allowRule)
            Set-Acl $keyPath $acl -ErrorAction Stop
            Write-DosMessage -Level "Information" -Message "The permission '$($permission)' was successfully added to the private key for user '$($iisUser)'"
        }else{
            Write-DosMessage -Level "Error" -Message "No key file was found at '$($keyPath)' for '$($signingCert)'. Ensure a valid signing certificate was provided"
            throw
        }
    }catch{
        Write-DosMessage -Level "Error" -Message "There was an error adding the '$($permission)' permission for the user '$($iisUser)' to the private key. Ensure you selected a certificate that you have read access on the private key. Error $($_.Exception.Message)."
        throw
    }
}

function Get-AppInsightsKey([string] $appInsightsInstrumentationKey, [string] $installConfigPath, [bool] $quiet){
    if(!$quiet){
        $userEnteredAppInsightsInstrumentationKey = Read-Host  "Enter Application Insights instrumentation key or hit enter to accept the default [$appInsightsInstrumentationKey]"

        if(![string]::IsNullOrEmpty($userEnteredAppInsightsInstrumentationKey)){   
            $appInsightsInstrumentationKey = $userEnteredAppInsightsInstrumentationKey
        }
    }
    if($appInsightsInstrumentationKey){ Add-InstallationSetting "identity" "appInsightsInstrumentationKey" "$appInsightsInstrumentationKey" $installConfigPath | Out-Null }
    if($appInsightsInstrumentationKey){ Add-InstallationSetting "common" "appInsightsInstrumentationKey" "$appInsightsInstrumentationKey" $installConfigPath  Out-Null }
    return $appInsightsInstrumentationKey
}

function Get-SqlServerAddress([string] $sqlServerAddress, [string] $installConfigPath, [bool] $quiet){
    if(!$quiet){
        $userEnteredSqlServerAddress = Read-Host "Press Enter to accept the default Sql Server address '$($sqlServerAddress)' or enter a new Sql Server address" 

        if(![string]::IsNullOrEmpty($userEnteredSqlServerAddress)){
            $sqlServerAddress = $userEnteredSqlServerAddress
        }
    }
    if($sqlServerAddress){ Add-InstallationSetting "common" "sqlServerAddress" "$sqlServerAddress" $installConfigPath | Out-Null }
    return $sqlServerAddress
}

function Get-IdentityDatabaseConnectionString([string] $identityDbName, [string] $sqlServerAddress, [string] $installConfigPath, [bool] $quiet){
    if(!$quiet){
        $userEnteredIdentityDbName = Read-Host "Press Enter to accept the default Identity DB Name '$($identityDbName)' or enter a new Identity DB Name"
        if(![string]::IsNullOrEmpty($userEnteredIdentityDbName)){
            $identityDbName = $userEnteredIdentityDbName
        }
    }
    $identityDbConnStr = "Server=$($sqlServerAddress);Database=$($identityDbName);Trusted_Connection=True;MultipleActiveResultSets=True;"

    Invoke-Sql $identityDbConnStr "SELECT TOP 1 ClientId FROM Clients" | Out-Null
    Write-DosMessage -Level "Information" -Message "Identity DB Connection string: $identityDbConnStr verified"
    if($identityDbName){ Add-InstallationSetting "identity" "identityDbName" "$identityDbName" $installConfigPath | Out-Null }
    return @{DbName = $identityDbName; DbConnectionString = $identityDbConnStr}
}

function Get-MetadataDatabaseConnectionString([string] $metadataDbName, [string] $sqlServerAddress, [string] $installConfigPath, [bool] $quiet){
    if(!($quiet)){
        $userEnteredMetadataDbName = Read-Host "Press Enter to accept the default Metadata DB Name '$($metadataDbName)' or enter a new Metadata DB Name"
        if(![string]::IsNullOrEmpty($userEnteredMetadataDbName)){
            $metadataDbName = $userEnteredMetadataDbName
        }
    }
    $metadataConnStr = "Server=$($sqlServerAddress);Database=$($metadataDbName);Trusted_Connection=True;MultipleActiveResultSets=True;"

    Invoke-Sql $metadataConnStr "SELECT TOP 1 RoleID FROM CatalystAdmin.RoleBASE" | Out-Null
    Write-DosMessage -Level "Information" -Message "Metadata DB Connection string: $metadataConnStr verified"
    if($metadataDbName){ Add-InstallationSetting "common" "metadataDbName" "$metadataDbName" $installConfigPath | Out-Null }
    return @{DbName = $metadataDbName; DbConnectionString = $metadataConnStr}
}

function Get-DiscoveryServiceUrl([string]$discoveryServiceUrl, [string] $installConfigPath, [bool]$quiet){
    $defaultDiscoUrl = Get-DefaultDiscoveryServiceUrl -discoUrl $discoveryServiceUrl
    if(!$quiet){
        $userEnteredDiscoveryServiceUrl = Read-Host "Press Enter to accept the default DiscoveryService URL [$defaultDiscoUrl] or enter a new URL"
        if(![string]::IsNullOrEmpty($userEnteredDiscoveryServiceUrl)){   
            $defaultDiscoUrl = $userEnteredDiscoveryServiceUrl
        }
    }
    if($defaultDiscoUrl){ Add-InstallationSetting "common" "discoveryService" "$defaultDiscoUrl" $installConfigPath | Out-Null }
    return $defaultDiscoUrl
}

function Get-ApplicationEndpoint([string] $appName, [string] $applicationEndpoint, [string] $installConfigPath, [bool] $quiet){
    $defaultAppEndpoint = Get-DefaultApplicationEndpoint -appName $appName -appEndPoint $applicationEndpoint
    if(!$quiet){
        $userEnteredApplicationEndpoint = Read-Host "Press Enter to accept the default Application Endpoint URL [$defaultAppEndpoint] or enter a new URL"
        if(![string]::IsNullOrEmpty($userEnteredApplicationEndpoint)){
            $defaultAppEndpoint = $userEnteredApplicationEndpoint
        }
    }
    if($defaultAppEndpoint){ Add-InstallationSetting "identity" "applicationEndPoint" "$defaultAppEndpoint" $installConfigPath | Out-Null }
    if($defaultAppEndpoint){ Add-InstallationSetting "common" "identityService" "$defaultAppEndpoint" $installConfigPath | Out-Null }
    return $defaultAppEndpoint
}

function Unlock-ConfigurationSections(){   
    [System.Reflection.Assembly]::LoadFrom("$env:systemroot\system32\inetsrv\Microsoft.Web.Administration.dll") | Out-Null
    $manager = new-object Microsoft.Web.Administration.ServerManager      
    $config = $manager.GetApplicationHostConfiguration()

    $section = $config.GetSection("system.webServer/security/authentication/anonymousAuthentication")
    $section.OverrideMode = "Allow"    
    Write-DosMessage -Level "Information" -Message "Unlocked system.webServer/security/authentication/anonymousAuthentication"

    $section = $config.GetSection("system.webServer/security/authentication/windowsAuthentication")
    $section.OverrideMode = "Allow"    
    Write-DosMessage -Level "Information" -Message "Unlocked system.webServer/security/authentication/windowsAuthentication"
    
    $manager.CommitChanges()
}

function Publish-Identity([System.Object] $site, [string] $appName, [hashtable] $iisUser, [string] $zipPackage){
    $appDirectory = [io.path]::combine([System.Environment]::ExpandEnvironmentVariables($site.physicalPath), $appName)
    New-AppRoot $appDirectory $iisUser.UserName

    if(!(Test-AppPoolExistsAndRunsAsUser -appPoolName $appName -userName $iisUser.UserName)){
        New-AppPool $appName $iisUser.UserName $iisUser.Credential
    }

    New-App $appName $site.Name $appDirectory | Out-Null
    Publish-WebSite $zipPackage $appDirectory $appName $true
    Set-Location $PSScriptRoot
    $version = Get-InstalledVersion -appDirectory $appDirectory -assemblyPath "Fabric.Identity.API.dll"
    return @{applicationDirectory = $appDirectory; version = $version }
}

function Get-InstalledVersion([string] $appDirectory, [string] $assemblyPath){
    return [System.Diagnostics.FileVersionInfo]::GetVersionInfo("$appDirectory\$assemblyPath").FileVersion
}

function Register-IdentityWithDiscovery([string] $iisUserName, [string] $metadataConnStr, [string] $version, [string] $identityServerUrl){
    Add-ServiceUserToDiscovery $iisUserName $metadataConnStr

    $discoveryPostBody = @{
        buildVersion = $version;
        serviceName = "IdentityService";
        serviceVersion = 1;
        friendlyName = "Fabric.Identity";
        description = "The Fabric.Identity service provides centralized authentication across the Fabric ecosystem.";
        identityServerUrl = $identityServerUrl;
        serviceUrl = $identityServerUrl;
        discoveryType = "Service";
    }
    Add-DiscoveryRegistrationSql -discoveryPostBody $discoveryPostBody -connectionString $metadataConnStr | Out-Null
    Write-DosMessage -Level "Information" -Message "Identity registered URL: $identityServerUrl with DiscoveryService."
}

function Add-DatabaseSecurity([string] $userName, [string] $role, [string] $connString)
{
    Add-DatabaseLogin $userName $connString
    Add-DatabaseUser $userName $connString
    Add-DatabaseUserToRole $userName $connString $role
    Write-DosMessage -Level "Information" -Message "Database security applied successfully"
}

function Set-IdentityEnvironmentVariables([string] $appDirectory, `
    [string] $primarySigningCertificateThumbprint, `
    [string] $encryptionCertificateThumbprint, `
    [string] $appInsightsInstrumentationKey, `
    [string] $applicationEndpoint, `
    [string] $identityDbConnStr, `
    [string] $discoveryServiceUrl, `
    [bool] $noDiscoveryService){
    $environmentVariables = @{"HostingOptions__StorageProvider" = "SqlServer"; "HostingOptions__UseTestUsers" = "false"; "AllowLocalLogin" = "false"}

    if ($primarySigningCertificateThumbprint){
        $environmentVariables.Add("SigningCertificateSettings__UseTemporarySigningCredential", "false")
        $environmentVariables.Add("SigningCertificateSettings__PrimaryCertificateThumbprint", $primarySigningCertificateThumbprint)
    }

    if ($encryptionCertificateThumbprint){
        $environmentVariables.Add("SigningCertificateSettings__EncryptionCertificateThumbprint", $encryptionCertificateThumbprint)
    }

    if($appInsightsInstrumentationKey){
        $environmentVariables.Add("ApplicationInsights__Enabled", "true")
        $environmentVariables.Add("ApplicationInsights__InstrumentationKey", $appInsightsInstrumentationKey)
    }

    $environmentVariables.Add("IdentityServerConfidentialClientSettings__Authority", "$applicationEndpoint")

    if($identityDbConnStr){
        $environmentVariables.Add("ConnectionStrings__IdentityDatabase", $identityDbConnStr)
    }

    if(!($noDiscoveryService) -and $discoveryServiceUrl){
        $environmentVariables.Add("DiscoveryServiceEndpoint", "$discoveryServiceUrl")
        $environmentVariables.Add("UseDiscoveryService", "true")
    }else{
        $environmentVariables.Add("UseDiscoveryService", "false")
    }

    Set-EnvironmentVariables $appDirectory $environmentVariables | Out-Null
}

function Add-RegistrationApiRegistration([string] $identityServerUrl, [string] $accessToken){
    $body = @{
        Name = "registration-api";
        UserClaims = @("name","email","role","groups");
        Scopes = @(@{Name = "fabric/identity.manageresources"}, @{ Name = "fabric/identity.read"}, @{ Name = "fabric/identity.searchusers"});
    }
    $jsonBody = ConvertTo-Json $body

    Write-DosMessage -Level "Information" -Message "Registering Fabric.Identity Registration API."
    $registrationApiSecret = ([string](Add-ApiRegistration -authUrl $identityServerUrl -body $jsonBody -accessToken $accessToken)).Trim()
    return $registrationApiSecret
}

function Add-InstallerClientRegistration([string] $identityServerUrl, [string] $accessToken, [string] $fabricInstallerSecret){
    $body = @{
        ClientId = "fabric-installer";
        ClientName = "Fabric Installer";
        RequireConsent = $false;
        AllowedGrantTypes = @("client_credentials");
        AllowedScopes = @("fabric/identity.manageresources", "fabric/authorization.read", "fabric/authorization.write", "fabric/authorization.dos.write", "fabric/authorization.manageclients")
    }
    $jsonBody = ConvertTo-Json $body

    Write-DosMessage -Level "Information" -Message "Registering Fabric.Installer Client."
    $installerClientSecret = ([string](Add-ClientRegistration -authUrl $identityServerUrl -body $jsonBody -accessToken $accessToken -shouldResetSecret $false)).Trim()
    
    if([string]::IsNullOrWhiteSpace($installerClientSecret)) {
        $installerClientSecret = $fabricInstallerSecret
    }
    return $installerClientSecret
}

function Add-IdentityClientRegistration([string] $identityServerUrl, [string] $accessToken){
    $body = @{
        ClientId = "fabric-identity-client"; 
        ClientName = "Fabric Identity Client"; 
        RequireConsent = $false;
        AllowedGrantTypes = @("client_credentials"); 
        AllowedScopes = @("fabric/idprovider.searchusers");
    }
    $jsonBody = ConvertTo-Json $body

    Write-DosMessage -Level "Information" -Message "Registering Fabric.Identity Client."
    $identityClientSecret = ([string](Add-ClientRegistration -authUrl $identityServerUrl -body $jsonBody -accessToken $accessToken)).Trim()
    return $identityClientSecret
}

function Add-SecureIdentityEnvironmentVariables([System.Security.Cryptography.X509Certificates.X509Certificate2] $encryptionCert, [string] $identityClientSecret, [string] $registrationApiSecret, [string] $appDirectory){
    $environmentVariables = @{}
    if($identityClientSecret){
        $encryptedSecret = Get-EncryptedString $encryptionCert $identityClientSecret
        $environmentVariables.Add("IdentityServerConfidentialClientSettings__ClientSecret", $encryptedSecret)
    }
    
    if($registrationApiSecret){
        $encryptedSecret = Get-EncryptedString $encryptionCert $registrationApiSecret
        $environmentVariables.Add("IdentityServerApiSettings__ApiSecret", $encryptedSecret)
    }
    Set-EnvironmentVariables $appDirectory $environmentVariables | Out-Null
}

function Test-RegistrationComplete([string] $authUrl)
{
    $url = "$authUrl/api/client/fabric-installer"
    $headers = @{"Accept" = "application/json"}
    
    try {
        Invoke-RestMethod -Method Get -Uri $url -Headers $headers
    } catch {
        $exception = $_.Exception
    }

    if($null -ne $exception -and $exception.Response.StatusCode.value__ -eq 401)
    {
        Write-DosMessage -Level "Information" -Message "Fabric registration is already complete."
        return $true
    }

    return $false
}

function Test-MeetsMinimumRequiredPowerShellVerion([int] $majorVersion){
    if($PSVersionTable.PSVersion.Major -lt $majorVersion){
        Write-DosMessage -Level "Error" -Message "PowerShell version $majorVersion is the minimum required version to run this installation. PowerShell version $($PSVersionTable.PSVersion) is currently installed."
        throw
    }
}

function Add-DatabaseLogin([string] $userName, [string] $connString)
{
    $query = "USE master
            If Not exists (SELECT * FROM sys.server_principals
                WHERE sid = suser_sid(@userName))
            BEGIN
                print '-- creating database login'
                DECLARE @sql nvarchar(4000)
                set @sql = 'CREATE LOGIN ' + QUOTENAME('$userName') + ' FROM WINDOWS'
                EXEC sp_executesql @sql
            END"
    Invoke-Sql $connString $query @{userName=$userName} | Out-Null
}

function Add-DatabaseUser([string] $userName, [string] $connString)
{
    $query = "IF( NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = @userName))
            BEGIN
                print '-- Creating user';
                DECLARE @sql nvarchar(4000)
                set @sql = 'CREATE USER ' + QUOTENAME('$userName') + ' FOR LOGIN ' + QUOTENAME('$userName')
                EXEC sp_executesql @sql
            END"
    Invoke-Sql $connString $query @{userName=$userName} | Out-Null
}

function Add-DatabaseUserToRole([string] $userName, [string] $connString, [string] $role)
{
    $query = "DECLARE @exists int
            SELECT @exists = IS_ROLEMEMBER(@role, @userName) 
            IF (@exists IS NULL OR @exists = 0)
            BEGIN
                print '-- Adding @role to @userName';
                EXEC sp_addrolemember @role, @userName;
            END"
    Invoke-Sql $connString $query @{userName=$userName; role=$role} | Out-Null
}
function Add-ServiceUserToDiscovery([string] $userName, [string] $connString){

    $query = "DECLARE @IdentityID int;
                DECLARE @DiscoveryServiceUserRoleID int;

                SELECT @IdentityID = IdentityID FROM CatalystAdmin.IdentityBASE WHERE IdentityNM = @userName;
                IF (@IdentityID IS NULL)
                BEGIN
                    print ''-- Adding Identity'';
                    INSERT INTO CatalystAdmin.IdentityBASE (IdentityNM) VALUES (@userName);
                    SELECT @IdentityID = SCOPE_IDENTITY();
                END

                SELECT @DiscoveryServiceUserRoleID = RoleID FROM CatalystAdmin.RoleBASE WHERE RoleNM = 'DiscoveryServiceUser';
                IF (NOT EXISTS (SELECT 1 FROM CatalystAdmin.IdentityRoleBASE WHERE IdentityID = @IdentityID AND RoleID = @DiscoveryServiceUserRoleID))
                BEGIN
                    print ''-- Assigning Discovery Service user'';
                    INSERT INTO CatalystAdmin.IdentityRoleBASE (IdentityID, RoleID) VALUES (@IdentityID, @DiscoveryServiceUserRoleID);
                END"
    Invoke-Sql $connString $query @{userName=$userName} | Out-Null
}

function Restart-W3SVC(){
    net stop was /y
    net start w3svc
}

function Test-ShouldShowCertMenu([string] $primarySigningCertificateThumbprint, [string] $encryptionCertificateThumbprint, [bool] $quiet){
    return !$quiet -and ([string]::IsNullOrWhitespace($encryptionCertificateThumbprint) -or [string]::IsNullOrWhitespace($primarySigningCertificateThumbprint))
}

function Get-DefaultDiscoveryServiceUrl([string] $discoUrl)
{
    if([string]::IsNullOrEmpty($discoUrl)){
        return "$(Get-FullyQualifiedMachineName)/DiscoveryService/v1"
    }else{
	      $discoUrl = $discoUrl.TrimEnd("/")
          if ($discoUrl -notmatch "/v\d")
		  {
	  		  return $discoUrl + "/v1"
		  }
		  else 
		  {
		  	  return $discoUrl
		  }
    }
}

function Get-DefaultApplicationEndpoint([string] $appName, [string] $appEndPoint)
{
    if([string]::IsNullOrEmpty($appEndPoint)){
        return "$(Get-FullyQualifiedMachineName)/$appName"
    }else{
        return $appEndPoint
    }
}

function Get-FullyQualifiedMachineName() {
	return "https://$env:computername.$((Get-WmiObject Win32_ComputerSystem).Domain.tolower())"
}

Export-ModuleMember Get-FullyQualifiedInstallationZipFile
Export-ModuleMember Install-DotNetCoreIfNeeded
Export-ModuleMember Get-IISWebSiteForInstall
Export-ModuleMember Get-Certificates
Export-ModuleMember Get-IISAppPoolUser
Export-ModuleMember Add-PermissionToPrivateKey
Export-ModuleMember Get-AppInsightsKey
Export-ModuleMember Get-SqlServerAddress
Export-ModuleMember Get-IdentityDatabaseConnectionString
Export-ModuleMember Get-MetadataDatabaseConnectionString
Export-ModuleMember Get-DiscoveryServiceUrl
Export-ModuleMember Get-ApplicationEndpoint
Export-ModuleMember Unlock-ConfigurationSections
Export-ModuleMember Publish-Identity
Export-ModuleMember Register-IdentityWithDiscovery
Export-ModuleMember Add-DatabaseSecurity
Export-ModuleMember Set-IdentityEnvironmentVariables
Export-ModuleMember Add-RegistrationApiRegistration
Export-ModuleMember Add-IdentityClientRegistration
Export-ModuleMember Add-SecureIdentityEnvironmentVariables
Export-ModuleMember Test-RegistrationComplete
Export-ModuleMember Add-InstallerClientRegistration
Export-ModuleMember Test-MeetsMinimumRequiredPowerShellVerion