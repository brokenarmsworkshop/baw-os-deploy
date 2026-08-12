# RUN-REC-BRIDGE-001 — Intégration Git

## Dépôt cible

`G:\BAW_OS\repositories\baw-os-deploy`

## Chemin de versement

Ce package est construit pour être déposé à la racine du dépôt.

Le contenu suivi par Git se trouve sous :

`docs/runs/RUN-REC-BRIDGE-001/`

## Périmètre du versement

Le versement contient uniquement :
- la documentation de clôture ;
- la matrice de tests ;
- le DDL PostgreSQL appliqué ;
- les preuves de publication ;
- les décisions HUM et reconstructions ;
- l'anomalie résiduelle connue ;
- l'inventaire des sauvegardes et empreintes ;
- l'état final n8n ;
- les trois workflows de production reconstruits ;
- les trois harnesses de test archivés ;
- le manifeste SHA-256 du versement.

## Exclusions volontaires

Ne sont pas versés dans Git :
- les dumps PostgreSQL ;
- les exports n8n globaux volumineux ;
- les archives de restauration ;
- les secrets et valeurs de credentials ;
- le ZIP de transmission de clôture.

Ces éléments restent conservés sous :

`G:\BAW_OS\recovery\RUN-REC-BRIDGE-001`

Leur existence et leurs SHA-256 sont consignés dans `07_INVENTAIRE_SAUVEGARDES_SHA256.md`.

## État fonctionnel documenté

- `WF-SLM-001` : actif
- `WF-MISTRAL-001` : actif
- `WF-MON-001` : actif
- harnesses TEST : inactifs et archivés
- Gateway : inchangé
- Bridge : 0.7.1 restauré et validé
- `BUG-UI-071` : non bloquant, hors correction de ce run

## Règle

Ce package ne modifie aucun fichier en dehors de `docs/runs/RUN-REC-BRIDGE-001/`.
