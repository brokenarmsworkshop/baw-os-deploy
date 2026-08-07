# BAW Secrets Bootstrap

## Objectif

Le bootstrap centralise la création et la restauration des secrets nécessaires
à BAW OS.

Les valeurs sensibles sont écrites hors Git, dans le dossier `secrets` de la
racine d'installation.

## Protections

- un fichier distinct par secret ;
- un seul secret canonique par application ;
- compte PostgreSQL d'administration séparé du compte d'automatisation ;
- secret d'automatisation : `postgres\baw_automation_password.txt` ;
- chemins dédiés : `notion`, `mistral`, `openai`, `github`, `smtp`, `wsl` ;
- migration sûre des anciens fichiers du dossier `providers` ;
- les valeurs sensibles sont masquées ; les identifiants non sensibles restent visibles ;
- identifiants WSL : utilisateur `bawops` et mot de passe technique généré ;
- affichage temporaire et copie avec effacement automatique du presse-papiers ;
- héritage NTFS conservé et contrôle total explicitement accordé au compte courant ;
- copie locale DPAPI liée au compte Windows ;
- export portable AES-256 protégé par mot de passe maître ;
- index documentaire sans aucune valeur sensible ;
- aucun secret dans le dépôt `baw-os-deploy`.

## Restauration

Le coffre portable permet de restaurer les secrets sur un nouveau disque ou un
nouveau poste, à condition de conserver son mot de passe maître.

La sauvegarde DPAPI locale ne doit pas être considérée comme portable : elle est
liée au compte Windows qui l'a créée.

Les coffres portables de schéma 1 créés avant la V1.9 restent compatibles.
Lorsqu'une nouvelle entrée WSL est absente d'un ancien coffre, elle peut être
complétée dans l'interface puis enregistrée sans migration destructive.

## n8n

La clé `N8N_ENCRYPTION_KEY` doit rester stable pendant la durée de vie de
l'instance. Elle est sauvegardée avec les autres secrets, séparément de la base
PostgreSQL.

Les fichiers secrets seront montés dans les conteneurs via Docker Compose et
lus avec les variables de configuration suffixées par `_FILE` lorsque le
service le permet.
