#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for the initialisation functionality.
.DESCRIPTION
    Tests:
        1)
.NOTES
    This script requires the Pester module to be installed.
#>

BeforeAll {
        # Dot-source the initialise script
        . (Join-Path -Path $PSScriptRoot -ChildPath 'initialise.ps1')
    }

Describe "Set-PSResourceGetv3" -Tag 'Unit' {
    BeforeAll {
        Mock Install-Module { param($args) return $null }
        Mock Ensure-ModuleVersion {
            [PSCustomObject]@{
                Name = 'Microsoft.PowerShell.PSResourceGet'
                Version = [Version]'1.1.1'
            }
        }
    }
    Context " When - not installed" {
        BeforeAll {
            Mock Get-Module { return $null }
        }
        It " Should - install and import PSResourceGet v3" {
            # Call the function
            Set-PSResourceGetv3 -Version '1.1.1'
            # Assert that the mocks were called
            Assert-MockCalled Install-Module -Times 1
            Assert-MockCalled Ensure-ModuleVersion -Times 1
        }
        It " Should - return the expected module object" {
            $result = Set-PSResourceGetv3 -Version '1.1.1'
            $result.Name | Should -Be 'Microsoft.PowerShell.PSResourceGet'
            $result.Version | Should -Be '1.1.1'
        }
    }
    Context "Correct version already installed" {
        BeforeAll {
            Mock Get-Module {
                return [PSCustomObject]@{
                    Name = 'Microsoft.PowerShell.PSResourceGet'
                    Version = [Version]'1.1.1'
                }
            }
        }
        It " Should - not install PSResourceGet v3" {
            # Call the function
            Set-PSResourceGetv3 -Version '1.1.1'
            # Assert that the mocks were called
            Assert-MockCalled Install-Module -Times 0
            Assert-MockCalled Ensure-ModuleVersion -Times 1
        }
        It " Should - return the expected module object" {
            $result = Set-PSResourceGetv3 -Version '1.1.1'
            $result.Name | Should -Be 'Microsoft.PowerShell.PSResourceGet'
            $result.Version | Should -Be '1.1.1'
        }
    }
}

