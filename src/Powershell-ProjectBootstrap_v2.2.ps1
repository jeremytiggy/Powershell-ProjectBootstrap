[CmdletBinding()]
param(
    [string]$ManifestFileName = 'Manifest.psd1',
    [string[]]$LocalInstancesPath = @(".", ".\lib", "..\lib"),
    [string]$GitHubToken,
	[switch]$DoNotAutoRun
)
if ($PSBoundParameters.ContainsKey('Debug')) {
    $DebugPreference = 'Continue'
}

function GitHub_REST_API_GET_LatestRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [Parameter(Mandatory = $true)]
        [string]$Repo,

        [string]$Token
    )
	# GitHub REST Documentation: https://docs.github.com/en/rest/using-the-rest-api/getting-started-with-the-rest-api?apiVersion=2026-03-10
	# GitHub Release REST API Documentation: https://docs.github.com/en/rest/releases/releases?apiVersion=2026-03-10&versionId=free-pro-team%40latest&restPage=getting-started-with-the-rest-api
	# Latest Release REST API: https://docs.github.com/en/rest/releases/releases?apiVersion=2026-03-10&versionId=free-pro-team%40latest&restPage=getting-started-with-the-rest-api#get-the-latest-release
	# GET /repos/{owner}/{repo}/releases/latest
    $apiUrl = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
    
    $headers = @{
        'Accept' = 'application/vnd.github.v3+json'
    }
    if ($Token) {
        $headers['Authorization'] = "Bearer $Token"
    }
	Write-Debug "[Get-GitHubLatestRelease]: Owner: $($Owner), Repo: $($Repo), Token: $($Token)"
	
    try {
		$LatestRelease = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get        
        Write-Verbose "[Get-GitHubLatestRelease: $Owner/$Repo]: [$($LatestRelease.tag_name)] $($LatestRelease.name)"
        return $LatestRelease
    }
    catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) {
            Write-Error "[Get-GitHubLatestRelease: $Owner/$Repo]: Resource not found"
        } elseif ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 403) {
            Write-Error "[Get-GitHubLatestRelease: $Owner/$Repo]: Resource forbidden, try token"
        } else {
            Write-Error "[Get-GitHubLatestRelease: $Owner/$Repo]: $_"
        }
        return $null
    }
}
function Get-FileInfo_FileName {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$FileName
    )

    $FileInfo = [PSCustomObject]@{
        FileName 		= ''
        FileExtension	= ''
		FullName 		= ''
		FilePath 		= '.\'
		FullPath 		= '.\'
		HasExtension  = $false
        MajorVersion  = 0
        MinorVersion  = 0
    }
	
	# .FullName
    $FileInfo.FullName = [System.IO.Path]::GetFileName($FileName)
	# .FilePath
	$directoryName = [System.IO.Path]::GetDirectoryName($FileName)
    if ($directoryName) {
        $FileInfo.FilePath = $directoryName + '\'
    }
	# .FullPath
	$FileInfo.FullPath = $FileInfo.FilePath + $FileInfo.FullName
	# .FileExtension
    $FileInfo.FileExtension = [System.IO.Path]::GetExtension($FileName).TrimStart('.')
	
	# .HasExtension
	$FileInfo.HasExtension = ($null -ne $FileInfo.FileExtension) -and ($FileInfo.FileExtension -ne '')
    
	# .FileName
	# .MajorVersion
	# .MinorVersion
	# Remove the extension before looking for a version
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    # Look for a version in the format _v1.23
    if ($baseName -match '^(.*)_v(\d+)\.(\d+)$') {
        $FileInfo.FileName = $matches[1]
        $FileInfo.MajorVersion = [int]$matches[2]
        $FileInfo.MinorVersion = [int]$matches[3]
    }
    else {
        $FileInfo.FileName = $baseName
    }

    return $FileInfo
}
function Get-FileInfo_HighestRevisionInGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$FileInfos
    )
	$HighestRevision = [version]"0.0"
	$HighestRevisionFileInfo = $null
	foreach ($FileInfo in $FileInfos) {
		$FileVersion = [version]"$($FileInfo.MajorVersion).$($FileInfo.MinorVersion)"
		if ($FileVersion -gt $HighestRevision) {
			$HighestRevision = $FileVersion
			$HighestRevisionFileInfo = $FileInfo
		}
	}
	return $HighestRevisionFileInfo
}
function Get-FileInfo_HighestRevisionLocalInstanceFileName {
    [CmdletBinding()]
    param( 
		[Parameter(Mandatory = $true)]
        [string]$LocalFileName,
		[string[]]$LocalInstancesPath = @(".", ".\lib", "..\lib")
	)
	$inputFileInfo = Get-FileInfo_FileName -FileName $LocalFileName
	$inputFileName = $inputFileInfo.FileName
	if ($inputFileInfo.HasExtension) {
		$inputFileExtension = $inputFileInfo.FileExtension
		$pattern = "${inputFileName}_v*.*$inputFileExtension"
	} else {
		$pattern = "${inputFileName}_v*.*"
	}
	$matchingFileInfos = @()
	foreach ($currentPath in $LocalInstancesPath) {
        $files = Get-ChildItem -Path $currentPath -Filter $pattern -File -ErrorAction SilentlyContinue
        if ($files) {
            # check major and minor revisions of the files, and return the FileInfo of the latest one
			foreach ($file in $files) {
				$matchingFileInfos += Get-FileInfo_FileName -FileName $file.FullName
			}
        } 
    }
	# $matchingFileInfos is now a collection of FileInfo entries for all the files.
    if ($matchingFileInfos.Count -gt 0) {
		$highestRevisionMatchingFileInfo = Get-FileInfo_HighestRevisionInGroup -FileInfos $matchingFileInfos
        Write-Verbose "[Get-FileInfo_HighestRevisionLocalInstanceFileName: $LocalFileName]: Found: $($highestRevisionMatchingFileInfo.FullPath)"
		return $highestRevisionMatchingFileInfo
	} else {
		Write-Warning "[Get-FileInfo_HighestRevisionLocalInstanceFileName: $LocalFileName]: No matching files found"
		$notFoundFileInfo = [PSCustomObject]@{
			FileName 		= 'FileNotFound'
			FileExtension	= ''
			FullName 		= ''
			FilePath 		= $inputFileInfo.FilePath
			FullPath 		= ''
			HasExtension  = $false
			MajorVersion  = 0
			MinorVersion  = 0
		}
		return $notFoundFileInfo
	}
}
function Get-FileInfo_AssetInstanceHighestRevision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AssetFileName,

        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [Parameter(Mandatory = $true)]
        [string]$Repo,

        [string]$Token,
		
		[string]$InstalledVersionReferenceAsset,

        [string[]]$LocalInstancePath = @(".", ".\lib", "..\lib")
    )

    # Get information about the requested file.
    # This also gives us the intended FilePath if the file does not exist locally.
    $AssetFileInfo = Get-FileInfo_FileName -FileName $AssetFileName

    # Get the highest revision of the file that exists locally.
	# Use Reference if provided
	if (($null -eq $InstalledVersionReferenceAsset) -or ($InstalledVersionReferenceAsset -eq '')) {
		$InstalledVersionReferenceAssetFileName = $AssetFileName
	} else {
		$InstalledVersionReferenceAssetFileName = $InstalledVersionReferenceAsset
		Write-Debug "[Get-FileInfo_AssetInstanceHighestRevision: $($AssetFileName)]: Using [$($InstalledVersionReferenceAsset)] as installed version reference"
	}	
    
	# Find the local copy of the actual asset.
	$LocalInstanceFileInfo = Get-FileInfo_HighestRevisionLocalInstanceFileName -LocalFileName $AssetFileName -LocalInstancesPath $LocalInstancePath
	
	# Find the local installed-version reference.
	$InstalledVersionFileInfo = Get-FileInfo_HighestRevisionLocalInstanceFileName -LocalFileName $InstalledVersionReferenceAssetFileName -LocalInstancesPath $LocalInstancePath

	# Get the latest release from GitHub.
    $latestGitHubRelease = GitHub_REST_API_GET_LatestRelease -Owner $Owner -Repo $Repo -Token $Token

    if ($null -eq $latestGitHubRelease) {
        Write-Warning "[Get-FileInfo_AssetInstanceHighestRevision: ${Owner}/${Repo}]: Unable to determine latest GitHub revision"

        if ($LocalInstanceFileInfo.FileName -ne 'FileNotFound') {
            return $LocalInstanceFileInfo
        }

        return $AssetFileInfo
    }

    # Look through the release assets for files matching the requested base name.
    $matchingGitHubFileInfos = @()

    foreach ($asset in $latestGitHubRelease.assets) {
        $githubFileInfo = Get-FileInfo_FileName -FileName $asset.name

        if ($githubFileInfo.FileName -eq $AssetFileInfo.FileName) {
            # The GitHub asset's FullPath is its download URI.
            $githubFileInfo.FullPath = $asset.browser_download_url

            $matchingGitHubFileInfos += $githubFileInfo
        }
    }

    # Find the highest revision among matching GitHub assets.
    if ($matchingGitHubFileInfos.Count -gt 0) {
        $githubFileInfo = Get-FileInfo_HighestRevisionInGroup -FileInfos $matchingGitHubFileInfos
        Write-Verbose "[Get-FileInfo_AssetInstanceHighestRevision: ${Owner}/${Repo}]: Found GitHub asset [$($githubFileInfo.FullName)]"
        Write-Verbose "[Get-FileInfo_AssetInstanceHighestRevision: ${Owner}/${Repo}]: GitHub revision is v$($githubFileInfo.MajorVersion).$($githubFileInfo.MinorVersion)"
    }
    else {
        Write-Verbose "[Get-FileInfo_AssetInstanceHighestRevision: ${Owner}/${Repo}]: No matching GitHub asset found"

        if ($LocalInstanceFileInfo.FileName -ne 'FileNotFound') {
            return $LocalInstanceFileInfo
        }

        return $AssetFileInfo
    }

	# No installed version reference exists, so the GitHub file is the latest available file.
    if ($InstalledVersionFileInfo.FileName -eq 'FileNotFound') {
        if ($LocalInstanceFileInfo.FileName -ne 'FileNotFound') {
            $githubFileInfo.FilePath = $LocalInstanceFileInfo.FilePath
        }
        else {
            $githubFileInfo.FilePath = $AssetFileInfo.FilePath
        }

        Write-Verbose "[Get-FileInfo_AssetInstanceHighestRevision: $Owner/$Repo]: No installed version reference found"
        Write-Verbose "[Get-FileInfo_AssetInstanceHighestRevision: $Owner/$Repo]: GitHub file is the latest available revision"

        return $githubFileInfo
    }

    Write-Verbose "[Get-FileInfo_AssetInstanceHighestRevision: $Owner/$Repo]: Installed revision is v$($InstalledVersionFileInfo.MajorVersion).$($InstalledVersionFileInfo.MinorVersion)"	
	$localVersion = [version]"$($InstalledVersionFileInfo.MajorVersion).$($InstalledVersionFileInfo.MinorVersion)"
	$repoVersion = [version]"$($githubFileInfo.MajorVersion).$($githubFileInfo.MinorVersion)"

	# Revisions are equal, so use the local actual asset.
    if ($localVersion -eq $repoVersion) {
		Write-Verbose "[Get-FileInfo_AssetInstanceHighestRevision: ${Owner}/${Repo}]: Local and GitHub revisions are equal: v$($repoVersion) = v$($localVersion)"

        if ($LocalInstanceFileInfo.FileName -ne 'FileNotFound') {
            return $LocalInstanceFileInfo
        }

        # The reference exists, but the actual asset does not.
        $githubFileInfo.FilePath = $InstalledVersionFileInfo.FilePath

        return $githubFileInfo
    }
    
	# GitHub has a newer major revision.
    if ($repoVersion -gt $localVersion) {
        $githubFileInfo.FilePath = $InstalledVersionFileInfo.FilePath
        Write-Verbose "[Get-FileInfo_AssetInstanceHighestRevision: ${Owner}/${Repo}]: GitHub has the latest revision: v$($repoVersion) > v$($localVersion)"
        return $githubFileInfo
    }
    
	# Local file has a newer major revision.
    if ($repoVersion -lt $localVersion) {
        Write-Verbose "[Get-FileInfo_AssetInstanceHighestRevision: ${Owner}/${Repo}]: Local file has the latest major revision: v$($repoVersion) < v$($localVersion)"
        if ($LocalInstanceFileInfo.FileName -ne 'FileNotFound') {
            return $LocalInstanceFileInfo
        }
        $githubFileInfo.FilePath = $InstalledVersionFileInfo.FilePath
        return $githubFileInfo
    }

    return $LocalInstanceFileInfo
}
function Download-Asset_FromFileInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$AssetFileInfo
    )

    if ($AssetFileInfo.FullPath -notlike 'https://*') {
        Write-Warning "[Download-Asset_FromFileInfo]: Full Path is not a web address: $($AssetFileInfo.FullPath)"
        return $AssetFileInfo
    }

    $downloadUri = $AssetFileInfo.FullPath    
    $downloadDirectory = $AssetFileInfo.FilePath
	$downloadFileName = $AssetFileInfo.FullName

	# if download directory doesn't exist, create it
	$downloadDirectoryAlreadyExists = Test-Path -Path $downloadDirectory -PathType Container
    if (-not $downloadDirectoryAlreadyExists) {
        Write-Debug "[Download-Asset_FromFileInfo]: Could not find Download directory: $($downloadDirectory)"
		try {
            New-Item -Path $downloadDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
			Write-Debug "[Download-Asset_FromFileInfo]: Created Download directory: $($downloadDirectory)"
        }
        catch {
            Write-Error "[Download-Asset_FromFileInfo]: Unable to create download directory [$downloadDirectory]: $_"
            return $AssetFileInfo
        }
    }
	
	$downloadLocalPath = Join-Path -Path $downloadDirectory -ChildPath $downloadFileName
    Write-Verbose "[Download-Asset_FromFileInfo: $($AssetFileInfo.FileName)]: Downloading [$downloadUri]"
    Write-Verbose "[Download-Asset_FromFileInfo: $($AssetFileInfo.FileName)]: Saving to [$downloadLocalPath]"

    try {
		Invoke-WebRequest -Uri $downloadUri -OutFile $downloadLocalPath -ErrorAction Stop
		$UnconfirmedDownloadFileInfo = $AssetFileInfo
	} catch {
		Write-Error "[Download-Asset_FromFileInfo]: Invoke-WebRequest: $_ "
		return $AssetFileInfo
	}
	if (Test-Path -Path $downloadLocalPath -PathType Leaf) {
        $ConfirmedFileInfo = $UnconfirmedDownloadFileInfo
		$ConfirmedFileInfo.FullPath = $downloadLocalPath
        Write-Verbose "[Download-Asset_FromFileInfo]: Download completed and found at [$downloadLocalPath]"
		return $ConfirmedFileInfo
    }
    else {
        Write-Error "[Download-Asset_FromFileInfo]: Download completed but file [$downloadLocalPath] was not found"
		return $UnconfirmedDownloadFileInfo
    }

    return $AssetFileInfo
}
function Produce-FileInfo_AssetLocalInstance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AssetName,

        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [Parameter(Mandatory = $true)]
        [string]$Repo,

        [string]$Token,
		
		[string]$AssetDownloadPath = "not specified",
		
		[string]$AssetDownloadName = "not specified",

        [string[]]$LocalInstancesPath = @(".", ".\lib", "..\lib"),
		
		[string]$AssetInstalledVersionReference
		
    )

    $HighestRevisionFileInfo = Get-FileInfo_AssetInstanceHighestRevision -AssetFileName $AssetName -Owner $Owner -Repo $Repo -Token $Token  -LocalInstancePath $LocalInstancesPath -InstalledVersionReferenceAsset $AssetInstalledVersionReference
    	
	$FileInfoNotFound = $HighestRevisionFileInfo.FileName -eq 'FileNotFound'
	if ($FileInfoNotFound) {
        $ErrorContainingFileInfo = $HighestRevisionFileInfo
		Write-Warning "[Produce-FileInfo_AssetLocalInstance: ${AssetName}]: File not found locally or on GitHub"
        return $ErrorContainingFileInfo
    } else {
		$HighestRevisionLocalFileInfo = Get-FileInfo_HighestRevisionLocalInstanceFileName -LocalFileName $AssetName -LocalInstancesPath $LocalInstancesPath
	}
	$LocalFileInfoExists = $HighestRevisionLocalFileInfo.FileName -ne 'FileNotFound'
    
	$HighestRevisionFileInfoPointsToGitHub = $HighestRevisionFileInfo.FullPath -like 'https://*'
	$HighestRevisionFilePathPointsToLocal = ( $LocalFileInfoExists -and (-not $HighestRevisionFileInfoPointsToGitHub) )
	if ($HighestRevisionFilePathPointsToLocal) {
		Write-Verbose "[Produce-FileInfo_AssetLocalInstance: ${AssetName}]: Latest revision is already Local"
		return $HighestRevisionLocalFileInfo
	}
	
	if ($HighestRevisionFileInfoPointsToGitHub) {
        Write-Verbose "[Produce-FileInfo_AssetLocalInstance: ${AssetName}]: Latest revision is hosted on GitHub"
		$AssetDownloadPathNotSpecified = $AssetDownloadPath -eq "not specified"
		$useLocalFileInfoForDownloadPath =  $AssetDownloadPathNotSpecified -and $LocalFileInfoExists
        $useCurrentDirectoryForDownloadPath = ($AssetDownloadPath -eq "not specified") -and (-not $LocalFileInfoExists)
		if ($AssetDownloadPathNotSpecified) {
			if ($LocalFileInfoExists) {
				$AssetDownloadPath = $HighestRevisionLocalFileInfo.FilePath
			} else {
				$AssetDownloadPath = '.'
			}	
		}
		$DownloadedFileInfo_Successfully = $false
		if ($AssetDownloadName -eq "not specified") {
			$ProjectFileInfo = $HighestRevisionFileInfo
		} else {



			$ProjectFileInfo = Get-FileInfo_AssetInstanceHighestRevision -AssetFileName $AssetDownloadName -Owner $Owner -Repo $Repo -Token $Token -LocalInstancePath $LocalInstancesPath -InstalledVersionReferenceAsset $AssetInstalledVersionReference
			if ($ProjectFileInfo.FileName -eq 'FileNotFound') {
                Write-Warning "[Produce-FileInfo_AssetLocalInstance: $AssetName]: Unable to locate download asset: $AssetDownloadName"
                if ($LocalFileInfoExists) {
                    return $HighestRevisionLocalFileInfo
                } else {
					return $ProjectFileInfo
				}
            }
		}
		
		$ProjectFileInfo.FilePath = $AssetDownloadPath
		$DownloadedFileInfo = Download-Asset_FromFileInfo -AssetFileInfo $ProjectFileInfo
		$DownloadedFileInfo_Successfully = -not ($DownloadedFileInfo.FullPath -like 'https://*') #gets overwritten if successful
		if (-not $DownloadedFileInfo_Successfully) {
            Write-Warning "[Produce-FileInfo_AssetLocalInstance: ${AssetName}]: Unable to download latest revision."
			if ($LocalFileInfoExists) {
				Write-Warning "[Produce-FileInfo_AssetLocalInstance: ${AssetName}]: Using latest revision of local file."
				return $HighestRevisionLocalFileInfo
			} else {
				Write-Error "[Produce-FileInfo_AssetLocalInstance: ${AssetName}]: No file available. Exiting."
				return $DownloadedFileInfo
			}
		}
		
		if ($DownloadedFileInfo_Successfully) {
			Write-Verbose "[Produce-FileInfo_AssetLocalInstance: ${AssetName}]: Downloaded: $($DownloadedFileInfo.FullName)"

			# If the downloaded asset is a ZIP archive, extract it to the
			# requested download/install path.
			if ($DownloadedFileInfo.FileExtension -eq 'zip') {
				Write-Debug "[Produce-FileInfo_AssetLocalInstance: ${AssetName}]: Downloaded asset is a ZIP archive"
				Write-Debug "[Produce-FileInfo_AssetLocalInstance: ${AssetName}]: Extracting to [$AssetDownloadPath]"

				try {
					Expand-Archive -Path $DownloadedFileInfo.FullPath -DestinationPath $AssetDownloadPath -Force -ErrorAction Stop
					Write-Verbose "[Produce-FileInfo_AssetLocalInstance: ${AssetName}]: ZIP archive extracted successfully"
				}
				catch {
					Write-Error "[Produce-FileInfo_AssetLocalInstance: ${AssetName}]: Unable to extract ZIP archive [$($DownloadedFileInfo.FullPath)]: $_"
					return $DownloadedFileInfo
				}

				# The ZIP is no longer needed after extraction.
				try {
					Remove-Item -Path $DownloadedFileInfo.FullPath -Force -ErrorAction Stop
					Write-Debug "[Produce-FileInfo_AssetLocalInstance: ${AssetName}]: Removed ZIP archive [$($DownloadedFileInfo.FullPath)]"
				}
				catch {
					Write-Warning "[Produce-FileInfo_AssetLocalInstance: ${AssetName}]: Unable to remove ZIP archive [$($DownloadedFileInfo.FullPath)]: $_"
				}

				# Find the requested asset inside the extracted files.
				$ExtractedFileInfo = Get-FileInfo_HighestRevisionLocalInstanceFileName -LocalFileName $AssetName -LocalInstancesPath @($AssetDownloadPath)

				if ($ExtractedFileInfo.FileName -eq 'FileNotFound') {
					Write-Error "[Produce-FileInfo_AssetLocalInstance: ${AssetName}]: ZIP archive was extracted, but the requested asset was not found."
					return $DownloadedFileInfo
				}

				Write-Verbose "[Produce-FileInfo_AssetLocalInstance: ${AssetName}]: Extracted asset found at [$($ExtractedFileInfo.FullPath)]"
				return $ExtractedFileInfo
			} else {
				Write-Verbose "[Produce-FileInfo_AssetLocalInstance: ${AssetName}]: Downloaded: $($DownloadedFileInfo.FullPath)"
				return $DownloadedFileInfo
			}
		}
		
    }
	# just in case
    return $HighestRevisionLocalFileInfo
}



