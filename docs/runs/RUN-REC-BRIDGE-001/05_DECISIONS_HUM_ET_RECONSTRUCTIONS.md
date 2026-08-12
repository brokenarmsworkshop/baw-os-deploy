# RUN-REC-BRIDGE-001 — Décisions HUM et reconstructions

## Modèle SLM

**Décision HUM :** utiliser `llama3.2:3b`.

Motif :
- modèle installé ;
- Ollama opérationnel ;
- modèle déjà utilisé par un workflow BAW OS vivant ;
- absence de preuve formelle du modèle exact de l'ancien `WF-SLM-001`.

Qualification :
**reconstruction équivalente, modèle historique non prouvé.**

## Modèle Mistral

**Décision HUM :** utiliser `mistral-large-latest`.

Motif :
- credential canonique `BAW OS — Mistral` disponible ;
- endpoint vivant déjà validé ;
- workflow Mistral de test existant utilisant ce modèle ;
- absence de preuve formelle du modèle exact de l'ancien `WF-MISTRAL-001`.

Qualification :
**reconstruction équivalente, modèle historique non prouvé.**

## DDL PostgreSQL

La table historique `baw_mistral_usage_log` était absente des bases :
- `baw_core`
- `n8n`
- `postgres`

Aucun DDL historique exact n'a été retrouvé.

**Décision HUM :** appliquer un DDL minimal limité aux métadonnées techniques.

Aucun contenu utilisateur n'est journalisé.

## Seuils de monitoring

Les sept codes visuels du Bridge 0.7.1 ont été retrouvés :
- green
- green-yellow
- yellow
- yellow-orange
- orange
- red-orange
- red

Les seuils numériques historiques n'ont pas été retrouvés.

**Décision HUM :** reconstruire une grille à sept niveaux :

- niveau 1 : `< 20 %`
- niveau 2 : `20 % à < 40 %`
- niveau 3 : `40 % à < 60 %`
- niveau 4 : `60 % à < 75 %`
- niveau 5 : `75 % à < 90 %`
- niveau 6 : `90 % à < 100 %`
- niveau 7 : `>= 100 %`

Budget indicatif : `50 000 tokens/jour`.

Le monitoring reste non bloquant.
