# Crego Platform Architecture Documentation

This directory contains comprehensive architecture diagrams for the Crego SaaS platform, designed for enterprise client presentations, security/compliance reviews, and internal technical documentation.

## Overview

Crego is a multi-tenant financial services platform built with a modern microservices architecture, deployed across multiple cloud providers (GCP and AWS) using Kubernetes and GitOps practices.

### Platform Components

- **Frontend Applications**: React-based SPAs (Omni Web, Flow Web)
- **Backend APIs**: Django REST (Omni API) and FastAPI (Flow API)
- **Background Processing**: Celery workers with RabbitMQ message broker
- **Data Layer**: PostgreSQL (multi-tenant), MongoDB (per-tenant workflows), Redis (shared cache)
- **Infrastructure**: Kubernetes (GKE/EKS), ArgoCD (GitOps), Terraform

---

## Directory Structure

```
architecture/
├── README.md                                    ← You are here
├── TECH_STACK.md                                # Detailed tech stack per repo
├── TECH_STACK_SUMMARY.md                        # Condensed tech stack reference
├── high-level-design/
│   ├── 01-system-architecture.md                # System components and interactions
│   ├── 02-deployment-topology.md                # Multi-cloud deployment architecture
│   └── infrastructure-diagrams.md               # GCP & AWS architecture and networking diagrams
├── tenancy-model/
│   └── 03-multi-tenancy-isolation.md            # Data isolation architecture
└── data-flow/
    └── 04-request-flow.md                       # End-to-end request tracing
```

---

## Architecture Diagrams

### 1. [System Architecture](high-level-design/01-system-architecture.md)

**Purpose**: High-level overview of all major system components, their interactions, and data flow

**Target Audience**: Technical teams (CTO, architects, developers), enterprise clients

**What's Included**:
- Frontend layer (Omni Web, Flow Web)
- API layer (Omni API, Flow API)
- Worker layer (Celery workers and beat schedulers)
- Data layer (PostgreSQL, MongoDB, Redis, RabbitMQ)
- Authentication flow (OIDC/JWT with tenant resolution)
- Service integration patterns

**Use Cases**:
- Technical discovery sessions with enterprise clients
- Onboarding new engineering team members
- Architecture review sessions
- Technical due diligence

---

### 2. [Deployment Topology](high-level-design/02-deployment-topology.md)

**Purpose**: Multi-cloud, multi-environment deployment architecture with tenant isolation

**Target Audience**: DevOps teams, infrastructure engineers, enterprise clients

**What's Included**:
- Cloud provider setup (GCP primary, AWS secondary)
- Environment matrix (Dev, Production across both clouds)
- Kubernetes cluster architecture (GKE/EKS)
- Shared vs per-tenant components
- Managed services (Cloud SQL, RDS, Memorystore, ElastiCache)
- Infrastructure tools (Terraform, Kustomize, ArgoCD)
- Autoscaling strategies (KEDA, HPA)

**Use Cases**:
- Infrastructure planning and cost estimation
- Disaster recovery and high availability discussions
- Cloud migration planning
- Capacity planning sessions

---

### 3. [Multi-Tenancy Isolation](tenancy-model/03-multi-tenancy-isolation.md)

**Purpose**: Complete data isolation architecture for security and compliance

**Target Audience**: Security teams, compliance auditors, CISOs, enterprise security officers

**What's Included**:
- Tenant resolution flow (domain → tenant config → database routing)
- Database-per-tenant model (PostgreSQL + MongoDB)
- Per-tenant queues in RabbitMQ
- Per-tenant worker deployments
- Redis key prefixing strategy
- TenantMiddleware and TenantDatabaseRouter implementation
- Security boundaries and isolation guarantees

**Use Cases**:
- SOC 2 / ISO 27001 compliance reviews
- Enterprise security assessments
- GDPR/data residency discussions
- Security architecture reviews

---

### 4. [Request Flow](data-flow/04-request-flow.md)

