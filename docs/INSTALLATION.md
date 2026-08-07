# Installation propre de BAW OS

## Principe

Ce déploiement doit pouvoir être reconstruit à partir :

1. des dépôts Git ;
2. des fichiers de configuration ;
3. des sauvegardes PostgreSQL ;
4. des exports n8n ;
5. des secrets conservés séparément.

## Données non versionnées

Les volumes Docker, bases actives, journaux, caches et secrets restent hors Git.


## ComfyUI / LTX

La recette du socle local ComfyUI/LTX est conservee dans `deploy/comfyui-ltx/`.

Les versions validees, les montages et le manifeste du modele sont documentes dans `docs/COMFYUI-LTX.md`.

Les modeles IA restent hors Git.
