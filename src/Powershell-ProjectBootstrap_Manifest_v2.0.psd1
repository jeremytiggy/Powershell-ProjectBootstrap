@{
    SchemaVersion = '2.0'
	
	Manifest = @{
        AssetName = 'Powershell-ProjectBootstrap_Manifest.psd1'
        Owner    = 'jeremytiggy'
        Repo     = 'Powershell-ProjectBootstrap'
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
			InstalledVersionReferenceAsset = 'Powershell-ProjectBootstrap_Archive_InstalledVersionReference.md'
			
        }

    )
	
}