**Purpose**: End-to-end request tracing from client to database

**Target Audience**: Developers, QA engineers, performance engineers

**What's Included**:
- Synchronous API request flow (HTTP → Load Balancer → API → Database)
- Asynchronous background task flow (API → RabbitMQ → Celery Worker → Database)
- Workflow execution flow (Flow API → MongoDB → Omni API calls)
- Authentication and tenant resolution at each step
- Error handling and retry mechanisms

**Use Cases**:
- Performance optimization
- Debugging production issues
- API integration development
- Load testing planning

---

### 5. [Infrastructure Diagrams](high-level-design/infrastructure-diagrams.md)

**Purpose**: GCP and AWS architecture and networking diagrams with detailed component views

**Target Audience**: DevOps engineers, infrastructure teams, security teams

**What's Included**:
- GCP architecture diagram (load balancer, GKE cluster, services, secret management)
- AWS architecture diagram (ALB, EKS cluster, services, secret management)
- GCP networking diagram (VPC, private nodes, Cloud NAT, traffic flows)
- AWS networking diagram (Multi-AZ VPC, public/private subnets, NAT gateways)
- GCP vs AWS architectural differences comparison

---

## Viewing the Diagrams

### GitHub

All diagrams use Mermaid syntax and render automatically in GitHub's markdown viewer:

1. Navigate to any diagram file (e.g., `high-level-design/01-system-architecture.md`)
2. GitHub will automatically render the Mermaid diagrams

### VS Code

Install the Mermaid extension for live preview:

