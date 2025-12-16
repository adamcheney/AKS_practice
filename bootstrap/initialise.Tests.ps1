#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for the initialisation functionality.
.DESCRIPTION
    Unit tests for functions in initialise.ps1:
      - Set-PSResourceGetv3: 
        ensures PSResourceGet v3 is installed/imported and returns the module info.
      - Ensure-ModuleVersionImport: 
        validates that a specific module/version is available, imports or reloads as required.
      - Import-BootstrapDependencies: 
        reads a PSD1 of RequiredModules, installs missing modules and ensures versions are imported.
      - Initialize-Bootstrap: 
        high-level entry that invokes Set-PSResourceGetv3 and Import-BootstrapDependencies.

    Each Describe/Context exercises success and failure branches. External commands (Get-Module, Install-PSResource,
    Import-Module, Remove-Module, Import-PowerShellDataFile, Test-Path, etc.) are mocked to keep tests deterministic
    and side-effect free.
.EXAMPLE
    # Run the test file
    Invoke-Pester -Path ./bootstrap/initialise.Tests.ps1
.NOTES
    - Requires Pester installed.
    - Tests should be executed from the repository root so $PSScriptRoot resolves correctly.
#>

BeforeAll {
    # Dot-source the initialise script
    . (Join-Path -Path $PSScriptRoot -ChildPath 'initialise.ps1')
}

Describe "Set-PSResourceGetv3" -Tag 'Unit' {
    BeforeAll {
        Mock Install-Module { param($args) $null }
        Mock Ensure-ModuleVersionImport {
            [PSCustomObject]@{
                Name = 'Microsoft.PowerShell.PSResourceGet'
                Version = [Version]'1.1.1'
            }
        }
    }
    Context "When not installed" {
        BeforeAll {
            Mock Get-Module { @() } -ParameterFilter { $ListAvailable }
        }
        It "Should install and import PSResourceGet v3" {
            # Call the function
            Set-PSResourceGetv3 -Version '1.1.1'
            # Assert that the mocks were called
            Should -Invoke Install-Module -Times 1
            Should -Invoke Ensure-ModuleVersionImport -Times 1
        }
        It "Should return the expected module object" {
            $result = Set-PSResourceGetv3 -Version '1.1.1'
            $result.Name | Should -Be 'Microsoft.PowerShell.PSResourceGet'
            $result.Version | Should -Be '1.1.1'
        }
    }
    Context "Correct version already installed" {
        BeforeAll {
            Mock Get-Module {
                @(
                    [PSCustomObject]@{
                        Name = 'Microsoft.PowerShell.PSResourceGet'
                        Version = [Version]'1.1.1'
                    }
                )
            }
        }
        It "Should not install PSResourceGet v3" {
            # Call the function
            Set-PSResourceGetv3 -Version '1.1.1'
            # Assert that the mocks were called
            Should -Invoke Install-Module -Times 0
            Should -Invoke Ensure-ModuleVersionImport -Times 1
        }
        It "Should return the expected module object" {
            $result = Set-PSResourceGetv3 -Version '1.1.1'
            $result.Name | Should -Be 'Microsoft.PowerShell.PSResourceGet'
            $result.Version | Should -Be '1.1.1'
        }
    }
}

