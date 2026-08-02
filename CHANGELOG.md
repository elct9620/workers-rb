# Changelog

## [0.2.0](https://github.com/elct9620/workers-rb/compare/v0.1.0...v0.2.0) (2026-08-02)


### ⚠ BREAKING CHANGES

* the chart installs from oci://ghcr.io/elct9620/workers-rb and the Host image is ghcr.io/elct9620/workers-rb/host. Neither reference existed before this, and 0.1.0's are withdrawn.

### Features

* publish the chart as the repository, and the Host under it ([3dd83b3](https://github.com/elct9620/workers-rb/commit/3dd83b34cd81a0b6a0ae243a7ea13c6c8763a6d9))

## 0.1.0 (2026-08-02)


### Bug Fixes

* **chart:** name the shared directory rather than create one ([02df446](https://github.com/elct9620/workers-rb/commit/02df44636f080a191e72d7ca5831690766345d85))
* run the released image as production, and as a user the kubelet can check ([88ed098](https://github.com/elct9620/workers-rb/commit/88ed09800c5bad8dfdcb321a1e8423f8419f497f))


### Continuous Integration

* keep the chart's comments through a release, and its appVersion true ([1c7aef7](https://github.com/elct9620/workers-rb/commit/1c7aef78ba2830be2dc3793a77071a3f3a602c6d))
