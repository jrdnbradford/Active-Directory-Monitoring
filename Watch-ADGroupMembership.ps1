<#
.Notes
#=====================================#
# Script: Watch-ADGroupMembership.ps1 #
# Author: Jordan Bradford             #
# GitHub: jrdnbradford                #
# Tested: PowerShell 5.1              #
# License: MIT                        #
#=====================================#

.Synopsis
Monitors Active Directory security groups.

.Description
On first run, this script creates a main directory (name supplied below).
Within this directory it creates a directory called Snapshots. It then retrieves the AD 
security group members for all groups within the searchbase (name supplied below) 
and outputs this data into a file called Snapshot%m%d%y.csv in the Snapshots directory. 
It outputs the same data in the main directory into a file called ReferenceData.csv and
also creates a text file titled Audit.txt. 

On every consecutive run, it retrieves the data security group from AD, compares it to
the data in ReferenceData.csv, and outputs the differences (or lack thereof) into the
Audit.txt file in the main directory. ReferenceData.csv then gets overwritten with the latest 
AD security group member data. 

After every run Audit.txt automatically opens in Notepad.
#>

# String. Supplies the path for the main directory.
$ADGroupAuditDir = ""

# String. Supplies the argument for Get-ADGroup's -SearchBase parameter in the script.
$Location = ""

# Create main directory
if (!(Test-Path -Path $ADGroupAuditDir)) {
    New-Item $ADGroupAuditDir -ItemType Directory
}

# Create snapshot directory
$SnapshotDir = "$ADGroupAuditDir\Snapshot History"
if (!(Test-Path -Path $SnapshotDir)) {
    New-Item $SnapshotDir -ItemType Directory
}

# Get AD Group objects
$ADGroups = Get-ADGroup -Filter {GroupCategory -eq "Security"} -SearchBase $Location

# For progress bar
$Length = $ADGroups.Length
$I = 0

# Get AD Group Member objects
$GroupsAuditData = ForEach ($Group in $ADGroups) {
    Get-ADGroupMember -Identity $Group |
    ForEach-Object {
        [PSCustomObject] @{
            GroupName = $Group.Name
            ADObject = $_.Name
        }
    }
   # Write progress
   $I++
   $Pct = [Math]::Round(($I * 100) / $Length)
   Write-Progress -Activity "Getting data from AD..." -Status "$Pct% Complete" -PercentComplete $Pct     
} 

# Create snapshot file
$DateSignature = Get-Date -UFormat %m%d%y 
$SnapshotPath = "$SnapshotDir\Snapshot$DateSignature.csv"
if (Test-Path -Path $SnapshotPath) {
    $J = 0
    do {
        $J++
        $SnapshotPath = "$SnapshotDir\Snapshot$DateSignature($J).csv"
    } while (Test-Path -Path $SnapshotPath)
} 
$GroupsAuditData | Export-Csv -Path $SnapshotPath -NoTypeInformation 

# Create audit file
$Date = (Get-Date).ToString()
$AuditFilePath = "$ADGroupAuditDir\Audit.txt"
if (!(Test-Path -Path $AuditFilePath)) { 
    "AUDIT FILE CREATED: $Date`r`n" | Out-File -FilePath $AuditFilePath      
}

# Params for appending to audit file
$AuditFileParams = @{
    Append = $True
    FilePath = $AuditFilePath
    Width = 100
}

# Add timestamp for each audit
$Timestamp = Get-Date -Format o
"Audit performed by $env:Username on $Timestamp" | Out-File @AuditFileParams 

# If reference file exists, import its data and compare
$RefFilePath = "$ADGroupAuditDir\ReferenceData.csv"
if (Test-Path -Path $RefFilePath) {
    # Import reference data
    $RefData = Import-Csv -Path $RefFilePath

    # Params for comparing data
    $CompareObjectParams = @{
        ReferenceObject = $RefData
        DifferenceObject = $GroupsAuditData
        Property = "GroupName", "ADObject"
    }

    # Compare imported reference data with current data and write differences to text file
    $Comparison = Compare-Object @CompareObjectParams | 
                  Select-Object GroupName,ADObject, 
                                @{N = "Status"; E = {@{"=>" = "Added"; "<=" = "Removed"}[$_.SideIndicator]}}
    
    if ($Comparison) {  
        $Comparison | Sort-Object -Property GroupName,Status | Out-File @AuditFileParams 
    } else {
        "No changes to AD group membership since the last audit.`r`n`r`n" | 
        Out-File @AuditFileParams 
    }  
} else {
      "ReferenceData.csv does not exist. No comparison was made.`r`n" | 
      Out-File @AuditFileParams
}

# Open audit file in Notepad
Notepad $AuditFilePath 
 
# Create/overwrite reference data file
$GroupsAuditData | Export-Csv -Path $RefFilePath -NoTypeInformation