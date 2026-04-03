# Accounts Page Observable Refactor Design

Date: 2026-04-03
Repository: `Copool`
Scope: macOS-first `Accounts` main page, with the same design applicable to iOS where the page uses the same state pipeline.

## Goal

Reduce scroll jank on the `Accounts` main page by shrinking state observation scope inside the SwiftUI view tree.

This design explicitly excludes UI restyling and rendering polish work. The target is the update pipeline: broad state fan-out, repeated whole-page projection work, and unnecessary invalidation of the scroll content subtree.

## Problem Summary

The current `Accounts` page uses a page-level `AccountsPageViewStore` that:

- listens to multiple `AccountsPageModel` publishers
- rebuilds all card projections on each relevant change
- synchronizes all card stores on each refresh
- republishes page structure through a single aggregated `contentPresentation`

This has two distinct costs:

1. Main-thread projection cost before SwiftUI diffing
2. A broad dependency surface for the scroll subtree

The existing row-level `AccountCardStore` split already avoids some whole-page republishing for single-card changes, but the architecture still pays the cost of full card projection and full store synchronization on many updates.

## Current Evidence

Relevant files:

- `Sources/Copool/Features/Accounts/AccountsPageViewStore.swift`
- `Sources/Copool/Features/Accounts/AccountsPageShells.swift`
- `Sources/Copool/Features/Accounts/AccountsPageSections.swift`
- `Sources/Copool/Features/Accounts/AccountsPagePresentation.swift`
- `Sources/Copool/App/RootScene.swift`
- `Sources/Copool/App/TrayMenuModel+Refresh.swift`

Observed constraints from the current implementation:

- `RootScene` continuously feeds account snapshots and refresh activity back into `AccountsPageModel`.
- `TrayMenuModel` performs recurring background refresh work on macOS.
- `AccountsPageViewStore` currently merges multiple publishers and recomputes page/card projections from the full model.
- Existing tests already enforce that some card-only updates should not republish whole-page content.

## Non-Goals

- No redesign of card visuals, layout rules, toolbar visuals, or animations
- No changes to the background refresh policy itself
- No repository-wide migration to `@Observable`
- No changes to `Proxy` or `Settings` pages in this slice

## Approaches Considered

### Approach A: Split the current store into multiple `ObservableObject` stores

Pros:

- Moderate change set
- Keeps the current Combine-based structure
- Easier incremental migration

Cons:

- Preserves publisher-driven whole-store coordination
- Still encourages aggregated projections
- Does not fully use SwiftUI property-level dependency tracking

### Approach B: Keep the current store shape and optimize local diffing only

Pros:

- Smallest code churn
- Lowest migration risk

Cons:

- Only reduces compute cost
- Does not materially improve observation boundaries in the view tree
- Leaves the page rooted in a broad aggregate state object

### Approach C: Replace page aggregation with `@Observable` page and row models

Pros:

- Best match for the root problem: dependency fan-out
- Moves the page to property-level observation instead of page-level publication
- Lets each section and row depend only on the properties it actually reads

Cons:

- Largest migration among the three
- Requires test migration away from `contentPresentation`
- Makes dependency edges more implicit, so view boundaries must be kept strict

Recommendation: Approach C

Reason: the reported issue is scroll smoothness under ongoing background state updates. Narrowing observation scope is the most direct fix. A smaller optimization inside the old architecture would leave the main source of fan-out in place.

## Design Overview

The refactor keeps `AccountsPageModel` as the single business-state source and replaces the current aggregated page projection layer with a property-driven observable UI state layer.

### Layer 1: Business source

`AccountsPageModel` remains the only source of truth for:

- account list state
- pending workspace state
- collapsed account IDs
- refreshing and switching activity
- usage display mode
- action execution state

This layer continues to own mutations and background-sync ingestion.

### Layer 2: Page UI state

Introduce a lightweight `@Observable` page UI state object for `Accounts`.

Responsibilities:

- expose `visibleCardIDs`
- expose `pendingWorkspaceCards`
- expose `pendingWorkspaceError`
- expose `isOverviewMode`
- provide `cardModel(id:)`

Rules:

- it may cache derived values
- it may map model state into row models
- it must not become a second source of business truth
- it must not reintroduce an aggregated page presentation type

### Layer 3: Row UI state

Introduce one `@Observable` row model per visible account card.

Responsibilities:

- hold the card-local projected values used by `AccountCardView`
- update only when that card's effective inputs change

Expected row fields include:

- `presentation`
- `isCollapsed`
- `switching`
- `refreshing`
- `showsRefreshButton`
- `isRefreshEnabled`
- `isUsageRefreshActive`

