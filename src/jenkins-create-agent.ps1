$DscWorkingFolder = $PSScriptRoot
$root = resolve-path "$PSScriptRoot\.."
$nssm = "$root\nssm.exe"

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

        File BinFolder {
            Type = 'Directory'
            DestinationPath = "$root\bin"
            Ensure = "Present"
        }

        File AgentFolder {
            Type = 'Directory'
            DestinationPath = "$root\agent"
            Ensure = "Present"
        }

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

        cChocoPackageInstaller installGit
        {
            Name = "git.install"
            DependsOn = "[cChocoInstaller]installChoco"
        }
        
        cChocoPackageInstaller installNodeJS
        {
            Name = "nodejs.install"
            DependsOn = "[cChocoInstaller]installChoco"
        }

        cChocoPackageInstaller installJdk8
        {
            Name = "jdk8"
            DependsOn = "[cChocoInstaller]installChoco"
        }

        Script DownloadFiles {
            DependsOn = "[cChocoPackageInstaller]installJdk8";
            GetScript = {
                return @{
                    Result = (
                        (Test-Path -Path "$($using:root)\bin\slave.jar") -and
                        (Test-Path -Path "$($using:root)\bin\jenkins-cli.jar")
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
                })

                foreach ($f in $files) {
                    $OutFile = "$($using:root)\bin\$($f.name)";
                    Invoke-WebRequest -Uri $f.url -OutFile $OutFile;
                    Unblock-File -Path $OutFile;
                }
            };
            TestScript = {
                (Test-Path -Path "$($using:root)\bin\slave.jar") -and
                (Test-Path -Path "$($using:root)\bin\jenkins-cli.jar")
            }
        }

        File CopySlaveJar {
            SourcePath = "$root\bin\slave.jar"
            DestinationPath = "$root\agent\slave.jar"
            Ensure = "Present"
            Type = "File"
        }

        Script AddJenkinsAgent {
            DependsOn = "[Script]DownloadFiles";
            GetScript = {
                return @{
                    Result = '';
                }
            };
            SetScript = {
                (gc "$($using:DscWorkingFolder)\node.xml") -replace '{agentName}', "$using:agentName"`
                    -replace '{nodeSlaveHome}', "$using:nodeSlaveHome"`
                    -replace '{numExecutors}', "$using:numExecutors"`
                    -replace '{label}', "$using:label" |
                    & java "-jar" "$($using:root)\bin\jenkins-cli.jar" "-noKeyAuth" "-noCertificateCheck" `
                        "-s" "$using:jenkinsUrl" "create-node" "$using:agentName" `
                        "--username" "$using:username" "--password" "$using:password"
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
                & $($using:nssm) "install" "JenkinsAgent-$using:agentName" "java" "-jar" "$($using:root)\agent\slave.jar" " -noCertificateCheck" "-jnlpUrl" "$using:jenkinsUrl/computer/$using:agentName/slave-agent.jnlp" "-jnlpCredentials" "$($using:username):$($using:userToken)"
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