# Crego Platform V2

## **1. Loan & Product Management (LMS Core)**

- **Multi-loan and multi-tranche support**
    
    Supports multiple concurrent loans and multiple disbursement tranches under a single facility with independent schedules.
    
- **Product / Program / Customer-wise loan summary**
    
    Consolidated view of exposure, outstanding, disbursements, and repayments at each hierarchy level.
    
- **Loan-level and account-level ledger summaries**
    
    Detailed accounting view of balances, movements, and postings for every loan and ledger account.
    
- **Fractional difference handling**
    
    Automatically manages rounding differences and residual amounts to ensure ledger balancing.
    
- **Write-off, loss settlement, and recovery management**
    
    Structured process to write off NPAs, record losses, and track post write-off recoveries.
    
- **Routed lending support (SCF & Term Loans)**
    
    Enables routing of disbursements and repayments through anchors or intermediaries.
    
- **Co-lending support (SCF & Term Loans)**
    
    Supports multiple lenders in a single loan with independent accounting and reporting.
    
- **Component-level split**
    
    Separates principal, interest, fees, and charges for precise allocation across lenders.
    
- **Three synchronized loan snapshots**
    
    Maintains aligned views for Borrower, Lender, and Co-lender without data inconsistency.
    

---

## **2. Customer, Anchor & Counterparty Management**

- **Entity categorization (Customers, Anchors, Buyers, Sellers, etc.)**
    
    Flexible tagging and classification for risk, reporting, and workflow control.
    
- **Limit management (Customer, Loan, Anchor, Program, Product)**
    
    Enforces exposure caps at every business level with real-time utilization tracking.
    
- **Fees and charges management**
    
    Configurable fee structures applicable across customers, loans, programs, and products.
    

---

## **3. Flexible LOS (Loan Origination System)**

- **Customizable onboarding journey**
    
    Configurable steps based on product, customer type, and regulatory requirements.
    
- **Configurable KYC workflows**
    
    Supports individual and non-individual KYC with document and rule flexibility.
    
- **End-to-end journey visibility**
    
    Complete traceability from lead creation to final disbursement.
    
- **Customizable BRE (Business Rule Engine)**
    
    Rule-based eligibility, pricing, and decisioning at multiple hierarchy levels.
    
- **Policy checklist with deviation handling**
    
    Captures policy compliance, deviations, and approval justifications in-system.
    
- **External system integrations**
    
    API-based integrations with bureaus, GST, banking, and third-party data providers.
    

---

## **4. Workflow, Controls & Governance**

- **Multi-stage maker-checker workflows**
    
    Supports sequential and parallel approvals across operational and financial actions.
    
- **Role-based access control (RBAC)**
    
    Granular permission control based on role, department, and responsibility.
    
- **Approval history and audit trail**
    
    Immutable record of every approval, rejection, and modification.
    
- **Bulk upload capabilities**
    
    Mass ingestion of customers, loans, payments, and limits with validations.
    
- **Bulk approvals**
    
    Batch approval flows while maintaining individual audit trails.
    

---

## **5. Accounting, GL & Financial Controls**

- **Product-wise GL account mapping**
    
    Maps accounting entries dynamically based on product and transaction type.
    
- **Controlled GL posting rules**
    
    Ensures accounting consistency with configurable posting logic.
    
- **Journal voucher posting with maker-checker**
    
    Enforces approval before financial impact on books.
    
- **Financial period management**
    
    Supports opening, closing, and locking of accounting periods.
    
- **Month-end reporting control**
    
    Prevents backdated changes post closure and ensures reporting integrity.
    

---

## **6. Document Management System (DMS)**

- **Centralized document repository**
    
    Secure storage of all customer, loan, and compliance documents.
    
- **Document categorization**
    
    Documents linked to customer, loan, product, or program context.
    
- **Automatic expiry tracking**
    
    Tracks document validity dates without manual intervention.
    
- **Expiry alerts and notifications**
    
    Proactive reminders to avoid compliance lapses.
    

---

## **7. Reporting, Audit & Analytics**

- **System and custom reports**
    
    Standard and configurable reports generated directly from source data.
    
- **100% audit trail-backed reporting**
    
    Every report line traceable to transaction and user action.
    
- **Audit reports**
    
    Covers financial, operational, and user activity audits.
    
- **Product dashboards and analytics**
    
    Real-time insights into portfolio performance and risk metrics.
    

---

## **8. Dashboards & User Experience**

- **Role-based dashboards**
    
    Personalized dashboards based on user role and responsibilities.
    
- **Anchor login and dashboard**
    
    Visibility into programs, limits, utilization, and repayments.
    
- **Customer login and dashboard**
    
    Self-service access to loan details, statements, and documents.
    

---

## **9. Notifications & Communication**

- **Centralized notification engine**
    
    Single system for managing all outbound communications.
    
- **Multi-channel communication**
    
    Supports email, SMS, and in-app notifications.
    
- **Event-based triggers**
    
    Automated alerts for approvals, disbursements, overdues, and expiries.
    

---

## **10. Compliance, Auditability & Trust**

- **End-to-end auditability**
    
    Every data change and action is logged with user and timestamp.
    
- **Regulatory-grade traceability**
    
    Ensures compliance with internal, statutory, and audit requirements.