Identity rule:

- row model instances must remain stable for unchanged cards across unrelated updates

## View Tree Boundaries

The refactor should produce these read boundaries:

- `AccountsMacContentHost` reads only page-level structural properties
- pending workspace section reads only pending workspace properties
- grid section reads only `visibleCardIDs`, `isOverviewMode`, and layout inputs
- each card row reads only its own row model

This is the key performance property of the design. If a parent view reads row-local fields, the design fails even if `@Observable` is used.

## Data Flow

Target flow for a single-card refresh-state change:

`TrayMenuModel -> RootScene -> AccountsPageModel -> Accounts page UI state -> row model(account X) -> AccountCardView(account X)`

Not acceptable after refactor:

`TrayMenuModel -> RootScene -> AccountsPageModel -> whole page projection rebuild -> whole scroll subtree reevaluates`

Target flow for pending workspace changes:

`AccountsPageModel -> Accounts page UI state -> PendingWorkspaceAuthorizationSection`

The grid path should remain unaffected unless visible account structure also changes.

## Migration Plan

### Step 1: Introduce the new observable page and row models

- add the new page UI state object
- add row models
- keep `AccountsPageModel` unchanged as the source of truth
- preserve existing screen behavior

### Step 2: Move the view tree to the new observation boundaries

- update `AccountsPageShells`
- update `AccountsPageSections`
- update `AccountCardView` inputs
- ensure pending section and grid section no longer share a single aggregate presentation dependency

### Step 3: Remove the old aggregated projection path

- remove `contentPresentation`
- remove `AccountCardStore`
- remove or shrink old projection-only types in `AccountsPagePresentation`
- update tests to assert the new dependency model

## File Impact

Expected primary files:

- `Sources/Copool/Features/Accounts/AccountsPageViewStore.swift`
- `Sources/Copool/Features/Accounts/AccountsPagePresentation.swift`
- `Sources/Copool/Features/Accounts/AccountsPageSections.swift`
- `Sources/Copool/Features/Accounts/AccountsPageShells.swift`
- `Sources/Copool/Features/Accounts/AccountCardView.swift`
- `Tests/CopoolTests/AccountsCoordinatorTests.swift`

New file creation is acceptable if it improves boundary clarity, but file splitting should stay moderate and limited to this feature area.

## Acceptance Criteria

The design is complete only if all of the following are true:

- background refresh no longer requires rebuilding a full `[AccountCardViewState]` style array for every relevant UI update
- single-card activity changes update only the affected row model
- pending workspace changes do not force grid structure updates
- row model identity remains stable for unchanged cards
- macOS `Accounts` page behavior and layout remain unchanged
- the same architecture remains applicable to the iOS page path

## Test Plan

Add or migrate tests to verify:

1. card-only updates change only the affected row model
2. unchanged row models keep identity across unrelated updates
3. pending workspace changes do not alter grid structure properties
4. structure changes update `visibleCardIDs` correctly
5. overview-mode changes affect only the expected layout-facing properties

These tests replace reliance on `contentPresentation` as the primary assertion target.

## Runtime Verification Plan

Use debug invalidation tracing plus manual interaction on macOS:

1. open the `Accounts` main page
2. leave the page idle during background refresh intervals
3. scroll continuously through the page during the same intervals
4. compare logs before and after the refactor

Expected qualitative result:

- fewer whole-page structural invalidations
- more localized row-level updates
- smoother scroll behavior during background refresh activity

If code inspection remains inconclusive, capture a SwiftUI Instruments trace in a Release build and compare update frequency and hitch counts before and after.

## Risks

### Risk 1: Hidden broad reads in parent views

`@Observable` only helps if views read narrowly scoped properties. A parent that reads too much can recreate the same fan-out with less obvious code.

Mitigation:

- keep parent views intentionally thin
- keep row-local reads inside row views
- keep pending-section reads outside grid views

### Risk 2: Duplicate state ownership

The new page UI state may drift into owning business logic or mutation decisions.

Mitigation:

- keep all business mutations in `AccountsPageModel`
- treat page UI state as a projection/cache layer only

### Risk 3: Test churn

Tests currently reference the old store shape.

Mitigation:

- migrate tests alongside each step
- preserve behavior assertions while changing the state surface they inspect

## Verification Status

Repository tests are not currently a clean baseline because the working tree already contains debug-trace edits in `AccountsPageViewStore.swift` that trigger a Swift concurrency compile error during `swift test`.

This design therefore records the intended verification path, but current test execution is blocked until that existing issue is resolved or adjusted.
