[CmdletBinding()]
param(
    [string]$ManifestFileName = 'Manifest.psd1',
    [string]$GitHubToken,
	[switch]$DoNotAutoRun,
	[switch]$PreserveOldVersions,
	[switch]$RestartingFromSelfUpdate,
	[switch]$UserBypassSelfUpdate
)
if ($PSBoundParameters.ContainsKey('Debug')) {
    $DebugPreference = 'Continue'
}
$ErrorActionPreference = 'Stop'

# Get Launch Information & Parameters
[string[]]$LocalInstancesPath = @(".", ".\lib", "..\lib")
$ThisScriptFileName = [string]( [System.IO.Path]::GetFileName($PSCommandPath) )

[string]$BootstrapperArguments = " -ManifestFileName `"$ManifestFileName`""
if ($PSBoundParameters.ContainsKey('GitHubToken')) {
	[string]$BootstrapperArguments_GitHubToken = " -GitHubToken `"$GitHubToken`""
	$BootstrapperArguments += $BootstrapperArguments_GitHubToken
}
$AutoRun_CommandLineBypass = ($PSBoundParameters.ContainsKey('DoNotAutoRun'))
if ($AutoRun_CommandLineBypass) {
	[string]$BootstrapperArguments_DoNotAutoRun = " -DoNotAutoRun"
	$BootstrapperArguments += $BootstrapperArguments_DoNotAutoRun
}

$DontDeleteOlderBootstrapperVersions = ($PSBoundParameters.ContainsKey('PreserveOldVersions'))
$Global:PurgeOldVersions = ( -not ($PSBoundParameters.ContainsKey('PreserveOldVersions')) )
if ($DontDeleteOlderBootstrapperVersions) {
	[string]$BootstrapperArguments_PreserveOldVersions = " -PreserveOldVersions"
	$BootstrapperArguments += $BootstrapperArguments_PreserveOldVersions
}
$UserRequestsBypassOfUpdate = $PSBoundParameters.ContainsKey('UserBypassSelfUpdate')
if ($UserRequestsBypassOfUpdate) {
	[string]$BootstrapperArguments_UserBypassSelfUpdate = " -UserBypassSelfUpdate"
	$BootstrapperArguments += $BootstrapperArguments_UserBypassSelfUpdate
}

if ($PSBoundParameters.ContainsKey('Debug')) {
	[string]$BootstrapperArguments_Debug = " -Debug"
	$BootstrapperArguments += $BootstrapperArguments_Debug
}
if ($PSBoundParameters.ContainsKey('Verbose')) {
	[string]$BootstrapperArguments_Debug = " -Verbose"
	$BootstrapperArguments += $BootstrapperArguments_Debug
}

[string]$BootstrapperArgumentsToPass = $BootstrapperArguments
$JustRestartedFromSelfUpdate = [boolean]($PSBoundParameters.ContainsKey('RestartingFromSelfUpdate'))
if ($JustRestartedFromSelfUpdate) {
	[string]$BootstrapperArguments_RestartingFromSelfUpdate = " -RestartingFromSelfUpdate"
	$BootstrapperArguments += $BootstrapperArguments_RestartingFromSelfUpdate
}
Write-Debug "[$ThisScriptFileName]: Program: jeremytiggy/Powershell-ProjectBootstrap"
Write-Debug "[$ThisScriptFileName]: Arguments: $BootstrapperArguments"

# Independent Functions
function GitHub_REST_API_GET_LatestRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [Parameter(Mandatory = $true)]
        [string]$Repo,

        [string]$Token
    )
	Write-Debug "[ function GitHub_REST_API_GET_LatestRelease ]"
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
	Write-Debug "[Get-GitHubLatestRelease: $($Owner)/$($Repo)]: Attempting to connect to Github Repository"
	
    try {
		$LatestRelease = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get        
        Write-Debug "[Get-GitHubLatestRelease: $($Owner)/$($Repo)]: [$($LatestRelease.tag_name)] $($LatestRelease.name)"
        return $LatestRelease
    }
    catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) {
            Write-Warning "[Get-GitHubLatestRelease: $($Owner)/$($Repo)]: Resource not found"
        } elseif ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 403) {
            Write-Warning "[Get-GitHubLatestRelease: $($Owner)/$($Repo)]: Resource forbidden, try token"
        } else {
            Write-Warning "[Get-GitHubLatestRelease: $($Owner)/$($Repo)]: $_"
        }
        return $null
    }
}

