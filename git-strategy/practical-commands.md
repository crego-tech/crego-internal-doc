### **Feature Development (Squash)**

```bash
# Create from Linear issue
git checkout -b feature/CRE-123-description develop

# Make commits (as many as needed)
git commit -m "feat: add user auth"
git commit -m "fix: auth validation"
git commit -m "test: add auth tests"

# Push and create PR
git push origin feature/CRE-123-description
# In GitHub: Choose "Squash and merge" to develop

```

### **Preprod Release**

```bash
# Create release branch
git checkout -b release/v2.0.0 develop

# Push to remote
git push origin release/v2.0.0
```

### **Main Release (Merge Commit)**

```bash
# After testing, merge to main with no-ff
git checkout main
git merge --no-ff release/v2.0.0 -m "Release v2.0.0"
git tag -a v2.0.0 -m "Version 2.0.0"

# Also merge back to develop
git checkout develop
git merge --no-ff release/v2.0.0 -m "Merge release v2.0.0 to develop"
```

### **Hotfix (Merge Commit)**

```bash
# Create from production branch (master or main depending on repo)
git checkout -b hotfix/cre-456-urgent master

# Make fix commits
git commit -m "fix: critical security issue"

# Push and create PR
git push origin hotfix/cre-456-urgent
# In GitHub: Choose "Create a merge commit" to master/main

# Tag the fix
git checkout master
git pull origin master
git tag -a v2.0.1 -m "Hotfix v2.0.1"

# Merge hotfix back to develop (merge commit)
git checkout develop
git merge --no-ff hotfix/cre-456-urgent -m "Merge hotfix v2.0.1 back to develop"
git push origin develop
```

### **Infrastructure Updates**

```bash
# For shared environment updates
git checkout env/prod
git merge --ff-only main  # Fast-forward only
git push origin env/prod
# ArgoCD auto-deploys

# For client-specific updates
git checkout clients/client-a/prod
git merge --squash main   # Squash main changes
# Add client-specific configs
git commit -m "feat: update client A to v2.0.0"
git push origin clients/client-a/prod

```