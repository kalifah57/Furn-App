# Furnishing Project Model — the complete journey

- **Status:** Approved design (target model)
- **Date:** 2026-07-29
- **Scope:** The `Project` as the spine of the whole journey, from intake to purchases. Multi-room. No code.
- **Related:** `docs/domain_model.md`, `docs/decision_context.md`, `docs/knowledge_base.md`

> Extends the domain model: **one project now spans many rooms**, and the domain grows from *decision-making* into *decision execution & tracking* (Shopping Plan → Purchases). Everything from Shopping Plan onward is **new journey surface**, correctly out of the current MVP — it is additive, not a rewrite.

---

## 0) The journey in one line

```mermaid
flowchart LR
  A[Intake] --> B[Decision Context<br/>per Room] --> C[Recommendations<br/>+ Alternatives] --> D[Shopping Plan] --> E[Purchases] --> F[Completed]
  C -. re-decide .-> B
  G((Snapshots)) -.capture.-> B & C & D
  H[(History)] -.records.-> A & C & D & E
```

**Three temporal concepts kept strictly distinct:**
- **Timeline** = the **future plan** — phases with target dates.
- **History** = the **past** — an append-only audit log of events.
- **Snapshots** = **points in time** — immutable full captures for compare / restore / versioning.

---

## 1) Aggregate boundary map

Five aggregates referenced by identity — not one giant object.

```mermaid
flowchart TB
  subgraph AG1[Aggregate: PROJECT]
    P[Project root]
    R[Room · entity xN]
    TL[Timeline to Phases]
    PB[ProjectBudget]
    PS[ProjectState]
    P --- R & TL & PB & PS
  end
  subgraph AG2[Aggregate: DECISION per room]
    DEC[Decision root<br/>Recommendations + Alternatives]
  end
  subgraph AG3[Aggregate: SHOPPING PLAN]
    SP[ShoppingPlan root]
    SI[ShoppingItem · entity xN]
    SP --- SI
  end
  subgraph AG4[Aggregate: PURCHASE xN]
    PU[Purchase root]
  end
  subgraph AG5[Aggregate: SNAPSHOT xN]
    SN[Snapshot root · immutable]
  end
  HIST[(ProjectHistory<br/>event stream — read model)]:::rm

  R -->|currentDecisionId| DEC
  P -->|currentShoppingPlanId| SP
  SI -->|chosen productRef| DEC
  PU -->|shoppingItemRef| SI
  PU -->|consumes| PB
  SN -->|captures| P
  P -. emits events .-> HIST
  classDef rm stroke-dasharray:4 3,fill:#eef;
```

| Aggregate | Why its own boundary |
|---|---|
| **Project** | Consistency of multi-room budget allocation, timeline, and state |
| **Decision** | Immutable computed result per room/context-version; heavy; read-mostly |
| **ShoppingPlan** | Independent lifecycle (draft→active→completed); edited frequently |
| **Purchase** | Each real acquisition is a fact with its own lifecycle; append-only |
| **Snapshot** | Immutable capture; never mutated after creation |

---

## 2) The Project aggregate (Project · Rooms · Timeline · Budget · State)

```mermaid
classDiagram
  class Project {
    +ProjectId id
    +AccountId owner
    +Title title
    +ProjectState state
    +StyleProfile sharedStyle
    +currentShoppingPlanId
    +snapshotIds[]
  }
  class Room {
    +RoomId id
    +Space space
    +RoomDecisionContext context
    +RoomBudget budget
    +currentDecisionId
    +RoomState state
  }
  class Timeline { +Phase[] phases }
  class Phase {
    +PhaseId id
    +Label label
    +DateRange target
    +RoomId[] rooms
    +PhaseStatus status
  }
  class ProjectBudget {
    +Money total
    +Map allocations
    +bool flexible
    +Money committed
    +Money remaining
  }

  Project "1" *-- "N" Room : furnishes
  Project "1" *-- "1" Timeline
  Project "1" *-- "1" ProjectBudget
  Timeline "1" *-- "N" Phase
  Phase ..> Room : schedules
```

