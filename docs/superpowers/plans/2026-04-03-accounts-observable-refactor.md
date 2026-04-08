# Accounts Observable Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the `Accounts` page to use `@Observable` page and row models so macOS scrolling is less affected by broad state fan-out during background refresh activity.

**Architecture:** Keep `AccountsPageModel` as the single business-state source. Replace the current aggregate `AccountsPageViewStore.contentPresentation` plus `AccountCardStore` pipeline with a lightweight `@Observable` page UI state object and stable per-card row models, then update the `Accounts` view tree to read only the properties each section actually needs.

**Tech Stack:** Swift 6, SwiftUI, Observation (`@Observable`), XCTest, Swift Package Manager, existing `Accounts` feature structure.

---

### Task 1: Establish a Clean Test Baseline for the Accounts View-State Refactor

**Files:**
- Modify: `Sources/CodeXPool/Features/Accounts/AccountsPageViewStore.swift`
- Test: `Tests/CodeXPoolTests/AccountsCoordinatorTests.swift`

- [ ] **Step 1: Write the failing test**

Add a focused test near the existing `AccountsPageViewStore` tests in `Tests/CodeXPoolTests/AccountsCoordinatorTests.swift` that constructs the current `AccountsPageViewStore` and proves the test target can compile and instantiate it without relying on the current debug trace implementation details.

Use the existing helper at `Tests/CodeXPoolTests/AccountsCoordinatorTests.swift:4511` onward (`makeAccountsPageModelForViewStoreTests`) rather than introducing a new test fixture.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AccountsCoordinatorTests/testAccountsPageViewStoreDoesNotRepublishContentForNoticeChanges`

Expected: FAIL at compile time because `Sources/CodeXPool/Features/Accounts/AccountsPageViewStore.swift` contains the current debug trace static mutable state that is not concurrency-safe.

- [ ] **Step 3: Write minimal implementation**

Adjust `Sources/CodeXPool/Features/Accounts/AccountsPageViewStore.swift` so the debug trace helper is concurrency-safe and does not block the test target from compiling.

Constraints:
- Keep the current tracing behavior intact
- Do not change runtime logic unrelated to trace safety
- Use the smallest possible change

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AccountsCoordinatorTests/testAccountsPageViewStoreDoesNotRepublishContentForNoticeChanges`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CodeXPool/Features/Accounts/AccountsPageViewStore.swift Tests/CodeXPoolTests/AccountsCoordinatorTests.swift
git commit -m "test: restore accounts view store baseline"
```

### Task 2: Replace Aggregate Page Presentation Tests with Property-Scoped UI State Tests

**Files:**
- Modify: `Tests/CodeXPoolTests/AccountsCoordinatorTests.swift`
- Reference: `Sources/CodeXPool/Features/Accounts/AccountsPagePresentation.swift`
- Reference: `Sources/CodeXPool/Features/Accounts/AccountsPageViewStore.swift`

- [ ] **Step 1: Write the failing test**

Replace or supplement the current `contentPresentation`-centric tests with tests that assert the new target behavior:

- single-card refresh activity changes only the affected row model
- pending workspace changes do not alter grid structure
- row model instances remain stable across unrelated updates
- visible card order changes update the structural card ID list

Write the tests first, using current names as a guide but targeting the new page UI state API you intend to create.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AccountsCoordinatorTests/testAccountsPage`

Expected: FAIL because the new page UI state API and row model API do not exist yet.

- [ ] **Step 3: Write minimal implementation**

Create just enough placeholder API in the `Accounts` view-state layer to let the tests compile against the intended names and shapes. Do not perform the full migration in this step.

