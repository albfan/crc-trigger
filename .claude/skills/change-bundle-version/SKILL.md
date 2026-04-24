---
name: change-bundle-version
description: Update the bundle version (openshift or microshift) in the config-crc-release ConfigMap used by nightly test suites. Use this skill whenever the user mentions changing, updating, or bumping the bundle version, OCP version, or microshift version for nightly runs, or wants to see what bundle versions are currently configured in the ConfigMap. Also trigger when the user references config-crc-release or nightly bundle configuration.
---

# Change Bundle Version

Update the OCP or microshift bundle version in the `config-crc-release` ConfigMap. This ConfigMap controls which bundle version the nightly test suite runs against.

The script `crc-change-bundle-version` in the repo root handles the patch. This skill guides the full workflow: inspect current state, validate the new version exists, apply the change, and confirm.

## Workflow

### 1. Parse the request

Extract two things from what the user said:

- **Bundle type**: `openshift` or `microshift`
  - "OCP", "ocp", "openshift" all mean `openshift`
  - "microshift" means `microshift`
- **Bundle version**: format `X.Y.Z` (e.g., `4.21.10`)

If either is missing or ambiguous, ask before proceeding.

### 2. Show current state

Display the ConfigMap so the user can see what's currently configured:

```bash
oc get cm config-crc-release -o yaml | oc neat
```

Point out the current value of the field that's about to change (`ocp-version` or `microshift-version`).

### 3. Validate the bundle exists

Check that the bundle is available on the build server before patching:

```bash
curl -s -fI -o /dev/null -w "%{http_code}" \
  "https://cdk-builds.usersys.redhat.com/builds/crc/bundles/<bundle-type>/<version>/sha256sum.txt"
```

Replace `<bundle-type>` with `openshift` or `microshift`, and `<version>` with the target version.

- **200**: bundle exists, proceed.
- **Anything else**: warn the user that the bundle doesn't appear to be available at that URL. Ask whether they want to proceed anyway or abort.

### 4. Apply the change

Run from the repo root:

```bash
./crc-change-bundle-version <bundle-type> <version>
```

Where `<bundle-type>` is `openshift` or `microshift` and `<version>` is the target version (e.g., `4.21.10`).

The script patches the ConfigMap and prints the updated YAML.

### 5. Summarize the change

After the script runs, highlight what changed:
- Field name (`ocp-version` or `microshift-version`)
- Previous value
- New value
