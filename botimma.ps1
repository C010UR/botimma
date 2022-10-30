#requires -version 7.2
[CmdletBinding()]
Param(
    [Parameter(
        Position = 0,
        Mandatory,
        HelpMessage = "Input recipe (can be a link, file or a JSON string)",
        ValueFromPipeline,
        ValueFromPipelineByPropertyName
    )]
    [ValidateNotNullOrEmpty()]
    [string]$recipe
)
Begin {
    function Get-File {
        [CmdletBinding()]
        Param(
            [Parameter(
                Position = 0,
                Mandatory,
                HelpMessage = "URI path starting with HTTP or HTTPS",
                ValueFromPipeline,
                ValueFromPipelineByPropertyName
            )]
            [Alias("file")]
            [string]$path
        )
        Process {
            try {
                if (!(Test-Path -Path $path -PathType Leaf -Include "*.json" -ErrorAction Stop)) {
                    return $False
                }
                $res = Get-Content -Path $path -ErrorAction Stop
                if ($res.Length -gt 0) {
                    return [string]$res
                }
                return $False
            }
            catch {
                return $False
            }
        }
    }
    
    function Get-URI {
        [CmdletBinding()]
        Param(
            [Parameter(
                Position = 0,
                Mandatory,
                HelpMessage = "Path to a JSON file",
                ValueFromPipeline,
                ValueFromPipelineByPropertyName
            )]
            [Alias("url")]
            [string]$uri,
    
            [ValidateRange("Positive")]
            [int]$timeout = 30
        )
        Begin {
            $acceptedTypes = @(
                "application/json",
                "text/plain"
            )
        }
        Process {
            Try {
                if (!($uri -match "^(http|https)://")) {
                    return $False
                }
                $params = @{
                    Uri              = $uri
                    Method           = 'HEAD'
                    DisableKeepAlive = $True
                    TimeoutSec       = $timeout
                    ErrorAction      = 'stop'
                }
                $test = Invoke-WebRequest @params
                if ($test.statuscode -ne 200) {
                    #it is unlikely this code will ever run but just in case
                    return $False
                }
                else {
                    $params = @{
                        Uri              = $uri
                        Method           = 'GET'
                        DisableKeepAlive = $true
                        TimeoutSec       = $timeout
                        ErrorAction      = 'stop'
                    }
                    foreach ($type in $acceptedTypes) {
                        if ($test.Headers['Content-Type'] -like "$type*") {
                            return $(Invoke-WebRequest @params).Content
                        }
                    }
                    return $False
                }
            }
            Catch {
                return $False
            }
        }
    }
    function Write-Big {
        param(
            [Parameter(Mandatory)][string]$text,
            [switch]$err,
            [switch]$warn
        )
        
        $text = $($text -replace " +", " ").Trim()
        [String] $textSpacing = " " * (([Math]::Max(0, $Host.UI.RawUI.WindowSize.Width) - $text.Length - 4))
        [String] $emptyLine = " " * [Math]::Max(0, $Host.UI.RawUI.WindowSize.Width)
        [String] $resetMode = "`e[0m"

        if ($err) {
            $res = " !! $text$textSpacing"
            $Mode = "`e[37;41m"
        } elseif($warn) {
            $res = "  ! $text$spaces"
            $Mode = "`e[37;43m"
        } else {
            $res = "    $text$spaces"
            $Mode = "`e[37;42m"
        }
    
        Write-Host
        Write-Host "$Mode$emptyLine$resetMode"
        Write-Host "$Mode$res$resetMode"
        Write-Host "$Mode$emptyLine$resetMode"
        Write-Host
    }
    
    function Write-Small {
        param(
            [Parameter(Mandatory)][string]$text,
            [switch]$err,
            [switch]$warn
        )

        $text = $($text -replace " +", " ").Trim() -replace "\n", ""
    
        if ($err) {
            Write-Host "`e[37;41m !! $text `e[0m"
        } elseif($warn) {
            Write-Host "`e[37;43m  ! $text `e[0m"
        } else {
            Write-Host "`e[37;42m    $text `e[0m"
        }
    }
}
Process {
    $recipe = $recipe.Trim()
    # try file
    $json = Get-File $recipe
    # if it was not a file
    if (!$json) {
        # try uri
        $json = Get-URI $recipe
        # if it was not an uri
        if (!$json) {
            # get raw input
            $json = $recipe
        }
    }

    # check if string is a json
    try {
        $params = @{
            Uri              = 'https://raw.githubusercontent.com/C010UR/botimma/main/schema.json'
            Method           = 'GET'
            DisableKeepAlive = $true
            TimeoutSec       = 30
            ErrorAction      = 'stop'
        }
        $schema = $(Invoke-WebRequest @params).Content
    }
    catch {
        Write-Big -err "Cannot get recipe schema."
        exit
    }
    try {
        if (!(Test-Json -Json $json -Schema $schema -ErrorAction Stop)) {
            throw
        }
    }
    catch {
        Write-Big -err -text "Recipe is not valid."
        Write-Small -err -text "Provided recipe: $recipe"
        if ($recipe -ne $json) {
            Write-Small -warn -text "Contents: $json"
        }
        exit
    }
}