Suggested minimum API surface:
- observable page UI state object
- observable row model type
- structural properties (`visibleCardIDs`, `pendingWorkspaceCards`, `pendingWorkspaceError`, `isOverviewMode`)
- `cardModel(id:)`

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AccountsCoordinatorTests/testAccountsPage`

Expected: Some tests still fail logically, but compile succeeds and the failures are now behavior failures, not missing-symbol failures.

- [ ] **Step 5: Commit**

```bash
git add Tests/CodeXPoolTests/AccountsCoordinatorTests.swift Sources/CodeXPool/Features/Accounts/AccountsPageViewStore.swift Sources/CodeXPool/Features/Accounts/AccountsPagePresentation.swift
git commit -m "test: define accounts observable state expectations"
```

### Task 3: Implement Observable Page UI State and Stable Row Models

**Files:**
- Modify: `Sources/CodeXPool/Features/Accounts/AccountsPageViewStore.swift`
- Modify: `Sources/CodeXPool/Features/Accounts/AccountsPagePresentation.swift`
- Optionally Create: `Sources/CodeXPool/Features/Accounts/AccountsPageUIState.swift`
- Optionally Create: `Sources/CodeXPool/Features/Accounts/AccountCardRowModel.swift`
- Test: `Tests/CodeXPoolTests/AccountsCoordinatorTests.swift`

- [ ] **Step 1: Write the failing test**

Add or tighten a test that proves a single refresh-state change no longer requires full-card projection rebuild semantics:

- create two visible accounts
- capture `cardModel("acct-1")` and `cardModel("acct-2")`
- mutate `model.refreshingAccountIDs = ["acct-2"]`
- assert `acct-1` model identity is stable
- assert `acct-2` model updates `refreshing == true`
- assert `visibleCardIDs` is unchanged

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AccountsCoordinatorTests/testAccountsPageObservable`

Expected: FAIL because the current implementation still uses the old aggregated store behavior.

- [ ] **Step 3: Write minimal implementation**

Implement the new page UI state layer:

- keep `AccountsPageModel` as the only business-state source
- replace `@Published contentPresentation` with property-based state
- maintain stable row model instances keyed by account ID
- update only the changed row models when account-local inputs change
- update structural properties only when structure actually changes
- keep pending workspace properties separate from grid structure properties

Remove old code only when the new path is active and covered.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AccountsCoordinatorTests/testAccountsPageObservable`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CodeXPool/Features/Accounts/AccountsPageViewStore.swift Sources/CodeXPool/Features/Accounts/AccountsPagePresentation.swift Sources/CodeXPool/Features/Accounts/AccountsPageUIState.swift Sources/CodeXPool/Features/Accounts/AccountCardRowModel.swift Tests/CodeXPoolTests/AccountsCoordinatorTests.swift
git commit -m "refactor: adopt observable accounts page state"
```

### Task 4: Move the Accounts View Tree to the New Observation Boundaries

**Files:**
- Modify: `Sources/CodeXPool/Features/Accounts/AccountsPageView.swift`
- Modify: `Sources/CodeXPool/Features/Accounts/AccountsPageShells.swift`
- Modify: `Sources/CodeXPool/Features/Accounts/AccountsPageSections.swift`
- Modify: `Sources/CodeXPool/Features/Accounts/AccountCardView.swift`
- Test: `Tests/CodeXPoolTests/AccountsCoordinatorTests.swift`

- [ ] **Step 1: Write the failing test**

Add a test or assertion-oriented helper coverage that proves pending workspace changes and card-structure changes are read through different properties on the new page UI state.

At minimum, add a test for:
- pending workspace mutation changes pending properties
- `visibleCardIDs` remains unchanged

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AccountsCoordinatorTests/testAccountsPagePending`

Expected: FAIL because the SwiftUI layer still depends on the old aggregate interfaces.

- [ ] **Step 3: Write minimal implementation**

Update the view tree so that:

- `AccountsPageView` owns the new page UI state object
- `AccountsMacContentHost` and `AccountsIOSContentHost` receive the new page UI state object
- pending workspace section reads only pending workspace properties
- grid section reads only `visibleCardIDs`, `isOverviewMode`, layout inputs, and per-card row models
- `AccountCardView` consumes the row model or a narrow row projection sourced from that row model

Do not widen parents by reading row-local state in section/container views.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AccountsCoordinatorTests/testAccountsPage`

