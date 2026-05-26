---
name: manage-errata
description: Manage Red Hat errata advisories for CRC bundle releases. Use this skill when the user mentions errata, advisory, QE ACK, REL_PREP, or wants to check/approve/move an errata advisory after nightly test results pass. Also trigger when the user references errata.devel.redhat.com or asks about the status of a bundle release errata.
---

# Manage Errata

Check and ACK Red Hat errata advisories for CRC bundle releases. After nightly test results pass, the QE workflow is: add a "QE ACK" comment and move the advisory from QE to REL_PREP.

The errata API uses Kerberos authentication — a valid `kinit` ticket is required.

## Errata API

The errata URL is stored in ConfigMap `errata-info` (namespace `devtoolsqe--pipeline`), key `url`.

### Retrieve connection details

Before making API calls, fetch the URL and verify Kerberos:

```bash
ERRATA_URL=$(oc get cm errata-info -n devtoolsqe--pipeline -o jsonpath='{.data.url}')
klist 2>&1 | head -5
```

If the Kerberos ticket is expired or missing, ask the user to run `kinit` in a separate terminal (Claude cannot handle the interactive password prompt).

Use `$ERRATA_URL` in all subsequent curl calls.

## Workflow

### 1. Parse the request

Extract the **errata ID** from what the user said. It may come as:
- A number: `167277`
- A URL: `$ERRATA_URL/advisory/167277`
- A reference to a bundle version: "errata for 4.21.14" — in this case ask the user for the errata ID

### 3. Check current state

```bash
curl -s --negotiate -u : "$ERRATA_URL/api/v1/erratum/<id>" \
  | jq '.errata | to_entries[0].value | {id, synopsis, status, publish_date}'
```

Show the user the advisory synopsis, current status, and publish date.

The errata type varies (`.rhea`, `.rhba`, `.rhsa`), so use `to_entries[0].value` to handle any type.

### 4. ACK the errata

Only proceed if the advisory is in **QE** status. If it's already in REL_PREP or later, inform the user.

Always confirm with the user before executing these steps:

**Step 1 — Add QE ACK comment:**

```bash
curl -s --negotiate -u : \
  -H 'Content-Type: application/json' \
  -d '{"comment": "QE ACK"}' \
  -X POST \
  "$ERRATA_URL/api/v1/erratum/<id>/add_comment"
```

**Step 2 — Change state to REL_PREP:**

```bash
curl -s --negotiate -u : \
  -H 'Content-Type: application/json' \
  -d '{"new_state": "REL_PREP"}' \
  -X POST \
  "$ERRATA_URL/api/v1/erratum/<id>/change_state"
```

### 5. Confirm

After both steps, fetch the advisory again to verify the state changed:

```bash
curl -s --negotiate -u : "$ERRATA_URL/api/v1/erratum/<id>" \
  | jq '.errata | to_entries[0].value | {id, synopsis, status}'
```

Report the final status to the user.
