# RUN-REC-BRIDGE-001 — État final n8n

## Workflows de production

| ID | Workflow | Active | Archivé | activeVersionId = versionId |
|---|---|---:|---:|---:|
| `rR21ZmKlmVv94GNg` | `WF-SLM-001 — Ask Local Model — RECOVERY 0.7.1` | oui | non | oui |
| `NDC8WZX9cJxhPNoQ` | `WF-MISTRAL-001 — Ask Mistral — RECOVERY 0.7.1` | oui | non | oui |
| `LPBJmQqbU7XcBOtu` | `WF-MON-001 — Mistral Daily Usage — RECOVERY 0.7.1` | oui | non | oui |

## Harnesses du run

| ID | Workflow | Active | Archivé |
|---|---|---:|---:|
| `Cqk51ZOEBUFGQ355` | `TEST — WF-SLM-001 — RUN-REC-BRIDGE-001` | non | oui |
| `59NM7JvwVTBkn6Iz` | `TEST — WF-MISTRAL-001 — RUN-REC-BRIDGE-001` | non | oui |
| `7ozeiJJbtoLz8rJN` | `TEST — WF-MON-001 — RUN-REC-BRIDGE-001` | non | oui |

## Compte global

- Export initial : **64 workflows**
- Export final : **73 workflows**

Écart expliqué :
- +3 production RUN-REC-BRIDGE-001 ;
- +3 harnesses RUN-REC-BRIDGE-001 ;
- +3 workflows RUN-REC-002 créés parallèlement.

Les trois workflows RUN-REC-002 constatés pendant le run sont hors périmètre et n'ont pas été modifiés :

- `OxuhS2D16gkuw0kb` — `RUN-REC-002 — TEST — LIB-005 Contract Matrix A-G`
- `eC9f0KizVv8hGgTY` — `RUN-REC-002 — PATCH — WF-LIB-005-DYN — Contract Parameters`
- `L0EIPZr6z40FZXof` — `RUN-REC-002 — TEST — WF-GTW-001 — Patched LIB-005`
