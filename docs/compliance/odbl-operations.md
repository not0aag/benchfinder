# ODbL operations checklist

## Pre-release compliance checks
- Verify OSM-derived rows remain attributable through `source_osm_id`.
- Verify ODbL attribution string is present in map surfaces.
- Verify export endpoints do not mix ODbL and proprietary data without explicit labeling.

## Export discipline
- Keep OSM-derived export process scripted and reproducible.
- Tag each export with source snapshot date and schema version.
- Store legal review status for public export changes.

## Legal gates
- Require counsel sign-off before changing export semantics.
- Re-run compliance checklist before public launch and every major data model change.
