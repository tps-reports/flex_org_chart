# Node editing API — design

Feature #2 of the post-0.1.0 roadmap (README row: "Node editing
(add/remove/re-parent via API)"). Adds programmatic add / remove /
reparent / update operations to `OrgChartController`, building on the
0.2.0 drag-and-drop foundation (`setData(preserveState: true)` and its
animated relayout).

## Decisions (settled during brainstorming)

| Question | Decision |
| --- | --- |
| How does the controller write a parent id into opaque `T`? | Optional constructor callback `T Function(T item, String? newParentId) withParent`. Apps that edit provide it; `reparent()` and child promotion need it and throw `StateError` without it. |
| `removeNode` descendants | Children are promoted to the removed node's parent (via `withParent`). Removing a root promotes its children to roots. No subtree-removal mode in v1. |
| Op set | `addNode`, `removeNode`, `reparent`, `updateNode`, plus `List<T> get data`. No batch variants (YAGNI). |
| Persistence signal | Optional `void Function(List<T> data)? onDataChanged` constructor callback, fired after every successful edit op with the new list (the same unmodifiable view the `data` getter returns). Never fired by `setData` (the app initiated that itself). |
| Internal application | Validate → build new `List<T>` → reuse `setData`'s preserve-state machinery (full re-stratify, state restore, animated relayout) → fire `onDataChanged`. No incremental tree surgery. |

## Public API

All on `OrgChartController<T>`; the widget layer is untouched.

```dart
OrgChartController<T>(
  data: ...,
  idOf: ...,
  parentIdOf: ...,
  // NEW, optional. Returns a copy of item with its parent id replaced.
  withParent: (item, newParentId) => item.copyWith(managerId: newParentId),
  // NEW, optional. The persistence hook.
  onDataChanged: (data) => api.save(data),
);

void addNode(T item);
void removeNode(String id);
void reparent(String id, String? newParentId);
void updateNode(T item);
List<T> get data; // unmodifiable view of the current list
```

Every edit op animates exactly like a drag-drop confirmation: surviving
ids keep expansion/highlight state and lerp to their new positions.

## Op semantics & error handling

Edit ops are programmer-driven, so invalid calls **throw before mutating
anything** — unlike `expand()`/`highlight()`, which no-op on unknown ids
because they are UI-driven. A thrown op leaves the controller
byte-for-byte unchanged: no relayout, no notify, no `onDataChanged`, and
`dataError` can never be set by an edit op.

- **`addNode(item)`** — `ArgumentError` if `idOf(item)` already exists or
  `parentIdOf(item)` names a non-existent id (non-null). A null/empty
  parent id adds a new root (multi-root charts are supported). The new
  node follows normal visibility rules — hidden if its parent is
  collapsed; the parent is not auto-expanded.
- **`removeNode(id)`** — `ArgumentError` on unknown id. Children
  re-attach to the removed node's parent via `withParent`; removing a
  root promotes its children to roots (`withParent(child, null)`).
  `StateError` if the node has children and `withParent` was not
  provided (a leaf removes fine without it). The removed id's
  expansion/highlight state vanishes; promoted children keep theirs.
- **`reparent(id, newParentId)`** — `StateError` without `withParent`;
  `ArgumentError` on unknown `id`, unknown non-null `newParentId`,
  `id == newParentId`, or when `newParentId` is a descendant of `id`
  (the drag-and-drop cycle rule, validated here too because programmatic
  callers bypass `resolveDropTarget`). Reparenting to the current parent
  is a silent no-op — no relayout, no `onDataChanged`.
- **`updateNode(item)`** — `ArgumentError` on unknown id. Replaces the
  item wholesale. If the replacement's `parentIdOf` differs from the
  current one, that is honored — a combined update+reparent (`withParent`
  not needed; the app already wrote the parent id itself). Expansion and
  highlight survive (same id). When the parent id changed, the new
  parent id passes the same validation as `reparent` (existence,
  not-self, not-a-descendant) before anything mutates.
- **`data`** — `List.unmodifiable` view. Mutating the app's own original
  list does nothing until an op or `setData` is called.

**`withParent` contract:** the returned item must keep its id. Each op
that calls `withParent` verifies `idOf(result) == idOf(input)` and throws
`StateError` on violation — catching the bug at the source rather than
as a confusing downstream stratify error.

## Internals & file layout

All production changes in
`lib/src/controller/org_chart_controller.dart` (~440 lines today, ~600
after; the ops are cohesive with the data they mutate — no split).

- Extract `setData`'s capture/restore block into a private
  `_applyData(List<T> newData, {bool preserveState})`; `setData` and all
  four ops route through it — exactly one mutation path.
- Each op is ~15 lines: validation + list building, then `_applyData`
  (always `preserveState: true`), then `onDataChanged?.call(_data)`.
- `withParent` and `onDataChanged` are constructor params alongside
  `idOf`/`parentIdOf`.

**Drag-and-drop synergy:** the example app's `onReparent` becomes
`(n, p) => controller.reparent(n.id, p.id)` with `withParent` /
`onDataChanged` wired on its controller. The `OrgChart` widget does NOT
auto-call `reparent` when `withParent` exists — the explicit handler
stays the contract (no hidden magic; apps can still intercept).

## Testing

Controller-level unit tests (no widget pumping) plus one widget test:

- Per-op happy paths: add (child + new root), remove (leaf, mid-tree
  promotion, root promotion), reparent (including to root via null),
  update (including combined update+reparent) — each asserting resulting
  tree shape, preserved expansion/highlights, and `onDataChanged` firing
  with the new list.
- Per-op error paths: every `ArgumentError`/`StateError` case above,
  each also asserting the controller is unchanged after the throw
  (data, state, no notify, no `onDataChanged`).
- The `withParent`-changes-id contract violation.
- Reparent-to-current-parent silent no-op (no notify, no callback).
- One widget test: drag-and-drop wired to `controller.reparent`
  end-to-end.

## Docs

- README: flip the "Node editing (add/remove/re-parent via API)" row to
  done; short usage snippet.
- CHANGELOG: 0.3.0 entry.

## Roadmap context

Post-0.2.0 order (user-decided 2026-08-06): this feature, then
3) department bounding boxes, 4) image/PDF export. Pagination not
planned.