$ErrorActionPreference = 'Stop'

# Find the latest locally available version of the manifest.
Write-Debug "[PowerShell-ProjectBootstrap]: Get-FileInfo_HighestRevisionLocalInstanceFileName -LocalFileName $($ManifestFileName) -LocalInstancesPath $($LocalInstancesPath)"
$ManifestFileInfo = Get-FileInfo_HighestRevisionLocalInstanceFileName -LocalFileName $ManifestFileName -LocalInstancesPath $LocalInstancesPath
if ($ManifestFileInfo.FileName -eq 'FileNotFound') {
    Write-Error "[PowerShell-ProjectBootstrap]: Unable to find [$ManifestFileName]"
    exit 1
}
Write-Debug "[PowerShell-ProjectBootstrap]: Found candidate [$($ManifestFileInfo.FullPath)]"
$ManifestData = Import-PowerShellDataFile -Path $ManifestFileInfo.FullPath
if ($null -eq $ManifestData.Manifest) {
    Write-Error "[PowerShell-ProjectBootstrap]: $($ManifestFileInfo.FullPath) ended up not being a valid manifest."
    exit 1
}

# If we are still here, then, hooray! we found a manifest file!
$ManifestFileName = $ManifestData.Manifest.AssetName
$ManifestOwner = $ManifestData.Manifest.Owner
$ManifestRepo = $ManifestData.Manifest.Repo
Write-Debug "[PowerShell-ProjectBootstrap]: Produce-FileInfo_AssetLocalInstance -AssetName $($ManifestFileName) -Owner $($ManifestOwner) -Repo $($ManifestRepo) -Token $($GitHubToken) -LocalInstancesPath $($LocalInstancesPath)"
# Fetch the highest revision either locally or remotely from GitHub
$ManifestFileInfo = Produce-FileInfo_AssetLocalInstance -AssetName $ManifestFileName -Owner $ManifestOwner -Repo $ManifestRepo -Token $GitHubToken -LocalInstancesPath $LocalInstancesPath

