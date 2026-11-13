# Provision Failure Analysis — Failure-mode field notes

Notes on failure modes seen in earlier investigations (2026-07 to 2026-11). They
are **priors, not rules**: a way to generate hypotheses and queries faster. A
matching signature does not establish the cause. Test the note against the run in
front of you, state whether it held, and say so when it did not.

- Absence of a match is normal. Investigate from the evidence (SKILL.md, "When nothing matches").
- Check anything marked "may be stale" in the current repo before relying on it.
- Some "how to separate it" steps use Azure (Activity Log, `az vm list-skus`,
  `az vm list-usage`). Azure read access cannot be assumed; see SKILL.md. Without
  it, report the step as not examined.
- Entries marked *seen once* come from a single investigation.
- Entry format: **Signature** → **What it was** → **How to separate it** → **Cautions**.
- Maintenance: the process for adding entries is not defined yet. Each entry
  should carry a signature, evidence, a date, and a query to re-verify it.

## Primary error hidden by fallout

**Signature:** `failed to lookup subscription ID`, `failed to get next page of
subscriptions: context canceled`, a `ResourceGroupNotFound` from
`gather-observability`, errgroup cancellation.
**What it was:** downstream of an earlier failure (for example an empty-digest
image-mirror failure; a templatize stamped-graph error recorded as an
alert-collection error).
**How to separate it:** read the raw step `build-log.txt` for the earliest error
and exclude it before treating these as primary. If a retry fails with a different
error, there are two defects.
**Cautions:** do not make an observability collector tolerate
`ResourceGroupNotFound` to hide the symptom.

## Same Helm or timeout text, several causes

**Signature:** Helm `Available: 0/1 ... context deadline exceeded`; a `Deployment/... Progress deadline exceeded`; `CreateHCPClusterAndWait; context deadline exceeded`.
**What it was:** at least a kubelet credential-provider hang, a deterministic
crash-loop (see next entry), etcd PV attach stalls, and a node freeze preceded by an NVMe I/O timeout.
**How to separate it:** pod-level Kusto evidence per occurrence; compare with
successful runs of the same job; measure a candidate log signature's sensitivity and specificity over healthy and failed nodes.
**Cautions:** a failed Tide batch is "flake or bad interaction between PRs in the batch".

## Helm rollout crash-loops on unknown flags

**Signature:** `Progress deadline exceeded` plus pod crash-loop (`unknown flag: --cluster-types`).
**What it was:** the chart was newer than the static image digest in `config/config.yaml`; the
job's step registry did not build and override the component image.
**How to separate it:** compare the chart's arguments with the deployed digest; inspect the step that
resolves `pipeline:*` or `*_IMAGE` and writes the override that provision consumes.
**Cautions:** every other job that consumes the same pipeline may share the defect.

## Throttling or capacity text in output

**Signature:** ARM 429 inside node-pool timeouts; `SubscriptionRequestsThrottled`; several regions failing the same ARM step at once.
**What it was:** in the cases seen, a mix. Some were real throttling, some
were capacity or unrelated deadlines, and some counts came from runs that never reached the creating stage.
**How to separate it:** group by terminal error and by the operation still `Running` at the deadline;
pull Activity Log for representative correlation IDs; read `x-ms-ratelimit-remaining-subscription-reads`
and `Retry-After`; reconcile code-derived cost estimates against independent volume (ARM and Kusto counts times runs).
**Cautions:** a throttle bucket (per principal vs aggregate) is an inference until the actor ID maps to a
concrete credential. Teardown can mask the backend error (`AKSOperationPreemptedByDelete`); then say the backend cause is unknown.

## ARM 429 or deadline in an acquire/admission step

**Signature:** `aro-hcp-lease-acquire` with 429 and `failed deleting role assignment ... context deadline exceeded` under a shared budget (acquire over 60 containers took 8 of 10 minutes).
**What it was:** too many ARM calls per slot.
**How to separate it:** quantify calls before and after a change; compute requests per second per subscription and per
principal against the documented limits using observed latency and worst-case concurrent slots (`e2e-slots.yaml`).
**Cautions:** timeouts do not fix tenant-wide throttling. If the step's own log is empty (see below), fix capture first.

## Empty step log

**Signature:** a 0-byte log for the failing step (slot-manager `lease-acquire` on PR runs).
**What it was:** a change in log capture, which made throttling and slow cleanup indistinguishable.
**How to separate it:** find what changed in capture; require request-level logging (operation duration, retries) before choosing between a timeout bump and volume reduction.

## SKU or region restriction

