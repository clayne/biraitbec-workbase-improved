# Copyright 2022 Dan Cassidy

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY# without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# SPDX-License-Identifier: GPL-3.0-or-later


# functions
# ---------

Write-Host "Loading Functions..."

Set-Variable "FunctionsVersion" -Value $(New-Object "System.Version" -ArgumentList @(1, 5, 0))

function Add-Hash {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string] $VariableName,
        [Parameter(Mandatory)] [string] $Hash,
        [Parameter(Mandatory)] [string] $FileName,
        [Parameter(Mandatory)] [string] $Tag
    )

    $var = (Get-Variable -Name $VariableName -ErrorAction Stop).Value
    if ($var.ContainsKey($Hash)) {
        if ($var[$Hash].FileName -ne $FileName) {
            Write-Error "Assigning file `"$FileName`" to hash `"$Hash`" failed because that hash is already in use by file `"$($var[$Hash].FileName)`"."
            Exit-Script 1
        }
        $var[$Hash].Tags = $var[$Hash].Tags + @($Tag) | Sort-Object -Unique
    }
    else {
        $var[$Hash] = @{
            FileName = $FileName
            Tags = @($Tag)
        }
    }
}

function Exit-Script {
    [CmdletBinding()]
    param (
        [int] $ExitCode = 0,
        [switch] $Immediate,
        [System.Diagnostics.Stopwatch] $ScriptTimer = $scriptTimer,
        [System.ConsoleColor] $OriginalBackgroundColor = $OriginalBackgroundColor
    )

    $ScriptTimer.Stop()
    Write-Custom ""
    Write-Custom "Elapsed time: " -NoNewLine
    Write-Info "$(Write-TimeSpan $ScriptTimer.Elapsed)" -NoJustifyRight

    if (-not $Immediate) {
        Write-Custom "" -BypassLog
        Wait-KeyPress
    }
    Write-Log "","Exit Code: $ExitCode"
    $Host.UI.RawUI.BackgroundColor = $OriginalBackgroundColor
    exit $ExitCode
}

