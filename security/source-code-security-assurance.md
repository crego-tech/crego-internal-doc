# Source Code Security Assurance

Author: Abhishek Sharma
Status: In Review
Category: PRD
Last edited time: December 4, 2025 1:25 PM

### **1. Static Application Security Testing (SAST)**

**Tool**: SonarQube or CodeQL

**When**: On every Pull Request (PR) and nightly builds

**How**:

- Integrate into CI pipeline (e.g., GitHub Actions/GitLab CI)
- Define fail-gate thresholds (e.g., block merge if critical issue is found)
- Developers review SAST reports during PR reviews
    
    **Owner**: DevSecOps
    

---

### **2. Dynamic Application Security Testing (DAST)**

**Tool**: OWASP ZAP or Burp Suite (Automated scan mode)

**When**: After every QA deployment (staging environment)

**How**:

- Run automated scan against running app in staging
- Focus on endpoints handling sensitive data (login, user update, file upload)
- Set up DAST job in CI/CD (triggered post-deployment)
    
    **Owner**: QA Security Analyst
    

---

### **3. Software Composition Analysis (SCA)**

**Tool**: Snyk or OWASP Dependency-Check

**When**: On every dependency update / release branch

**How**:

- Integrate in pipeline to scan package.json, requirements.txt, etc.
- Auto-fail build on known CVEs with high/critical severity
- Weekly vulnerability report generated
    
    **Owner**: DevSecOps + Developers
    

---

### **4. Secrets Scanning**

**Tool**: GitGuardian / Gitleaks

**When**: Every code commit / PR

**How**:

- Configure pre-commit hooks to scan for secrets
- Block commits to main if secrets found
- Periodic scan of entire repo history
    
    **Owner**: Developers (enforced by CI)
    

---

### **5. Code Quality & Linting**

**Tool**: ESLint, Pylint, SonarLint

**When**: Every PR / commit

**How**:

- Enforce lint rules with CI checks
- Use IDE plugins for real-time alerts
- Include lint as build step in pipeline
    
    **Owner**: Developers + Reviewer
    

---

### **6. Unit & Integration Security Testing**

**Tool**: JUnit / pytest / Jest (language-dependent)

**When**: Every commit and PR

**How**:

- Write unit tests for auth checks, input sanitization, role permissions
- Include negative test cases (e.g., invalid tokens, XSS strings)
- Minimum test coverage required (e.g., 80%)
    
    **Owner**: Developers + QA
    

---

### **10. Threat Modeling**

**Tool**: Microsoft Threat Modeling Tool / OWASP Threat Dragon

**When**: At the beginning of major feature or architecture changes

**How**:

- Identify assets, trust boundaries, threats (using STRIDE model)
- Document mitigations for each threat
- Review output as part of design sign-off
    
    **Owner**: Architecture Team + Security Lead
    

---

### **12. Secure CI/CD Integration**

**Tool**: GitHub Actions / GitLab CI / Jenkins

**When**: Always-on

**How**:

- Pipeline steps:
    1. **Checkout Code**
    2. **Run Lint + Unit Tests**
    3. **Run SAST**
    4. **Run Secrets Scan**
    5. **Build + Deploy to Staging**
    6. **Run DAST in Staging**
    7. **Run SCA on dependencies**
- Fail gates on high-severity issues
- Notifications sent to Slack/email for any failure
    
    **Owner**: DevSecOps
    

---

### **Summary Table**

| **Security Task** | **Tool(s) Used** | **Trigger Point** |
| --- | --- | --- |
| Static Analysis (SAST) | SonarQube | Every PR |
| Dynamic Analysis (DAST) | OWASP ZAP, Burp Suite | Post QA Deploy |
| Dependency Scan (SCA) | Snyk, OWASP DC, Dependabot | Every build & monthly report |
| Secrets Scanning | GitGuardian, Gitleaks | Every commit/PR |
| Code Linting | ESLint, Pylint, SonarLint | Every PR |
| Secure CI/CD | GitHub Actions | Every pipeline |