Describe "Ensure-ModuleVersion" -Tag 'Unit' {
    Context " When - module is not installed" {}
        BeforeAll {
            Mock Get-Module { return $null }
        }
        It " Should - throw an error" {
            { Ensure-ModuleVersion -ModuleName 'Null' -ModuleVersion '0.0' } `
              | Should -Throw "Module 'Null' version '0.0' not installed."
        }
    Context " When - installed incorrect version" {
        BeforeAll {
            Mock Get-Module {
                return @(
                    [PSCustomObject]@{
                        Name = 'Test'
                        Version = [String]'4.2.0'
                    }
                )
            }
        }
        It " Should - throw an error" {
            { Ensure-ModuleVersion -ModuleName 'Test' -ModuleVersion '5.0.0' } `
              | Should -Throw "Module 'Test' version '5.0.0' not installed."
        }
    }
    Context " When - module installed none imported" {
        BeforeAll {
            # Mock Get-Module -ListAvailable to return an array of installed modules
            Mock Get-Module {
                @(
                    [PSCustomObject]@{
                        Name    = 'Test'
                        Version = [Version]'4.2.0'
                    }
                )
            } -ParameterFilter { $ListAvailable }
            # Mock Get-Module (no parameters) to indicate nothing is loaded in session
            Mock Get-Module { return $null } -ParameterFilter { -not $ListAvailable }
            Mock Remove-Module { param($args) return $null }
            Mock Import-Module {
                param($args)
                return [PSCustomObject]@{
                    Name = 'Test'
                    Version = [Version]'4.2.0'
                }
            }
        }
        It " Should - import module and not unload" {
            Ensure-ModuleVersion -ModuleName 'Test' -ModuleVersion '4.2.0'
            Assert-MockCalled Remove-Module -Times 0
            Assert-MockCalled Import-Module -Times 1
        }
        It " Should - return module object" {
            $result = Ensure-ModuleVersion -ModuleName 'Test' -ModuleVersion '4.2.0'
            $result.Name | Should -Be 'Test'
            $result.Version | Should -Be '4.2.0'
        }
    }
    Context " When - module is installed correct version loaded" {
        BeforeAll {
            # Mock Get-Module -ListAvailable to return an array of installed modules
            Mock Get-Module {
                return @(
                    [PSCustomObject]@{
                        Name    = 'Test'
                        Version = [Version]'4.2.0'
                    }
                )
            } -ParameterFilter { $ListAvailable }
            # Mock Get-Module (no parameters) to indicate nothing is loaded in session
            Mock Get-Module {
                return [PSCustomObject]@{
                    Name    = 'Test'
                    Version = [Version]'4.2.0'
                } 
            } -ParameterFilter { -not $ListAvailable }
            Mock Remove-Module { param($args) return $null }
            Mock Import-Module {
                param($args)
                return [PSCustomObject]@{
                    Name = 'Test'
                    Version = [Version]'4.2.0'
                }
            }
        }
        It " Should - not unload but still import module" {
            Ensure-ModuleVersion -ModuleName 'Test' -ModuleVersion '4.2.0'
            Assert-MockCalled Remove-Module -Times 0
            Assert-MockCalled Import-Module -Times 1
        }
        It " Should - return module object" {
            $result = Ensure-ModuleVersion -ModuleName 'Test' -ModuleVersion '4.2.0'
            $result.Name | Should -Be 'Test'
            $result.Version | Should -Be '4.2.0'
        }
    }
    Context " When - module is installed incorrect version loaded" {
        BeforeAll {
            # Mock Get-Module -ListAvailable to return an array of installed modules
            Mock Get-Module {
                return @(
                    [PSCustomObject]@{
                        Name    = 'Test'
                        Version = [Version]'3.1.0'
                    },
                    [PSCustomObject]@{
                        Name    = 'Test'
                        Version = [Version]'4.2.0'
                    }
                )
            } -ParameterFilter { $ListAvailable }
            # Mock Get-Module (no parameters) to indicate an incorrect version is loaded in session
            Mock Get-Module {
                return [PSCustomObject]@{
                    Name    = 'Test'
                    Version = [Version]'3.1.0'
                }
            } -ParameterFilter { -not $ListAvailable }
            Mock Remove-Module { param($args) return $null }
            Mock Import-Module {
                param($args)
                return [PSCustomObject]@{
                    Name = 'Test'
                    Version = [Version]'4.2.0'
                }
            }
        }
        It " Should - unload and import correct module version" {
            Ensure-ModuleVersion -ModuleName 'Test' -ModuleVersion '4.2.0'
            Assert-MockCalled Remove-Module -Times 1
            Assert-MockCalled Import-Module -Times 1
        }
        It " Should - return module object" {
            $result = Ensure-ModuleVersion -ModuleName 'Test' -ModuleVersion '4.2.0'
            $result.Name | Should -Be 'Test'
            $result.Version | Should -Be '4.2.0'
        }
    }
    Context "When Remove-Module fails" {
        BeforeAll {
            Mock Get-Module {
                return [PSCustomObject]@{
                    Name = 'Test';
                    Version = [Version]'3.1.0'
                }
            } -ParameterFilter { -not $ListAvailable }
            Mock Get-Module { 
                return @(
                    [PSCustomObject]@{
                        Name = 'Test';
                        Version = [Version]'4.2.0'
                    }
                )
            } -ParameterFilter { $ListAvailable }
            Mock Remove-Module { throw "Removal failed" }
            Mock Import-Module {
                return [PSCustomObject]@{
                    Name = 'Test';
                    Version = [Version]'4.2.0'
                }
            }
            Mock Write-Error {}
        }
        It "Should write an error if Remove-Module fails" {
            Ensure-ModuleVersion -ModuleName 'Test' -ModuleVersion '4.2.0'
            Assert-MockCalled Write-Error -ParameterFilter { 
                $Message -match 'Failed to remove module' 
            } -Times 1
        }
    }
    Context "When Import-Module fails" {
        BeforeAll {
            Mock Get-Module {
                return @(
                    [PSCustomObject]@{
                        Name = 'Test';
                        Version = [Version]'4.2.0'
                    }
                )
            } -ParameterFilter { $ListAvailable }
            Mock Get-Module { return $null } -ParameterFilter { -not $ListAvailable }
            Mock Remove-Module {}
            Mock Import-Module { throw "Import failed" }
            Mock Write-Error {}
        }
        It "Should write an error if Import-Module fails" {
            { Ensure-ModuleVersion -ModuleName 'Test' -ModuleVersion '4.2.0' } | Should -Throw "Import failed"
            Assert-MockCalled Write-Error -ParameterFilter { $Message -match 'Failed to import module' } -Times 1
        }
    }

}
Describe "Import-BootstrapDependencies" -Tag 'Unit' {
    BeforeAll {
        Mock Set-PSResourceGetv3 { return $null } # prevent calling the real Ensure-ModuleVersion for PSResourceGet
    }
    Context " When - dependency file not found" {
        BeforeAll {
            Mock Test-Path { return $false }
        }
        It " Should - throw an error" {
            { Import-BootstrapDependencies -DependencyFile 'nonexistent.psd1' } `
              | Should -Throw "Dependency file 'nonexistent.psd1' not found."
        }
    }
    Context " When - file present but empty" {
        BeforeAll {
            Mock Test-Path { return $true }
            Mock Import-PowerShellDataFile { return $null }
            Mock Write-Information {}
        }
        It " Should - write 'No RequiredModules found' and return early" {
            Import-BootstrapDependencies -DependencyFile 'empty.psd1'
            Assert-MockCalled Write-Information -Times 1 -ParameterFilter {
                $Message -like '*No RequiredModules found*'
            }
        }
    }
    Context " When - invalid dependency" {
        BeforeAll {
            Mock Test-Path { return $true }
            Mock Import-PowerShellDataFile {
                return @{
                    RequiredModules = @(
                        @{ ModuleName = 'Invalid'; ModuleVersion = '1.0.0' }
                    )
                }
            }
            Mock Get-Module { return $null } -ParameterFilter { $ListAvailable }
            Mock Install-PSResource { throw "Package(s) 'Invalid' could not be installed from repository 'PSGallery'." }
            Mock Write-Error {}
        }
        It " Should - throw an error" {
            { Import-BootstrapDependencies } | Should -Throw "Package(s) 'Invalid' could not be installed from repository 'PSGallery'."
            Assert-MockCalled Write-Error -ParameterFilter {
                $Message -match "Failed to install module"
            } -Times 1
        }
    }
    Context " When - dependency file is malformed" {
        BeforeAll {
            Mock Test-Path { return $true }
            Mock Import-PowerShellDataFile { throw "Simulated parse failure" }
        }
        It " Should - throw an import error" {
            { Import-BootstrapDependencies -DependencyFile 'malformed.psd1' } `
              | Should -Throw "Failed to import dependency file 'malformed.psd1'. Error: Simulated parse failure"
        }
    }
    Context " When - dependency file has valid module not installed" {
        BeforeAll {
            Mock Test-Path { return $true }
           Mock Import-PowerShellDataFile {
                return @{
                    RequiredModules = @(
                        @{ ModuleName = 'Test'; ModuleVersion = '4.2.0' }
                    )
                }
            }
            Mock Get-Module { return $null }
            Mock Install-PSResource {
                return [PSCustomObject]@{
                    Name = 'Test'
                    Version = [Version]'4.2.0'
                }
            }
            Mock Ensure-ModuleVersion {
                return [PSCustomObject]@{
                    Name = 'Test'
                    Version = [Version]'4.2.0'
                }
            }
        }
        It " Should - install each missing module" {
            Import-BootstrapDependencies -DependencyFile 'valid.psd1'
            Assert-MockCalled Install-PSResource -ParameterFilter {
                $Name -eq 'Test' -and $Version -eq '4.2.0'
            } -Times 1
            Assert-MockCalled Ensure-ModuleVersion -ParameterFilter {
                $ModuleName -eq 'Test' -and $ModuleVersion -eq '4.2.0'
            } -Times 1
        }
    }
    Context " When - required module version already installed" {
        BeforeAll {
            Mock Test-Path { return $true }
            Mock Import-PowerShellDataFile {
                return @{
                    RequiredModules = @(
                        @{ ModuleName = 'Test'; ModuleVersion = '4.2.0' }
                    )
                }
            }
            Mock Get-Module {
                return [PSCustomObject]@{
                    Name = 'Test'
                    Version = [Version]'4.2.0'
                }
            }
            Mock Install-PSResource {}
            Mock Ensure-ModuleVersion {
                return [PSCustomObject]@{
                    Name = 'Test'
                    Version = [Version]'4.2.0'
                }
            }
        }
        It " Should - skip installation and call Ensure-ModuleVersion" {
            Import-BootstrapDependencies -DependencyFile 'valid.psd1'
            Assert-MockCalled Install-PSResource -Times 0
            Assert-MockCalled Ensure-ModuleVersion -ParameterFilter {
                $ModuleName -eq 'Test' -and $ModuleVersion -eq '4.2.0'
            } -Times 1
        }
    }
    Context " When - Install-PSResource fails" {
            BeforeAll {
                Mock Test-Path { return $true }
                Mock Import-PowerShellDataFile {
                    return @{
                        RequiredModules = @(
                            @{ ModuleName = 'Fail'; ModuleVersion = '1.0.0' }
                        )
                    }
                }
                Mock Get-Module { return $null } -ParameterFilter { $ListAvailable }
                Mock Install-PSResource { throw "Package(s) 'Fail' could not be installed from repository 'PSGallery'." }
                Mock Write-Host {}
                Mock Write-Error {}
            }
            It " Should - throw an error and stop processing" {
                { Import-BootstrapDependencies -DependencyFile 'fail.psd1' } `
                  | Should -Throw "Package(s) 'Fail' could not be installed from repository 'PSGallery'."
                Assert-MockCalled Write-Host -ParameterFilter {
                    $Message -match "Installing module 'Fail' version '1.0.0'..."
                } -Times 1
                Assert-MockCalled Write-Host -ParameterFilter {
                    $Message -match "Module 'Fail' installed successfully."
                } -Times 0
                Assert-MockCalled Write-Error -ParameterFilter {
                    $Message -match "Failed to install module 'Fail'.*"
                } -Times 1
            }
    }
}
Describe "Initialize-Bootstrap" -Tag 'Unit' {
  BeforeAll {
    Mock Set-PSResourceGetv3 {}
    Mock Import-BootstrapDependencies {}
    Mock Join-Path {
      return './deps.psd1'
    }
  }
  It "Should call Set-PSResourceGetv3 and Import-BootstrapDependencies" {
    Initialize-Bootstrap
    Assert-MockCalled Set-PSResourceGetv3 -ParameterFilter { $Version -eq '1.1.1' } -Times 1
    Assert-MockCalled Import-BootstrapDependencies -ParameterFilter { $DependencyFile -eq './deps.psd1' } -Times 1
  }
}

