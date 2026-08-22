# Image Manifest and Prompt Set

All images were generated with the built-in image-generation workflow. The user's selected Guided Operations image was used as a visual reference. Files are design artifacts only and are not runtime assets.

## Approved-direction set

| File | Purpose |
|---|---|
| `guided-home-v2-mobile.png` | Refined mobile Home with honest separation of clinical urgency and sync/system state |
| `guided-work-mobile.png` | Unified permission-aware Work queue |
| `guided-people-mobile.png` | Consolidated patient/staff People directory with privacy-conscious rows |
| `guided-work-tablet.png` | Medium-tier Work master/detail layout |
| `guided-home-desktop.png` | Expanded desktop/web Home using the same four groups/components |

## Exploration archive

| File | Purpose |
|---|---|
| `concept-a-action-hub.png` | Action-first dashboard exploration |
| `concept-b-work-queue.png` | Queue-first exploration |
| `concept-c-guided-hub.png` | Original selected guided-goals exploration |

## Final prompt set (condensed)

### Guided Home v2 mobile

Create a production-ready portrait mCare admin Home using the selected guided-goal design. Separate `1 urgent item needs attention` from a factual freshness/health chip. Show four goal cards (Urgent care, People, Requests, Platform), three next actions, a collapsed Platform pulse, and exactly Home/Work/People/More navigation. Use accessible neutral surfaces, violet accent, and status colours only for meaning.

### Guided Work mobile

Create a matching portrait Work workspace combining authorized urgent, request, support and conversation tasks. Each row shows type, subject, reason, time/due state, owner, and one action. Include All/Urgent/Requests/Messages filters and the same four-tab navigation. Keep PHI minimal and commands type-specific.

### Guided People mobile

Create a matching portrait People directory replacing separate Patients and Users primary pages. Include universal search, Patients/Staff/Assistants segments, permission-aware Create person, privacy helper, and rows with identity/role/status/care-team context but no vitals or diagnoses. Use the same four-tab navigation.

### Guided Work tablet

Create a 1024×768 landscape master/detail Work layout with compact four-item rail, queue on the left, selected typed alert detail on the right, and canonical Acknowledge/Assign actions. Reuse mobile components; do not create tablet-only modules.

### Guided Home desktop

Create a 1536×1024 desktop/web Home using the same design system and four-item rail. Reflow goal cards horizontally and show Next actions plus Platform pulse/activity in constrained columns. Use universal search, bell, freshness, keyboard-friendly density, and minimum necessary patient context.

## Mockup limitations

- Generated text/data can contain illustrative artifacts and is not a backend contract.
- `Systems online` may only ship with a real, defined health signal; otherwise show sync freshness.
- Dates, names, counts and readings in images are demonstration data.
- Final implementation uses shared code tokens and accessibility measurements, not pixel sampling from the images.
- The specifications and traceability documents override visual inconsistencies.

