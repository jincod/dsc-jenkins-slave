$DscWorkingFolder = $PSScriptRoot
$nssm = "$PSScriptRoot\nssm.exe"

Configuration JenkinsAgent {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$jenkinsUrl,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$agentName,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$nodeSlaveHome,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$username,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$password,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$userToken,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$numExecutors,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$label
    )

    Import-DscResource –ModuleName PSDesiredStateConfiguration, cChoco

    node "localhost" {

        WindowsFeature NetFrameworkCore
        {
            Ensure = "Present"
            Name = "NET-Framework-Core"
        }

        cChocoInstaller installChoco
        {
            InstallDir = "c:\choco"
            DependsOn = "[WindowsFeature]NetFrameworkCore"
        }

        cChocoPackageInstaller installJdk8
        {
            Name = "jdk8"
            DependsOn = "[cChocoInstaller]installChoco"
        }

        cChocoPackageInstaller installGit
        {
            Name = "git.install"
            DependsOn = "[cChocoInstaller]installChoco"
        }

        Script DownloadFiles {
            DependsOn = "[cChocoPackageInstaller]installJdk8";
            GetScript = {
                return @{
                    Result = (
                        (Test-Path -Path "$($using:DscWorkingFolder)\node-v4.5.0-x64.msi") -and
                        (Test-Path -Path "$($using:DscWorkingFolder)\slave.jar") -and
                        (Test-Path -Path "$($using:DscWorkingFolder)\jenkins-cli.jar")
                    );
                }
            };
            SetScript = {
                $files = @(@{
                    name = "slave.jar";
                    url = "$using:jenkinsUrl/jnlpJars/slave.jar"
                }, @{
                    name = "jenkins-cli.jar";
                    url = "$using:jenkinsUrl/jnlpJars/jenkins-cli.jar"
                }, @{
                    name = "node-v4.5.0-x64.msi";
                    url = "https://nodejs.org/dist/v4.5.0/node-v4.5.0-x64.msi"
                })

                foreach ($f in $files) {
                    $OutFile = "$($using:DscWorkingFolder)\$($f.name)";
                    Invoke-WebRequest -Uri $f.url -OutFile $OutFile;
                    Unblock-File -Path $OutFile;
                }
            };
            TestScript = {
                (Test-Path -Path "$($using:DscWorkingFolder)\node-v4.5.0-x64.msi") -and
                (Test-Path -Path "$($using:DscWorkingFolder)\slave.jar") -and
                (Test-Path -Path "$($using:DscWorkingFolder)\jenkins-cli.jar")
            }
        }

        Package installNodeJS
        {
            DependsOn = "[Script]DownloadFiles";
            Name = 'Node.js';
            Path = "$DscWorkingFolder\node-v4.5.0-x64.msi";
            Ensure = 'Present';
            ProductId = '';
            Arguments = 'ALLUSERS=1';
        }

        Script AddJenkinsAgent {
            DependsOn = "[Script]DownloadFiles";
            GetScript = {
                return @{
                    Result = '';
                }
            };
            SetScript = {
                $params = @(
                    '-jar',
                    "$($using:DscWorkingFolder)\jenkins-cli.jar",
                    '-noKeyAuth',
                    '-noCertificateCheck',
                    '-s',
                    "$using:jenkinsUrl",
                    'create-node',
                    "$using:agentName",
                    '--username',
                    "$using:username",
                    '--password',
                    "$using:password"
                )
                (gc "$($using:DscWorkingFolder)\node.xml") -replace '{agentName}', "$using:agentName"`
                    -replace '{nodeSlaveHome}', "$using:nodeSlaveHome"`
                    -replace '{numExecutors}', "$using:numExecutors"`
                    -replace '{label}', "$using:label" |
                    & java @params
            };
            TestScript = {
                if (Get-Service "JenkinsAgent-$using:agentName" -ErrorAction SilentlyContinue)
                {
                   return $true
                }
                return $false
            }
        }

        Script InstallJenkinsAgentService {
            DependsOn = "[Script]AddJenkinsAgent";
            GetScript = {
                return @{
                    Result = (Test-Path -Path $using:nssm);
                }
            };
            SetScript = {
                $params = @(
                    'install',
                    "JenkinsAgent-$using:agentName",
                    'java',
                    '-jar',
                    "$($using:DscWorkingFolder)\slave.jar",
                    ' -noCertificateCheck',
                    '-jnlpUrl',
                    "$using:jenkinsUrl/computer/$using:agentName/slave-agent.jnlp",
                    '-jnlpCredentials',
                    "$($using:username):$($using:userToken)"
                ) 
                & $($using:nssm) @params 
                & $($using:nssm) set "JenkinsAgent-$using:agentName" AppDirectory $using:nodeSlaveHome
                & $($using:nssm) start "JenkinsAgent-$using:agentName"
            };
            TestScript = {
                if (Get-Service "JenkinsAgent-$using:agentName" -ErrorAction SilentlyContinue)
                {
                   return $true
                }
                return $false
            }
        }
    }
}