- **Project** *(Aggregate Root)* — the whole journey for one home/effort. *Invariant:* valid state transitions; Σ room allocations ≤ budget total (unless `flexible`).
- **Room** *(Entity in Project)* — a sub-space, each with its own Decision Context, budget slice, current decision, and lifecycle state. Plurality is the key extension.
- **Timeline** *(Entity in Project)* — the forward plan: ordered **Phases** with target `DateRange` and status.
- **ProjectBudget** *(Entity in Project)* — multi-level money: `total` → per-room `allocations` → (inside a Decision) category `BudgetAllocation`. Derives `committed`/`remaining`.
- **ProjectState** *(VO)* — the state machine governing allowed operations (§6).

---

## 3) Recommendations & Alternatives (the Decision aggregate, per room)

```mermaid
classDiagram
  class Decision {
    +DecisionId id
    +RoomId room
    +ContextVersion pinned
    +PolicyVersion policy
  }
  class DecisionOption {
    +ProductRef product
    +FurnitureRole role
    +Money price
    +Priority priority
    +Rationale why
    +DecisionScore score
  }
  class Alternative {
    +ProductRef product
    +Money price
    +DecisionScore score
  }
  class Bundle { +BundleTier tier; +Money total; +bool exceedsBudget }
  Decision "1" *-- "N" DecisionOption : recommendations
  DecisionOption "1" *-- "N" Alternative : ranked swaps
  Decision "1" *-- "3" Bundle : budget/balanced/premium
```

- **Decision** *(Aggregate Root)* — immutable "**Recommendations**" for a room's context version.
- **DecisionOption** *(VO)* — a recommended pick for a requirement.
- **Alternative** *(VO)* — a ranked swap candidate attached to each option (the "**Alternatives**" concept). Swappable in the Shopping Plan.
- **Bundle** *(VO)* — the three coordinated tiers.

> Re-deciding never mutates a Decision — it produces a **new** `DecisionId`; a Snapshot is taken first.

---

## 4) Shopping Plan & Purchases (decision → execution)

```mermaid
classDiagram
  class ShoppingPlan {
    +ShoppingPlanId id
    +ProjectId project
    +ShoppingPlanState state
  }
  class ShoppingItem {
    +ShoppingItemId id
    +RoomId room
    +ProductRef chosen
    +ProductRef selectedAlternative
    +Quantity qty
    +Money estimatedPrice
    +Priority priority
    +PhaseId phase
    +ShoppingItemStatus status
  }
  class Purchase {
    +PurchaseId id
    +ShoppingItemId item
    +Money pricePaid
    +PurchaseDate date
    +PurchaseStatus status
  }
  ShoppingPlan "1" *-- "N" ShoppingItem
  ShoppingItem ..> Decision : chosen from an option/alternative
  ShoppingItem ..> Phase : assigned to
  Purchase ..> ShoppingItem : fulfills
```

- **Shopping Plan** *(Aggregate Root)* — the actionable buy-list derived from selected options across all rooms; ordered, grouped by room/phase, per-item status.
- **ShoppingItem** *(Entity)* — one thing to buy (chosen product or `selectedAlternative`, qty, estimate, phase, status).
- **Purchase** *(Aggregate Root, ×N)* — the fact that an item was bought; the thing that **consumes budget** (`committed`).

---

## 5) Budget rollup, Snapshots & History

```mermaid
flowchart TD
  T[ProjectBudget.total] --> AR[allocated to RoomBudget per room]
  AR --> CAT[category ceilings in Decision]
  CAT --> PLAN[planned = sum ShoppingItem.estimatedPrice]
  PLAN --> COMM[committed = sum Purchase.pricePaid]
  COMM --> REM[remaining = total minus committed]
```

```mermaid
flowchart LR
  subgraph FUT[Timeline · FUTURE plan]
    P1[Phase 1<br/>Living room · this month] --> P2[Phase 2<br/>Bedroom · next month]
  end
  subgraph NOW[Snapshots · POINTS in time]
    S1[Snapshot @ plan approved]
    S2[Snapshot @ before re-decide]
  end
  subgraph PAST[History · PAST log]
    H1[ContextConfirmed] --> H2[DecisionProduced] --> H3[PlanApproved] --> H4[ItemPurchased]
  end
```

- **Snapshot** *(Aggregate Root, immutable)* — `{SnapshotId, takenAt, SnapshotReason, CapturedState}`; enables compare & restore.
- **ProjectHistory** *(read model)* — append-only `HistoryEntry` projected from Domain Events.

