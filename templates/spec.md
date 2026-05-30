# <slug> — <summary>

## Summary

One-sentence description of what this feature does.

## Scope

### In scope

- What the feature will do

### Out of scope

- What the feature will NOT do

## Behavior

Detailed behavioral specification. Each requirement should be testable.
For UI features: describe visual states (loading, empty, error, success),
user interactions, and responsive behavior.

## UI / Component Breakdown

<!-- For frontend features only. Delete if not applicable. -->

List of components affected, their hierarchy, and visual states:

| Component | State(s) | Description |
|-----------|----------|-------------|
| `MyComponent` | loading / empty / error / success | Shows a spinner while data loads, empty state when no results |

## User Flows

<!-- For frontend features only. Delete if not applicable. -->

Step-by-step user interaction sequences:

1. User lands on page → sees loading skeleton
2. Data loads → skeleton replaced with content
3. User clicks "Save" → optimistic UI update, then API call...

## Visual / Design Requirements

<!-- For frontend features only. Delete if not applicable. -->

- Mockup / Figma reference: `<!-- link -->`
- Design tokens: colors, typography, spacing
- Responsive breakpoints: mobile / tablet / desktop
- Dark mode support: yes / no

## Accessibility Requirements

<!-- For frontend features only. Delete if not applicable. -->

- ARIA roles and labels
- Keyboard navigation and focus management
- Screen reader behavior
- Color contrast ratios (WCAG AA / AAA)

## State Management

<!-- For frontend features with data flow. Delete if not applicable. -->

- Data flow: how data moves between components, stores, and APIs
- Caching strategy: stale-while-revalidate, optimistic updates, etc.
- State shape: key store/state slices affected

## API Contract (Frontend Perspective)

<!-- For frontend features consuming APIs. Delete if not applicable. -->

| Endpoint | Method | Request | Response |
|----------|--------|---------|----------|
| `/api/v1/resource` | GET | query params | `{ items: [...] }` |

## Implementation Context

Files, classes, components, endpoints, stores, hooks, and services relevant to this feature.

## Expected Change Scope

Concrete estimate of files and layers touched.

## Safe Constraints

### Safe

- Things the implementation MUST do

### Unsafe

- Things the implementation MUST NOT do

## Open Questions

Unresolved items blocking progression. Format: `- [ ] **#N** <question>`
