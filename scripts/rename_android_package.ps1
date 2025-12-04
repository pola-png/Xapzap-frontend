Param(
  [Parameter(Mandatory = $true)][string]$ProjectPath,
  [Parameter(Mandatory = $true)][string]$NewPackage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Update-TextFile {
  param([string]$Path,[scriptblock]$Updater)
  if (-not (Test-Path $Path)) { return }
  $content = Get-Content -LiteralPath $Path -Raw
  $new = & $Updater $content
  if ($new -ne $content) {
    Set-Content -LiteralPath $Path -Value $new -NoNewline
    Write-Host "Updated: $Path"
  }
}

function Ensure-Permission {
  param([string]$ManifestPath,[string]$Permission)
  if (-not (Test-Path $ManifestPath)) { return }
  $text = Get-Content -LiteralPath $ManifestPath -Raw
  if ($text -notmatch [regex]::Escape($Permission)) {
    # Insert after opening <manifest ...>
    $new = $text -replace '(<manifest[^>]*>)', "$1`n    $Permission"
    Set-Content -LiteralPath $ManifestPath -Value $new -NoNewline
    Write-Host "Inserted permission into: $ManifestPath"
  }
}

$androidApp = Join-Path $ProjectPath 'android/app'
if (-not (Test-Path $androidApp)) {
  throw "Android app module not found at: $androidApp"
}

# 1) build.gradle / build.gradle.kts
$gradle = Join-Path $androidApp 'build.gradle'
$gradleKts = Join-Path $androidApp 'build.gradle.kts'
if (Test-Path $gradle) {
  Update-TextFile $gradle {
    param($t)
    $t = $t -replace 'applicationId\s+"[^"]+"', "applicationId \"$NewPackage\""
    $t = $t -replace 'namespace\s+"[^"]+"', "namespace \"$NewPackage\""
    return $t
  }
} elseif (Test-Path $gradleKts) {
  Update-TextFile $gradleKts {
    param($t)
    $t = $t -replace 'applicationId\s*=\s*"[^"]+"', "applicationId = \"$NewPackage\""
    $t = $t -replace 'namespace\s*=\s*"[^"]+"', "namespace = \"$NewPackage\""
    return $t
  }
} else {
  Write-Warning "No Gradle build file found at $androidApp"
}

# 2) Manifests
$manifests = @(
  Join-Path $androidApp 'src/main/AndroidManifest.xml',
  Join-Path $androidApp 'src/debug/AndroidManifest.xml',
  Join-Path $androidApp 'src/profile/AndroidManifest.xml'
)
foreach ($m in $manifests) {
  Update-TextFile $m {
    param($t)
    $t -replace 'package="[^"]+"', "package=\"$NewPackage\""
  }
}

# 3) RECORD_AUDIO permission in main manifest
$mainManifest = Join-Path $androidApp 'src/main/AndroidManifest.xml'
Ensure-Permission $mainManifest '<uses-permission android:name="android.permission.RECORD_AUDIO" />'

# 4) Move MainActivity to new package path and update package line
$kotlinRoot = Join-Path $androidApp 'src/main/kotlin'
if (Test-Path $kotlinRoot) {
  $mainActivity = Get-ChildItem -Path $kotlinRoot -Recurse -Filter 'MainActivity.kt' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $mainActivity) {
    $newPkgPath = Join-Path $kotlinRoot ($NewPackage -replace '\.', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path $newPkgPath)) { New-Item -ItemType Directory -Path $newPkgPath | Out-Null }
    $dest = Join-Path $newPkgPath 'MainActivity.kt'
    # Update package line
    $content = Get-Content -LiteralPath $mainActivity.FullName -Raw
    $content = $content -replace '^package\s+.*', "package $NewPackage"
    Set-Content -LiteralPath $dest -Value $content -NoNewline
    if ($mainActivity.FullName -ne $dest) {
      Remove-Item -LiteralPath $mainActivity.FullName -Force
    }
    Write-Host "Moved MainActivity to: $dest"
  } else {
    Write-Warning "MainActivity.kt not found under $kotlinRoot"
  }
} else {
  Write-Warning "Kotlin source root not found: $kotlinRoot"
}

Write-Host "Package rename complete -> $NewPackage"
