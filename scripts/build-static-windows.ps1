param(
    [string]$Prefix = "",
    [string]$Re2Version = "2023-03-01"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $repoRoot "out"
$sourceDir = Join-Path $outDir "src"
$buildRoot = Join-Path $outDir "build"
if (-not $Prefix) {
    $Prefix = Join-Path $outDir "static-prefix"
}
$prefixUnix = $Prefix.Replace('\', '/')

$gcc = (Get-Command gcc -ErrorAction Stop).Source
$gxx = (Get-Command g++ -ErrorAction Stop).Source
$ar = (Get-Command ar -ErrorAction Stop).Source
$ranlib = (Get-Command ranlib -ErrorAction Stop).Source
$null = Get-Command git -ErrorAction Stop
$null = Get-Command cmake -ErrorAction Stop
$null = Get-Command ninja -ErrorAction Stop

New-Item -ItemType Directory -Force -Path $sourceDir, $buildRoot, $Prefix | Out-Null

# RE2 releases after 2023-03-01 require Abseil. On MinGW, statically linking
# that combination also pulls in Abseil's pthread waiter and can cause process
# shutdown heap corruption. This release is API-compatible with CRE2 and keeps
# the Windows archive smaller and self-contained.
$re2Source = Join-Path $sourceDir "re2-$Re2Version"
if (-not (Test-Path $re2Source)) {
    git clone --depth 1 --branch $Re2Version https://github.com/google/re2.git $re2Source
}

$env:CC = $gcc
$env:CXX = $gxx

$re2Build = Join-Path $buildRoot "re2-$Re2Version"
cmake -S $re2Source -B $re2Build -G Ninja `
    -DCMAKE_BUILD_TYPE=Release `
    "-DCMAKE_INSTALL_PREFIX=$prefixUnix" `
    -DCMAKE_INSTALL_LIBDIR=lib `
    -DBUILD_SHARED_LIBS=OFF `
    -DRE2_BUILD_TESTING=OFF `
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cmake --build $re2Build --target install --parallel

$bundleDir = Join-Path $buildRoot "bundle-$Re2Version"
New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null
$wrapperObject = Join-Path $bundleDir "cre2.o"
$cre2Dir = Join-Path $repoRoot "internal\cre2"
& $gxx -std=c++17 -O2 -DNDEBUG `
    "-I$($Prefix.Replace('\', '/'))/include" `
    "-I$($cre2Dir.Replace('\', '/'))" `
    -c (Join-Path $cre2Dir "cre2.cpp") `
    -o $wrapperObject

$re2Archive = Join-Path $Prefix "lib\libre2.a"
if (-not (Test-Path $re2Archive)) {
    throw "Static RE2 archive was not installed at $re2Archive"
}

$outputDir = Join-Path $cre2Dir "lib\windows_amd64"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$outputArchive = Join-Path $outputDir "libre2_cre2.a"
$mriFile = Join-Path $bundleDir "bundle.mri"
$mri = [System.Collections.Generic.List[string]]::new()
$mri.Add("CREATE $($outputArchive.Replace('\', '/'))")
$mri.Add("ADDMOD $($wrapperObject.Replace('\', '/'))")
$mri.Add("ADDLIB $($re2Archive.Replace('\', '/'))")
$mri.Add("SAVE")
$mri.Add("END")
[System.IO.File]::WriteAllLines($mriFile, $mri)

if (Test-Path $outputArchive) {
    Remove-Item -LiteralPath $outputArchive -Force
}
$process = Start-Process -FilePath $ar -ArgumentList "-M" -NoNewWindow -Wait -PassThru -RedirectStandardInput $mriFile
if ($process.ExitCode -ne 0) {
    throw "ar failed with exit code $($process.ExitCode)"
}
& $ranlib $outputArchive

$item = Get-Item $outputArchive
Write-Output "Built $($item.FullName) ($($item.Length) bytes)"
