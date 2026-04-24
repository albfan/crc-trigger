# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Bash-based CI/CD orchestration toolkit for triggering **Tekton pipeline runs** that test [CRC (Code Ready Containers)](https://github.com/crc-org/crc) across multiple platforms (Windows, macOS ARM/AMD, Linux AMD/ARM). Scripts generate Tekton `PipelineRun`/`TaskRun` YAML from templates and apply them to an OpenShift cluster in the `devtoolsqe-pipeline` namespace.

Pipeline definitions live in a separate repo: `github.com/crc-org/ci-definitions.git` (referenced via Tekton git resolver).

## Key Scripts

| Script | Purpose |
|--------|---------|
| `crc-latest-new.sh` | Main entry point. Generates and applies PipelineRun YAML for CRC testing. Supports purposes: `bundle-test`, `interop-test`, `nightly-run`, `crc-pr-test`, `snc-pr-test` |
| `bundle-create.sh` | Creates PipelineRuns for building CRC bundles from specific OCP/SNC versions |
| `crc-release-test.sh` | Orchestrates CRC release testing on bare metal and virtualized environments |
| `upload-bundle-s3.sh` | Creates TaskRun to upload bundles to S3 (`crcqe-asia` bucket) |
| `trigger-macadam.sh` | Triggers macadam cross-platform tests (Windows, macOS, Linux) |
| `trigger-ocp-nightly-run.sh` | Reads ConfigMaps and triggers nightly OCP test runs |
| `crc-change-bundle-version` | Updates bundle version (openshift/microshift) in `config-crc-release` ConfigMap for nightly runs |
| `track-taskrun-created` | Interactive utility to follow Tekton TaskRun logs via `tkn` |

## Architecture

1. **Template-based generation**: Scripts copy YAML templates from `template/` and use `sed` to substitute parameters (bundle version, platform, PR number, etc.)
2. **Generated output**: Substituted YAML goes into `test/` (gitignored), then gets applied with `oc create -f`
3. **URL verification**: Scripts verify that bundle/OCP URLs exist (via `curl --head`) before creating pipeline runs
4. **Date-stamped S3 paths**: Results are stored under paths like `nightly/crc/YYYYMMDD/<version>/<platform>`

## Common Workflows

See `README.md` for full examples. Key patterns:

```bash
# Bundle creation + test (interop)
./bundle-create.sh -v 4.17.14
./crc-latest-new.sh -p interop-test -b 4.17.14

# Bundle release test (openshift preset)
./upload-bundle-s3.sh 4.17.14
./crc-latest-new.sh -p bundle-test -b 4.17.14 --preset openshift

# CRC release test
./crc-release-test.sh 2.48.0

# PR testing
./crc-latest-new.sh -p crc-pr-test -b 4.17.14 --pr 4620

# Change nightly bundle version
./crc-change-bundle-version openshift 4.21.10
./crc-change-bundle-version microshift 4.21.10
```

## Important Constraints

- **Never run `mac-arm` and `mac-amd` simultaneously** -- they share one builder machine
- **Never run `openshift` and `microshift` presets simultaneously** -- they share the same bare metal machine
- Pipeline timeouts are 5-8 hours

## Required CLI Tools

`bash`, `oc` (OpenShift CLI), `tkn` (Tekton CLI), `curl`, `wget`, `sed`, `awk`, `jq`

## Shell Conventions

- No package manager or build system -- pure bash scripts
- Bash completion available in `etc/crc-latest-new.completion`
- `awk_function` is a shared AWK helper for parsing download/upload progress output
