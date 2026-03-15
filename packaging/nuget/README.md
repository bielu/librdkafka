# Package assembly

This set of scripts collect CI artifacts from a local directory or S3, and
assembles them into a package structure defined by a packaging class in a
staging directory.
For the NugetPackage class the NuGet tool is then run (from within docker) on
this staging directory to create a proper NuGet package (with all the metadata).
While the StaticPackage class creates a tarball.

The finalized nuget package maybe uploaded manually to NuGet.org

## Requirements

 * Requires Python 3
 * Requires Docker
 * (if --s3) Requires private S3 access keys for the librdkafka-ci-packages bucket.



## Usage (CI release flow)

1. Trigger CI builds by creating and pushing a new release (candidate) tag
   in the librdkafka repo. Make sure the tag is created on the correct branch.

    $ git tag v0.11.0-RC3
    $ git push origin v0.11.0-RC3

2. Wait for CI builds to finish, monitor the builds here:

 New builds

 * https://confluentinc.semaphoreci.com/projects/librdkafka

 Previous builds

 * https://travis-ci.org/edenhill/librdkafka
 * https://ci.appveyor.com/project/edenhill/librdkafka

Or if using SemaphoreCI, just have the packaging job depend on prior build jobs
in the same pipeline.

3. On a Linux host, run the release.py script to assemble the NuGet package

    $ cd packaging/nuget
    # Specify the tag
    $ ./release.py v0.11.0-RC3
    # Optionally, if the tag was moved and an exact sha is also required:
    # $ ./release.py --sha <the-full-git-sha> v0.11.0-RC3

4. If all artifacts were available the NuGet package will be built
   and reside in the current directory as librdkafka.redist.<v-less-tag>.nupkg

