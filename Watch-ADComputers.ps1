<#
.Notes
#===============================#
# Script: Watch-ADComputers.ps1 # 
# Author: Jordan Bradford       #
# GitHub: jrdnbradford          #
# Tested: PowerShell 5.1        #
# License: MIT                  #
#===============================#

.Synopsis
Monitors computer objects in Active Directory.

.Description
On first run, this script creates a main directory (name supplied below).
Within this directory it creates a subdirectory called Snapshots. It 
then retrieves the Name, Operating System, and Canonical Name of the 
AD computers within the set location (supplied below) and outputs 
this data into a file called Snapshot%m%d%y.csv in the Snapshots 
subdirectory. It outputs the same data into a file called ReferenceData.csv 
and also creates a text file titled Audit.txt, both in the main directory.

On every consecutive run, it retrieves the AD data, compares it to the data 
in ReferenceData.csv, and outputs the differences (or lack thereof) into the
Audit.txt file in the main directory. ReferenceData.csv then gets overwritten 
with the latest AD computer data. 

After every run, Audit.txt automatically opens in Notepad.
#>

# String. Supplies the path for the main directory.
$ADComputerAuditDir = ""

# String. Supplies the argument for Get-ADGroup's -SearchBase parameter in the script.
$Location = ""

# Create main directory
if (!(Test-Path -Path $ADComputerAuditDir)) {
    New-Item $ADComputerAuditDir -ItemType Directory
}

# Create snapshot directory
$SnapshotDir = "$ADComputerAuditDir\Snapshot History"
if (!(Test-Path -Path $SnapshotDir)) {
    New-Item $SnapshotDir -ItemType Directory
}

# Get AD computer objects
$ADComputersData = Get-ADComputer -SearchBase $Location -Filter * -Properties Name,OperatingSystem,CanonicalName | 
                   Select-Object Name,OperatingSystem,CanonicalName 
                       
# Create snapshot file
$DateSignature = Get-Date -UFormat %m%d%y 
$SnapshotPath = "$SnapshotDir\Snapshot$DateSignature.csv"
if (Test-Path -Path $SnapshotPath) {
    $I = 0
    do {
        $I++
        $SnapshotPath = "$SnapshotDir\Snapshot$DateSignature($I).csv"
    } while (Test-Path -Path $SnapshotPath)
} 
$ADComputersData | Export-Csv -Path $SnapshotPath -NoTypeInformation

# Create audit file
$Date = (Get-Date).ToString()
$AuditFilePath = "$ADComputerAuditDir\Audit.txt"
if (!(Test-Path -Path $AuditFilePath)) { 
    "AUDIT FILE CREATED: $Date`r`n" | Out-File -FilePath $AuditFilePath      
}

# Params for appending to audit file
$AuditFileParams = @{
    Append = $True
    FilePath = $AuditFilePath
    Width = 1000
}

# Add timestamp for each audit
$Timestamp = Get-Date -Format o
"Audit performed by $env:Username on $Timestamp" | Out-File @AuditFileParams 

# Block should only run if reference file exists
$RefFilePath = "$ADComputerAuditDir\ReferenceData.csv"
if (Test-Path -Path $RefFilePath) {
    # Import reference data
    $RefData = Import-Csv -Path $RefFilePath | 
               Select-Object Name,
                             @{N="OperatingSystem"; E={if ($_.OperatingSystem -eq "") {$null} else {$_.OperatingSystem}}},
                             CanonicalName
            
    # Params for comparing data
    $CompareObjectParams = @{
        ReferenceObject = $RefData
        DifferenceObject = $ADComputersData
        Property = "Name", "OperatingSystem", "CanonicalName"
    }

    # Compare imported reference data with current data and write differences to text file
    $Comparison = Compare-Object @CompareObjectParams | 
                  Select-Object Name,OperatingSystem,CanonicalName,
                                @{N="Status"; E={@{"=>" = "Added"; "<=" = "Removed"}[$_.SideIndicator]}}
    
    if ($Comparison) {  
        $Comparison | Sort-Object -Property Name,Status | Out-File @AuditFileParams 
    } else {
        "No changes to AD computers since the last audit.`r`n`r`n" | Out-File @AuditFileParams 
    }  
} else {
      "ReferenceData.csv does not exist. No comparison was made.`r`n" | Out-File @AuditFileParams
}

# Open audit file
Invoke-Item $AuditFilePath 
 
# Create/overwrite reference data file
$ADComputersData | Export-Csv -Path $RefFilePath -NoTypeInformation 