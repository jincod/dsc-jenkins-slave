$ErrorActionPreference = "Stop"

$config = cat .\config.json | ConvertFrom-Json

$root = resolve-path "$PSScriptRoot\.."
$nssm = "$root\nssm.exe"

$params = @(
    '-jar',
    "$root\bin\jenkins-cli.jar",
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