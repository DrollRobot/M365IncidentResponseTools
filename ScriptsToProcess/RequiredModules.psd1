# Source\ScriptsToProcess\RequiredModules.psd1

# Read by both Confirm-Dependency.ps1 and Install-Dependency.ps1

@{
    RequiredModules = @(
        @{ ModuleName = 'Microsoft.Graph.Applications'; ModuleVersion = '2.30.0' }
        @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.30.0' }
        @{ ModuleName = 'Microsoft.Graph.DeviceManagement'; ModuleVersion = '2.30.0' }
        @{ ModuleName = 'Microsoft.Graph.Beta.Identity.Signins'; ModuleVersion = '2.30.0' }
        @{ ModuleName = 'Microsoft.Graph.Beta.Reports'; ModuleVersion = '2.30.0' }
        @{ ModuleName = 'Microsoft.Graph.DirectoryObjects'; ModuleVersion = '2.30.0' }
        @{ ModuleName = 'Microsoft.Graph.Groups'; ModuleVersion = '2.30.0' }
        @{ ModuleName = 'Microsoft.Graph.Identity.DirectoryManagement'
            ModuleVersion = '2.30.0'
        }
        @{ ModuleName = 'Microsoft.Graph.Identity.Signins'; ModuleVersion = '2.30.0' }
        @{ ModuleName = 'Microsoft.Graph.Reports'; ModuleVersion = '2.30.0' }
        @{ ModuleName = 'Microsoft.Graph.Users'; ModuleVersion = '2.30.0' }
        @{ ModuleName = 'Microsoft.Graph.Users.Actions'; ModuleVersion = '2.30.0' }
        @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.6.0' }
        @{ ModuleName = 'ImportExcel'; ModuleVersion = '7.8.0' }
        @{ ModuleName = 'PSToml'; ModuleVersion = '0.4.0' }
        @{ ModuleName = 'PSFramework'; ModuleVersion = '1.13.0' }
    )
}
