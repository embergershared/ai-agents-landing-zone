<#
.SYNOPSIS
    Deploys an environment's Terraform state backend from its tfvars file.

.DESCRIPTION
    Reads src/landing-zone/environments/<env>.tfvars and runs the src/state-backend bootstrap with
    it: the resource group, the storage account and the environment's tfstate-<env> container.
    Then writes src/landing-zone/environments/<env>.backend.hcl from the backend_config output.

    Environments that share a name_prefix share one backend. Each subscription and name_prefix has
    its own bootstrap state, outside the working copy:
        <StateRoot>/<subscription-id>/<name_prefix>/terraform.tfstate
    The backend keeps the environments it already has: the script adds this one to the list.

    The bootstrap takes location, name_prefix, tags and allowed_ip_ranges from the environment's
    tfvars file (it overrides the same values in src/state-backend/terraform.tfvars). Its other
    variables, such as github_deployer, still come from src/state-backend/terraform.tfvars.
    Terraform warns about the environment's variables the bootstrap doesn't declare.

    The script stops when the plan would delete or replace anything, and asks before it applies.

.PARAMETER Environment
    The environment: src/landing-zone/environments/<Environment>.tfvars must exist.

.PARAMETER PlanOnly
    Stop after the plan. Nothing is applied and no file is written.

.PARAMETER AutoApprove
    Apply the plan without asking.

.PARAMETER StateRoot
    Folder that holds the bootstrap states, outside the repository working copy.

.EXAMPLE
    ./scripts/New-StateBackend.ps1 -Environment dev -PlanOnly

.EXAMPLE
    ./scripts/New-StateBackend.ps1 -Environment dev
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Environment,

    [switch] $PlanOnly,

    [switch] $AutoApprove,

    [string] $StateRoot = (Join-Path $HOME '.terraform-state/ai-agents-landing-zone/state-backend')
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$repoRoot = Split-Path -Parent $PSScriptRoot
$bootstrapDir = Join-Path $repoRoot 'src/state-backend'
$environmentsDir = Join-Path $repoRoot 'src/landing-zone/environments'
$tfvarsPath = Join-Path $environmentsDir "$Environment.tfvars"
$backendHclPath = Join-Path $environmentsDir "$Environment.backend.hcl"
$planFile = 'bootstrap.tfplan'
# Same key as environments/<env>.backend.hcl.example.
$stateKey = 'landing-zone.tfstate'

function Write-BackendLog {
    param(
        [ValidateSet('INFO', 'WARNING')] [string] $Level,
        [string] $Message
    )
    if ($Level -eq 'WARNING') { Write-Warning $Message } else { Write-Information "INFO  $Message" }
}

# Runs terraform in the bootstrap folder and stops on a non-zero exit code.
function Invoke-Terraform {
    param([string[]] $Arguments)
    & terraform "-chdir=$bootstrapDir" @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "terraform $($Arguments[0]) failed with exit code $LASTEXITCODE."
    }
}

