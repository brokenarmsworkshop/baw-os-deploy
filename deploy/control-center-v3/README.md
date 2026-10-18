# BAW Control Center V3.1 — pilote

Le projet Compose est **indépendant** de n8n et PostgreSQL existants et partage seulement le réseau externe `baw-backend`.

## Préparer les deux clones pilotes

```powershell
$base = "G:\BAW_OS\pilots\control-center-v3"
New-Item -ItemType Directory -Path "$base\library" -Force | Out-Null
git -C "$base\baw-os-app" pull --ff-only
git -C "$base\baw-os-deploy" pull --ff-only
Set-Location "$base\baw-os-deploy"
docker compose -f .\deploy\control-center-v3\compose.yaml config
docker compose -f .\deploy\control-center-v3\compose.yaml up -d --build
docker compose -f .\deploy\control-center-v3\compose.yaml ps
```

Ouvrir :
- `http://127.0.0.1:18765/`
- `http://127.0.0.1:18765/library`

Le seul bind mount est `G:/BAW_OS/pilots/control-center-v3/library` vers `/data/library:ro`.
Il est obligatoire et non créé automatiquement par Docker.
Ne pas déplacer des fichiers confidentiels ou des secrets dans cette bibliothèque de démonstration.

## Retour arrière

```powershell
docker compose -f .\deploy\control-center-v3\compose.yaml down
```

Ne pas utiliser `down -v`, `volume prune` ou `system prune`.

## Sécurité et limites

Le service ne peut ni écrire, ni supprimer, ni télécharger de fichiers ;
la page affiche les noms et tailles des fichiers du dossier pilote, et le hash SHA-256 sur demande.
L'accès web reste limité à la boucle locale Windows. Aucun port n'est ouvert sur le LAN.
Les images ne sont pas encore figées par digest, les tests ne sont pas exécutés sur le poste.