1. Install [Markdown Preview Mermaid Support](https://marketplace.visualstudio.com/items?itemName=bierner.markdown-mermaid)
2. Open any diagram file
3. Press `Cmd+Shift+V` (Mac) or `Ctrl+Shift+V` (Windows/Linux) for preview

### Mermaid Live Editor

For interactive editing and exporting:

1. Visit [mermaid.live](https://mermaid.live)
2. Copy the Mermaid code from any diagram
3. Edit interactively
4. Export as PNG, SVG, or PDF

### Documentation Sites

If using Docusaurus, MkDocs, or similar:

- Mermaid diagrams are supported with plugins
- Follow your documentation platform's Mermaid integration guide

---

## Target Audience Guide

### For Executive Presentations (CTO, VP Engineering)

**Recommended Diagrams**:
1. System Architecture (01) - Show overall platform capabilities
2. Deployment Topology (02) - Demonstrate cloud redundancy and scalability

**Focus On**: Business value, scalability, reliability, cost optimization

---

### For Technical Teams (Developers, Architects)

**Recommended Diagrams**:
1. System Architecture (01) - Understand component interactions
2. Request Flow (04) - Learn data flow patterns
3. Multi-Tenancy Isolation (03) - Understand tenant separation

**Focus On**: Implementation details, integration patterns, best practices

---

### For Security/Compliance Reviews

**Recommended Diagrams**:
1. Multi-Tenancy Isolation (03) - Prove data isolation
2. Deployment Topology (02) - Show security boundaries
3. System Architecture (01) - Understand authentication flow

**Focus On**: Data isolation, encryption, access control, audit trails

---

### For Sales/Business Development

**Recommended Diagrams**:
1. System Architecture (01) - Platform capabilities overview
2. Deployment Topology (02) - Multi-cloud reliability story

**Focus On**: Scalability, reliability, enterprise-readiness, compliance

---

## Maintenance

### Update Schedule

- **Quarterly Review**: Review all diagrams for accuracy
- **After Major Changes**: Update immediately when architecture changes
- **Version Alignment**: Keep synchronized with code releases

### How to Update

1. **Identify Changes**: Review recent architectural changes
2. **Update Mermaid Code**: Edit the diagram source directly
3. **Verify Rendering**: Test in GitHub, VS Code, or mermaid.live
4. **Update Metadata**: Change "Last Updated" date in diagram file
5. **Add Notes**: Document what changed in the diagram's notes section
6. **Export Images**: Update PNG/SVG exports for presentations (optional)

### Version Control

All diagrams are version-controlled alongside code:

- Changes tracked in Git history
- Use conventional commit messages (e.g., `docs(arch): update deployment topology for new AWS region`)
- Link diagram updates to related code changes in commit messages

---

## Exporting for Presentations

### Export as Images

**Using Mermaid Live**:
1. Open [mermaid.live](https://mermaid.live)
2. Paste diagram code
3. Click "Actions" → Download PNG/SVG

**Using Mermaid CLI**:
```bash
# Install Mermaid CLI
npm install -g @mermaid-js/mermaid-cli

# Export diagram
mmdc -i high-level-design/01-system-architecture.md -o system-architecture.png
```

### PowerPoint Integration

1. Export diagrams as high-resolution PNG (use 2x or 3x scale)
2. Insert into PowerPoint slides
3. Add speaker notes with key talking points
4. Include diagram source link for reference

---

## Contributing

### Adding New Diagrams

1. Create a new markdown file in the appropriate sub-folder
2. Follow the template structure (see existing diagrams)
3. Include metadata: Title, Purpose, Audience, Last Updated
4. Add Mermaid diagram code
5. Write explanatory text for key components
6. Update this README with new diagram link and description

### Diagram Standards

- **Clarity**: Keep diagrams focused and uncluttered
- **Consistency**: Use similar colors, shapes, and terminology across diagrams
- **Simplicity**: Prefer multiple simple diagrams over one complex diagram
- **Accuracy**: Diagrams must match actual implementation
- **Context**: Include legends and explanatory notes

---

## Technology Stack Summary

### Frontend
- React 19.2.3 with TypeScript
- Vite build system
- Tailwind CSS v4, Radix UI, shadcn/ui
- TanStack Query (React Query)

### Backend
- **Omni API**: Django 5.2+, Django REST Framework, PostgreSQL
- **Flow API**: FastAPI, MongoDB, Motor (async MongoDB)

### Infrastructure
- **Container Orchestration**: Kubernetes (GKE on GCP, EKS on AWS)
- **GitOps**: ArgoCD with App-of-Apps pattern
- **Configuration**: Kustomize overlays
- **Secrets**: External Secrets Operator (GCP Secret Manager, AWS Secrets Manager)
- **Autoscaling**: KEDA (workers), HPA (APIs)
- **Monitoring**: Prometheus, Grafana, OpenTelemetry, Sentry

### Data Layer
- **PostgreSQL**: Multi-tenant with database-per-tenant model
- **MongoDB**: Per-tenant workflow databases
- **Redis**: Shared cache with tenant key prefixing
- **RabbitMQ**: Per-tenant queues for background jobs

### Background Processing
- **Celery**: Distributed task queue
- **RabbitMQ**: Message broker
- **Flower**: Celery monitoring UI

---

## Support and Questions

### Internal Resources

- **Engineering Wiki**: [Internal link to wiki]
- **Slack Channel**: #architecture-discussions
- **Office Hours**: Weekly architecture review sessions

### External Resources

- **GitHub Issues**: Report inaccuracies or request new diagrams
- **Email**: architecture-team@crego.example.com

---

## Future Enhancements

Planned diagrams for future releases:

- **CI/CD Pipeline Diagram**: GitHub Actions → ArgoCD → Kubernetes deployment flow
- **Security Architecture**: Defense-in-depth model with security controls
- **Scaling & Performance**: Autoscaling strategies and capacity planning
- **Disaster Recovery**: Backup, restore, and failover procedures
- **Cost Optimization**: Resource allocation and multi-tenant cost distribution
- **Data Flow Diagram**: Detailed data processing and transformation flows
- **Integration Architecture**: External system integrations and APIs

---

**Last Updated**: 2026-02-15

**Maintained By**: Platform Engineering Team

**Review Schedule**: Quarterly (Next review: 2026-05-15)
