# V3.3 — Préparation du transfert Git vers G: sans activation

Le montage additionnel `compose.staging-prep.yaml` doit être activé **avec**
`compose.yaml` et jamais seul.

Ce montage ajoute uniquement :
- le clone Git de démonstration `bridge-v33-tests`, en **lecture seule** ;
- le dossier `G:\BAW_OS\pilots\bridge-v33-isolated\staging`, en **écriture**.

Aucun secret d'administration n'est monté. Le point d'accès
`/api/v1/v33/staging-capability` doit répondre avec `enabled: false`.
Même si Git est installé et les montages présents, le transfert depuis
Firefox reste donc impossible.

## Vérifications avant le démarrage

Le dossier staging est **réservé aux essais**, jamais aux archives
officielles. Ne pas déplacer ARC-0001 ou d'autres originaux dans ce dossier.

Créer `staging` sur G: avant `docker compose config`. Les montages ont
`create_host_path: false` pour éviter toute création silencieuse.
La première vérification concerne seulement `docker compose config`, puis
la reconstruction du pilote sur autorisation de l'auteur.

Après démarrage, vérifier `healthz`, `staging-capability`,
et le contrôle d'accès de `/stage`. Aucun jeton GitHub n'est utilisé.
Le clone Git reste une source de **test local**, pas une source universelle.

## Risques non résolus

La simple présence d'un secret local fixe n'est pas encore suffisante pour
autoriser une exploitation courante : limitation des tentatives, gestion
de session/CSRF, stockage du secret, protection contre les requêtes
concurrentes, journal d'audit et retour après erreur restent à tester.
Le transfert web doit rester désactivé jusqu'à leur examen.
