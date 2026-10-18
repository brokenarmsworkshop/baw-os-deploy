# BAW Bridge V3.3 — pilote isolé (non production)

Ce Compose doit être utilisé uniquement avec le clone de `baw-os-app` placé dans
`G:\\BAW_OS\\pilots\\bridge-v33-isolated\\baw-os-app`, branche
`run/baw-bridge-v3.3-atomic-receipts-20261018`.

## Isolation

- Port : `127.0.0.1:18766` (V3.2 demeure sur 18765).
- Dossiers pilotes : `library:ro`, `inbox:rw`, `queue:rw`.
- Aucun montage des archives officielles, dépôts de production, sauvegardes, bases ou secrets.
- Aucun raccordement au réseau `baw-backend`.
- Aucun transfert GitHub -> G: ni synchronisation automatique.
- `POST /api/v1/v33/queue/<id>/decision` renvoie 501 : approbation désactivée.
- Émetteur et intérêt sont déclaratifs, non authentifiés.

## Prérequis

Créer les trois dossiers locaux `library`, `inbox`, `queue` à la racine
`G:\\BAW_OS\\pilots\\bridge-v33-isolated` avant le lancement. Ne pas
y placer de fichiers sensibles ou irremplaçables.

## Vérification préalable

Effectuer les tests du module queue et du module upload sous Linux Python 3.12 ;
arrêter le déploiement au moindre échec.

## Accès

- `http://127.0.0.1:18766/healthz`
- `http://127.0.0.1:18766/queue-v33` : aperçu des demandes
- `GET /api/v1/v33/queue` : registre documentaire
- `POST /api/v1/v33/queue` : déposer une fiche de demande complète
- `POST /api/v1/v33/inbox` : pilote de réception de fichiers, pas d'archives officielles

## Retour arrière

Depuis le dossier du clone `baw-os-deploy` :

```powershell
docker compose -f .\deploy\bridge-v33-isolated\compose.yaml down
```

Ne pas exécuter `down -v`, `volume prune` ou `system prune`.
Les dossiers pilotes sur G: restent à conserver jusqu'à une décision explicite.