5. Test the package (see [Testing the NuGet package](#testing-the-nuget-package)
   below).

6. Upload the package to NuGet

 * https://www.nuget.org/packages/manage/upload

7. If you trust this process you can have release.py upload the package
   automatically to NuGet after building it:

    $ ./release.py --retries 100 --upload your-nuget-api.key v0.11.0-RC3


## Building the NuGet package from local artifacts

If you want to build and test a NuGet package locally (e.g. to validate
ARM64 changes or a development build), you can collect pre-built artifacts
into a local directory and run the packaging scripts against it.

### Prerequisites

 * Python 3 with pip
 * Docker (the `nuget` tool runs inside a `mono:latest` container)
 * .NET SDK 6.0+ (for testing the package)

### Step 1 — Collect artifacts

The packaging script expects artifacts organized in directories whose names
encode platform metadata using the token format
`p-librdkafka__plat-<plat>__arch-<arch>__...`.

Create a directory (e.g. `artifacts/`) and populate it with build outputs
from CI or from your own builds. Each sub-directory must contain the
build output archive (`librdkafka.tgz` for Linux/macOS or
`librdkafka.redist.zip` for Windows).

**Directory layout example** (not all platforms are required — the packaging
script will build the package with whatever is available):

```
artifacts/
├── p-librdkafka__plat-linux__dist-centos8__arch-x64__lnk-std/
│   └── librdkafka.tgz
├── p-librdkafka__plat-linux__dist-centos8__arch-x64__lnk-all/
│   └── librdkafka.tgz
├── p-librdkafka__plat-linux__dist-centos8__arch-arm64__lnk-all/
│   └── librdkafka.tgz
├── p-librdkafka__plat-linux__dist-alpine__arch-x64__lnk-all/
│   └── librdkafka.tgz
├── p-librdkafka__plat-linux__dist-alpine__arch-arm64__lnk-all/
│   └── librdkafka.tgz
├── p-librdkafka__plat-osx__arch-x64__lnk-all/
│   └── librdkafka.tgz
├── p-librdkafka__plat-osx__arch-arm64__lnk-all/
│   └── librdkafka.tgz
├── p-librdkafka__plat-windows__dist-msvc__arch-x64__lnk-std/
│   └── librdkafka.redist.zip
├── p-librdkafka__plat-windows__dist-msvc__arch-x86__lnk-std/
│   └── librdkafka.redist.zip
└── p-librdkafka__plat-windows__dist-msvc__arch-arm64__lnk-std/
    └── librdkafka.redist.zip
```

**Creating a Windows artifact from a local MSVC build** (on a Windows
machine with Visual Studio):

```powershell
# Build all platforms (Win32, x64, ARM64) — requires VS ARM64 tools
.\win32\build.bat

# Package the x64 build into artifacts/
.\win32\package-zip.ps1 -platform x64
# Package the ARM64 build into artifacts/
.\win32\package-zip.ps1 -platform ARM64
# Package the Win32 build into artifacts/
.\win32\package-zip.ps1 -platform Win32
```

**Creating a Linux/macOS artifact from a local build:**

```bash
./configure --enable-static --disable-lz4-ext --enable-strip
make -j
make DESTDIR=$(pwd)/dest install
cd dest && tar czf ../librdkafka.tgz . && cd ..
mkdir -p artifacts/p-librdkafka__plat-linux__dist-centos8__arch-x64__lnk-std
mv librdkafka.tgz artifacts/p-librdkafka__plat-linux__dist-centos8__arch-x64__lnk-std/
```

### Step 2 — Install Python dependencies

```bash
cd packaging/nuget
pip install -r requirements.txt
```

### Step 3 — Build the NuGet package

```bash
cd packaging/nuget

# Build using local artifacts directory, --ignore-tag skips tag validation
./release.py --directory ../../artifacts --ignore-tag \
    --nuget-version 0.0.1-local \
    --no-cleanup \
    v0.0.1-local

# On success the .nupkg file is created in the current directory:
ls -la librdkafka.redist.*.nupkg
```

The `--no-cleanup` flag keeps the staging directory (`out-*-release/`)
so you can inspect the extracted tree for debugging.

Key flags for `release.py`:

| Flag | Purpose |
|------|---------|
| `--directory <path>` | Use local artifact directory instead of S3 |
| `--ignore-tag` | Skip git tag matching (required for local builds) |
| `--nuget-version <ver>` | Override the NuGet package version |
| `--no-cleanup` | Keep staging directory for inspection |
| `--dry-run` | Locate artifacts but don't build anything |
| `--class NugetPackage` | Build NuGet package (default) |
| `--class StaticPackage` | Build static library bundle instead |


## Testing the NuGet package

After building the `.nupkg`, you can test it locally with a .NET project
that uses the `confluent-kafka-dotnet` client (or any project that depends
on `librdkafka.redist`).

### Option 1 — Quick verification: inspect the package contents

A `.nupkg` file is a ZIP archive. Inspect it to verify the expected
native libraries are included:

```bash
# List the contents
unzip -l librdkafka.redist.0.0.1-local.nupkg

# Check that the expected runtimes are present, for example:
unzip -l librdkafka.redist.0.0.1-local.nupkg | grep runtimes/
# Should show entries like:
#   runtimes/win-x64/native/librdkafka.dll
#   runtimes/win-arm64/native/librdkafka.dll
#   runtimes/linux-x64/native/librdkafka.so
#   runtimes/osx-arm64/native/librdkafka.dylib
#   ...
```

### Option 2 — Test with a .NET project using a local NuGet source

1. Create a local NuGet source directory and copy the package into it:

```bash
mkdir -p /tmp/local-nuget-feed
cp librdkafka.redist.0.0.1-local.nupkg /tmp/local-nuget-feed/
```

2. Create a test .NET console project:

```bash
mkdir -p /tmp/kafka-test && cd /tmp/kafka-test
dotnet new console

# Add the local feed as a NuGet source
dotnet nuget add source /tmp/local-nuget-feed --name local-librdkafka

# Install your locally-built package (use the exact version you built)
dotnet add package librdkafka.redist --version 0.0.1-local \
    --source /tmp/local-nuget-feed

# Optionally add the Confluent Kafka .NET client
dotnet add package Confluent.Kafka
```

3. Write a minimal test program (`Program.cs`):

```csharp
using Confluent.Kafka;

// This will load the native librdkafka library from the NuGet package
var version = Library.VersionString;
Console.WriteLine($"librdkafka version: {version}");

// Quick producer config (no broker needed for this sanity check)
var config = new ProducerConfig { BootstrapServers = "localhost:9092" };
using var producer = new ProducerBuilder<Null, string>(config).Build();
Console.WriteLine("Producer created successfully — native library loaded OK");
```

4. Build and run:

```bash
dotnet build
dotnet run
# Expected output:
#   librdkafka version: 2.x.y
#   Producer created successfully — native library loaded OK
```

If the native library fails to load, you will see a
`System.DllNotFoundException` — check that the package contains the
correct runtime for your OS/architecture.

### Option 3 — Test ARM64 specifically on a Windows ARM64 machine

```powershell
mkdir C:\temp\kafka-test; cd C:\temp\kafka-test
dotnet new console

# Add local feed
dotnet nuget add source C:\temp\local-nuget-feed --name local-librdkafka

# Install your package
dotnet add package librdkafka.redist --version 0.0.1-local `
    --source C:\temp\local-nuget-feed
dotnet add package Confluent.Kafka

# Build and run natively on ARM64
dotnet run
```

On a Windows ARM64 device, the .NET runtime will select the
`runtimes/win-arm64/native/` binaries from the NuGet package.


## Other uses

### Create static library bundles

To create a bundle (tarball) of librdkafka self-contained static library
builds, use the following command:

    $ ./release.py --class StaticPackage v1.1.0


### Clean up S3 bucket

To clean up old non-release/non-RC builds from the S3 bucket, first check with:

    $ AWS_PROFILE=.. ./cleanup-s3.py --age 360

Verify that the listed objects should really be deleted, then delete:

    $ AWS_PROFILE=.. ./cleanup-s3.py --age 360 --delete