# Reads a top-level string attribute (name = "value") from a tfvars file.
function Get-TfvarsString {
    param([string] $Path, [string] $Name)
    $match = Select-String -Path $Path -Pattern "^\s*$Name\s*=\s*`"([^`"]*)`"" | Select-Object -First 1
    if (-not $match) {
        throw "$Path doesn't set $Name. Set it to a string value."
    }
    $match.Matches[0].Groups[1].Value
}

# ---- Inputs ----
if (-not (Test-Path $tfvarsPath)) {
    throw "$tfvarsPath doesn't exist. Copy environments/dev.tfvars and set environment = `"$Environment`"."
}
$fileEnvironment = Get-TfvarsString -Path $tfvarsPath -Name 'environment'
if ($fileEnvironment -ne $Environment) {
    throw "$tfvarsPath sets environment = `"$fileEnvironment`", not `"$Environment`". The file name and the value must match."
}
$namePrefix = Get-TfvarsString -Path $tfvarsPath -Name 'name_prefix'

# ---- Azure context ----
$account = az account show --query '{id:id, name:name, tenantId:tenantId, user:user.name}' -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $account) {
    throw 'Azure CLI is not signed in. Run az login --tenant <tenant-id> and az account set --subscription <subscription-id>.'
}
$env:ARM_SUBSCRIPTION_ID = $account.id
Write-BackendLog INFO "Subscription: $($account.name) ($($account.id)), tenant $($account.tenantId), signed in as $($account.user)"
Write-BackendLog INFO "Environment: $Environment, name_prefix: $namePrefix, values from $tfvarsPath"

# ---- Init on this subscription and prefix's bootstrap state ----
$statePath = Join-Path $StateRoot "$($account.id)/$namePrefix/terraform.tfstate"
Write-BackendLog INFO "Bootstrap state: $statePath"

# Before this script, the bootstrap state was one file at the root of StateRoot. A backend recorded
# there would be created a second time, so it must move to its subscription and prefix folder first.
$legacyStatePath = Join-Path $StateRoot 'terraform.tfstate'
if ((Test-Path $legacyStatePath) -and -not (Test-Path $statePath)) {
    $legacy = Get-Content $legacyStatePath -Raw | ConvertFrom-Json
    if (@($legacy.resources).Count -gt 0) {
        throw "$legacyStatePath holds a deployed backend. If it is this subscription's $namePrefix backend, move it first: New-Item -ItemType Directory -Force (Split-Path '$statePath'); Move-Item '$legacyStatePath' '$statePath'"
    }
}
Invoke-Terraform @('init', '-reconfigure', '-input=false', "-backend-config=path=$statePath")

# The environments the backend already has, plus this one. A new state has no outputs ({}).
$outputs = (& terraform "-chdir=$bootstrapDir" output -json | Out-String | ConvertFrom-Json -AsHashtable)
if ($LASTEXITCODE -ne 0) {
    throw 'terraform output failed.'
}
$existing = if ($outputs.ContainsKey('containers')) { @($outputs.containers.value.Keys) } else { @() }
$environments = @(@($existing) + $Environment | Sort-Object -Unique)
Write-BackendLog INFO "State containers after this run: $($environments -join ', ')"

$environmentsVarFile = Join-Path ([System.IO.Path]::GetTempPath()) "state-backend-$([guid]::NewGuid()).tfvars.json"
@{ environments = $environments } | ConvertTo-Json | Set-Content -Path $environmentsVarFile -Encoding utf8

try {
    # ---- Plan ----
    Invoke-Terraform @('plan', '-input=false', '-compact-warnings', "-var-file=$tfvarsPath", "-var-file=$environmentsVarFile", "-out=$planFile")

    $plan = & terraform "-chdir=$bootstrapDir" show -json $planFile | Out-String | ConvertFrom-Json -Depth 100
    if ($LASTEXITCODE -ne 0) {
        throw 'terraform show failed.'
    }
    $deletes = @($plan.resource_changes | Where-Object { $_.change.actions -contains 'delete' })
    if ($deletes.Count -gt 0) {
        $addresses = ($deletes | ForEach-Object address) -join ', '
        throw "The plan deletes or replaces $($deletes.Count) resource(s): $addresses. Nothing was applied. Check that $tfvarsPath has the same location, name_prefix and tags as the backend's other environments."
    }
    $changes = @($plan.resource_changes | Where-Object { $_.change.actions -notcontains 'no-op' -and $_.change.actions -notcontains 'read' })
    Write-BackendLog INFO "The plan adds or updates $($changes.Count) resource(s) and deletes none."

    if ($PlanOnly) {
        Write-BackendLog INFO 'PlanOnly: nothing applied, no file written.'
        return
    }

    # ---- Apply ----
    if ($changes.Count -gt 0) {
        if (-not $AutoApprove) {
            $answer = Read-Host "Apply this plan to subscription $($account.name)? Type yes to apply"
            if ($answer -ne 'yes') {
                Write-BackendLog WARNING 'Not applied.'
                return
            }
        }
        Invoke-Terraform @('apply', '-input=false', $planFile)
    }

    # ---- Check and write the environment's backend file ----
    $storageAccount = (& terraform "-chdir=$bootstrapDir" output -raw storage_account_name)
    $publicAccess = az storage account show -n $storageAccount --query publicNetworkAccess -o tsv
    if ($LASTEXITCODE -ne 0) {
        throw "az storage account show failed for $storageAccount."
    }
    if ($publicAccess -ne 'Enabled') {
        throw "Storage account $storageAccount has publicNetworkAccess = $publicAccess, so Terraform can't reach the state. See docs/state-backend.md, 'Subscriptions with a policy that turns off public network access'."
    }

    $backendConfig = (& terraform "-chdir=$bootstrapDir" output -json backend_config | Out-String | ConvertFrom-Json -AsHashtable)[$Environment]
    if (-not $backendConfig) {
        throw "backend_config has no entry for $Environment."
    }
    if ($backendConfig.key -ne $stateKey) {
        throw "backend_config key is $($backendConfig.key), expected $stateKey."
    }
    @(
        "resource_group_name  = `"$($backendConfig.resource_group_name)`""
        "storage_account_name = `"$($backendConfig.storage_account_name)`""
        "container_name       = `"$($backendConfig.container_name)`""
        "key                  = `"$($backendConfig.key)`""
        "use_azuread_auth     = $($backendConfig.use_azuread_auth.ToString().ToLowerInvariant())"
    ) | Set-Content -Path $backendHclPath -Encoding utf8
    Write-BackendLog INFO "Wrote $backendHclPath (container $($backendConfig.container_name) in $($backendConfig.storage_account_name))."
    Write-BackendLog INFO "Back up ${StateRoot}: it is the only copy of the bootstrap state."
    Write-BackendLog INFO "Next: Set-Location src/landing-zone; terraform init -reconfigure -backend-config=`"environments/$Environment.backend.hcl`""
}
finally {
    Remove-Item -Path $environmentsVarFile -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $bootstrapDir $planFile) -ErrorAction SilentlyContinue
}
