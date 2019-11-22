param ([switch]$noTest = $false)

# Create NuGet package
$commitSha = & { git rev-parse --short HEAD }
$commitCount = & { git rev-list --count HEAD }
$revision = $commitCount.ToString().PadLeft(5, '0')

# CI triggered by v3
$version = "3.0.0-beta-$revision-$commitSha"

function exec([string] $cmd) {
    Write-Host $cmd -ForegroundColor Green
    & ([scriptblock]::Create($cmd))
    if ($lastexitcode -ne 0) {
        throw ("Error: " + $cmd)
    }
}

function test() {
    if ($noTest) {
        return
    }

    exec "dotnet test -c Release --logger trx /p:CollectCoverage=true /p:CoverletOutputFormat=opencover"

    if ($env:CODECOV_TOKEN) {
        exec "$env:USERPROFILE\.nuget\packages\codecov\1.9.0\tools\codecov.exe -f ./test/docfx.Test/coverage.opencover.xml"
    }
}

function publish() {
    Remove-Item ./drop -Force -Recurse -ErrorAction Ignore
    exec "dotnet pack src\docfx -c Release -o $PSScriptRoot\drop /p:Version=$version /p:InformationalVersion=$version"
    exec "dotnet pack src\Microsoft.DocAsTest -c Release -o $PSScriptRoot\drop /p:Version=$version /p:InformationalVersion=$version"
}

function testNuGet() {
    if ($noTest) {
        return
    }

    exec "dotnet tool install docfx --version $version --add-source drop --tool-path drop"
    exec "drop\docfx --version"

    Remove-Item $env:USERPROFILE/.nuget/packages/microsoft.docastest -Force -Recurse -ErrorAction Ignore

    Remove-Item $PSScriptRoot\test\Microsoft.DocAsTest.NuGetTest\bin\Debug\netcoreapp2.2\foo -Force -Recurse -ErrorAction Ignore
    exec "dotnet restore test/Microsoft.DocAsTest.NuGetTest --no-cache --force --source $PSScriptRoot\drop"
    exec "dotnet test test/Microsoft.DocAsTest.NuGetTest --no-restore"

    if (-not (Test-Path -Path "$PSScriptRoot\test\Microsoft.DocAsTest.NuGetTest\bin\Debug\netcoreapp2.2\foo")) {
        throw 'Microsoft.DocAsTest.NuGetTest failed'
    }
}

try {
    pushd $PSScriptRoot
    test
    publish
    testNuGet
} finally {
    popd
}