Expected: PASS for the view-state tests

- [ ] **Step 5: Commit**

```bash
git add Sources/CodeXPool/Features/Accounts/AccountsPageView.swift Sources/CodeXPool/Features/Accounts/AccountsPageShells.swift Sources/CodeXPool/Features/Accounts/AccountsPageSections.swift Sources/CodeXPool/Features/Accounts/AccountCardView.swift Tests/CodeXPoolTests/AccountsCoordinatorTests.swift
git commit -m "refactor: narrow accounts page observation boundaries"
```

### Task 5: Remove Legacy Aggregate Presentation Path

**Files:**
- Modify: `Sources/CodeXPool/Features/Accounts/AccountsPagePresentation.swift`
- Modify: `Sources/CodeXPool/Features/Accounts/AccountsPageViewStore.swift`
- Modify: `Sources/CodeXPool/Features/Accounts/AccountsPageSections.swift`
- Test: `Tests/CodeXPoolTests/AccountsCoordinatorTests.swift`

- [ ] **Step 1: Write the failing test**

Add one cleanup-oriented test that ensures no legacy aggregate page presentation API is required by the `Accounts` page path.

This can be expressed by removing the last test references to `contentPresentation` / `AccountCardStore` and letting the test target fail until the production code no longer depends on them.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AccountsCoordinatorTests/testAccountsPage`

Expected: FAIL because production code still exposes or uses legacy aggregate interfaces.

- [ ] **Step 3: Write minimal implementation**

Delete the legacy path once the new one is fully active:

- remove `contentPresentation`
- remove `AccountCardStore`
- remove obsolete projection helpers that existed only for the old aggregate store path
- keep only helpers still used by the new observable page or row models

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AccountsCoordinatorTests/testAccountsPage`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CodeXPool/Features/Accounts/AccountsPagePresentation.swift Sources/CodeXPool/Features/Accounts/AccountsPageViewStore.swift Sources/CodeXPool/Features/Accounts/AccountsPageSections.swift Tests/CodeXPoolTests/AccountsCoordinatorTests.swift
git commit -m "refactor: remove legacy accounts aggregate state"
```

### Task 6: Verify Behavior and Capture Performance Evidence

**Files:**
- Reference: `Sources/CodeXPool/Features/Accounts/AccountsPageViewStore.swift`
- Reference: `Sources/CodeXPool/App/RootScene.swift`
- Reference: `docs/superpowers/specs/2026-04-03-accounts-observable-refactor-design.md`

- [ ] **Step 1: Run focused tests**

Run: `swift test --filter AccountsCoordinatorTests/testAccountsPage`

Expected: PASS

- [ ] **Step 2: Run the full test suite**

Run: `swift test`

Expected: PASS

- [ ] **Step 3: Manual macOS verification**

Run the macOS app in Debug with `CODEXPOOL_TRACE_INVALIDATION=1`, open the `Accounts` page, and verify:

- idle background refresh no longer causes obvious whole-page structure churn
- scrolling during background refresh feels smoother than before
- pending workspace changes do not disturb grid structure

Record the result in your handoff notes with concrete observations.

- [ ] **Step 4: Optional profiling pass if manual result is ambiguous**

Capture a SwiftUI Instruments trace in Release mode and compare:

- update frequency
- long view body updates
- hitch frequency during `Accounts` page scroll

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "test: verify accounts observable refactor"
```

## Notes for Execution

- Reuse `Tests/CodeXPoolTests/AccountsCoordinatorTests.swift` instead of creating a new test file.
- Keep `AccountsPageModel` as the mutation owner. The new UI-state layer is projection/cache only.
- Do not change `TrayMenuModel` refresh policy in this plan.
- Preserve existing page behavior on macOS and keep the same architecture usable on iOS.
- Respect any unrelated local modifications already present in the worktree.
