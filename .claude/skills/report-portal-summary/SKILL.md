---
name: report-portal-summary
description: Summarize CRC test results from Report Portal. Use this skill whenever the user asks about test results, nightly results, launch status, test summary, Report Portal, or wants to know what passed/failed in recent test runs. Also trigger when the user mentions nightly summary, test report, launch results, flaky tests, or asks about results for a specific bundle version, platform, or test purpose (bundle-test, interop-test, nightly-run, crc-pr-test, snc-pr-test).
---

# Report Portal Summary

Query the Report Portal API to fetch and summarize CRC test launch results. Tests run across multiple platforms (linux-amd64, linux-arm64, darwin-amd64, darwin-arm64, windows-amd64) and presets (openshift, microshift).

## Report Portal API

Connection details are stored in OpenShift secret `reportportal-crc` (namespace `devtoolsqe--pipeline`) with keys: `url`, `project`, `token`.

### Retrieve connection details

Before making API calls, fetch all values from the secret:

```bash
RP_URL=$(oc get secret reportportal-crc -n devtoolsqe--pipeline -o jsonpath='{.data.url}' | base64 -d)
RP_PROJECT=$(oc get secret reportportal-crc -n devtoolsqe--pipeline -o jsonpath='{.data.project}' | base64 -d)
RP_TOKEN=$(oc get secret reportportal-crc -n devtoolsqe--pipeline -o jsonpath='{.data.token}' | base64 -d)
```

API prefix: `$RP_URL/api/v1/$RP_PROJECT`

Use `Authorization: Bearer $RP_TOKEN` in all subsequent curl calls.

## Workflow

### 1. Parse the request

Determine what launches to fetch based on what the user said:

| User says | Filter |
|-----------|--------|
| "last nightly", "nightly summary", "nightly results" | `filter.eq.description=nightly-run`, latest 10 launches |
| A specific platform (e.g. "linux arm64 results") | `filter.cnt.name=<platform>` |
| A specific launch ID | `filter.eq.id=<id>` |
| A specific bundle version (e.g. "results for 4.21.14") | Fetch recent launches, then filter by `bundle-version` attribute |
| A specific purpose (e.g. "interop-test results") | `filter.eq.description=<purpose>` |
| "test results", "show results" (no qualifier) | Default to latest nightly: `filter.eq.description=nightly-run`, latest 10 |

### 2. Fetch launches

```bash
curl -s -H "Authorization: Bearer $RP_TOKEN" \
  "$RP_URL/api/v1/$RP_PROJECT/launch?page.size=10&page.sort=startTime,desc&<filters>" \
  | jq .
```

Replace `<filters>` with the appropriate query parameters from step 1.

Each launch contains:
- `name`: e.g. `crc-openshift-linux-amd64` (format: `crc-<preset>-<os>-<arch>`)
- `description`: the test purpose (e.g. `nightly-run`)
- `statistics.executions`: `{total, passed, failed, skipped}`
- `attributes`: array with `bundle-version`, `crc-version`, `preset` keys

### 3. Fetch failing tests

For each launch where `statistics.executions.failed > 0`, fetch the failed test items:

```bash
curl -s -H "Authorization: Bearer $RP_TOKEN" \
  "$RP_URL/api/v1/$RP_PROJECT/item?filter.eq.launchId=<id>&filter.eq.status=FAILED&isLatest=false&launchesLimit=0&page.size=50" \
  | jq '[.content[] | {name, status}]'
```

Fetch all failed launches in parallel where possible.

### 4. Classify failures

Compare the actual failed count from `statistics.executions.failed` against the failed items returned. Some items are parent suites that show FAILED because a child failed — the `statistics.executions.failed` count is the real number of test failures.

#### Known flaky patterns

| Pattern | How to identify | Flaky label |
|---------|-----------------|-------------|
| **JKube deploy timeout** | Failed item name contains "Deploy a java application using Eclipse JKube in pod and then verify it's health" | `JKube deploy` |
| **CRC start / SSH failure** | Many failures (typically 5+) AND failed items include infrastructure tests like "CRC start usecase", "Basic test", "CRC version", "Overall cluster health", "Test configuration settings" | `crc start failed (SSH unreachable)` |

#### Status logic

- `failed == 0` → ✅
- `failed > 0` AND all failures match a known flaky pattern → ✅❓
- `failed > 0` AND some failures are NOT flaky → ❌

When a launch has only 1 failure and it matches the JKube test → ✅❓ with flaky `JKube deploy`.

When a launch has many failures and they're all infrastructure tests cascading from a failed CRC start → ✅❓ with flaky `crc start failed (SSH unreachable)`.

Note: Report Portal marks launches as FAILED when `skippedIssue=true` and tests are skipped, even with 0 actual failures. Ignore the launch-level status and use the `statistics.executions.failed` count instead.

### 5. Present results

Group launches by preset (extract from launch name: `crc-<preset>-<os>-<arch>` or from the `preset` attribute). Show the bundle version used (from attributes).

#### Table format

For each preset, show a table:

```
### <Preset> preset (bundle `<version>`)

| Platform | Passed | Failed | Skipped | Total | Flaky | Status |
|----------|--------|--------|---------|-------|-------|--------|
| **<os>-<arch>** | N | N | N | N | <reason or empty> | ✅/✅❓/❌ |
```

Bold the failed count when it's > 0 and the status is ❌.

After the tables, add a brief summary highlighting any platforms with real (non-flaky) failures.

### 6. Drill-down

If the user asks to dig into specific failures, fetch the failed items for that launch and list the test names with their failure details. Use:

```bash
curl -s -H "Authorization: Bearer $RP_TOKEN" \
  "$RP_URL/api/v1/$RP_PROJECT/item/<item-id>/log?page.size=5&page.sort=logTime,desc" \
  | jq '[.content[] | {message, level}]'
```
