# Changelog

## [0.4.0](https://github.com/elct9620/workers-rb/compare/v0.3.0...v0.4.0) (2026-08-02)


### Features

* **chart:** keep the Hosts off one machine while there is another ([07a456c](https://github.com/elct9620/workers-rb/commit/07a456c61c3924b31812f5524e5f647fb3758c07))

## [0.3.0](https://github.com/elct9620/workers-rb/compare/v0.2.0...v0.3.0) (2026-08-02)


### Features

* bound how long a Host may take to stop ([aa23b9e](https://github.com/elct9620/workers-rb/commit/aa23b9eee515b1b48b81cd83c3dc7393ada02ecf))
* **chart:** say what each workload costs the machine it runs on ([d65b632](https://github.com/elct9620/workers-rb/commit/d65b632ef540f55cbd8fe70e85f012191e4ae315))


### Bug Fixes

* answer the connections already waiting when a Host is told to stop ([2b9f169](https://github.com/elct9620/workers-rb/commit/2b9f169ef74aa00b9c4ad9363fde7b14e35c0ea8))
* **chart:** drop the wait a Host kept before hearing it should stop ([2ad65dd](https://github.com/elct9620/workers-rb/commit/2ad65ddaf7b95f1d4ccf09e63b9f9b84bf4c0cb7))
* **chart:** let a raised stop bound be the one that ends the stop ([38b15b8](https://github.com/elct9620/workers-rb/commit/38b15b87cadc7e5facf066d1b126a2e336c0b6c5))
* **chart:** stop replacing a Host for a mount a replacement would inherit ([890e608](https://github.com/elct9620/workers-rb/commit/890e608d9efc08d6c9d4550fdbc2c719cb7cd53b))

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