**Signature:** `NotAvailableForSubscription`, "selector matched no usable VM size", `InvalidRequestContent` "Machine type ... is not supported".
**What it was:** sometimes a real subscription restriction, sometimes the test's own SKU filter or an RP allowlist mismatch.
**How to separate it:** confirm the SKU listing is complete (paging, row count); compare the same
SKU/region against a healthy subscription; separate quota (`az vm list-usage`) from restriction;
separate "the filter rejected everything" from "Azure cannot allocate".
**Cautions:** a live listing that contradicts earlier CI-log evidence is an unknown. Any exclusion is temporary.
Verify a ticket's assumed platform behavior empirically before implementing it.

## Admission/lease failure on leftover state, or a limit suddenly exceeded

**Signature:** `aro-hcp-lease-acquire` failing with hundreds of dangling role assignments; `RoleAssignmentLimitExceeded` on a limit that long fit.
**What it was:** both a leak from an earlier run's teardown and, in another case, a per-unit cost increase
(role assignments per hosted cluster rose from 24 to 26 after a PR) with no leak at all.
**How to separate it:** find the run that last leased the slot (`createdOn`, scopes, run log, its slot-manager
`build-log.txt`) and show why teardown missed things. Then test the leak theory with evidence. If unsupported,
recompute the capacity model (identities x role assignments x containers x concurrent jobs + reserve) and bisect `git log` for the cost change.
**Cautions:** a longer admission timeout does not stop a leak.

## Reused or leased infrastructure arrives dirty

**Signature:** pooled identity bundles with leftover federated credentials or role assignments after a crashed job; a global name (a DNS zone) reused while an async delete is still running (`The zone '...' is not available`).
**What it was:** state left by a crashed or no-cleanup path.
**How to separate it:** verify the crash and no-cleanup path. Look for the invariant that should hold at acquisition time.
**Cautions:** post-job cleanup ordering alone does not cover the crash path. A design that adds delete-then-create churn can itself create a failure class.

## Concurrent-write conflicts on shared resources

**Signature:** 409-style errors: `DeploymentStackInNonTerminalState`, `InvalidStateForUpdating`, `UpdateConflict`, `ConflictingConcurrentWriteNotAllowed`, `DeploymentActive`, `ConflictError`.
**What it was:** per-job (Region entrypoint) steps writing resources owned by the Global or Geography layer; in another case a per-job name (job ID in the resource-group name) that
pointed to an intra-job templatize race, not topology.
**How to separate it:** read `topology.yaml`, the owning `pipeline.yaml`, and `docs/ci/execution.md`. Identify
which resource the racing writers ultimately touch and whether a fixed name is an intentional lock.
**Cautions:** a retry or per-attempt unique names move the race down a layer.

## CI script and ARM template own the same resource

**Signature:** a CI-created resource (an NSG rule) disappears and a later call fails (`dial tcp ...:443 i/o timeout`) in an in-place-upgrade job.
**What it was:** the upgrade re-ran the Bicep that owns the NSG; templatize skips the step on unchanged hashes on `main` but redeploys on PRs with changed inputs.
**How to separate it:** find which ci-operator step and pod makes the call; check whether templatize skips the step on unchanged hashes and which calls (including failure-path cleanup) hit the resource during redeployment.
**Cautions:** acceptance needs a real redeploy of the owning template, not another cache hit.

## Transient or load-sensitive platform dependency

**Signature:** IMDS/ACR credential-provider hangs; hard-freezing management VMs; alerts whose metrics vanish at teardown.
**What it was:** unproven in most cases seen.
**How to separate it:** look at data already in Kusto first, then at Activity Log and Resource Health. Report only the timestamped event sequence unless the cause is shown.
**Cautions:** do not propose always-on probes or live replication. Prefer a one-shot, failure-triggered
diagnostic in the Helm failure path that records status and timing only (never token bodies). Platform metrics vanish with the resource.

## Failure in a component being removed

**Signature:** `DeploymentScriptACIProvisioningTimeout` (an ACI-backed Bicep `deploymentScript` that never provisioned, about 21 min, then the retry hit the 30-minute step context).
**What it was:** a component being migrated to native pipeline shell steps (may be stale).
**How to separate it:** check open PRs and Jira for the migration before proposing anything.
**Cautions:** if it is being removed, propose no timeout, retry, or IcM change for it.

## Mitigation merged but pattern persists

**Signature:** the same pattern after a retry or timeout fix merged.
**What it was:** in one case the mitigation never engaged because a 404 returned as `resp, nil` by the SDK transport does not trigger an error-based retry policy; in others the error text did not reach `errorContainsAny` after wrapping.
**How to separate it:** failure duration against the backoff schedule; repeated GETs in the per-run logs; test fidelity against the real SDK transport.
**Cautions:** a moved failing read is not a fix.

