@{
    Schema = @{
		Version = '2.2'
        AssetName = 'Powershell-ProjectBootstrap_Manifest.psd1'
        Owner	= 'jeremytiggy'
        Repo	= 'Powershell-ProjectBootstrap'
		Token	= ''		
	}
	
	
	Manifest = @{
        AssetName = 'Powershell-ProjectBootstrap_Manifest.psd1'
        Owner	= 'jeremytiggy'
        Repo	= 'Powershell-ProjectBootstrap'
		Token	= ''
		InstallPath = ''
		InstalledVersionReferenceAsset = ''
		ReferencePath = ''
    }

    AutoRun = @{
        AssetName = 'Powershell-ProjectBootstrap_MainScript.ps1'
    }

    Assets = @(
		@{
            AssetName  = 'Powershell-ProjectBootstrap_MainScript.ps1'
            Owner     = 'jeremytiggy'
            Repo      = 'Powershell-ProjectBootstrap'
			Token = ''
            InstallPath = '.\example'
			InstalledVersionReferenceAsset = ''
			ReferencePath = ''
        }
		@{
            AssetName  = 'Powershell-ProjectBootstrap.ps1'
            Owner     = 'jeremytiggy'
            Repo      = 'Powershell-ProjectBootstrap'
			Token = ''
            InstallPath = '.\example'
			InstalledVersionReferenceAsset = ''
			ReferencePath = ''
        }
		@{
            AssetName  = 'Powershell-ProjectBootstrap_Archive.zip'
            Owner     = 'jeremytiggy'
            Repo      = 'Powershell-ProjectBootstrap'
			Token = ''
            InstallPath = '.\example'
			InstalledVersionReferenceAsset = 'Powershell-ProjectBootstrap_FileWithinArchive.md'
			ReferencePath = '.\example\folderwithinarchive'
        }

    )
	
}
