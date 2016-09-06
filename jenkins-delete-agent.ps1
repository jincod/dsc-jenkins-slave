$ErrorActionPreference = "Stop"

$config = cat .\config.json | ConvertFrom-Json

$nssm = "$PSScriptRoot\nssm.exe"
$params = @(
    '-jar',
    "$PSScriptRoot\jenkins-cli.jar",
    '-noKeyAuth',
    '-noCertificateCheck',
    '-s',
    $config.jenkinsUrl,
    'delete-node',
    $config.agentName,
    '--username',
    $config.username,
    '--password',
    $config.password
)
& $nssm stop "JenkinsAgent-$($config.agentName)"
& $nssm remove "JenkinsAgent-$($config.agentName)" confirm
& java @params