# Dépendances du redéploiement BAW OS

## Git

Git est utilisé pour restaurer et versionner :

- `baw-os-app` ;
- `baw-os-deploy`.

Les données actives, sauvegardes et secrets restent hors Git.

## Docker Desktop

Docker Desktop fournit le moteur Linux et Docker Compose.

Les données Docker doivent être placées dans le dossier `docker-data` de la
racine BAW OS sélectionnée.

## n8n

n8n est prévu comme service Docker. Une installation globale avec npm n'est
donc pas requise pour BAW OS.

Le simple état « Non déployé » est normal avant la création du fichier Compose
complet.

## Ollama

Ollama est le moteur SLM local prévu à ce stade.

Le contrôle porte sur :

- la commande `ollama` ;
- l'API locale sur le port 11434 ;
- les modèles déjà téléchargés.

Le choix du ou des modèles BAW OS sera documenté séparément.