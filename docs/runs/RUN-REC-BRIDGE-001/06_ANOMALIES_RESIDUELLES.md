# RUN-REC-BRIDGE-001 — Anomalies résiduelles

## BUG-UI-071 — Contraste monitoring en thème clair

**Sévérité :** faible / non bloquante
**Composant :** BAW HUM Bridge 0.7.1 — interface Firefox

### Observation

En thème clair, les valeurs de certaines cartes du bloc Monitoring Mistral présentent un contraste insuffisant sur leur fond sombre.

Cartes concernées :
- Aujourd'hui
- Niveau
- Requêtes
- Moyenne

Le thème sombre est correct.

### Impact

Aucun impact sur :
- le calcul du monitoring ;
- l'appel du webhook ;
- la diode ;
- les métriques ;
- le fonctionnement SLM/Mistral ;
- la persistance ;
- les fonctions Copier/Injecter.

### Décision

Ne pas corriger dans `RUN-REC-BRIDGE-001`.

Motif : le mandat impose de restaurer la 0.7.1 avant d'améliorer et interdit de transformer la restauration en refonte.

À traiter ultérieurement dans un correctif UI séparé.
