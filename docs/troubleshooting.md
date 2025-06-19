### 4.2 Guide de dépannage (docs/troubleshooting.md)

```markdown
# Guide de Dépannage

## Problèmes courants

### 1. Erreur de connexion SQL
**Symptôme**: Cannot connect to server
**Solution**: Vérifier les règles de pare-feu Azure

### 2. Instance EC2 inaccessible
**Symptôme**: SSH timeout
**Solution**: Vérifier les groupes de sécurité AWS

### 3. Problème DNS
**Symptôme**: Nom de serveur non résolu
**Solution**: Attendre la propagation DNS (5-10 minutes)