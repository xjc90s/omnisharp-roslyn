##########################################################################
# This is the Cake bootstrapper script for PowerShell.
# This file was downloaded from https://github.com/cake-build/resources
# Feel free to change this file to fit your needs.
##########################################################################

<#

.SYNOPSIS
This is a Powershell script to bootstrap a Cake build.

.DESCRIPTION
This Powershell script will download NuGet if missing, restore NuGet tools (including Cake)
and execute your Cake build script with the parameters you provide.

.PARAMETER Script
The build script to execute.
.PARAMETER Target
The build script target to run.
.PARAMETER Configuration
The build configuration to use.
.PARAMETER Verbosity
Specifies the amount of information to be displayed.
.PARAMETER UseDotNetTest
Run tests against the .NET SDK build of OmniSharp
.PARAMETER ScriptArgs
Remaining arguments are added here.

.LINK
https://cakebuild.net

#>

[CmdletBinding()]
Param(
    [parameter(position = 0)]
    [string]$Target = "Default",
    [string]$Script = "build.cake",
    [string]$Configuration,
    [ValidateSet("Quiet", "Minimal", "Normal", "Verbose", "Diagnostic")]
    [string]$Verbosity,
    [switch]$UseDotNetTest,
    [Parameter(Position = 0, Mandatory = $false, ValueFromRemainingArguments = $true)]
    [string[]]$ScriptArgs
)

[Reflection.Assembly]::LoadWithPartialName("System.Security") | Out-Null
function MD5HashFile([string] $filePath) {
    if ([string]::IsNullOrEmpty($filePath) -or !(Test-Path $filePath -PathType Leaf)) {
        return $null
    }

    [System.IO.Stream] $file = $null;
    [System.Security.Cryptography.MD5] $md5 = $null;
    try {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $file = [System.IO.File]::OpenRead($filePath)
        return [System.BitConverter]::ToString($md5.ComputeHash($file))
    }
    finally {
        if ($file -ne $null) {
            $file.Dispose()
        }
    }
}

function GetProxyEnabledWebClient {
    $wc = New-Object System.Net.WebClient
    $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    $proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    $wc.Proxy = $proxy
    return $wc
}

Write-Host "Preparing to run build script..."

if (!$PSScriptRoot) {
    $PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}

$TOOLS_DIR = Join-Path $PSScriptRoot "tools"
$NUGET_EXE = Join-Path $TOOLS_DIR "nuget.exe"
$NUGET_URL = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
$PACKAGES_CONFIG = Join-Path $TOOLS_DIR "packages.config"
$PACKAGES_CONFIG_MD5 = Join-Path $TOOLS_DIR "packages.config.md5sum"

# Make sure tools folder exists
if ((Test-Path $PSScriptRoot) -and !(Test-Path $TOOLS_DIR)) {
    Write-Verbose -Message "Creating tools directory..."
    New-Item -Path $TOOLS_DIR -Type directory | out-null
}

# Make sure that packages.config exist.
if (!(Test-Path $PACKAGES_CONFIG)) {
    Write-Verbose -Message "Downloading packages.config..."
    try {
        $wc = GetProxyEnabledWebClient
        $wc.DownloadFile("https://cakebuild.net/download/bootstrapper/packages", $PACKAGES_CONFIG)
    }
    catch {
        Throw "Could not download packages.config."
    }
}

# Try find NuGet.exe in path if not exists
if (!(Test-Path $NUGET_EXE)) {
    Write-Verbose -Message "Trying to find nuget.exe in PATH..."
    $existingPaths = $Env:Path -Split ';' | Where-Object { (![string]::IsNullOrEmpty($_)) -and (Test-Path $_ -PathType Container) }
    $NUGET_EXE_IN_PATH = Get-ChildItem -Path $existingPaths -Filter "nuget.exe" | Select -First 1
    if ($NUGET_EXE_IN_PATH -ne $null -and (Test-Path $NUGET_EXE_IN_PATH.FullName)) {
        Write-Verbose -Message "Found in PATH at $($NUGET_EXE_IN_PATH.FullName)."
        $NUGET_EXE = $NUGET_EXE_IN_PATH.FullName
    }
}

# Try download NuGet.exe if not exists
if (!(Test-Path $NUGET_EXE)) {
    Write-Verbose -Message "Downloading NuGet.exe..."
    try {
        $wc = GetProxyEnabledWebClient
        $wc.DownloadFile($NUGET_URL, $NUGET_EXE)
    }
    catch {
        Throw "Could not download NuGet.exe."
    }
}

# Save nuget.exe path to environment to be available to child processed
$ENV:NUGET_EXE = $NUGET_EXE

# Restore tools from NuGet
if (Test-Path $PACKAGES_CONFIG) {
    Push-Location
    Set-Location $TOOLS_DIR

    # Check for changes in packages.config and remove installed tools if true.
    [string] $md5Hash = MD5HashFile($PACKAGES_CONFIG)
    if ((!(Test-Path $PACKAGES_CONFIG_MD5)) -Or
        ($md5Hash -ne (Get-Content $PACKAGES_CONFIG_MD5 ))) {
        Write-Verbose -Message "Missing or changed package.config hash..."
        Remove-Item * -Recurse -Exclude packages.config, nuget.exe
    }

    Write-Verbose -Message "Restoring tools from NuGet..."
    $NuGetOutput = Invoke-Expression "&`"$NUGET_EXE`" install -ExcludeVersion -OutputDirectory `"$TOOLS_DIR`""

    if ($LASTEXITCODE -ne 0) {
        Throw "An error occurred while restoring NuGet tools."
    }
    else {
        $md5Hash | Out-File $PACKAGES_CONFIG_MD5 -Encoding "ASCII"
    }
    Write-Verbose -Message ($NuGetOutput | out-string)

    Pop-Location
}

dotnet tool restore

# Build Cake arguments
$cakeArguments = @("$Script");
if ($Target) { $cakeArguments += "--target=$Target" }
if ($Configuration) { $cakeArguments += "--configuration=$Configuration" }
if ($Verbosity) { $cakeArguments += "--verbosity=$Verbosity" }
if ($UseDotNetTest) { $cakeArguments += "--use-dotnet-test" }
$cakeArguments += $ScriptArgs

# Start Cake
Write-Host "Running build script..."
dotnet cake $cakeArguments
exit $LASTEXITCODE
