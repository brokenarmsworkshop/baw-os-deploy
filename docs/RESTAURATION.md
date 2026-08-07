# Reprise après sinistre BAW OS

## Objectif

Valider le redéploiement complet de BAW OS sur un environnement propre.

## Contrôles principaux

- Docker Desktop opérationnel ;
- PostgreSQL opérationnel ;
- n8n opérationnel ;
- HUM Bridge opérationnel ;
- workflows restaurés ;
- secrets réinjectés ;
- tests fonctionnels exécutés ;
- sauvegarde finale créée.


## ComfyUI / LTX

Pour restaurer le socle video local, reconstruire le composant depuis `deploy/comfyui-ltx/`.

Les modeles sont retélécharges depuis les sources du manifeste puis controles par SHA-256.

Le controle final ComfyUI doit obtenir HTTP 200 sur `/system_stats`.