function Get-Fallout4DataFolder {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string] $DiscoveryMethod
    )

    switch -exact ($DiscoveryMethod) {
        "Registry" {
            # attempt to get the install path of Fallout 4 from the registry
            $fallout4RegistryFolder = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Bethesda Softworks\Fallout4" -ErrorAction SilentlyContinue)."installed path"
            if (-not $fallout4RegistryFolder -or -not (Test-Path $fallout4RegistryFolder)) { return "" }
            # if it exists, set the location of the Fallout 4 folder
            $fallout4Folder = $fallout4RegistryFolder
            break
        }
        "Steam" {
            # attempt to get steam install path from the registry
            $steamDir = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue).InstallPath
            if (-not $steamDir) { return "" }
            # set the location of the file that has the configuration of Steam's library folders
            $steamLibraryFile = "$steamDir\config\libraryfolders.vdf"
            if (-not (Test-Path $steamLibraryFile)) { return "" }
            # search the steam library file for the game ID of Fallout 4
            #   (Select-String "^\s+`"377160`"" -Path $steamLibraryFile)
            # get the line number it's found at
            #   .LineNumber
            $fallout4EntryLineNumber = (Select-String "^\s+`"377160`"" -Path $steamLibraryFile).LineNumber
            if (-not $fallout4EntryLineNumber) { return "" }
            # search for "path" entries in the steam library file, making sure it's an array
            #   (@(Select-String "^\s+`"path`"" -Path $steamLibraryFile)
            # find the path entry just before the fallout 4 ID, will be an entry similar to '       "path"      "C:\Foo"'
            #   .Where({$_.LineNumber -lt $fallout4EntryLineNumber}, "Last")
            # split the line using " as a delimiter
            #   .Line -split "`"")
            # trim any whitespace from the resulting array entries
            #   .Trim()
            # get the last entry that's not an empty string, which should be the location of the steam library where Fallout 4 is
            #   .Where({$_}, "Last")
            $steamLibraryPath = (@(Select-String "^\s+`"path`"" -Path $steamLibraryFile).Where({$_.LineNumber -lt $fallout4EntryLineNumber}, "Last").Line -split "`"").Trim().Where({$_}, "Last")
            if (-not $steamLibraryPath) { return "" }
            # set the location of the Fallout 4 folder gotten through this method
            $fallout4SteamFolder = "$steamLibraryPath\steamapps\common\Fallout 4"
            if (-not (Test-Path $fallout4SteamFolder)) { return "" }
            # if it exists, set the location of the Fallout 4 folder
            $fallout4Folder = $fallout4SteamFolder
            break
        }
        default {
            throw "Invalid discovery method `"$DiscoveryMethod`" specified."
        }
    }
    # set the location of the fallout 4 data folder
    $fallout4DataFolder = [IO.Path]::GetFullPath("$fallout4Folder\Data")
    if (-not (Test-Path $fallout4DataFolder)) { return "" }
    # if it exists, return the location of the fallout 4 data folder
    return $fallout4DataFolder
}

function Get-Folder {
    [CmdletBinding()]
    param (
        [Parameter()] [string] $Description = "",
        [Parameter()] [string] $InitialDirectory = (Get-Location),
        [Parameter()] [string] $RootFolder = "MyComputer"
    )

    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms")|Out-Null

    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderDialog.Description = $Description
    $folderDialog.RootFolder = $RootFolder
    $folderDialog.SelectedPath = $InitialDirectory

    if($folderDialog.ShowDialog() -eq "OK")
    {
        $folder += $folderDialog.SelectedPath
    }
    return $folder
}

function Get-WindowsVersion {
    $regKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    return @(
        Get-ItemPropertyValue -Path $regKey -Name "ProductName"
        Get-ItemPropertyValue -Path $regKey -Name "DisplayVersion"
        "(Version"
        (Get-ItemPropertyValue -Path $regKey -Name "ReleaseId") + ","
        "OS Build"
        (Get-ItemPropertyValue -Path $regKey -Name "CurrentBuild") + "." + (Get-ItemPropertyValue -Path $regKey -Name "UBR") + ")"
    ) -join " "
}

function Wait-KeyPress {
    [CmdletBinding()]
    param (
        [Parameter()] [string] $Message = "Press any key to continue . . . ",
        [switch] $NoPadding
    )
    Write-Custom $Message -NoNewLine -BypassLog
    [Void][System.Console]::ReadKey($true)
    if (-not $NoPadding) {
        Write-Custom "","" -BypassLog
    }
}

function Write-Error {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [AllowEmptyString()] [string[]] $Message,
        [switch] $NoJustifyRight,
        [string]$Prefix = $null,
        [int]$SnippetLength = 0
    )

    $hashArguments = @{
        Message = $Message
        JustifyRight = -not $NoJustifyRight
        Prefix = $Prefix
        SnippetLength = $SnippetLength
        Color = [System.ConsoleColor]::Red
    }
    Write-Custom @hashArguments
}

function Write-Custom {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [AllowEmptyString()] [string[]] $Message,
        [switch] $NoNewLine,
        [switch] $BypassLog,
        [string] $Prefix = $null,
        [switch] $JustifyRight,
        [switch] $JustifyCenter,
        [int] $LineWidth = $LineWidth,
        [switch] $UseErrorStream,
        [int] $SnippetLength = 0,
        [PSObject] $Color = $null,
        [ref] $PreviousLineLength = [ref] $writeCustomPrevNoNewLineLength
    )

    if ($UseErrorStream) {
        $stream = [Console]::Error
    }
    else {
        $stream = [Console]::Out
    }

    if ($null -ne $Color -and $Color.GetType().FullName -eq "System.ConsoleColor") {
        [Console]::ForegroundColor = $Color
    }

    $doSnip = $Message.Length -gt $SnippetLength * 2 -and $SnippetLength -gt 0

    for ($index = 0; $index -lt $Message.Length; $index++) {
        $line = $Message[$index]
        if ($doSnip -and $index -eq $SnippetLength) {
            $line = "--- snip ---"
            $index = $Message.Length - $SnippetLength - 1
        }
        if ($NoNewLine) {
            if ($JustifyRight) {
                $stream.Write("{0,$LineWidth}", $Prefix + $line)
            }
            elseif ($JustifyCenter) {
                $stream.Write("{0,$([int](($LineWidth - $PreviousLineLength.Value) / 2.0 + ($Prefix.Length + $line.Length) / 2.0))}", $Prefix + $line)
            }
            else {
                $stream.Write("{0}", $Prefix + $line)
            }
            $PreviousLineLength.Value = $Host.UI.RawUI.CursorPosition.X
        }
        else {
            if ($JustifyRight) {
                $stream.WriteLine("{0,$($LineWidth - $PreviousLineLength.Value)}", $Prefix + $line)
            }
            elseif ($JustifyCenter) {
                $stream.WriteLine("{0,$([int](($LineWidth - $PreviousLineLength.Value) / 2.0 + ($Prefix.Length + $line.Length) / 2.0))}", $Prefix + $line)
            }
            else {
                $stream.WriteLine("{0}", $Prefix + $line)
            }
            $PreviousLineLength.Value = 0
        }
    }

    if ($null -ne $Color -and $Color.GetType().FullName -eq "System.ConsoleColor") {
        [Console]::ResetColor()
    }

    if (-not $BypassLog) {
        Write-Log $($Message | ForEach-Object {"$Prefix$_"})
    }
}

function Write-Info {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [AllowEmptyString()] [string[]] $Message,
        [switch] $NoJustifyRight,
        [string] $Prefix = $null
    )

    $hashArguments = @{
        Message = $Message
        JustifyRight = -not $NoJustifyRight
        Prefix = $Prefix
        Color = [System.ConsoleColor]::Blue
    }
    Write-Custom @hashArguments
}

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [AllowEmptyString()] [PSObject] $Message,
        [string] $Log = "install",
        [string] $LogStartTime = $RunStartTime,
        [switch] $NoTimestamp
    )

    if ($(Test-Path -LiteralPath $dir.logs) -eq $false) {
        New-Item $dir.logs -ItemType "directory" -ErrorAction Stop | Out-Null
    }
    $(if ($NoTimestamp) {
        Write-Output $Message
    }
    else {
        Write-Output $Message |
            ForEach-Object {"[$((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))] $_".Trim()}
    }) | Out-File -LiteralPath "$($dir.logs)\${Log}_$LogStartTime.log" -Append
}

function Write-Success {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [AllowEmptyString()] [string[]] $Message,
        [switch] $NoJustifyRight,
        [string] $Prefix = $null
    )

    $hashArguments = @{
        Message = $Message
        JustifyRight = -not $NoJustifyRight
        Prefix = $Prefix
        Color = [System.ConsoleColor]::Green
    }
    Write-Custom @hashArguments
}

function Write-TimeSpan {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [System.TimeSpan] $TimeSpan
    )

    $formatString = @(
        "$(if ($TimeSpan.TotalDays -ge 1) {"d\d"})"
        "$(if ($TimeSpan.TotalHours -ge 1) {"h\h"})"
        "$(if ($TimeSpan.TotalMinutes -ge 1) {"m\m"})"
        "$(if ($TimeSpan.TotalSeconds) {"s\.f\s"})"
    ).Where{$_} -join "\ "
    return [System.TimeSpan]::FromSeconds([Math]::Round($TimeSpan.TotalSeconds, 1)).ToString($formatString)
}

function Write-Warning {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [AllowEmptyString()] [string[]] $Message,
        [switch] $NoJustifyRight,
        [string] $Prefix = $null
    )

    $hashArguments = @{
        Message = $Message
        JustifyRight = -not $NoJustifyRight
        Prefix = $Prefix
        Color = [System.ConsoleColor]::Yellow
    }
    Write-Custom @hashArguments
}