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