# Program Specific Custom Classes
Class FileInfo {
	# This is a object class designed to handle the many different locators and aliases that files within this program may have
	#Public Properties
	[string]$FileName
	[string]$FileExtension
	[string]$FullName
	[string]$FilePath
	[string]$FullPath
	[string]$AssetName
	[string]$HasExtension
	[string]$MajorVersion
	[string]$MinorVersion
	[version]$Revision
	[boolean]$NotFoundLocally
	[boolean]$NotFoundRemotely
	[boolean]$FoundLocally
	[boolean]$FoundRemotely
	
	# Static Functions
	static [hashtable]ParseParameters([hashtable]$Properties) {
		Write-Debug "[ [FileInfo]::ParseParameters([hashtable]Properties) ]"
		$UsableProperties = @{
			FileInfo = $null
			
			FileName = $null
			FileExtension = $null
			FullName = $null
			FilePath = $null
			FullPath = $null
			AssetName = $null
			HasExtension = $null
			MajorVersion = $null
			MinorVersion = $null
			Revision = $null
			NotFoundLocally = $null
			NotFoundRemotely = $null
			FoundLocally = $null
			FoundRemotely = $null

			InstalledVersionReferenceAsset = $null
			ReferencePath = $null
			
			AssetFileName = $null
			InstallPath = $null
			
			LocalFileName = $null
			LocalInstancesPath =  $null
			
		}
		foreach ($Property in @($UsableProperties.Keys)) {
			if ($Properties.ContainsKey($Property)) {
				$UsableProperties[$Property] = $Properties[$Property]
			}
		}

		$FileInfoHashtable = ( ($UsableProperties.HasExtension -ne $null) -and ( ($UsableProperties.HasExtension -eq $true) -or ($UsableProperties.HasExtension -eq $false) ) )		
		if ($null -ne $UsableProperties.FileInfo) {
			if ($UsableProperties.FileInfo.ContainsKey('FullPath')) {
				$FullPath_Valid = (-not [string]::IsNullOrWhiteSpace([string]$UsableProperties.FileInfo.FullPath))
				$FileInfoObjectClone = $FullPath_Valid
			} else { $FileInfoObjectClone = $false }
		} else { $FileInfoObjectClone = $false }
		if ($FileInfoHashtable -or $FileInfoObjectClone) {
			[hashtable]$FileInfo_Properties = @{
				FileName = $null
				FileExtension = $null
				FullName = $null
				FilePath = $null
				FullPath = $null
				AssetName = $null
				HasExtension = $null
				MajorVersion = $null
				MinorVersion = $null
				Revision = $null
				NotFoundLocally = $null
				NotFoundRemotely = $null
				FoundLocally = $null
				FoundRemotely = $null
			}
			if ($FileInfoHashtable) {
				foreach ($Property in @($FileInfo_Properties.Keys)) {
					if ($UsableProperties.ContainsKey($Property)) {
						$FileInfo_Properties[$Property] = $UsableProperties[$Property]
					}
				}
			}
			if ($FileInfoObjectClone) {
				foreach ($Property in @($FileInfo_Properties.Keys)) {
					if ($UsableProperties.FileInfo.ContainsKey($Property)) {
						$FileInfo_Properties[$Property] = $UsableProperties.FileInfo[$Property]
					}
				}				
			}
			Write-Debug "[FileInfo.ParseParameters: $FileInfo_Properties.FileName]: Passing FileInfo properties"
			return [hashtable]$FileInfo_Properties
		}
		
		[hashtable]$InputParameters = @{
			FileName = ''
			FilePath = ''
		}
		# $InputParameters from $UsableProperties
		# InputParameters.FileName
		[string]$Input_FileName = ''
		if ($null -ne $UsableProperties.FileInfo) {
			if ($UsableProperties.FileInfo.ContainsKey('FullPath')) {
				$FullPath_Usable = ($UsableProperties.FileInfo.FullPath -notlike 'https://*')
				$FullPath_URL = ($UsableProperties.FileInfo.FullPath -like 'https://*')
				$FullPath_Valid = (-not [string]::IsNullOrWhiteSpace([string]$UsableProperties.FileInfo.FullPath))
				if ($FullPath_Usable -and $FullPath_Valid) {
					Write-Debug "[FileInfo.ParseParameters: InputParameters.FileName]:  UsableProperties.FileInfo.FullPath = $([string]$UsableProperties.FileInfo.FullPath)"
					$Input_FileName = [string]$UsableProperties.FileInfo.FullPath
				} else {
					$FullName_Valid = (-not [string]::IsNullOrWhiteSpace([string]$UsableProperties.FileInfo.FullName))
					if ($FullName_Valid) {
						Write-Debug "[FileInfo.ParseParameters: InputParameters.FileName]: UsableProperties.FileInfo.FullName = $([string]$UsableProperties.FileInfo.FullName)"
						$Input_FileName = [string]$UsableProperties.FileInfo.FullName
					}
				}
			}
		}
		$FileName_StillBlank = ( ($Input_FileName -eq '') -or ([string]::IsNullOrWhiteSpace($Input_FileName)) )
		if ($FileName_StillBlank) {
			if (-not [string]::IsNullOrWhiteSpace([string]$UsableProperties.InstalledVersionReferenceAsset)) {
				Write-Debug "[FileInfo.ParseParameters: InputParameters.FileName]: UsableProperties.InstalledVersionReferenceAsset = $([string]$UsableProperties.InstalledVersionReferenceAsset)"
				$Input_FileName = [string]$UsableProperties.InstalledVersionReferenceAsset
			} elseif (-not [string]::IsNullOrWhiteSpace([string]$UsableProperties.AssetName)) {
				Write-Debug "[FileInfo.ParseParameters: InputParameters.FileName]: UsableProperties.AssetName = $([string]$UsableProperties.AssetName)"
				$Input_FileName = [string]$UsableProperties.AssetName
			} elseif (-not [string]::IsNullOrWhiteSpace([string]$UsableProperties.FileName)) {
				Write-Debug "[FileInfo.ParseParameters: InputParameters.FileName]: UsableProperties.FileName = $([string]$UsableProperties.FileName)"
				$Input_FileName = [string]$UsableProperties.FileName
			} elseif (-not [string]::IsNullOrWhiteSpace([string]$UsableProperties.FullName)) {
				Write-Debug "[FileInfo.ParseParameters: InputParameters.FileName]: UsableProperties.FullName = $([string]$UsableProperties.FullName)"
				$Input_FileName = [string]$UsableProperties.FullName
			} elseif (-not [string]::IsNullOrWhiteSpace([string]$UsableProperties.LocalFileName)) {
				Write-Debug "[FileInfo.ParseParameters: InputParameters.FileName]: UsableProperties.LocalFileName = $([string]$UsableProperties.LocalFileName)"
				$Input_FileName = [string]$UsableProperties.LocalFileName
			} elseif (-not [string]::IsNullOrWhiteSpace([string]$UsableProperties.AssetFileName)) {
				Write-Debug "[FileInfo.ParseParameters: InputParameters.FileName]: UsableProperties.AssetFileName = $([string]$UsableProperties.AssetFileName)"
				$Input_FileName = [string]$UsableProperties.AssetFileName
			}			
		}
		Write-Debug "[FileInfo.ParseParameters: InputParameters.FileName]: FileName = $Input_FileName"
		$FileName_StillBlank = ( ($Input_FileName -eq '') -or ([string]::IsNullOrWhiteSpace($Input_FileName)) )
		if ($FileName_StillBlank) {
			Write-Warning "[FileInfo::ParseParameters: InputParameters.FileName]: FileName is null or empty. "
			$InputParameters.FileName = ''
		} else {
			$InputParameters.FileName = $Input_FileName
		}
		Write-Debug "[FileInfo::ParseParameters: InputParameters]: InputParameters.FileName = $($InputParameters.FileName)"

		
		# InputParameters.FilePath
		[string]$Input_FilePath = ''
		if ($null -ne $UsableProperties.FileInfo) {
			if ($UsableProperties.FileInfo.ContainsKey('FilePath')) {
					Write-Debug "[FileInfo.ParseParameters: InputParameters.FilePath]:  UsableProperties.FileInfo.FilePath = $([string]$UsableProperties.FileInfo.FilePath)"
					$Input_FilePath = [string]$UsableProperties.FileInfo.FilePath
			}
		}
		$FilePath_StillBlank = ( ($Input_FilePath -eq '') -or ([string]::IsNullOrWhiteSpace($Input_FilePath)) )
		if ($FilePath_StillBlank) {
			if (-not [string]::IsNullOrWhiteSpace([string]$UsableProperties.ReferencePath)) {
				Write-Debug "[FileInfo.ParseParameters: InputParameters.FilePath]: UsableProperties.ReferencePath = $([string]$UsableProperties.ReferencePath)"
				$Input_FilePath = [string]$UsableProperties.ReferencePath
			} elseif (-not [string]::IsNullOrWhiteSpace([string]$UsableProperties.InstallPath)) {
				Write-Debug "[FileInfo.ParseParameters: InputParameters.FilePath]: UsableProperties.InstallPath = $([string]$UsableProperties.InstallPath)"
				$Input_FilePath = [string]$UsableProperties.InstallPath
			} elseif (-not [string]::IsNullOrWhiteSpace([string]$UsableProperties.FilePath)) {
				Write-Debug "[FileInfo.ParseParameters: InputParameters.FilePath]: UsableProperties.FilePath = $([string]$UsableProperties.FilePath)"
				$Input_FilePath = [string]$UsableProperties.FilePath
			} elseif (-not [string]::IsNullOrWhiteSpace([string]$UsableProperties.LocalInstancesPath)) {
				Write-Debug "[FileInfo.ParseParameters: InputParameters.FilePath]: UsableProperties.LocalInstancesPath = $([string]$UsableProperties.LocalInstancesPath)"
				$Input_FilePath = [string]$UsableProperties.LocalInstancesPath
			}
		}
		Write-Debug "[FileInfo.ParseParameters: InputParameters.FilePath]: FilePath = $Input_FilePath"
		$FilePath_StillBlank = ( ($Input_FilePath -eq '') -or ([string]::IsNullOrWhiteSpace($Input_FilePath)) )
		if ($FilePath_StillBlank) {
			Write-Debug "[FileInfo::ParseParameters: InputParameters.FilePath]: FilePath is null or empty. "
			$InputParameters.FilePath = ''
		} else {
			$InputParameters.FilePath = $Input_FilePath
		}
		Write-Debug "[FileInfo::ParseParameters: InputParameters]: InputParameters.FileName = $($InputParameters.FileName)"
		
		Write-Debug "[FileInfo::ParseParameters]: FileName: $([string]($InputParameters.FileName)), FilePath: $([string]($InputParameters.FilePath))"
		return $InputParameters
		
	}
	static [version] Revision_FileName( [string]$Versioned_FileName ) {
		Write-Debug "[ [FileInfo]::Revision_FileName([string]Versioned_FileName) ]"
		$Versioned_FileNameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($Versioned_FileName)
		if ( $Versioned_FileNameWithoutExtension -match '^(.*)_v(\d+)\.(\d+)$' ) {
			$Major = $matches[2]
			$Minor = $matches[3]
			return [version]"$($Major).$($Minor)"
		}
		else {
			return [version]"0.0"
		}
	}
	static [FileInfo]HighestRevisionWithin_FileInfos([PSCustomObject[]]$FileInfos) {
		Write-Debug "[ [FileInfo]::HighestRevisionWithin_FileInfos([PSCustomObject[]]FileInfos) ]"
		$HighestRevision = [version]"0.0"
		$HighestRevisionFileInfo = $null
		Write-Debug "[FileInfo.HighestRevisionWithin_FileInfos]: Evaluating FileInfo list:"
		foreach ($FileInfo in $FileInfos) {
			Write-Debug "[FileInfo.HighestRevisionWithin_FileInfos]: $([string]$FileInfo.FullName)"
			[version]$FileRevision = $FileInfo.Revision
			if ($FileRevision -gt $HighestRevision) {
				$HighestRevision = $FileRevision
				$HighestRevisionFileInfo = $FileInfo
			}
		}
		Write-Debug "[FileInfo.HighestRevisionWithin_FileInfos]: Highest Revision FileInfo: $([string]$HighestRevisionFileInfo.FullName)"
		return $HighestRevisionFileInfo
	}	
	static [FileInfo]DownloadFullPath([hashtable]$Properties) {
		Write-Debug "[ [FileInfo]::DownloadFullPath([hashtable]Properties) ]"

		$AssetFileInfo = [FileInfo]::new([hashtable]$Properties)
		$AssetFileInfo.FullPath = $Properties.FullPath
		$AssetFileInfo.WD()
		
		if ($AssetFileInfo.FullPath -notlike 'https://*') {
			Write-Warning "[FileInfo.DownloadFullPath]: Full Path is not a web address: $($AssetFileInfo.FullPath)"
			return $AssetFileInfo
		}

		$downloadUri = $AssetFileInfo.FullPath    
		$downloadDirectory = $AssetFileInfo.FilePath
		$downloadFileName = $AssetFileInfo.FullName

		# if download directory doesn't exist, create it
		$downloadDirectoryAlreadyExists = Test-Path -Path $downloadDirectory -PathType Container
		if (-not $downloadDirectoryAlreadyExists) {
			Write-Debug "[FileInfo.DownloadFullPath]: Could not find Download directory: $($downloadDirectory)"
			try {
				New-Item -Path $downloadDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
				Write-Debug "[FileInfo.DownloadFullPath]: Created Download directory: $($downloadDirectory)"
			}
			catch {
				Write-Warning "[FileInfo.DownloadFullPath]: Unable to create download directory [$downloadDirectory]: $_"
				return $AssetFileInfo
			}
		} else {
			Write-Debug "[FileInfo.DownloadFullPath]: Download directory: $($downloadDirectory)"
		}
		
		$downloadLocalPath = Join-Path -Path $downloadDirectory -ChildPath $downloadFileName
		[hashtable]$downloadFileInfo_Properties = 	@{
														FileName = [string]$downloadFileName
														FilePath = [string]$downloadDirectory
													}		
		Write-Debug "[FileInfo.DownloadFullPath: $($AssetFileInfo.FileName)]: Downloading [$downloadUri]"
		Write-Debug "[FileInfo.DownloadFullPath: $($AssetFileInfo.FileName)]: Saving to [$downloadLocalPath]"

		try {
			Invoke-WebRequest -Uri $downloadUri -OutFile $downloadLocalPath -ErrorAction Stop
			Write-Debug "[FileInfo.DownloadFullPath: $($AssetFileInfo.FileName)]: Download completed"
			if (Test-Path -Path $downloadLocalPath -PathType Leaf) {

				[FileInfo]$ConfirmedFileInfo = [FileInfo]::HighestRevisionLocalInstanceFileName($downloadFileInfo_Properties)
				Write-Debug "[FileInfo.DownloadFullPath: $($AssetFileInfo.FileName)]: Download completed and found at: $([string]$ConfirmedFileInfo.FullPath)"
				return $ConfirmedFileInfo
			}
			else {
				Write-Warning "[FileInfo.DownloadFullPath]: Download completed but file [$downloadLocalPath] was not found"
				return $AssetFileInfo
			}
		} catch {
			Write-Warning "[FileInfo.DownloadFullPath]: Invoke-WebRequest: $_ "
			return $AssetFileInfo
		}
		return $AssetFileInfo
	}	
	static [FileInfo]HighestRevisionLocalInstanceFileName([hashtable]$Properties) {
		Write-Debug "[ function [FileInfo]::HighestRevisionLocalInstanceFileName ]"
		
		[hashtable]$AssetFile_Properties = [hashtable]([FileInfo]::ParseParameters($Properties))
		Write-Debug "[FileInfo.HighestRevisionLocalInstanceFileName]: FileName = $([string]$AssetFile_Properties.FileName), FilePath = $([string]$AssetFile_Properties.FilePath)"
		$AssetFile = [FileInfo]::new([hashtable]$AssetFile_Properties)
		if ( [string]$AssetFile.FullName -eq 'FileNotFound' ) {
			Write-Warning "[FileInfo.HighestRevisionLocalInstanceFileName]: Malformed input"
			return $Global:FileNotFound_FileInfo
		}
		[string]$AssetFileName = [string]$AssetFile.FileName
		[string]$AssetFilePath = [string]$AssetFile.FilePath
		if ($AssetFile.HasExtension) {
			[string]$AssetFileExtension = [string]$AssetFile.FileExtension
			[string]$AssetFileNamePattern = [string]"${AssetFileName}_v*.*$AssetFileExtension"
		} else {
			[string]$AssetFileNamePattern = [string]"${AssetFileName}_v*.*"
		}
		Write-Debug "[FileInfo.HighestRevisionLocalInstanceFileName: $AssetFileName]: Search Directory: $($AssetFilePath), Search Pattern: $($AssetFileNamePattern)"
		
		[version]$HighestRevisionLocalInstance = [version]"0.0"
		[string]$HighestRevisionLocalInstanceFileName = ''
		[string]$HighestRevisionLocalInstanceFilePath = ''
		foreach ($LocalInstanceFilePath in $AssetFilePath) {
			$FilteredFilePathFileNames = Get-ChildItem -Path $LocalInstanceFilePath -Filter $AssetFileNamePattern -File -ErrorAction SilentlyContinue
			if ($FilteredFilePathFileNames) {
				foreach ($LocalInstanceFile in $FilteredFilePathFileNames) {
					[string]$LocalInstanceFileName = [string]$LocalInstanceFile.Name
					[version]$RevisionLocalInstance = [version]([FileInfo]::Revision_FileName($LocalInstanceFileName))
					Write-Debug "[FileInfo.HighestRevisionLocalInstanceFileName: $AssetFileName]: Examining $([string]$LocalInstanceFileName) v$([string]$RevisionLocalInstance)"
					if ($RevisionLocalInstance -ge $HighestRevisionLocalInstance) {
						$HighestRevisionLocalInstance = $RevisionLocalInstance
						$HighestRevisionLocalInstanceFileName = $LocalInstanceFileName
						$HighestRevisionLocalInstanceFilePath = $([string]$LocalInstanceFilePath)
						Write-Debug "[FileInfo.HighestRevisionLocalInstanceFileName: $AssetFileName]: Current Highest Revision of $([string]$AssetFileName) in $([string]$LocalInstanceFilePath): $([string]$HighestRevisionLocalInstance)"
					}
				}
			} 
		}
		$NoHighestRevisionFileInfo = ( ($HighestRevisionLocalInstanceFileName -eq '') -and ($HighestRevisionLocalInstanceFilePath -eq '') )
		if ($NoHighestRevisionFileInfo) {
			Write-Debug "[FileInfo.HighestRevisionLocalInstanceFileName: $AssetFileName]: No Highest Revision Info Found"
			return $Global:FileNotFound_FileInfo
		}
		$IncompleteHighestRevisionFileInfo = ( ( $HighestRevisionLocalInstanceFileName -ne '' ) -and ($HighestRevisionLocalInstanceFilePath -eq '') )
		$CompleteHighestRevisionFileInfo   = ( ( $HighestRevisionLocalInstanceFileName -ne '' ) -and ($HighestRevisionLocalInstanceFilePath -ne '') )
		if ( $CompleteHighestRevisionFileInfo -or $IncompleteHighestRevisionFileInfo ) {
			Write-Debug "[FileInfo.HighestRevisionLocalInstanceFileName: $AssetFileName]: Highest Revision File Found: $HighestRevisionLocalInstanceFileName"
			if ($IncompleteHighestRevisionFileInfo) {
				Write-Debug "[FileInfo.HighestRevisionLocalInstanceFileName: $AssetFileName]: Warning: FilePath empty. Possibly error, or same directory."
			}
			[hashtable]$HighestRevisionLocalInstanceFile_Properties = @{
				FileName = $HighestRevisionLocalInstanceFileName
				FilePath = $HighestRevisionLocalInstanceFilePath
			}
			$FileInfo_HighestRevisionLocalInstanceFileName = [FileInfo]::new($HighestRevisionLocalInstanceFile_Properties)
			return $FileInfo_HighestRevisionLocalInstanceFileName
		}
		return $Global:FileNotFound_FileInfo
	}
	static [FileInfo]DeleteLowerRevisionLocalInstances([hashtable]$Properties) {
		Write-Debug "[ function DeleteLowerRevisionLocalInstances ]"
		$FileInfo = [FileInfo]::new($Properties)
		if ($FileInfo.FileName -eq 'FileNotFound' -or
			[string]::IsNullOrWhiteSpace($FileInfo.FullPath)) {
			Write-Debug "[DeleteLowerRevisionLocalInstances]: FileInfo does not identify a valid file"
			return $FileInfo
		}

		[string]$inputFileName = [string]($FileInfo.FileName)
		Write-Debug "[DeleteLowerRevisionLocalInstances]: Survivor: $inputFileName"
		if ($FileInfo.HasExtension) {
			[string]$inputFileExtension = [string]($FileInfo.FileExtension)
			[string]$pattern = "${inputFileName}_v*.*$inputFileExtension"
		}
		else {
			$pattern = "${inputFileName}_v*.*"
		}
		Write-Debug "[DeleteLowerRevisionLocalInstances]: Pattern: $pattern"
		[string]$localPath = [string]($FileInfo.FilePath)

		if (-not (Test-Path -LiteralPath $localPath)) {
			Write-Warning "[DeleteLowerRevisionLocalInstances: $($FileInfo.AssetName)]: Path not found: $localPath"
			return $FileInfo
		}
		Write-Debug "[DeleteLowerRevisionLocalInstances]: Path: $localPath"
		$matchingFileInfos = @()

		$files = Get-ChildItem -Path $localPath -Filter $pattern -File -ErrorAction SilentlyContinue
		if (-not $files) {
			Write-Debug "[DeleteLowerRevisionLocalInstances: $($FileInfo.AssetName)]: No matching files found"
			return $FileInfo
		}
		foreach ($file in $files) {
			$matchingFileInfos += [FileInfo]::new(@{FileName=[string]($file.FullName)})
		}
		if ($matchingFileInfos.Count -eq 0) {
			Write-Debug "[DeleteLowerRevisionLocalInstances: $($FileInfo.AssetName)]: No valid matching FileInfo entries found"
			return $FileInfo
		}
		$highestRevisionMatchingFileInfo = $FileInfo
		[string]$highestRevisionMatchingFile_FullPath = [string]($highestRevisionMatchingFileInfo.FullPath)
		foreach ($matchingFileInfo in $matchingFileInfos) {
			[string]$matchingFile_FullPath = $matchingFileInfo.FullPath
			if ($matchingFileInfo.FullPath -eq $highestRevisionMatchingFileInfo.FullPath) {
				continue
			}
			if ([version]::new(
					$matchingFileInfo.MajorVersion,
					$matchingFileInfo.MinorVersion
				) -lt [version]::new(
					$highestRevisionMatchingFileInfo.MajorVersion,
					$highestRevisionMatchingFileInfo.MinorVersion
				)) {

				Write-Debug "[DeleteLowerRevisionLocalInstances: $($FileInfo.AssetName)]: Removing older revision: $matchingFile_FullPath"
				Remove-Item -LiteralPath $matchingFileInfo.FullPath -Force -ErrorAction Stop
				Write-Debug "[DeleteLowerRevisionLocalInstances: $($FileInfo.AssetName)]: Test-Path -LiteralPath $matchingFile_FullPath)"
				$fileSuccessfullyDeleted = (-not (Test-Path -LiteralPath $matchingFileInfo.FullPath))
				if ($fileSuccessfullyDeleted) {
					Write-Verbose "[DeleteLowerRevisionLocalInstances: $($FileInfo.AssetName)]: deleted out-of-date file $matchingFile_FullPath"
				} else {
					Write-Warning "[DeleteLowerRevisionLocalInstances: $($FileInfo.AssetName)]: Deletion attempt failed for $matchingFile_FullPath"
				}
				
			}
		}

		return $FileInfo
	}	
	# Shared Initializer
	[void]Init([hashtable]$InputParameters) {
		Write-Debug "[ [FileInfo]::[void]Init([hashtable]InputParameters) ]"
		Write-Debug "[FileInfo.Init]: FileName = $([string]($InputParameters.FileName)), FilePath = $([string]($InputParameters.FilePath))]"
		
		$FileInfoHashtable = ( ($InputParameters.HasExtension -ne $null) -and ( ($InputParameters.HasExtension -eq $true) -or ($InputParameters.HasExtension -eq $false) ) )		
		if ($FileInfoHashtable) {
			foreach ($Property in $InputParameters.Keys) {
				if ($this.PSObject.Properties.Name -contains $Property) {
					$this.PSObject.Properties[$Property].Value = $InputParameters[$Property]
				}
			}
			Write-Debug "[FileInfo.Init]: Hashtable Loaded."
		} else {
			# Initialize
			$this.NotFoundLocally = $true
			$this.NotFoundRemotely = $true
			$this.FoundLocally = $false
			$this.FoundRemotely = $false
			
			# .FullName
			# 'C:\directory\file.txt' >> 'file.txt'
			if ([string]::IsNullOrWhiteSpace([string]$InputParameters.FileName)) {
				$this.FullName = 'FileNotFound'
			# '' >> 'FileNotFound'
			} else {
				$this.FullName = [System.IO.Path]::GetFileName([string]$InputParameters.FileName)
			}
			# .FilePath
			# 'C:\directory\file.txt' >> 'C:\directory'
			if ([string]::IsNullOrWhiteSpace([string]$InputParameters.FilePath)) {
				$this.FilePath = [System.IO.Path]::GetDirectoryName([string]$InputParameters.FileName)
			} else {
				$this.FilePath = [string]$InputParameters.FilePath
			}
			# '' >> '.\'
			if ([string]::IsNullOrWhiteSpace($this.FilePath)) {
				$this.FilePath = '.\'
			}
			# 'C:\directory' >> 'C:\directory\'
			if ( -not $this.FilePath.EndsWith('\') ) { $this.FilePath += '\' }
			
			# .FullPath
			# 'C:\directory\", 'file.txt >> 'C:\directory\file.txt'
			$this.FullPath = $this.FilePath + $this.FullName
			
			# .FileExtension
			# 'file.txt' >> '.txt' >> 'txt'
			$this.FileExtension = [System.IO.Path]::GetExtension($this.FullName).TrimStart('.')
			
			# .HasExtension
			# 'txt' O
			# '' 	X
			$this.HasExtension = ($null -ne $($this.FileExtension)) -and ($($this.FileExtension) -ne '')
			
			# '[1]_v[2].[3]'
			# 'file_v1.2.txt' >> [1]'file', [2]'1', [3]'2'
			if ([System.IO.Path]::GetFileNameWithoutExtension($this.FullName) -match '^(.*)_v(\d+)\.(\d+)$' ) {
				# .FileName
				# 'file_v1.2.txt' >> 'file'
				$this.FileName = $matches[1]
				# .MajorVersion
				# 'file_v1.2.txt' >> 1
				$this.MajorVersion = [int]$matches[2]
				# .MinorVersion
				# 'file_v1.2.txt' >> 2
				$this.MinorVersion = [int]$matches[3]
				# .Revision
				# 'file_v1.2.txt' >> "1.2"
				$this.Revision = [version]"$($matches[2]).$($matches[3])"
			}
			else {
				$this.FileName = [System.IO.Path]::GetFileNameWithoutExtension($this.FullName)
				$this.MajorVersion  = 0
				$this.MinorVersion  = 0
				$this.Revision = [version]"0.0"
			}
			
			# .AssetName
			# 'file_v1.2.txt' >> 'file.txt'
			$this.AssetName = $this.FileName + "." + $this.FileExtension			
		}
		
		$this.WD()
	}		
	# Get Value
	[hashtable]Hashtable() {
		Write-Debug "[ [FileInfo]::[hashtable]Hashtable() ]"
		return 	@{
					FileName = [string]$this.FileName
					FileExtension = [string]$this.FileExtension
					FullName = [string]$this.FullName
					FilePath = [string]$this.FilePath
					FullPath = [string]$this.FullPath
					AssetName = [string]$this.AssetName
					HasExtension = [string]$this.HasExtension
					MajorVersion = [string]$this.MajorVersion
					MinorVersion = [string]$this.MinorVersion
					Revision = [version]$this.Revision
					NotFoundLocally = [boolean]$this.NotFoundLocally
					NotFoundRemotely = [boolean]$this.NotFoundRemotely
					FoundLocally = [boolean]$this.FoundLocally
					FoundRemotely = [boolean]$this.FoundRemotely
				}
	}
	# Write-Debug Values
	[void]WD() {
		Write-Debug "[ [FileInfo]::[void]WD() ]"
		#Debug Output
		Write-Debug "[FileInfo.WD]: File Info for: $([string]$this.FullName)"
		Write-Debug "	FileName = $([string]$this.FileName)"
		Write-Debug "	FileExtension = $([string]$this.FileExtension)"
		Write-Debug "	FullName = $([string]$this.FullName)"
		Write-Debug "	FilePath = $([string]$this.FilePath)"
		Write-Debug "	FullPath = $([string]$this.FullPath)"
		Write-Debug "	AssetName = $([string]$this.AssetName)"
		Write-Debug "	HasExtension = $([string]$this.HasExtension)"
		Write-Debug "	MajorVersion = $([string]$this.MajorVersion)"
		Write-Debug "	MinorVersion = $([string]$this.MinorVersion)"
		Write-Debug "	Revision = $([string]$this.Revision)"
		Write-Debug "	NotFoundLocally = $([string]$this.NotFoundLocally)"
		Write-Debug "	NotFoundRemotely = $([string]$this.NotFoundRemotely)"
		Write-Debug "	FoundLocally = $([string]$this.FoundLocally)"
		Write-Debug "	FoundRemotely = $([string]$this.FoundRemotely)"
	}
	# Download to new file Info
	[FileInfo]DownloadToNewLocalInstanceFile() {
		Write-Debug "[ [FileInfo]::[FileInfo]DownloadToNewLocalInstanceFile() ]"
		$this.WD()
		return [FileInfo]([FileInfo]::DownloadFullPath( $this.Hashtable() ))
	}
	# Constructors
	FileInfo() { 
		Write-Debug "[ [FileInfo]::new() ]"
		$this.Init(@{
			FileName = 'FileNotFound'
			FilePath = '.\'
		}) 
	}
	FileInfo([hashtable]$Properties) {
		Write-Debug "[ [FileInfo]::new( [hashtable]Properties ) ]"
		Write-Debug "[FileInfo.new]: FileName = ?, FilePath = ?"
		$this.Init( [FileInfo]::ParseParameters($Properties) )
	}
}
Class GithubRepository {
	# This object class is designed to hold the URI information of a Github Repository, and the list of files included in the latest release
	# Class Properties
	[string]$Owner
	[string]$Repo
	[string]$Token
	[string]$uri
	[Object[]]$Release
	
	# Static Functions
	static [hashtable]ParseParameters([hashtable]$Properties) {
		Write-Debug "[ [GithubRepository]::ParseParameters([hashtable]Properties) ]"
		$UsableProperties = @{
			Owner = $null
			Repo = $null
			Token = $null
			uri = $null
		}
		foreach ($Property in @($UsableProperties.Keys)) {
			if ($Properties.ContainsKey($Property)) {
				$UsableProperties[$Property] = $Properties[$Property]
			}
		}
		$InputParameters = @{
			Owner = $null
			Repo = $null
			Token = $null
			uri = $null
		}
		# $InputParameters from $UsableProperties
		$Owner_Usable = (-not [string]::IsNullOrWhiteSpace($UsableProperties.Owner))
		$Owner_NotUsable = ([string]::IsNullOrWhiteSpace($UsableProperties.Owner))
		$Repo_Usable = (-not [string]::IsNullOrWhiteSpace($UsableProperties.Repo))
		$Repo_NotUsable = ([string]::IsNullOrWhiteSpace($UsableProperties.Repo))
		$uri_Usable = (-not [string]::IsNullOrWhiteSpace($UsableProperties.uri))
		$uri_NotUsable = ([string]::IsNullOrWhiteSpace($UsableProperties.uri))
		$OwnerRepo_Usable = ($Owner_Usable -and $Repo_Usable)
		$OwnerRepo_NotUsable = ($Owner_NotUsable -and $Repo_NotUsable)
		if ($OwnerRepo_NotUsable -and $uri_NotUsable) {
			Write-Warning "[GithubRepository::InputParameters]: Inputs empty"
		}
		# $InputParameters.uri
		$uri_fromOwnerRepo = ( $OwnerRepo_Usable -and $uri_NotUsable )
		if ($uri_Usable) {
			$InputParameters.uri = $UsableProperties.uri
		} elseif ($uri_fromOwnerRepo) {
			$InputParameters.uri = $UsableProperties.Owner + "/" + $UsableProperties.Repo
			Write-Debug "[GithubRepository::InputParameters: $($InputParameters.uri)]: URI built from Owner+Repo"
		}
		# InputParameters.Repo
		$Repo_fromURI = ($Repo_NotUsable -and $uri_Usable)
		if ($Repo_Usable) {
			$InputParameters.Repo = $UsableProperties.Repo
		} elseif ($Repo_fromURI) {
			$InputParameters.Repo = ($UsableProperties.uri -split "\/")[1]
			Write-Debug "[GithubRepository::InputParameters: $($InputParameters.uri)]: Repo extracted from URI"
		}
		# InputParameters.Owner
		$Owner_fromURI = ($Owner_NotUsable -and $uri_Usable)
		if ($Owner_Usable) {
			$InputParameters.Owner = $UsableProperties.Owner
		} elseif ($Owner_fromURI) {
			$InputParameters.Owner = ($UsableProperties.uri -split "\/")[0]
			Write-Debug "[GithubRepository::InputParameters: $($InputParameters.uri)]: Owner extracted from URI"
		}
		# InputParameters.Token
		if ([string]::IsNullOrWhiteSpace($UsableProperties.Token)) { 
			$InputParameters.Token = ''
		} else {
			$InputParameters.Token = $UsableProperties.Token
		}
		return $InputParameters
	}
	static [Int]RepositoryCollectionEntryIndexForURI([hashtable]$Properties) {
		$InputProperties = [GithubRepository]::ParseParameters($Properties)
		$Repository_uri = [string]$InputProperties.uri
		$uri_Usable = ( ($null -ne $Repository_uri) -and ($Repository_uri -ne '') )
		$uri_NotUsable = ( ($null -eq $Repository_uri) -or ($Repository_uri -eq '') )
		if ($uri_NotUsable) {
			Write-Debug "[RepositoryCollectionEntryIndexForURI]: URI Not Usable"
			return -4 #URI Not Usable during Lookup
		} elseif ($uri_Usable) {
			#[int]$Index = [int]$Global:GithubRepositories.Keys.IndexOf($Repository_uri)
			[int]$Index  = [int]([array]::IndexOf([array]$Global:GithubRepositories.Keys, $Repository_uri))
			if ($Index -lt 0) {
				Write-Debug "[RepositoryCollectionEntryIndexForURI: $Repository_uri]: Repository entry not found"
				return -5
			} elseif ($Index -ge 0) {
				Write-Debug "[RepositoryCollectionEntryIndexForURI: $Repository_uri]: Repository entry found: [$Index]"
				return $Index
			}
		}
		return -6
	}
	static [FileInfo]HighestRevisionLatestReleaseFileName([hashtable]$Properties) {
		Write-Debug "[ function HighestRevisionLatestReleaseFileName ]"
		$AssetFileToFind_FileInfo = [FileInfo]::new([hashtable]$Properties)
		if ([string]$AssetFileToFind_FileInfo.FullName -eq 'FileNotFound') {
			Write-Warning "[HighestRevisionLatestReleaseFileName: $([string]$Properties.FileName)]: File Not Found"
			return $AssetFileToFind_FileInfo
		}
		[string]$AssetFileNameToFind = [string]$AssetFileToFind_FileInfo.FileName
		
		[int]$AssetFileToFind_RepositoryCollectionIndex = [GithubRepository]::RepositoryCollectionEntryIndexForURI($Properties)
		[int]$Index = $AssetFileToFind_RepositoryCollectionIndex
		[boolean]$RepositoryCollectionIndex_NotUsable = ( ($null -eq $AssetFileToFind_RepositoryCollectionIndex) -or ($AssetFileToFind_RepositoryCollectionIndex -lt 0) )
		if ($RepositoryCollectionIndex_NotUsable) {
			Write-Warning "[HighestRevisionLatestReleaseFileName]: Unable to get collection index for repository"
			return $AssetFileToFind_FileInfo
		}
		if ($null -eq $Global:GithubRepositories[$Index]) {
			Write-Warning "[HighestRevisionLatestReleaseFileName]: Unable to Get Repository for Asset"
			return $AssetFileToFind_FileInfo
		}
		if ($null -eq ($Global:GithubRepositories[$Index]).Release) {
			Write-Warning "[HighestRevisionLatestReleaseFileName]: Unable to retrieve latest Release from Repository entry."
			return $AssetFileToFind_FileInfo
		}
		[GithubRepository]$AssetFileToFind_Repository = $Global:GithubRepositories[$Index]
		[string]$AssetFileToFind_uri = [string]$AssetFileToFind_Repository.uri + '/' + [string]$AssetFileToFind_FileInfo.AssetName
		[string]$AssetFileToFind_ReleaseTitle = [string]$AssetFileToFind_Repository.Release.name + " " + [string]$AssetFileToFind_Repository.Release.tag_name
		Write-Debug "[HighestRevisionLatestReleaseFileName: $($AssetFileToFind_uri)]: Searching Release: $($AssetFileToFind_ReleaseTitle)"
		# Look through the release assets for files matching the requested base name.
		$MatchingAssets_FileInfos = @()
		$HighestRevisionMatchingAsset_FileInfo = $AssetFileToFind_FileInfo
		[string]$HighestRevisionMatchingAssetFileName = $AssetFileToFind_FileInfo.FileName
		[version]$MatchingAsset_HighestRevision = [version]"0.0"
		foreach ($Asset in $AssetFileToFind_Repository.Release.assets) {
			$Asset_FileInfo = [FileInfo]::new( [hashtable]@{FileName = [string]$Asset.name})
			[string]$AssetFileName = [string]$Asset_FileInfo.FileName
			$AssetFileNameMatchesAssetToFind = ($AssetFileName -eq $AssetFileNameToFind)
			if ($AssetFileNameMatchesAssetToFind) {
				[version]$MatchingAsset_Revision = [version]$Asset_FileInfo.Revision
				$AssetRevisionIsHigherThanHighestRevisionAsset = $MatchingAsset_Revision -ge $MatchingAsset_HighestRevision
				#$AssetIsHighestRevisionMatch = $AssetFileNameMatchesAssetToFind -and $AssetRevisionIsHigherThanHighestRevisionAsset
				if ($AssetRevisionIsHigherThanHighestRevisionAsset) {
					$MatchingAsset_HighestRevision = $MatchingAsset_Revision
					$HighestRevisionMatchingAsset_FileInfo = $Asset_FileInfo
					$HighestRevisionMatchingAsset_FileInfo.FullPath = [string]$Asset.browser_download_url
					$HighestRevisionMatchingAsset_FileInfo.FilePath = [string]$AssetFileToFind_FileInfo.FilePath
					$HighestRevisionMatchingAsset_FileInfo.NotFoundRemotely = $false
					$HighestRevisionMatchingAsset_FileInfo.FoundRemotely = $true
					$HighestRevisionMatchingAssetFileName = [string]$Asset_FileInfo.FileName
					Write-Debug "[HighestRevisionLatestReleaseFileName: $($AssetFileToFind_ReleaseTitle)]: Matching Asset: $($HighestRevisionMatchingAssetFileName) [v$([string]$MatchingAsset_HighestRevision)]"
				}
			}
		}
		if ($MatchingAsset_HighestRevision -eq [version]"0.0") {
			Write-Debug "[HighestRevisionLatestReleaseFileName: $($AssetFileToFind_uri)]: No matching GitHub assets found in $($AssetFileToFind_ReleaseTitle). Using original Asset FileInfo."
		} else {
			Write-Debug "[HighestRevisionLatestReleaseFileName: $($AssetFileToFind_uri)]: Found Highest Revision of GitHub asset: $($HighestRevisionMatchingAssetFileName) [v$([string]$MatchingAsset_HighestRevision)]"
		}
		$HighestRevisionMatchingAsset_FileInfo.WD()
		return $HighestRevisionMatchingAsset_FileInfo
	}	
	static [int]AddToProjectCollection([hashtable]$Properties) {
		[hashtable]$InputProperties = [GithubRepository]::ParseParameters($Properties)
		[string]$Repository_uri = [string]$InputProperties.uri
		$uri_Present = ( ($Repository_uri -ne '') -and (-not [string]::IsNullOrWhiteSpace($Repository_uri)) )
		if ($uri_Present) {
			# Check to see if it is already in the collection
			$Existing_Index = [GithubRepository]::RepositoryCollectionEntryIndexForURI($Properties)
			$uriAlreadyInCollection = ($Existing_Index -ge 0)
			if ($uriAlreadyInCollection) {
				Write-Debug "[GithubRepository.AddToProjectCollection: $Repository_uri]: Already in collection at [$Existing_Index]"
				return $Existing_Index
			}
			Write-Debug "[GithubRepository.AddToProjectCollection: $Repository_uri]: Not yet in collection. Creating new Repository."
			[GithubRepository]$NewRepository = [GithubRepository]::new($InputProperties)
			if ($null -eq $NewRepository.Release) {
				Write-Warning "[GithubRepository.AddToProjectCollection: $Repository_uri]: Unable to connect and retrieve Repository Release."
			} else {
				Write-Debug "[GithubRepository.AddToProjectCollection: $Repository_uri]: Retrieved: $($NewRepository.Release.name) [$($NewRepository.Release.tag_name)]"
			}
			$count_before = $Global:GithubRepositories.Count
			$Global:GithubRepositories.Add($Repository_uri, $NewRepository)
			$count_after = $Global:GithubRepositories.Count
			$successfullyAdded = ($count_before -ne $count_after)
			if (-not $successfullyAdded) {
				Write-Debug "[GithubRepository.AddToProjectCollection: $Repository_uri]: Entry not added."
				return -2 #Entry not added
			}
			$index = $count_after - 1
			Write-Debug "[GithubRepository.AddToProjectCollection: $Repository_uri]: Validating collection entry [$($index)]"
			$ItMatches = ([string]$Global:GithubRepositories[$index].uri -eq $Repository_uri)
			if ($ItMatches) {
				Write-Debug "[GithubRepository.AddToProjectCollection: $Repository_uri]: Validated collection entry."
				return $index
			} else {
				Write-Debug "[GithubRepository.AddToProjectCollection: $Repository_uri]: Could not validate collection entry."
				return -3 #Could not Validate Entry
			}
		} else {
			Write-Warning "[GithubRepository.AddToProjectCollection]: Malformed uri input: $Repository_uri"
			return -1 #URI Not Present during addition
		}
	}
	static [GithubRepository]WithinCollection([hashtable]$Properties) {
		[hashtable]$InputProperties = [GithubRepository]::ParseParameters($Properties)
		[string]$Repository_uri = [string]$InputProperties.uri
		$uri_Present = ( ($Repository_uri -ne '') -and (-not [string]::IsNullOrWhiteSpace($Repository_uri)) )
		if ($uri_Present) {
			# Check to see if it is already in the collection
			$Existing_Index = [GithubRepository]::RepositoryCollectionEntryIndexForURI($Properties)
			$uriAlreadyInCollection = ($Existing_Index -ge 0)
			$uriValidButNotInCollection = ($Existing_Index -eq -5)
			$uriInvalidOrBadRepository = ( ($Existing_Index -lt 0) -and ($Existing_Index -ne -5) )
			if ($uriAlreadyInCollection) {
				Write-Debug "[GithubRepository.WithinCollection: $Repository_uri]: Returning Repository object from within Collection[$Existing_Index]"
				return $Global:GithubRepositories[$Existing_Index]
			} elseif ($uriInvalidOrBadRepository) {
				return $null
			} elseif ($uriValidButNotInCollection) {
				Write-Debug "[GithubRepository.WithinCollection: $Repository_uri]: Not yet in collection. Creating new Repository."
				$New_Index = [GithubRepository]::AddToProjectCollection($InputProperties)
				if ($New_Index -ge 0) {
					return $Global:GithubRepositories[$New_Index]
				} else {
					Write-Warning "[GithubRepository.WithinCollection: $Repository_uri]: Error creating new Repository. Returning null"
					return $null
				}
			}
		} else {
			Write-Warning "[GithubRepository.WithinCollection: $Repository_uri]: Malformed uri"
			return $null
		}
		return $null		

	}
	# Get Hashtable
	[hashtable]Hashtable() {
		Write-Debug "[ [GithubRepository]::Hashtable() ]"
		return @{
					Owner = $($this.Owner)
					Repo = $($this.Repo)
					uri = $($this.uri)
					Token = $($this.Token)
		}
	}
	# Print Debug
	[void]WD() {
		Write-Debug "[ [GithubRepository]::WD() ]"
		Write-Debug "[GithubRepository.WD]: Info for: $($this.uri)"
		Write-Debug "	Owner = $($this.Owner)"
		Write-Debug "	Repo = $($this.Repo)"
		Write-Debug "	uri = $($this.uri)"
		Write-Debug "	Token = $($this.Token)"
		if ($null -eq $this.Release) {
			Write-Debug "	Release = null"	
		} else {
			Write-Debug "	Release = not null"	
			Write-Debug "	Release.name = $($this.Release.name)"
			Write-Debug "	Release.tag_name = $($this.Release.tag_name)"
		}
	}
	# Fetch Release from GitHub
	[void] FetchRelease() {
		Write-Debug "[ [GithubRepository]::FetchRelease() ]"
		$this.Release = GitHub_REST_API_GET_LatestRelease -Owner $this.Owner -Repo $this.Repo -Token $this.Token
		if ($null -eq $this.Release) {
			Write-Debug "[GithubRepository.FetchRelease: $($this.uri)]: ERROR: Release unavailable"
		} else { Write-Debug "[GithubRepository.FetchRelease: $($this.uri)]: Success" }
	}
	# Shared Initializer Method
	[void] Init( [hashtable]$InputParameters ) {
		Write-Debug "[ [GithubRepository]::[void]Init( [hashtable]InputParameters ) ]"
		#$InputParameters = [GithubRepository]::ParseParameters($Properties)
		Write-Debug "[GithubRepository::new]: Initializing [$($InputParameters.Owner)/$($InputParameters.Repo)]"
		$this.Owner	= $InputParameters.Owner
        $this.Repo	= $InputParameters.Repo
		$this.uri = $InputParameters.uri
		$this.Token	= $InputParameters.Token
		#Attempt to go out to the internet and get the release information
		if (-not [string]::IsNullOrWhiteSpace($this.uri)) {
			$this.FetchRelease()
		} else {
			Write-Warning "[GithubRepository::new]: Creation incomplete for [$($InputParameters.Owner)/$($InputParameters.Repo)]"
		}
		$this.WD()
	}
	# Default Constructors
	GithubRepository() {
		Write-Debug "[ [GithubRepository]::new() ]"
		$this.Init( @{	Owner = 'jeremytiggy'
						Repo	= 'Powershell-ProjectBootstrap'
						uri = 'jeremytiggy/Powershell-ProjectBootstrap'
						Token	= '' } )

	}
	GithubRepository( [string]$uri ) {
		Write-Debug "[ [GithubRepository]::new([string]uri) ]"
		$this.Init( @{	Owner = ''
						Repo	= ''
						uri = $uri
						Token	= '' } )
	}
	GithubRepository( [string]$Owner, [string]$Repo ) {
		Write-Debug "[ [GithubRepository]::new([string]Owner, [string]Repo) ]"
		$this.Init( @{	Owner = $Owner
						Repo	= $Repo
						uri = ''
						Token	= '' } )
	}
	GithubRepository( [string]$Owner, [string]$Repo, [string]$Token ) {
		Write-Debug "[ [GithubRepository]::new([string]Owner, [string]Repo ,[string]Token) ]"
		$this.Init( @{	Owner = $Owner
						Repo	= $Repo
						uri = ''
						Token	= $Token } )
	}
	GithubRepository( [hashtable]$Properties ) {
		Write-Debug "[ [GithubRepository]::new([hashtable]Properties) ]"
		$this.Init([GithubRepository]::ParseParameters($Properties))
	}
	
}
Class ManifestFileEntry_Asset {
	# This object class is designed to have all the fields that are contained in a manifest file entry
	# Properties
	[string]$AssetName
	[string]$Owner
	[string]$Repo
	[string]$Token
	[string]$InstallPath
	[string]$InstalledVersionReferenceAsset
	[string]$ReferencePath
	# Constructor
	ManifestFileEntry_Asset([hashtable]$Properties) {
		Write-Debug "[ [ManifestFileEntry_Asset]::new([hashtable]Properties) ]"
		$this.Init($Properties)
	}
	# Shared initializer method
	[void] Init([hashtable]$Properties) {
		Write-Debug "[ [ManifestFileEntry_Asset]::[void]Init([hashtable]Properties) ]"
		foreach ($Property in $this.GetType().GetProperties()) {
			if ($Properties.ContainsKey($Property.Name)) {
				$this.($Property.Name) = $Properties[$Property.Name]
			}
		}
	}
		
	# Hashtable Value
	[hashtable]Hashtable() {
		Write-Debug "[ [ManifestFileEntry_Asset]::[hashtable]Hashtable() ]"
		return @{
					AssetName = $($this.AssetName)
					Owner = $($this.Owner)
					Repo = $($this.Repo)
					Token = $($this.Token)
					InstallPath = $($this.InstallPath)
					InstalledVersionReferenceAsset = $($this.InstalledVersionReferenceAsset)
					ReferencePath = $($this.ReferencePath)
				}
	}
	# Print Value
	[void]WD() {
		Write-Debug "[ [ManifestFileEntry_Asset]::[void]WD() ]"
		#Debug Output
		Write-Debug "[ManifestFileEntry_Asset.WD]: Info for: $($this.AssetName)"
		Write-Debug "	AssetName = $($this.AssetName)"
		Write-Debug "	Owner = $($this.Owner)"
		Write-Debug "	Repo = $($this.Repo)"
		Write-Debug "	Token = $($this.Token)"
		Write-Debug "	InstallPath = $($this.InstallPath)"
		Write-Debug "	InstalledVersionReferenceAsset = $($this.InstalledVersionReferenceAsset)"
		Write-Debug "	ReferencePath = $($this.ReferencePath)"
	}
	
}
Class LocalInstance {
	# This object class is designed to be a locator for a file on this computer that was installed here from a Github Repository by way of a bootstrapped manifest
	[boolean]$NotInstalled
	[boolean]$Installed
	[version]$InstalledVersion
	[boolean]$UpToDate
	[boolean]$Updated
	[FileInfo]$DownloadedFileInfo
	[boolean]$archiveExtractedOK
	[FileInfo]$FileInfo
	
	[void]Init([hashtable]$Properties) {
		Write-Debug "[ [LocalInstance]::[void]Init([hashtable]Properties) ]"
		# if (-not [string]::IsNullOrWhiteSpace($Properties.InstalledVersionReferenceAsset)) {
		#	
		# 	$this.FileInfo = HighestRevisionLocalInstanceFileName -LocalFileName $Properties.InstalledVersionReferenceAsset -LocalInstancesPath $Properties.ReferencePath
		# } else {
		# 	$this.FileInfo = HighestRevisionLocalInstanceFileName -LocalFileName $Properties.AssetName -LocalInstancesPath $Properties.InstallPath
		# }
		$this.FileInfo = [FileInfo]::HighestRevisionLocalInstanceFileName($Properties)
		$this.NotInstalled = $this.FileInfo.NotFoundLocally
		$this.Installed = $this.FileInfo.FoundLocally
		$this.InstalledVersion = [version]$this.FileInfo.Revision
	}
	# Common Constructor
	LocalInstance([hashtable]$Properties) {
		Write-Debug "[ [LocalInstance]::new([hashtable]Properties) ]"
		$this.Init($Properties)
	}

	# Print Value
	[void]WD() {
		Write-Debug "[ [LocalInstance]::[void]WD() ]"
		#Debug Output
		Write-Debug "[LocalInstance.WD]: Info for: $($this.FileInfo.FileName)"
		Write-Debug "	NotInstalled = $($this.NotInstalled)"
		Write-Debug "	Installed = $($this.Installed)"
		Write-Debug "	InstalledVersion = $($this.InstalledVersion)"
		Write-Debug "	UpToDate = $($this.UpToDate)"
		Write-Debug "	Updated = $($this.Updated)"
		Write-Debug "	archiveExtractedOK = $($this.archiveExtractedOK)"
		$this.DownloadedFileInfo.WD()
		$this.FileInfo.WD()
	}
}
Class LatestRelease {
	# This object class is designed to hold the file information relative to the source location within a github release
	[FileInfo]$FileInfo
	[boolean]$NotFoundRemotely
	[boolean]$FoundRemotely
	[version]$ReleaseVersion
	[boolean]$UpdateAvailable
	
	LatestRelease([hashtable]$Properties) {
		Write-Debug "[ [LatestRelease]::new([hashtable]Properties) ]"
		$this.Init($Properties)
	}
	[void]Init([hashtable]$Properties) {
		Write-Debug "[ [LatestRelease]::[void]Init([hashtable]Properties) ]"
		Write-Debug "[LatestRelease.Init]: Getting Latest Release of Github Repository Asset"
		[hashtable]$LatestRelease_Properties = @{}
		foreach ($Property in @($Properties.Keys)) {
			$LatestRelease_Properties[$Property] = $Properties[$Property]
		}
		$LatestRelease_Properties.Remove('InstalledVersionReferenceAsset')
		$LatestRelease_Properties.Remove('ReferencePath')		
		
		$this.FileInfo = [GithubRepository]::HighestRevisionLatestReleaseFileName($LatestRelease_Properties)
		$this.NotFoundRemotely = [boolean]$this.FileInfo.NotFoundRemotely
		$this.FoundRemotely = [boolean]$this.FileInfo.FoundRemotely
		$this.ReleaseVersion = [version]$this.FileInfo.Revision
	}
}
Class InstalledManifestAsset {
	# This object class is a representation of all the information necessary to keep an item listed in a manifest up-to-date and installed in the proper location
	[ManifestFileEntry_Asset]$ManifestEntry
	[LocalInstance]$LocalInstance
	[LatestRelease]$LatestRelease
	[GithubRepository]$GithubRepository
	
	InstalledManifestAsset([hashtable]$Properties) {
		Write-Debug "[ [InstalledManifestAsset]::new([hashtable]Properties) ]"
		$this.Init($Properties)
	}
	[void]Init([hashtable]$Properties) {
		Write-Debug "[ [InstalledManifestAsset]::[void]Init([hashtable]Properties) ]"
		Write-Debug "[InstalledManifestAsset.Init]: Initializing this.ManifestEntry"
		$this.ManifestEntry = [ManifestFileEntry_Asset]::new($Properties)
		$this.ManifestEntry.WD()
		Write-Debug "[InstalledManifestAsset.Init]: Initializing this.GithubRepository"
		$this.GithubRepository = [GithubRepository]::WithinCollection($this.ManifestEntry.Hashtable())
		Write-Debug "[InstalledManifestAsset.Init]: Initializing this.LocalInstance"
		$this.LocalInstance = [LocalInstance]::new($Properties)
		Write-Debug "[InstalledManifestAsset.Init]: Initializing this.LatestRelease"
		$this.LatestRelease = [LatestRelease]::new($Properties)
		Write-Debug "[InstalledManifestAsset.Init]: Checking if this.LatestRelease has an Update Available"
		$this.LatestRelease.UpdateAvailable = (($this.LatestRelease.ReleaseVersion -gt $this.LocalInstance.InstalledVersion) -and $this.LatestRelease.FoundRemotely)
		$this.LocalInstance.UpToDate = (($this.LocalInstance.InstalledVersion -ge $this.LatestRelease.ReleaseVersion) -and $this.LatestRelease.FoundRemotely)
		Write-Debug "[InstalledManifestAsset::Init($($this.ManifestEntry.AssetName))]: Local: $($this.LocalInstance.InstalledVersion), Release: $($this.LatestRelease.ReleaseVersion), Update Available: $($this.LatestRelease.UpdateAvailable), UpToDate: $($this.LocalInstance.UpToDate)"	
	}
	[void]ReplaceLocalInstanceWithLatestRelease() {
		Write-Debug "[ [InstalledManifestAsset]::[void]ReplaceLocalInstanceWithLatestRelease() ]"
		$this.LatestRelease.UpdateAvailable = (($this.LatestRelease.ReleaseVersion -gt $this.LocalInstance.InstalledVersion) -and $this.LatestRelease.FoundRemotely)
		if (-not $this.LatestRelease.UpdateAvailable) {
			Write-Debug "[InstalledManifestAsset.InstallUpdate: $($this.ManifestEntry.AssetName)]: No Update available"
		}
		if ($this.LatestRelease.UpdateAvailable) {
			Write-Debug "[InstalledManifestAsset.InstallUpdate: $($this.ManifestEntry.AssetName)]: Update Available. Downloading."
			$this.LocalInstance.DownloadedFileInfo = $this.LatestRelease.FileInfo.DownloadToNewLocalInstanceFile()
			[FileInfo]$DownloadedFileInfo = $this.LocalInstance.DownloadedFileInfo
			Write-Debug "[InstalledManifestAsset.InstallUpdate: $($this.ManifestEntry.AssetName)]: Downloaded: $([string]$this.LocalInstance.DownloadedFileInfo.FileName)"
			if ($this.LocalInstance.DownloadedFileInfo.FileName -eq 'FileNotFound') {
				Write-Warning "[InstalledManifestAsset.InstallUpdate: $($this.ManifestEntry.AssetName)]:  Unable to download update"
			}
			if ($this.LocalInstance.DownloadedFileInfo.FileExtension -eq 'zip') {
				Write-Debug "[InstalledManifestAsset.InstallUpdate: $($this.ManifestEntry.AssetName)]: Downloaded asset is a ZIP archive"
				Write-Debug "[InstalledManifestAsset.InstallUpdate: $($this.ManifestEntry.AssetName)]: Extracting to [$($this.ManifestEntry.InstallPath)]"
				# Extract Archive
				try {
					# Note: if a subfolder exists and has data in it, it won't clear the folder first
					Expand-Archive -LiteralPath $this.LocalInstance.DownloadedFileInfo.FullPath -DestinationPath $this.ManifestEntry.InstallPath -Force -ErrorAction Stop
					Write-Debug "[InstalledManifestAsset.InstallUpdate: $($this.ManifestEntry.AssetName)]: ZIP archive extracted successfully"
					$this.LocalInstance.archiveExtractedOK = $true
				}
				catch {
					Write-Warning "[InstalledManifestAsset.InstallUpdate: $($this.ManifestEntry.AssetName)]: Unable to extract ZIP archive [$($this.LocalInstance.DownloadedFileInfo.FullPath)]: $_"
					$this.LocalInstance.archiveExtractedOK = $false
				}
				# Delete Archive
				if ($this.LocalInstance.archiveExtractedOK) {
					try {
						Remove-Item -Path $this.LocalInstance.DownloadedFileInfo.FullPath -Force -ErrorAction Stop
						Write-Debug "[InstalledManifestAsset.InstallUpdate: $($this.ManifestEntry.AssetName)]: Removed ZIP archive [$($this.LocalInstance.DownloadedFileInfo.FullPath)]"
					}
					catch {
						Write-Warning "[InstalledManifestAsset.InstallUpdate: $($this.ManifestEntry.AssetName)]: Unable to remove ZIP archive [$($this.LocalInstance.DownloadedFileInfo.FullPath)]: $_"
					}
				}
			}
			# Validate that the upgrade worked
			$this.LocalInstance = [LocalInstance]::new($this.ManifestEntry.Hashtable())
			$this.LocalInstance.DownloadedFileInfo = $DownloadedFileInfo
			Write-Debug "[InstalledManifestAsset.InstallUpdate: $($this.ManifestEntry.AssetName)]: Downloaded Revision: $([string]($this.LocalInstance.DownloadedFileInfo.Revision)), Local Revision: $([string]([version]$this.LocalInstance.FileInfo.Revision))"
			if ([version]$this.LocalInstance.FileInfo.Revision -ge [version]$this.LocalInstance.DownloadedFileInfo.Revision) {
				Write-Verbose "[InstalledManifestAsset.InstallUpdate: $($this.ManifestEntry.AssetName)]: Updated to $([string]([version]$this.LocalInstance.FileInfo.Revision)) OK"
				$this.LocalInstance.Updated = $true
			} else {
				Write-Warning "[InstalledManifestAsset.InstallUpdate: $($this.ManifestEntry.AssetName)]: Update to v$([string]([version]$this.LocalInstance.DownloadedFileInfo.Revision)) FAILED. Current Local Revision: $([string]([version]$this.LocalInstance.FileInfo.Revision))"
				$this.LocalInstance.Updated = $false
			}
		}
	}
	static [InstalledManifestAsset]InstallLatestRelease([hashtable]$Properties) {
		Write-Debug "[ function InstallLatestRelease ]"
		[InstalledManifestAsset]$Asset = [InstalledManifestAsset]::new([hashtable]$Properties)
		if ($null -eq $Asset) {
			Write-Warning "[InstalledManifestAsset.InstallLatestRelease]: Asset is null, unable to update."
			return $null
		}
		Write-Debug "[InstallLatestRelease: $($Asset.ManifestEntry.AssetName)]: Update Available: $($Asset.LatestRelease.UpdateAvailable)"
		if ($Asset.LatestRelease.UpdateAvailable) { $Asset.ReplaceLocalInstanceWithLatestRelease() }
		$AssetLocalInstanceStillExistsAfterUpdate = ( ($null -ne $Asset.LocalInstance.FileInfo) -and ($Asset.LocalInstance.FileInfo.FileName -ne 'FileNotFound') )
		if (-not $AssetLocalInstanceStillExistsAfterUpdate) {
			Write-Verbose "[InstallLatestRelease: $($Asset.ManifestEntry.AssetName)]: Installed: NO. Up-to-Date: N/A"
			return $Asset
		}
		$InstalledButUnableToCheckOnline = $Asset.LocalInstance.Installed -and $Asset.LatestRelease.NotFoundRemotely		
		$InstalledAndAbleToCheckOnline = $Asset.LocalInstance.Installed -and $Asset.LatestRelease.FoundRemotely
		$AssetLocalInstanceUpToDate = $Asset.LocalInstance.Updated -or $Asset.LocalInstance.UpToDate
		$InstalledButNotUpToDate = $InstalledAndAbleToCheckOnline -and (-not $AssetLocalInstanceUpToDate)
		$InstalledAndUpToDate = $InstalledAndAbleToCheckOnline -and $AssetLocalInstanceUpToDate
		
		if ($InstalledButUnableToCheckOnline) {
			Write-Verbose "[InstallLatestRelease: $($Asset.ManifestEntry.AssetName)]: Installed: OK. Up-To-Date: OFFLINE"
			return $Asset
		}
		if ($InstalledButNotUpToDate) {
			Write-Verbose "[InstallLatestRelease: $($Asset.ManifestEntry.AssetName)]: Installed: OK. Up-To-Date: NO"
			return $Asset
		}
		if ($InstalledAndUpToDate) {
			$NotPurgedAccidentally = -not $Global:PurgeOldVersions
			if ($Global:PurgeOldVersions) {
				Write-Debug "[InstallLatestRelease: $($Asset.ManifestEntry.AssetName)]: Purging Out-Of-Date Local Instances"
				$PurgeResult = [FileInfo]::DeleteLowerRevisionLocalInstances($Asset.LocalInstance.FileInfo.Hashtable())
				if ($null -ne $PurgeResult) {
					$NotPurgedAccidentally = $PurgeResult.FileName -ne "FileNotFound"
				}
			}
			if ($NotPurgedAccidentally) {
				Write-Verbose "[InstallLatestRelease: $($Asset.ManifestEntry.AssetName)]: Installed: OK. Up-To-Date: OK"
			} else {
				Write-Verbose "[InstallLatestRelease: $($Asset.ManifestEntry.AssetName)]: Installed: ACCIDENTALLY PURGED. Up-To-Date: N/A"
			}
			return $Asset
		}
		return $Asset
	}
}

# Custom Class related variables
# Constant: File Not Found
$Global:FileNotFound_FileInfo = [FileInfo]::new() 
# FileInfo object of running Bootstrapper script
$RunningBootstrapperLocalFileInfo =  [FileInfo]::new(@{FileName=$PSCommandPath})
# Ordered Dictionary collection of all referenced Github Repositories
$Global:GithubRepositories = [System.Collections.Specialized.OrderedDictionary]::new()
# Github Repository Info for Bootstrapper
[hashtable]$Bootstrap_RepositoryInfo = @{
	Owner = 'jeremytiggy'
	Repo = 'Powershell-ProjectBootstrap'
	Token = ''
	uri = 'jeremytiggy/Powershell-ProjectBootstrap'
}
# Adding Bootstrapper repo information to main collection
$Bootstrap_Repository = [GithubRepository]::WithinCollection($Bootstrap_RepositoryInfo)

# Program Functions
function MakeArgumentListFile([hashtable]$Properties) {
	# Outputs a proper "-File "C:\path\filename.ps1"" string for the finnicky Start-Process function
	$UsableProperties = @{
			FileName = $null
			FilePath = $null
	}
	foreach ($Property in @($UsableProperties.Keys)) {
		if ($Properties.ContainsKey($Property)) {
			$UsableProperties[$Property] = $Properties[$Property]
		}
	}
	#FileName	
	[string]$Properties_FileName = [string]($UsableProperties.FileName)
	Write-Debug "[MakeArgumentListFile]: Properties_FileName: $($Properties_FileName)"
	$InputFileNameIsntGoingToWork = [string]::IsNullOrWhitespace($Properties_FileName)
	if ($InputFileNameIsntGoingToWork) {
		$InputFileName = $PSCommandPath
	} else {
		$InputFileName = $Properties_FileName
	}
	Write-Debug "[MakeArgumentListFile]: InputFileName: $($InputFileName)"
	$FileName = [string]( [System.IO.Path]::GetFileName($InputFileName) )
	Write-Debug "[MakeArgumentListFile]: FileName: $($FileName)"
	
	#FilePath	
	[string]$Properties_FilePath = [string]($UsableProperties.FilePath)
	Write-Debug "[MakeArgumentListFile]: Properties_FilePath: $($Properties_FilePath)"
	$InputFilePathIsntGoingToWork = [string]::IsNullOrWhitespace($Properties_FilePath)
	if ($InputFilePathIsntGoingToWork) {
		#check file first
		$InputFileNamePath = [System.IO.Path]::GetDirectoryName($InputFileName)
		$InputFileNameMightWork = (-not [string]::IsNullOrWhitespace($InputFileNamePath) )
		if ($InputFileNameMightWork) {
			$InputFilePath = $InputFileNamePath
		} else {
			$InputFilePath = [System.IO.Path]::GetDirectoryName($PSCommandPath)
		}
	} else {
		$InputFilePath = $Properties_FilePath
	}
	Write-Debug "[MakeArgumentListFile]: InputFilePath: $($InputFilePath)"
	
	$FileName = [string]( [System.IO.Path]::GetFileName($InputFileName) )
	Write-Debug "[MakeArgumentListFile]: FileName: $($FileName)"	
	$FilePath = $InputFilePath
	Write-Debug "[MakeArgumentListFile]: FilePath: $($FilePath)"	
	$FileFullPath = Join-Path -Path $FilePath -ChildPath $FileName
	Write-Debug "[MakeArgumentListFile]: FullFilePath: $FullFilePath"
	
	$ArgumentListString_File = "-File `"$FileFullPath`""
	Write-Debug "[MakeArgumentListFile]: ArgumentListString_File: $ArgumentListString_File"
	return $ArgumentListString_File
}
function PrintAssetStatus([InstalledManifestAsset]$Asset) {	
	Write-Host -NoNewLine "[Powershell-ProjectBootstrap]: " -ForegroundColor White
	if ($null -eq $Asset) {
		Write-Host -NoNewLine "NULL ASSET" -ForegroundColor Red
	} else {
		Write-Host -NoNewLine "$($Asset.ManifestEntry.AssetName): "
		[bool]$Installed = $false
		if ($null -ne $Asset.LocalInstance.FileInfo) {
			if ($Asset.LocalInstance.FileInfo.FileName -ne "FileNotFound") {
				$Installed = $true 
			}
		}
		if (-not $Installed) {
			Write-Host "ERROR" -ForegroundColor Red
		} else {
			# Installed version
			[version]$LocalInstanceRevision = [version]$Asset.LocalInstance.FileInfo.Revision
			[string]$LocalInstanceRevisionString = [string]($LocalInstanceRevision)
			[string]$InstalledRevision = "v$($Asset.LocalInstance.FileInfo.Revision)"
			if ($Asset.LatestRelease.NotFoundRemotely) {
				Write-Host "$InstalledRevision (Offline)" -ForegroundColor White
			} elseif ($Asset.LocalInstance.Updated -or $Asset.LocalInstance.UpToDate) {
				Write-Host "$InstalledRevision (Up-to-date)" -ForegroundColor Green
			} elseif ($Asset.LatestRevision.UpdateAvailable) {
				Write-Host "$InstalledRevision (Update Available)" -ForegroundColor Yellow
			} else {
				Write-Host "$InstalledRevision (Out-of-date)" -ForegroundColor Red
			}
		}
	}
}
# Program Subroutines
function Restart-Bootstrapper([string]$FileFullPath) {
	Write-Debug "[Restart-Bootstrapper]: File Full Path: $($FileFullPath)"
	Write-Host "[Restart-Bootstrapper]: The program is restarting in order to load the most up-to-date scripts" -Foreground Yellow
	Write-Host -NoNewLine "[Restart-Bootstrapper]: Restarting the program in 5..."
	Start-Sleep -Seconds 1
	Write-Host -NoNewLine "4..."
	Start-Sleep -Seconds 1
	Write-Host -NoNewLine "3..."
	Start-Sleep -Seconds 1
	Write-Host -NoNewLine "2..."
	Start-Sleep -Seconds 1
	Write-Host -NoNewLine "1..."
	Start-Sleep -Seconds 1
	Write-Host "0"

	[hashtable]$ArgumentList_FileFullPath = [hashtable](@{ FileName = $FileFullPath })
	$ArgumentList_File = MakeArgumentListFile($ArgumentList_FileFullPath)
	Write-Debug "[$ThisScriptFileName]: ArgumentList_File: $ArgumentList_File"
	
	[string]$BootstrapperArguments_RestartingFromSelfUpdate = " -RestartingFromSelfUpdate"
	$BootstrapperArgumentsToPass += $BootstrapperArguments_RestartingFromSelfUpdate
	
	[string]$ArgumentListString = $ArgumentList_File
	$ArgumentListString += $BootstrapperArguments
	Write-Debug "[$ThisScriptFileName]: ArgumentListString: $ArgumentListString"
	Write-Debug "[$ThisScriptFileName]: Start-Process powershell -ArgumentList $ArgumentListString"	
	Start-Process powershell -ArgumentList $ArgumentListString

	Write-Debug "[$ThisScriptFileName]: New Bootstrapper instance started."
	Write-Debug "[$ThisScriptFileName]: Exiting current Bootstrapper instance."
	Write-Host "[Restart-Bootstrapper]: You may close this window."
	Start-Sleep -Seconds 8
	exit 0
}
function Update-Bootstrapper {
	Write-Debug "[ function Update-Bootstrapper ]"
	Write-Debug "[Update-Bootstrapper]: Script Full Path: $($PSCommandPath)"
	# $BootstrapperLocalFileInfo = New-FileInfo_FileName -FileName $PSCommandPath
	[string]$Bootstrapper_AssetName = $RunningBootstrapperLocalFileInfo.AssetName
	[hashtable]$Bootstrapper_InstalledAssetInfo = @{ AssetName = $Bootstrapper_AssetName }
	$Bootstrapper_InstalledAssetInfo += $Bootstrap_RepositoryInfo
	[string]$Bootstrapper_InstallPath = [System.IO.Path]::GetDirectoryName($PSCommandPath) + '\'
	[hashtable]$Bootstrapper_InstallationInfo = @{
													InstallPath = $Bootstrapper_InstallPath
													InstalledVersionReferenceAsset = $PSCommandPath
													ReferencePath = $Bootstrapper_InstallPath
												}
	$Bootstrapper_InstalledAssetInfo += $Bootstrapper_InstallationInfo
	$Global:Bootstrapper_Asset = [InstalledManifestAsset]::InstallLatestRelease($Bootstrapper_InstalledAssetInfo)
	PrintAssetStatus($Global:Bootstrapper_Asset)
	
	$Global:Bootstrapper_Asset.LocalInstance.FileInfo.WD()
	$Global:Bootstrapper_Asset.LatestRelease.FileInfo.WD()

	if ($Global:Bootstrapper_Asset.LocalInstance.Updated) {
		$UpdatedBootstrapperFullPath = $Global:Bootstrapper_Asset.LocalInstance.FileInfo.FullPath
		Write-Debug "[Update-Bootstrapper]: Bootstrapper updated successfully."
		Write-Debug "[Update-Bootstrapper]: New Bootstrapper: $UpdatedBootstrapperFullPath"
		return $UpdatedBootstrapperFullPath
	}

	return $null
	
}

function Bootstrapper_Self-Update {
	Write-Debug "[PowerShell-ProjectBootstrap]: Initialized. Beginning Self-Update."
	# The first priority is to make sure that the Bootstrapper script itself is the most up-to-date vertsion of itself, both locally and remotely.
	# If a higher version of the file is present in the same directory, the program will close itself and launch a new Powershell instance running the higher revision script.
	# Once it has been determined that the highest local version is running, we need to determine if the Github repo has a newer release available for download.
	# If a newer release has been downloaded, the program will close itself and launch a new Powershell instance running the higher revision script.
	# Only when the version is confirmed to be the highest revision will the program begin to look at the manifest file.
	# The user can bypass the update procedure using the -UserBypassSelfUpdate command line switch.
	$RestartBootstapperScript = $false
	$BypassUpdate = $false

	# Check if we are running the highest revision local script
	Write-Debug "[Bootstrapper_Self-Update]: Searching for highest local revision of bootstrapper to make sure we are running it already"
	[FileInfo]$HighestRevisionBootsrapperFileInfo = [FileInfo]::HighestRevisionLocalInstanceFileName(@{FileName=$([string]$PSCommandPath)})
	Write-Debug "[Bootstrapper_Self-Update]: Highest Local Revision of Bootstrapper: $([string]$HighestRevisionBootsrapperFileInfo.Revision)"
	Write-Debug "[Bootstrapper_Self-Update]: Running Revision of Bootstrapper: $([string]$RunningBootstrapperLocalFileInfo.Revision)"
	[boolean]$RunningHighestRevisionBootsrapper = [version]$RunningBootstrapperLocalFileInfo.Revision -eq [version]$HighestRevisionBootsrapperFileInfo.Revision
	Write-Debug "[Bootstrapper_Self-Update]: Running Highest Revision of Bootstrapper: $([string]$RunningHighestRevisionBootsrapper)"
	if (-not $RunningHighestRevisionBootsrapper) {
		[string]$HighestRevisionBootsrapper_FullFilePath = [string]$HighestRevisionBootsrapperFileInfo.FullPath
		Write-Debug "[Bootstrapper_Self-Update]: Not newest revision. Relaunching with different script: $($HighestRevisionBootsrapper_FullFilePath)"
		Restart-Bootstrapper($HighestRevisionBootsrapper_FullFilePath)
	}
	Write-Host -NoNewLine "[Powershell=ProjectBootstrap]: $($RunningBootstrapperLocalFileInfo.AssetName): " -ForegroundColor White
	Write-Host "v$($RunningBootstrapperLocalFileInfo.Revision) (Updating)" -ForegroundColor Yellow

	$BypassUpdate = $BypassUpdate -or $JustRestartedFromSelfUpdate

	# The Self-Update Process is also bypassed if the user sends the -UserBypassSelfUpdate key at commandline.
	if ($UserRequestsBypassOfUpdate) { Write-Debug "[Bootstrapper_Self-Update]: User is bypassing Self-Update from command line parameter" }
	$BypassUpdate = $BypassUpdate -or $UserRequestsBypassOfUpdate

	if ($BypassUpdate) { 
		Write-Verbose "[Bootstrapper_Self-Update]: Bootstrapper Self-Update has been bypassed" 
	} else {
		# Ensure the Bootstrapper is up to date
		Write-Verbose "[Bootstrapper_Self-Update]: Bootstrapper is checking for updates to itself."
		[string]$UpdatedBootstrapper_FullPath = Update-Bootstrapper
		Write-Debug "[Bootstrapper_Self-Update]: Bootstrapper Update File: $UpdatedBootstrapper_FullPath"
		$BootstrapperLocalInstanceUpdated = $Global:Bootstrapper_Asset.LocalInstance.Updated
		$BootstrapperLocalInstanceValid = -not [string]::IsNullOrEmpty($UpdatedBootstrapper_FullPath)
		$BootstrapperLocalInstanceUpdateValid = $BootstrapperLocalInstanceUpdated -and $BootstrapperLocalInstanceValid
		if ($BootstrapperLocalInstanceUpdateValid) {
			Write-Verbose "[Bootstrapper_Self-Update]: Bootstrapper script file Updated. New File: $UpdatedBootstrapper_FullPath"
			Restart-Bootstrapper($UpdatedBootstrapper_FullPath)
		}
	}

	Write-Debug "[Bootstrapper_Self-Update]: Update Check completed."

	$Bootstrapper_ConfirmedUpToDate = $Global:Bootstrapper_Asset.LatestRelease.FoundRemotely -and $Global:Bootstrapper_Asset.LocalInstance.UpToDate
	
	# Purge Out of date file Versions 
	$Bootstrapper_PurgeOldVersions = ( ($Bootstrapper_ConfirmedUpToDate -or $JustRestartedFromSelfUpdate) -and $Global:PurgeOldVersions)
	if ($Bootstrapper_PurgeOldVersions) {
		Write-Verbose "[Bootstrapper_Self-Update]: Purging older revisions of Asset: $([string]($Global:Bootstrapper_Asset.LocalInstance.FileInfo.AssetName))"
		[hashtable]$SurvivorFileInfo = [hashtable]($Global:Bootstrapper_Asset.LocalInstance.FileInfo.Hashtable())
		$PurgeSurvivorFileInfo = [FileInfo]::DeleteLowerRevisionLocalInstances($SurvivorFileInfo)
	}
}


Write-Verbose "[$ThisScriptFileName]: Initializations completed."


# Main Body
Bootstrapper_Self-Update

#Start-Sleep -Seconds 10
#exit 1

# Manifest Bootstrapper
# This is an example Manifest file that also serves as the Self-Update agent
Write-Debug "[PowerShell-ProjectBootstrap]: Declare: ExampleManifest = @{}"
$ExampleManifest = @{
    Schema = @{
		Version = '2.4'
	}
	Manifest = @{
        AssetName = 'Powershell-ProjectBootstrap_Manifest.psd1'
        Owner	= 'jeremytiggy'
        Repo	= 'Powershell-ProjectBootstrap'
		Token	= ''
    }

    AutoRun = @{
        AssetName = 'Powershell-ProjectBootstrap_MainScript.ps1'
    }

    Assets = @(
		@{
            AssetName  = 'Powershell-ProjectBootstrap_MainScript.ps1'
            Owner     = 'jeremytiggy'
            Repo      = 'Powershell-ProjectBootstrap'
            InstallPath = '.\example'
			InstalledVersionReferenceAsset = ''
        }
		@{
            AssetName  = 'Powershell-ProjectBootstrap.ps1'
            Owner     = 'jeremytiggy'
            Repo      = 'Powershell-ProjectBootstrap'
            InstallPath = '.\example'
			InstalledVersionReferenceAsset = ''
        }
		@{
            AssetName  = 'Powershell-ProjectBootstrap_Archive.zip'
            Owner     = 'jeremytiggy'
            Repo      = 'Powershell-ProjectBootstrap'
            InstallPath = '.\example'
			InstalledVersionReferenceAsset = 'Powershell-ProjectBootstrap_FileWithinArchive.md'
			ReferencePath = '.\example\folderwithinarchive'
			
        }

    )
	
}


# Find the latest locally available version of the manifest.
Write-Debug "[PowerShell-ProjectBootstrap]: HighestRevisionLocalInstanceFileName -LocalFileName $($ManifestFileName) -LocalInstancesPath $($LocalInstancesPath)"
Write-Host -NoNewLine "[Powershell-ProjectBootstrap]: Manifest Data File: " -ForegroundColor White
Write-Host "$($ManifestFileName)" -ForegroundColor Yellow
[string]$Manifest_Path = [string]($RunningBootstrapperLocalFileInfo.FilePath)
$ManifestFileInfo = [FileInfo]::HighestRevisionLocalInstanceFileName(@{ LocalFileName = $ManifestFileName; LocalInstancesPath = $Manifest_Path })
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

$Manifest_AssetData = $ManifestData.Manifest
$Manifest_Asset = [InstalledManifestAsset]::new($Manifest_AssetData)
if ($Manifest_Asset.LatestRelease.UpdateAvailable) {
	$Manifest_Asset.ReplaceLocalInstanceWithLatestRelease()
}
$ManifestFileName = $ManifestData.Manifest.AssetName
$ManifestOwner = $ManifestData.Manifest.Owner
$ManifestRepo = $ManifestData.Manifest.Repo
if ($null -ne $GitHubToken) {
	$ManifestToken = $GitHubToken
} elseif ($null -ne $ManifestData.Manifest.Token) {
	$ManifestToken = $ManifestData.Manifest.Token
} else { $ManifestToken = $null }


# Fetch the highest revision either locally or remotely from GitHub
$ManifestUpdateInfo =	@{
							AssetName = $ManifestFileName
							Owner = $ManifestOwner 
							Repo = $ManifestRepo
							Token = $ManifestToken
							InstallPath = $ManifestFileInfo.FilePath
							InstalledVersionReferenceAsset = $ManifestFileName 
							ReferencePath = $ManifestFileInfo.FilePath						
						}

$ManifestAsset = [InstalledManifestAsset]::InstallLatestRelease($ManifestUpdateInfo)
PrintAssetStatus($ManifestAsset)
if ($Global:PurgeOldVersions -and $ManifestAsset.LocalInstance.UpToDate) {
	$ManifestFileInfo = [FileInfo]::DeleteLowerRevisionLocalInstances($ManifestAsset.LocalInstance.FileInfo.Hashtable())
} else {
	$ManifestFileInfo = $ManifestAsset.LocalInstance.FileInfo	
}

if ([string]($ManifestAsset.LocalInstance.FileInfo.FileName) -eq 'FileNotFound') {
    Write-Error "[PowerShell-ProjectBootstrap]: Unable to obtain Manifest file after update"
    exit 1
}
Write-Verbose "[PowerShell-ProjectBootstrap]: Manifest File: $([string]($ManifestAsset.LocalInstance.FileInfo.FullPath))"


# With the latest manifest now in hand, load it and update the variables
$ManifestData = Import-PowerShellDataFile -Path $ManifestAsset.LocalInstance.FileInfo.FullPath
$ManifestFileName = $ManifestData.Manifest.AssetName
$ManifestOwner = $ManifestData.Manifest.Owner
$ManifestRepo = $ManifestData.Manifest.Repo
$ManifestAutoRunScript = $ManifestData.AutoRun.AssetName
if ($null -ne $GitHubToken) {
	$ManifestToken = $GitHubToken
} elseif ($null -ne $ManifestData.Manifest.Token) {
	$ManifestToken = $ManifestData.Manifest.Token
} else { $ManifestToken = $null }

# AutoRun
# Check if there is a FileName in the AutoRun section.
$AutoRun_FileNameInManifest = $false
$AutoRunFileInfo = $null
if ($null -ne $ManifestData.AutoRun) {
	if ($null -ne $ManifestAutoRunScript) {
		if ('' -ne $ManifestAutoRunScript) {
			$AutoRun_FileNameInManifest = $true
		}
	}
}

# Process Assets
if ($ManifestData.Assets) {
	Write-Host "[PowerShell-ProjectBootstrap]: Updating files listed in Manifest: $($ManifestFileInfo.FileName) v$($ManifestFileInfo.Revision)" -ForegroundColor White
	foreach ($Entry in $ManifestData.Assets) {
		# Get Reference File if present
		if ($null -ne $Entry.InstalledVersionReferenceAsset) { $Asset_InstalledVersionReferenceAsset = $Entry.InstalledVersionReferenceAsset 
		} else { $Asset_InstalledVersionReferenceAsset = $null }
		if ($null -ne $Entry.ReferencePath) { $ReferencePath = $Entry.ReferencePath } else { $ReferencePath = $null }
		    # Use the manifest token when this entry doesn't specify one.
		if ([string]::IsNullOrWhiteSpace([string]$Entry.Token)) {
			$Entry.Token = $ManifestToken
		}
		Write-Debug "[PowerShell-ProjectBootstrap: $($ManifestFileName)]: Processesing Entry: $($Entry.AssetName)"
		Write-Debug "   AssetName: $($Entry.AssetName)"
		Write-Debug "   Owner: $($Entry.Owner)"
		Write-Debug "   Repo: $($Entry.Repo)"
		Write-Debug "   Token: $($Entry.Token)"
        Write-Debug "   InstallPath: $($Entry.InstallPath)"
		Write-Debug "   InstalledVersionReferenceAsset: $($Entry.InstalledVersionReferenceAsset)"
		Write-Debug "   ReferencePath: $($Entry.ReferencePath)"
		
		#$Asset = [InstalledManifestAsset]::new($Entry)
		

		#if ($Asset.LatestRelease.UpdateAvailable) {
		#	$Asset.ReplaceLocalInstanceWithLatestRelease()
		#	if ($Asset.LocalInstance.Updated) {
		#		$AssetFullPath = $Asset.LocalInstance.FileInfo.FullPath
		#		Write-Debug "[PowerShell-ProjectBootstrap: $($Asset.ManifestEntry.AssetName)]: Asset updated successfully."
		#		Write-Debug "[PowerShell-ProjectBootstrap]: New File: $AssetFullPath"
		#	}
		#	
		#}		
		
		$Asset = [InstalledManifestAsset]::InstallLatestRelease($Entry)
		PrintAssetStatus($Asset)
		
		$AssetFileInfo = $Asset.LocalInstance.FileInfo

		if ([string]($Asset.LocalInstance.FileInfo.FileName) -eq 'FileNotFound') {
			Write-Error "[PowerShell-ProjectBootstrap]: Unable to obtain Asset file after update"
			exit 1
		}
		Write-Verbose "[PowerShell-ProjectBootstrap]: Asset File: $([string]($Asset.LocalInstance.FileInfo.FullPath))"
		# Purge older versioned files
		#if ($Global:PurgeOldVersions) {
		#	$PurgeSurvivorFileInfo = [FileInfo]::DeleteLowerRevisionLocalInstances($Asset.LocalInstance.FileInfo.Hashtable())
		#	Write-Debug "[PowerShell-ProjectBootstrap: $($Asset.LocalInstance.FileInfo.AssetName)]: Older versions purged."
		#}
		
		Write-Verbose "[PowerShell-ProjectBootstrap: $($ManifestFileName)]: $($Asset.ManifestEntry.AssetName), v$($Asset.LocalInstance.InstalledVersion) - OK"

		#AutoRun
		if ($AutoRun_FileNameInManifest) {
			if ($ManifestData.AutoRun.AssetName -eq $Asset.ManifestEntry.AssetName) {
				$AutoRunFileInfo = $Asset.LocalInstance.FileInfo
			}
		}
		
	}

}
else {
    Write-Warning "[PowerShell-ProjectBootstrap: $($ManifestFileName)]: Manifest contains no Assets"
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
	if ($null -eq $AutoRunFileInfo) {
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