if ($ManifestFileInfo.FileName -eq 'FileNotFound') {
    Write-Error "[PowerShell-ProjectBootstrap]: Unable to obtain [$ManifestFileName]"
    exit 1
}
Write-Verbose "[PowerShell-ProjectBootstrap]: Manifest File: [$($ManifestFileInfo.FullPath)]"

# With the latest manifest now in hand, load it and update the variables
$ManifestData = Import-PowerShellDataFile -Path $ManifestFileInfo.FullPath
$ManifestFileName = $ManifestData.Manifest.AssetName
$ManifestOwner = $ManifestData.Manifest.Owner
$ManifestRepo = $ManifestData.Manifest.Repo
$ManifestAutoRunScript = $ManifestData.AutoRun.AssetName


# Process Assets
if ($ManifestData.Assets) {
	Write-Verbose "[PowerShell-ProjectBootstrap: $($ManifestFileName)]: Gathering Assets"
    foreach ($Asset in $ManifestData.Assets) {

        Write-Debug "[PowerShell-ProjectBootstrap: $($ManifestFileName)]: Processesing Asset: $($Asset.AssetName)"
        # re-create directory structures
		if (-not (Test-Path -Path $Asset.InstallPath -PathType Container)) {
			try {
				New-Item -Path $Asset.InstallPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
				Write-Verbose "[PowerShell-ProjectBootstrap: $($ManifestFileName): $($Asset.AssetName)]: Creating directory '$($Asset.InstallPath)'"
			}
			catch {
				Write-Error "[PowerShell-ProjectBootstrap: $($ManifestFileName): $($Asset.AssetName)]: $_"
				Write-Error "[PowerShell-ProjectBootstrap: $($ManifestFileName): $($Asset.AssetName)]: Unable to create directory '$($Asset.InstallPath)'"
				exit 1
			}
		}
		# Get Reference File if present
		if ($null -ne $Asset.InstalledVersionReferenceAsset) {
			$Asset_InstalledVersionReferenceAsset = $Asset.InstalledVersionReferenceAsset
		} else {
			$Asset_InstalledVersionReferenceAsset = $null
		}
		
		$AssetFileInfo = Produce-FileInfo_AssetLocalInstance -AssetName $Asset.AssetName -Owner $Asset.Owner -Repo $Asset.Repo -Token $GitHubToken -LocalInstancesPath @($Asset.InstallPath) -AssetDownloadPath $Asset.InstallPath -AssetInstalledVersionReference $Asset_InstalledVersionReferenceAsset
        if ($AssetFileInfo.FileName -eq 'FileNotFound') {
            Write-Error "[PowerShell-ProjectBootstrap: $($ManifestFileName): $($Asset.AssetName)]: Unable to obtain Asset"
            exit 1
        }
        Write-Verbose "[PowerShell-ProjectBootstrap: $($ManifestFileName)]: Asset '$($Asset.AssetName)' found at [$($AssetFileInfo.FullPath)]"
    }
}
else {
    Write-Verbose "[PowerShell-ProjectBootstrap: $($ManifestFileName)]: Manifest contains no Assets"
}