---

## 6) Project State — and the nested lifecycles

```mermaid
stateDiagram-v2
  [*] --> Draft
  Draft --> ContextBuilding : add room / start intake
  ContextBuilding --> Analyzing : room contexts ready
  Analyzing --> Decided : decisions produced
  Decided --> Planning : start shopping plan
  Planning --> Shopping : plan approved
  Shopping --> Completed : all planned items purchased
  Completed --> Archived
  Decided --> Analyzing : re-decide (snapshot first)
  Planning --> Analyzing : context/budget changed (snapshot first)
  Draft --> Archived : abandon
```

```mermaid
stateDiagram-v2
  state "Room" as R {
    [*] --> Pending --> Contextualized --> Decided --> Planned --> PartiallyPurchased --> Purchased
  }
  state "ShoppingItem" as I {
    [*] --> PlannedI --> InCart --> PurchasedI
    PlannedI --> Skipped
  }
  state "Purchase" as PU {
    [*] --> Ordered --> Delivered
    Ordered --> Cancelled
    Delivered --> Returned
  }
```

- Re-deciding from `Decided/Planning/Shopping` **must take a Snapshot first** (traceability). Nested `RoomState / ShoppingItemStatus / PurchaseStatus` roll up into project state.

---

## 7) Value Objects & Domain Events (summary)

**Value Objects** — *Shared kernel:* `Money`, `Currency`, `Dimensions`, `Quantity`, `Confidence`, `Percentage`, `ContextVersion`, `ProductRef`, `FurnitureRole`, `Category`, `Priority`, `DateRange`, tags. *Project:* `ProjectState`, `RoomState`, `RoomBudget`, `Space`, `RoomDecisionContext`, `RequirementSet`, `Requirement`, `ConstraintSet`, `StyleProfile`, `Gap`/`GapSet`, `Phase`, `PhaseStatus`, `Title`. *Decision:* `DecisionOption`, `Alternative`, `Bundle`, `BundleTier`, `DecisionScore`, `ScoreFactor`, `Rationale`, `TradeOff`, `DecisionWarning`, `BudgetAllocation`. *Plan/Purchase:* `ShoppingItemStatus`, `ShoppingPlanState`, `PurchaseStatus`, `PurchaseDate`. *Temporal:* `SnapshotReason`, `CapturedState`, `HistoryEntry`.

**Domain Events:**

| Area | Events |
|---|---|
| Project | `ProjectStarted`, `RoomAdded`, `RoomRemoved`, `BudgetAllocated`, `TimelinePlanned`, `PhaseScheduled`, `ProjectStateChanged`, `ProjectArchived` |
| Context | `ContextConfirmed`, `DecisionContextUpdated`, `DecisionContextReady`, `ClarificationAnswered` |
| Decision | `DecisionRequested`, `DecisionProduced`, `AlternativeSelected`, `BudgetConflictDetected` |
| Shopping | `ShoppingPlanCreated`, `ShoppingItemAdded/Removed`, `ItemAssignedToPhase`, `ShoppingPlanApproved` |
| Purchase | `PurchaseRecorded`, `PurchaseDelivered`, `PurchaseReturned`, `PurchaseCancelled` |
| Temporal | `SnapshotTaken`, `SnapshotRestored` |

---

## 8) Key invariants

1. Σ `RoomBudget` allocations ≤ `ProjectBudget.total` (unless `flexible`).
2. A `Decision` is immutable and pinned to one `ContextVersion` + `PolicyVersion`.
3. A `ShoppingItem` references a product in its room's current `Decision` (chosen option **or** one of its alternatives).
4. `committed` = Σ `Purchase.pricePaid`; `remaining` = `total − committed`.
5. Re-deciding or restoring **always** produces a `SnapshotTaken` first.
6. `ProjectState` transitions follow §6; illegal operations are rejected.
7. Purchases are append-only facts; corrections are new events (`Returned`/`Cancelled`), never deletions.

---

## 9) MVP scoping note

Today's `FurnishingProject` (single room) becomes a **Project with one Room**; `Recommendations` → `Decision`. **Shopping Plan / Purchases / Timeline / Snapshots are post-MVP journey surface** — modeled here so the code can grow into them without a rewrite.
