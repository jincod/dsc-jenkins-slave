$ErrorActionPreference = "Stop"

if ($PSversionTable.PSVersion.Major -lt 5) {
    Write-Host "Download url:"
    Write-Host "https://download.microsoft.com/download/2/C/6/2C6E1B4A-EBE5-48A6-B225-2D2058A9CEFB/Win8.1AndW2K12R2-KB3134758-x64.msu"
    Write-Error "PSVersion less than 5"
}

if (!(Get-Module cChoco –ListAvailable)) {
    Install-Module –Name cChoco
}

. .\src\jenkins-create-agent.ps1

$config = cat .\config.json | ConvertFrom-Json

JenkinsAgent `
    -jenkinsUrl $config.jenkinsUrl `
    -agentName $config.agentName `
    -nodeSlaveHome $config.nodeSlaveHome `
    -username $config.username `
    -password $config.password `
    -userToken $config.userToken `
    -numExecutors $config.numExecutors `
    -label $config.label

# Run
Start-DscConfiguration -Path .\JenkinsAgent -Wait -Force –Verbose