#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pester unit tests for BootstrapState private helper function Get-DefaultStatePath.
.DESCRIPTION
    No stub required to ensure deterministic, side-effect free tests. In fact, honestly, it barely deserves a test!
.EXAMPLE
    # Run the tests from the repository root
    Invoke-Pester -Path ./bootstrap/BootstrapState/Tests/Unit/Get-DefaultStatePath.Tests.ps1
.NOTES
    - Requires Pester v5+ and PowerShell 7+ (PowerShell Core).
    - The test file imports the module file BootstrapState.psm1 from the module root folder.
#>

$ModuleName = 'BootstrapState'
$script:ModuleDir = (Get-Item $PSScriptRoot).Parent.Parent # Go up from /Unit to /Tests to /BootstrapState
# Import the module
Import-Module $ModuleDir -Force

InModuleScope $ModuleName -Parameters @{ ModuleDir = $ModuleDir } {
    param($ModuleDir)
    Describe "Get-DefaultStatePath" {
        BeforeAll {
            $bootstrapPath = (Get-Item $ModuleDir).Parent # Go up from /BootstrapState to /bootstrap
            $expectedPath = Join-Path -Path $bootstrapPath -ChildPath 'infrastate.json'
        }
        It "Returns the expected default state path" {
            $result = Get-DefaultStatePath
            $result | Should -Be $expectedPath
        }
    }
}
