# Assistant de redéploiement BAW OS

Lancer sous Windows :

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\Install-BAW-OS.ps1
```

Le script :

1. demande le dossier d'installation ;
2. crée l'arborescence manquante ;
3. contrôle Git et les dépôts ;
4. contrôle Docker Desktop et Compose ;
5. détecte l'état de n8n ;
6. détecte Ollama et les modèles locaux ;
7. conserve ou crée le secret PostgreSQL ;
8. génère les rapports dans `recovery-log`.

Il n'installe pas encore automatiquement les dépendances absentes.