# AutoRun
$AutoRun_CommandLineBypass = ($null -ne $DoNotAutoRun)

# Check if there is a FileName in the AutoRun section.
$AutoRun_FileNameInManifest = $false
if ($null -ne $ManifestData.AutoRun) {
	if ($null -ne $ManifestAutoRunScript) {
		if ('' -ne $ManifestAutoRunScript) {
			$AutoRun_FileNameInManifest = $true
		}
	}
}

# If there is no FileName in the AutoRun section, then there is no need to proceed further.
if (-not $AutoRun_FileNameInManifest) {
	Write-Debug "[PowerShell-ProjectBootstrap: $($ManifestFileName)]: Manifest does not specify any AutoRun script."
	if (-not $AutoRun_CommandLineBypass) {
		Write-Warning "[PowerShell-ProjectBootstrap: $($ManifestFileName)]: AutoRun is not bypassed."
	}
	Write-Verbose "[PowerShell-ProjectBootstrap: $($ManifestFileName)]: Done, no AutoRuns present."
	exit 0
}
# If there is a FileName in the AutoRun section, make sure it's valid and up to date.
$AutoRun_Valid = $false

If ($AutoRun_FileNameInManifest) {
	$AutoRunFileInfo = Produce-FileInfo_AssetLocalInstance -AssetName $ManifestAutoRunScript -Owner $ManifestOwner -Repo $ManifestRepo -Token $GitHubToken -LocalInstancesPath $LocalInstancesPath
	if ($AutoRunFileInfo.FileName -eq 'FileNotFound') {
		if (-not $AutoRun_CommandLineBypass) {
			Write-Error "[PowerShell-ProjectBootstrap: $($ManifestFileName)]: Unable to obtain main script [$($ManifestAutoRunScript)]"
			exit 1
		} else {
			Write-Warning "[PowerShell-ProjectBootstrap: $($ManifestFileName)]: AutoRun Bypassed, but AutoRun script was invalid: $($ManifestAutoRunScript)"
			exit 0
		}
	} else { 
		Write-Debug "[PowerShell-ProjectBootstrap: $($ManifestFileName)]: AutoRun script found, is valid: $($ManifestAutoRunScript)"
		$AutoRun_Valid = $true
		if ($AutoRun_CommandLineBypass) {
			Write-Verbose "[PowerShell-ProjectBootstrap: $($ManifestFileName)]: AutoRun script '$($ManifestAutoRunScript)' was bypassed by the user."
			exit 0
		}		 
	}
}

if ($AutoRun_Valid) {
    Write-Verbose "[PowerShell-ProjectBootstrap: $ManifestFileName]: Executing AutoRun Script '$($AutoRunFileInfo.FullPath)'"
    . $AutoRunFileInfo.FullPath
}