## Fan-out ARM deployments

**Signature:** `DeploymentFailed: aggregated deployment error is too large`; nested `Microsoft.Graph/servicePrincipals` `Request_ResourceNotFound` (replication lag); `DeploymentQuotaExceeded` (800 deployments per resource group), in a 100+ item Bicep loop.
**What it was:** batching combined with retry budget: each failed batch consumes a retry, and `maximumRetryCount` counts total executions.
**How to separate it:** check `@batchSize` and whether `maximumRetryCount` is at least `ceil(poolSize/batchSize)+1` and `errorContainsAny` covers the aggregated text.
**Cautions:** removing batching does not help.

## Low-rate identity-permission failure (seen once)

**Signature:** `AzureKeyVaultKmsValidateIdentityPermissionCustomerError` on AKS creation in about 3% of runs; identities validated at lease admission; the retry then failed in `svc-cluster.bicep` because ARM would not read the existing Failed cluster (2026-11).
**What it was:** judged an RBAC propagation race. The reasoning was statistical: validated identities plus a low non-deterministic rate would not fail deterministically.
**How to separate it:** compute the rate across runs, check for interleaved successes in the same region, and independent runs on different SHAs.
**Cautions:** report it as *supported by rate*, not proven. Report the recovery blocker as a second failure mode. This does not show a PR fixes the original cause.

## AKS update rejected by the managing tool

**Signature:** `PropertyChangeNotAllowed: Changing property 'properties.vmSize' ...` on a postsubmit pipeline (2026-11).
**What it was:** the tool sent an API version that could not perform the operation.
**How to separate it:** check what the managing tool (Go AKS tool or Bicep) supports and which API version it sends, not only the Azure error text.
**Cautions:** use the API version the maintainers specify, not merely the minimum the error names.

## Regression spike attributed to a merged PR

**Signature:** a pattern spiking in one window (for example `cluster deletion did not complete before the deadline`, a teardown failure) with a suspect PR.
**How to separate it:** first only onset, recurrence, and PR-metadata correlation. Do not name a PR from timing and PR text alone. Then trace code. Then read the step logs (`ciTestResults.message`) of 2 or 3 runs (earliest onset, the suspect PR's pre-merge run, a post-merge spike run) and count distinct runs and distinct PRs to separate a shared regression from a PR-specific bug.
**Cautions:** consider a human review checkpoint before the code trace.

## Controller re-reconcile in an SLO-style e2e (seen once, low confidence)

**Signature:** the failing hosted cluster hit a double OAS rollout (a config-hash change from the control-plane PKI operator).
**What it was:** an ordinary re-reconcile that converges; the product behaved as designed.
**How to separate it:** check whether the end state converged and whether the e2e measures an SLO budget.
**Cautions:** the likely fix is test-side (headroom, timeout, final GET), not a product-code change. Do not generalize beyond SLO-type tests.

## Generic error with the nested detail lost (seen once)

**Signature:** `ERROR CODE: DeploymentFailed` with no detail code or provider, wrapped as `failed to poll previously-existing deployment: pre-existing deployment failed`, on `rp-upgrade` in `e2e-parallel-inplace-upgrade` (24 runs over 4 days, 2026-11). The step failed 1–3 seconds after it started, and the preceding cluster-create step had succeeded.
**What it was:** the original failure was not recoverable from the evidence. In `tooling/templatize/pkg/pipeline/arm.go`, the rejected-state path of `pollAndGetOutputFromExistingDeployment` returns nil operation details and the caller returns nil too, so `run.go` has nothing to collect. The failure gather (`openshift/release` step `aro-hcp-gather-provision-failure`) exits early when the baseline's `provision-from-main-complete` marker exists, so the upgrade's failure got no gather data either. The ARM provisioning state and the nested provider error are in neither Kusto nor the Prow artifacts. Whether the 24 runs share one cause was unknown.
**How to separate it:** pair the wrapper text with the step's duration, the preceding step's outcome, the nearest successful run of the same job, and a read of the source that builds the error (is the nested error or the details callback dropped?). Do not pick a retry or timeout from the generic code; a fast terminal rejection is not helped by a longer timeout.
**Cautions:** the right outcome here is a diagnostics change at the points of loss (propagate details on the error path, extend the gather condition to the upgrade phase), not a mitigation and not `inconclusive`. After it ships, re-read the next occurrences to see the real provider error.

## Reading across the notes

Things that recur: an early error hidden by later fallout; one message covering several causes; a
mitigation that never engaged; a cost or limit change that looked like a leak; shared state written from the wrong layer. When your finding looks like one of these, test it. When it looks like none, say so in the report.
