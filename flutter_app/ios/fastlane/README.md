fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios bump_patch

```sh
[bundle exec] fastlane ios bump_patch
```

Bump patch version (0.0.X)

### ios bump_minor

```sh
[bundle exec] fastlane ios bump_minor
```

Bump minor version (0.X.0)

### ios bump_major

```sh
[bundle exec] fastlane ios bump_major
```

Bump major version (X.0.0)

### ios bump_build

```sh
[bundle exec] fastlane ios bump_build
```

Bump build number only

### ios set_version

```sh
[bundle exec] fastlane ios set_version
```

Set specific version (e.g., version:1.2.3)

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload to TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Build and upload to App Store

### ios build

```sh
[bundle exec] fastlane ios build
```

Build only (no upload)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
