# Control Center V3 — déploiement pilote

Recette indépendante des projets Compose PostgreSQL (`baw-os-postgres`) et n8n (`baw-os-n8n`).
Ne modifie ni leurs volumes `baw-postgres-data`, `baw-n8n-data`, ni leurs secrets.

## Prérequis

- Docker Desktop démarré ;
- dépôts voisins dans `G:\BAW_OS\repositories\baw-os-app` et `...\baw-os-deploy` ;
- les branches pilotes récupérées et extraites dans les deux clones ;
- réseau externe `baw-backend` existant.

## Pré-vérification et lancement

Depuis `G:\BAW_OS\repositories\baw-os-deploy` :

```powershell
docker compose -f .\deploy\control-center-v3\compose.yaml config
docker compose -f .\deploy\control-center-v3\compose.yaml up -d --build
docker compose -f .\deploy\control-center-v3\compose.yaml ps
```

Navigateur : `http://127.0.0.1:18765`.

## Retour arrière

```powershell
docker compose -f .\deploy\control-center-v3\compose.yaml down
```

Cette commande arrête uniquement le projet pilote et ne supprime aucun volume des projets BAW existants.

## Limites

Ce pilote n'est **pas** une migration fonctionnelle du Control Center Git V2.
Il prouve le déploiement web local et l'accès réseau en lecture seule aux services.
Ne pas publier le port au-delà de `127.0.0.1`. Ne pas ajouter `docker.sock` à ce conteneur.
