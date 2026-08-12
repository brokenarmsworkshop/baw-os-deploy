# RUN-REC-BRIDGE-001 — Preuves de publication

## WF-SLM-001

- ID : `rR21ZmKlmVv94GNg`
- Nom : `WF-SLM-001 — Ask Local Model — RECOVERY 0.7.1`
- active : `true`
- isArchived : `false`
- activeVersionId : `13fdddd2-ddf2-4958-ad50-be8ee5f603d9`
- versionId : `13fdddd2-ddf2-4958-ad50-be8ee5f603d9`
- Webhook : `POST /webhook/baw/slm/ask`
- Test production : **OK**

## WF-MISTRAL-001

- ID : `NDC8WZX9cJxhPNoQ`
- Nom : `WF-MISTRAL-001 — Ask Mistral — RECOVERY 0.7.1`
- active : `true`
- isArchived : `false`
- activeVersionId : `3b777db2-4125-480f-8c1c-19b271850555`
- versionId : `3b777db2-4125-480f-8c1c-19b271850555`
- Webhook : `POST /webhook/baw/mistral/ask`
- Test production : **OK**

## WF-MON-001

- ID : `LPBJmQqbU7XcBOtu`
- Nom : `WF-MON-001 — Mistral Daily Usage — RECOVERY 0.7.1`
- active : `true`
- isArchived : `false`
- activeVersionId : `58d54efc-e60f-40c3-b6d8-42583567c3ae`
- versionId : `58d54efc-e60f-40c3-b6d8-42583567c3ae`
- Webhook : `GET /webhook/baw/monitoring/mistral/daily`
- Test production : **OK**

## Harnesses de test conservés

Les trois workflows de test sont inactifs et archivés :

- `Cqk51ZOEBUFGQ355` — TEST WF-SLM-001
- `59NM7JvwVTBkn6Iz` — TEST WF-MISTRAL-001
- `7ozeiJJbtoLz8rJN` — TEST WF-MON-001

Ils sont conservés comme preuves reproductibles et ne publient aucun endpoint de production.
