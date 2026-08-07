# ComfyUI / LTX local

## Objet

Cette recette conserve dans `baw-os-deploy` le socle Docker ComfyUI/LTX valide pour les essais locaux de generation video.

Principe : Git conserve la recette de reconstruction, jamais les modeles lourds, les caches, les donnees runtime ou les secrets.

## Etat valide le 7 aout 2026

- Docker Desktop 29.6.1
- WSL2 / moteur Docker Linux operationnel
- GPU de reference : NVIDIA RTX 2070 SUPER, 8 Go VRAM
- CUDA visible depuis Docker
- image locale : `baw/comfyui-test:v2`
- ComfyUI : `v0.24.0`
- PyTorch : `2.11.0`
- torchvision : `0.26.0`
- torchaudio : `2.11.0`
- endpoint `/system_stats` : HTTP 200

## Recette Git

Les fichiers reconstructibles sont conserves dans `deploy/comfyui-ltx/` :

- `Dockerfile`
- `compose.yaml`
- `.dockerignore`
- `.env.example`
- `models-manifest.json`

Le fichier `.env` reel ne doit jamais etre versionne.

## Donnees persistantes

Installation de reference : `G:\tools\comfyui-ltx-test`

Montages valides :

- `data/models` -> `/opt/ComfyUI/models`
- `data/user` -> `/opt/ComfyUI/user`
- `data/temp` -> `/opt/ComfyUI/temp`
- `data/input` -> `/opt/ComfyUI/input`
- `data/output` -> `/opt/ComfyUI/output`
- `data` -> `/data`

Ces donnees restent hors Git.

## Modele LTX valide

Checkpoint : `ltxv-2b-0.9.6-distilled-04-25.safetensors`

Emplacement local : `data/models/checkpoints/`

SHA-256 : `94891BD4BD08DE30D484BEFBFC54FDCFFE6D1596A131BAAD700B9BAA5E1DE86B`

Le checkpoint reste hors Git. Sa source et son empreinte sont conservees dans `models-manifest.json`.

## Controle apres reconstruction

La reconstruction est conforme lorsque :

1. Docker Desktop fonctionne.
2. Le moteur Docker repond.
3. Le GPU NVIDIA est visible depuis Docker.
4. Le conteneur ComfyUI demarre.
5. `http://localhost:8188/system_stats` retourne HTTP 200.
6. Les montages persistants sont corrects.
7. Les modeles correspondent aux SHA-256 declares.

## Etat de reprise

Valide :

- socle Docker
- ComfyUI
- montages persistants
- checkpoint LTX 2B distille

Reste a valider lors du prochain run :

- encodeur texte
- workflow ComfyUI image-to-video
- premier test video local
- consommation VRAM et RAM
- temps de generation et stabilite
- conversion video eventuelle pour Godot