Describe "Import-BootstrapDependencies" -Tag 'Unit' {
    BeforeAll {
        Mock Set-PSResourceGetv3 { $null } # prevent calling the real Ensure-ModuleVersionImport for PSResourceGet
    }
    Context "When dependency file not found" {
        BeforeAll {
            Mock Test-Path { $false }
        }
        It "Should throw an error" {
            { Import-BootstrapDependencies -DependencyFile 'nonexistent.psd1' } |
                Should -Throw "Dependency file 'nonexistent.psd1' not found."
        }
    }
    Context "When file present but empty" {
        BeforeAll {
            Mock Test-Path { $true }
            Mock Import-PowerShellDataFile { $null }
            Mock Write-Information {}
        }
        It "Should write 'No RequiredModules found' and return early" {
            Import-BootstrapDependencies -DependencyFile 'empty.psd1'
            Should -Invoke Write-Information -Times 1 -ParameterFilter {
                $Message -like '*No RequiredModules found*'
            }
        }
    }
    Context "When invalid dependency" {
        BeforeAll {
            Mock Test-Path { $true }
            Mock Import-PowerShellDataFile {
                @{
                    RequiredModules = @(
                        @{ ModuleName = 'Invalid'; ModuleVersion = '1.0.0' }
                    )
                }
            }
            Mock Get-Module { $null } -ParameterFilter { $ListAvailable }
            Mock Install-PSResource { throw "Package(s) 'Invalid' could not be installed from repository 'PSGallery'." }
            Mock Write-Error {}
        }
        It "Should throw an error" {
            { Import-BootstrapDependencies } | Should -Throw "Package(s) 'Invalid' could not be installed from repository 'PSGallery'."
            Should -Invoke Write-Error -ParameterFilter {
                $Message -match "Failed to install module"
            } -Times 1
        }
    }
    Context "When dependency file is malformed" {
        BeforeAll {
            Mock Test-Path { $true }
            Mock Import-PowerShellDataFile { throw "Simulated parse failure" }
        }
        It "Should throw an import error" {
            { Import-BootstrapDependencies -DependencyFile 'malformed.psd1' } |
                Should -Throw "Failed to import dependency file 'malformed.psd1'. Error: Simulated parse failure"
        }
    }
    Context "When dependency file has valid module not installed" {
        BeforeAll {
            Mock Test-Path { $true }
            Mock Import-PowerShellDataFile {
                @{
                    RequiredModules = @(
                        @{ ModuleName = 'Test'; ModuleVersion = '4.2.0' }
                    )
                }
            }
            Mock Get-Module { @() } -ParameterFilter { $ListAvailable }
            Mock Install-PSResource {
                [PSCustomObject]@{
                    Name = 'Test'
                    Version = [Version]'4.2.0'
                }
            }
            Mock Ensure-ModuleVersionImport {
                [PSCustomObject]@{
                    Name = 'Test'
                    Version = [Version]'4.2.0'
                }
            }
        }
        It "Should install each missing module" {
            Import-BootstrapDependencies -DependencyFile 'valid.psd1'
            Should -Invoke Install-PSResource -ParameterFilter {
                $Name -eq 'Test' -and $Version -eq '4.2.0'
            } -Times 1
            Should -Invoke Ensure-ModuleVersionImport -ParameterFilter {
                $ModuleName -eq 'Test' -and $ModuleVersion -eq '4.2.0'
            } -Times 1
        }
    }
    Context "When required module version already installed" {
        BeforeAll {
            Mock Test-Path { $true }
            Mock Import-PowerShellDataFile {
                @{
                    RequiredModules = @(
                        @{ ModuleName = 'Test'; ModuleVersion = '4.2.0' }
                    )
                }
            }
            Mock Get-Module {
                [PSCustomObject]@{
                    Name = 'Test'
                    Version = [Version]'4.2.0'
                }
            }
            Mock Install-PSResource {}
            Mock Ensure-ModuleVersionImport {
                [PSCustomObject]@{
                    Name = 'Test'
                    Version = [Version]'4.2.0'
                }
            }
        }
        It "Should skip installation and call Ensure-ModuleVersionImport" {
            Import-BootstrapDependencies -DependencyFile 'valid.psd1'
            Should -Invoke Install-PSResource -Times 0
            Should -Invoke Ensure-ModuleVersionImport -ParameterFilter {
                $ModuleName -eq 'Test' -and $ModuleVersion -eq '4.2.0'
            } -Times 1
        }
    }
    Context "When Install-PSResource fails" {
            BeforeAll {
                Mock Test-Path { $true }
                Mock Import-PowerShellDataFile {
                    @{
                        RequiredModules = @(
                            @{ ModuleName = 'Fail'; ModuleVersion = '1.0.0' }
                        )
                    }
                }
                Mock Get-Module { @() } -ParameterFilter { $ListAvailable }
                Mock Install-PSResource { throw "Package(s) 'Fail' could not be installed from repository 'PSGallery'." }
                Mock Write-Verbose {}
                Mock Write-Error {
            }
            It "Should throw an error and stop processing" {
                { Import-BootstrapDependencies -DependencyFile 'fail.psd1' } |
                    Should -Throw "Package(s) 'Fail' could not be installed from repository 'PSGallery'."
                Should -Invoke Write-Verbose -ParameterFilter {
                    $Message -match "Installing module 'Fail' version '1.0.0'..."
                } -Times 1
                Should -Invoke Write-Verbose -ParameterFilter {
                    $Message -match "Module 'Fail' installed successfully."
                } -Times 0
                Should -Invoke Write-Error -ParameterFilter {
                    $Message -match "Failed to install module 'Fail'.*"
                } -Times 1
            }
        }
    }
}
Describe "Initialize-Bootstrap" -Tag 'Unit' {
  BeforeAll {
    Mock Set-PSResourceGetv3 {}
    Mock Import-BootstrapDependencies {}
    Mock Join-Path {
      './deps.psd1'
    }
  }
  It "Should call Set-PSResourceGetv3 and Import-BootstrapDependencies" {
    Initialize-Bootstrap
    Should -Invoke Set-PSResourceGetv3 -ParameterFilter { $Version -eq '1.1.1' } -Times 1
    Should -Invoke Import-BootstrapDependencies -ParameterFilter { $DependencyFile -eq './deps.psd1' } -Times 1
  }
}

Describe "Import-IaCAzureBackendModules" -Tag 'Unit' {
    BeforeAll {
        Mock Import-Module {}
        Mock Write-Warning {}
    }
    Context "When specific modules are specified in an array" {
        It "Should import the specified modules" {
            Import-IaCAzureBackendModules -Module @('AzureBootstrap', 'AzureIdentity')
            Should -Invoke Import-Module -ParameterFilter { $Name -like '*AzureBootstrap*' } -Times 1
            Should -Invoke Import-Module -ParameterFilter { $Name -like '*AzureIdentity*' } -Times 1
            Should -Invoke Import-Module -ParameterFilter { $Name -like '*AzureStorage*' } -Times 0
        }
    }
    Context "When modules are not specified" {
        It "Should import default modules" {
            Import-IaCAzureBackendModules
            Should -Invoke Import-Module -ParameterFilter { $Name -like '*AzureBootstrap*' } -Times 1
            Should -Invoke Import-Module -ParameterFilter { $Name -like '*AzureIdentity*' } -Times 1
            Should -Invoke Import-Module -ParameterFilter { $Name -like '*AzureStorage*' } -Times 1
        }
    }
    Context "When incorrect module is specified" {
        It "Should warn and not import module" {
            Import-IaCAzureBackendModules -Module @('SomethingSomething')
            Should -Invoke Import-Module -Times 0
            Should -Invoke Write-Warning -ParameterFilter { $Message -like '*SomethingSomething*' } -Times 1
        }
    }
    Context "When a single string is passed" {
        It "Should import the specified module" {
            Import-IaCAzureBackendModules -Module 'AzureBootstrap'
            Should -Invoke Import-Module -ParameterFilter { $Name -like '*AzureBootstrap*' } -Times 1
        }
    }
}

Describe "Initialize-IaCAzureBackend" -Tag 'Unit' {
    BeforeAll {
        Mock Load-Module {}
    }
}

