<#  For authentication method see: 
    https://www.alanps1.io/powershell/connect-pnponline-unattended-using-azure-app-only-tokens/
#>

New-Module {

    <# Update the default values below - Or leave blank to be prompted for values #>
    $Script:Tenant   = "" # Like 'contoso'
    $Script:ClientID = ""
    $Script:CertPath = ""

    Function Invoke-Prerequisites {

        [OutputType()]
        [CmdletBinding()]
        Param (
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$CertPass,
        [Parameter(Mandatory = $false, HelpMessage = "Enter your O365 tenant name, like 'contoso'")]
        [ValidateNotNullorEmpty()]
        [string] $Tenant = $Tenant,
        [Parameter(Mandatory = $false, HelpMessage = "Enter your Az App Client ID")]
        [ValidateNotNullorEmpty()]
        [string] $ClientID = $ClientID,
        [Parameter(Mandatory = $false, HelpMessage = "Enter certificate .pfx path")]
        [String]$CertPath = $CertPath
        )

        $Script:MySPUrl     = "https://$($Tenant)-my.sharepoint.com/personal"
        $Script:AadDomain   = "$($Tenant).onmicrosoft.com"
        $Script:ClientID    = $ClientID
        $Script:CertPass    = $CertPass
        $Script:CertPath    = $CertPath

        If (-Not $Tenant -or -Not $ClientID -or -Not $CertPath) {

            Add-RequiredValues

        }
        Else {

            $Answer = Read-Host "Are you performing actions on $Tenant tenant (y/n)"

            While ("y", "n" -notcontains $Answer ) {
                $Answer = Read-Host "Are you performing actions on $Tenant tenant (y/n)"
            }

            If ($Answer -ne "y") {

                Add-RequiredValues

            }

        }

        $Script:RootFolder = Read-Host "Do you want to add a retention label to the 'Documents' root (y/n)"

        While ("y", "n" -notcontains $RootFolder ) {

            $RootFolder = Read-Host "Do you want to add a retention label to the 'Documents' root (y/n)"

        }

        If ($RootFolder -eq "y") {

            $Script:RootLabel = Read-Host "Enter the label to be applied to 'Documents'"
            $Answer = Read-Host "You are applying label '$RootLabel' to 'Documents' (y/n)"
            Write-Host ""

        }

        $Script:FolderLabelPairs = @()

        Initialize-FolderLabelPair

    }

    Function Add-RequiredValues {

        [ValidatePattern('^[a-zA-Z0-9]+$')]
        $Tenant             = Read-Host "Enter your O365 tenant name, like 'contoso'"

        $Script:MySPUrl     = "https://$($Tenant)-my.sharepoint.com/personal"
        $Script:AadDomain   = "$($Tenant).onmicrosoft.com"

        [ValidatePattern('^[a-zA-Z0-9]{8}-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{12}$')]
        $Script:ClientID    = Read-Host "Enter your Az App Client ID"

        $CertPath           = $null

        If (-Not $CertPath) {

            Add-Type -AssemblyName System.Windows.Forms

            $Dialog = New-Object System.Windows.Forms.OpenFileDialog
            $Dialog.InitialDirectory = "$InitialDirectory"
            $Dialog.Title = "Select certificate file"
            $Dialog.Filter = "Certificate file|*.pfx"        
            $Dialog.Multiselect = $false

            Write-Host "Please Select your certificate .pfx file"

            $Result = $Dialog.ShowDialog()

            If ($Result -eq 'OK') {

                Try {

                    $Script:CertPath = $Dialog.FileName

                }

                Catch {

                    $Script:CertPath = $null
                    Break

                }

            }

            Else {

                #Shows upon cancellation of Save Menu
                Write-Host -ForegroundColor Yellow "Notice: No file selected."
                Break

            }
        }

        Write-Host ""

    }
    Function Initialize-FolderLabelPair {

        $Folder = Read-Host "Enter folder to be created"
        $Label  = Read-Host "Enter the label to be applied to $Folder"
        $Answer = Read-Host "You are creating Folder '$Folder' and applying label '$label' (y/n)"

        While ("y", "n" -notcontains $Answer ) {

            $Answer = Read-Host "You are creating Folder '$Folder' and applying label '$label' (y/n)"

        }

        If ($Answer -eq "y") {

            $Datum = New-Object -TypeName PSObject
            $Datum | Add-Member -MemberType NoteProperty -Name FolderName -Value $Folder
            $Datum | Add-Member -MemberType NoteProperty -Name LabelName -Value $Label

        }

        $Script:FolderLabelPairs += $Datum

        $Answer = Read-Host "Would you like to create another folder (y/n)"
        While ("y", "n" -notcontains $Answer ) {

            $Answer = Read-Host "Would you like to create another folder (y/n)"

        }

        Write-Host ""

        If ($Answer -eq "y") {

            Initialize-FolderLabelPair

        }

    }

    Function Add-FolderWithLabel {

        <#
        .SYNOPSIS
        Add-FolderWithLabel firstly checks if the user has provisioned there OneDrive. If the
        user has not provisioned their OneDrive the script will do it for them. After that, the 
        script goes on to create either 3 or 4 folders within their OneDrive and adds the
        required retention label to each folder. There is a an additional label that gets added
        to the root "Documents" folder. There is no need to create that folder, just to apply
        the label. 
        
        This function will handle both authentication to PnP Online using a service pricipal and 
        then disconnect the session at the end. 
        
        This function can process multiple users at one time.

        This function depends on authentication using an Azure App connecting using the .pfx directly.
        More information here: 
        https://github.com/pnp/PnP-PowerShell/tree/master/Samples/SharePoint.ConnectUsingAppPermissions

        .DESCRIPTION
        This Function will deploy 3 folders within a user's OneDrive Folder.
        When using -Designs switch, a 4th folder is deployed cad "My Designs".
        Each folder's label has a 6 month retention applied except for "My Designs"
        which has a 7 year retention applied.

        .PARAMETER Password
        Mandatory parameter for the service principal certificate password.

        .PARAMETER UserPrincipalName
        Mandatory parameter for the service principal certificate password.

        .EXAMPLE
        PS C:\> Add-FolderWithLabel -CertPass <Cert Pass> -UserPrincipalName "john.doe@contoso.com" -Verbose

        This will create the following 3 folders and apply the required label to each folder.

        My Recipes      : Recipes
        My WorkOuts     : WorkOuts
        My Certificates : Certificates

        A label called "Default" is applied to the root Documents folder.

        .EXAMPLE
        PS C:\> Add-FolderWithLabel -CertPass <Cert Pass> -UserPrincipalName "john.doe@contoso.com", "jane.doe@contoso.com"

        This will create the following 3 folders and apply the required label to each folder.

        My Recipes      : Recipes
        My WorkOuts     : WorkOuts
        My Certificates : Certificates

        A label called "Default" is applied to the root Documents folder.

        .NOTES

        Author:  Alan Wightman
        Website: http://AlanPs1.io
        Twitter: @AlanO365

        #>

        [OutputType()]
        [CmdletBinding()]
        Param (
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$CertPass,
        [Parameter(Mandatory = $true, Position = 2)]
        [string[]] $UserPrincipalName
        )

        Invoke-Prerequisites $CertPass

        Foreach ($User in $UserPrincipalName) {

        $SiteUrl = "$($MySPUrl)/$(($User).Replace("@", "_").Replace(".", "_"))"

        $Params = @{
            ClientId            = $ClientID
            CertificatePath     = $CertPath
            CertificatePassword = (ConvertTo-SecureString -AsPlainText $CertPass -Force)
            Url                 = $SiteUrl
            Tenant              = $AadDomain
        }

        Connect-PnPOnline @Params

        $Context = New-Object Microsoft.SharePoint.Client.ClientContext($SiteUrl) 
        $web = $Context.Web 
        $Context.Load($Web)

        $TheUser = ($User).Split("@")[0]

        Write-Host "Verifying User:" $TheUser

            Try {

                $Response = Invoke-WebRequest -Uri $SiteUrl
                $StatusCode = $Response.StatusCode

            }
            Catch {

                $StatusCode = $_.Exception.Response.StatusCode.value__

            }

            If ($StatusCode -eq 200 -or $StatusCode -eq 400) {

                Write-Host -ForegroundColor Green "Site for user $TheUser has already been provisioned"

            }
            Else {

                Write-Host -ForegroundColor Yellow "Provisioning OneDrive for User: $TheUser"
                New-PnPPersonalSite -Email $User

            }

        $Response = $null
        $StatusCode = $null

            If ($RootFolder -eq "y") {
    
                Try {

                    Set-PnPLabel -List "Documents" -Label $RootLabel -SyncToItems $true -ErrorAction Stop
                    Write-Verbose "Label called '$($RootLabel)' applied to 'Documents - Root' Folder"

                } 
                Catch [Microsoft.SharePoint.Client.ServerException] {

                    Write-Warning -Message $($_.Exception.Message)

                } 
                Catch {

                    Write-Warning -Message $($_.Exception.Message)

                }

            }

        ForEach ($Entry in $Script:FolderLabelPairs) {

            $Folder = $Entry.FolderName
            $Label  = $Entry.LabelName

            Try {

                Get-PnPFolder -Url "Documents/$($Folder)" -ErrorAction Stop

            } 
            Catch [Microsoft.SharePoint.Client.ServerException] {

                Add-PnPFolder -Name $Folder -Folder "Documents" -ErrorAction Stop

            } 
            Catch {

                Write-Warning -Message $($_.Exception.Message)

            }

            $Folder = Get-PnPFolder -Url "Documents/$($Folder)"
            $Folder.ListItemAllFields.SetComplianceTagWithNoHold($Label) 
            Invoke-PnPQuery
            Write-Verbose "Label called '$($Label)' applied to '$($Folder.Name)' Folder"

        }

        Disconnect-PnPOnline

        }

    }

    # ToDo: Find-MissingFolder - This should be performed on 1 to many userprincipalnames (Pipeline compatible)
    # ToDo: Find-MissingLabel - This should be performed on 1 to many userprincipalnames (Pipeline compatible)
    # ToDo: Get-FolderStatus - This should be performed on 1 to many userprincipalnames (Pipeline compatible) & check for a single folder's existence. 
    # Record output of above, Folder exists $boolean, Label, Folder Created Date, Creator of folder

Export-ModuleMember Add-FolderWithLabel

} | Out-Null