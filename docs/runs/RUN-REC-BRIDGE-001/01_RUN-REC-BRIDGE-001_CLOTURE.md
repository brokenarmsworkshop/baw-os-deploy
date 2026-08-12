# RUN-REC-BRIDGE-001 — Clôture

## 1. Décision de clôture

Le run `RUN-REC-BRIDGE-001` est **clos avec succès**.

Le BAW HUM Bridge a été rétabli dans un état fonctionnel équivalent à la référence **0.7.1**, sans ouverture du chantier 0.7.2.

Doctrine appliquée : **restaurer avant d’améliorer**.

## 2. État fonctionnel final

Chaîne restaurée et validée :

```text
Firefox
→ n8n
→ SLM local / Ollama
→ Mistral
→ monitoring PostgreSQL
→ Gateway documentaire
```

Les trois workflows historiquement absents ont été reconstruits, testés, puis publiés :

- `WF-SLM-001 — Ask Local Model — RECOVERY 0.7.1`
- `WF-MISTRAL-001 — Ask Mistral — RECOVERY 0.7.1`
- `WF-MON-001 — Mistral Daily Usage — RECOVERY 0.7.1`

Le Gateway documentaire existant n'a pas été modifié.

## 3. Extension Firefox

Extension restaurée dans :

`G:\BAW_OS\runtime\hum-bridge\0.7.1`

Référence :
- nom : `BAW HUM Bridge`
- version : `0.7.1`
- Manifest V3
- Gecko ID : `baw-hum-bridge@broken-arms-workshop.local`
- host permission : `http://localhost:5678/*`

Le chargement temporaire dans Firefox et le panneau latéral ont été validés.

## 4. SLM local

Ollama est opérationnel sur `127.0.0.1:11434`.

Modèle retenu par validation HUM pour la reconstruction :

`llama3.2:3b`

Le modèle historique exact de l'ancien `WF-SLM-001` n'a pas été prouvé. Le modèle retenu était toutefois déjà installé et utilisé par un workflow BAW OS vivant.

Contrat SLM de production validé :
- `ok = true`
- `contractStatus = valid`
- `source = slm`
- réponse séparée ;
- `needsEscalation` distinct ;
- métriques tokens présentes.

## 5. Mistral

Credential canonique réutilisé :

`BAW OS — Mistral`

Endpoint :

`https://api.mistral.ai/v1/chat/completions`

Modèle retenu par validation HUM :

`mistral-large-latest`

L'escalade Mistral reste explicitement déclenchée après une réponse SLM précédente.

Le Bridge conserve une réponse Mistral séparée de la réponse SLM.

## 6. Journalisation PostgreSQL

Table reconstruite :

`public.baw_mistral_usage_log`

Base :

`baw_core`

La table contient exclusivement des métadonnées techniques :
- modèle ;
- tokens prompt ;
- tokens completion ;
- total tokens ;
- statut de contrat ;
- statut HTTP ;
- identifiant de requête Mistral ;
- horodatage.

Aucun prompt, aucune sélection, aucune réponse, aucun contenu utilisateur n'est journalisé.

## 7. Monitoring

Contrat du Bridge restauré :
- `totalTokens`
- `dailyBudget`
- `usagePercent`
- `indicator.code`
- `indicator.label`
- `indicator.level`
- `usage.requestCount`
- `usage.averageTokensPerRequest`
- `usage.lastRequestAt`
- `overBudget`

Budget indicatif : **50 000 tokens/jour**.

Le monitoring est informatif et non bloquant.

Les seuils historiques exacts n'ayant pas été retrouvés, une grille à sept niveaux a été reconstruite et validée HUM.

## 8. Test réel du Bridge

Validés depuis Firefox :
- monitoring ;
- capture de page ;
- SLM local ;
- escalade explicite vers Mistral ;
- réponses SLM et Mistral séparées ;
- comptabilisation tokens ;
- persistance après fermeture/réouverture du panneau ;
- Copier ;
- Injecter séparément ;
- recherche documentaire ;
- lecture documentaire ponctuelle.

Aucune publication Notion complète n'a été déclenchée.

## 9. État n8n final

Workflows de production :
- actifs ;
- non archivés ;
- `activeVersionId = versionId`.

Harnesses de test :
- inactifs ;
- archivés ;
- conservés comme preuves reproductibles.

État final exporté : **73 workflows**.

L'écart par rapport aux 64 workflows initiaux est entièrement expliqué :
- +3 workflows Bridge restaurés ;
- +3 harnesses de test de ce run ;
- +3 workflows `RUN-REC-002` créés parallèlement et hors périmètre.

Les workflows `RUN-REC-002` n'ont pas été modifiés dans ce run.

## 10. Anomalie résiduelle

`BUG-UI-071 — contraste monitoring en thème clair`

Les quatre cartes du monitoring présentent un contraste insuffisant en thème clair. Le thème sombre est conforme.

Cette anomalie est non bloquante et volontairement laissée hors du run afin de ne pas transformer la restauration en refonte.

## 11. Conclusion

Les critères essentiels du mandat sont remplis.

**Décision finale :**

```text
RUN-REC-BRIDGE-001
CLOS
RESTAURATION BAW HUM BRIDGE 0.7.1 RÉUSSIE
```

Le chantier 0.7.2 reste distinct et n'est pas ouvert par cette clôture.
