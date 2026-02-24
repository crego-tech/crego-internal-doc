# DR Drill Dec 2024 (1)

You can prepare document which covers below points. This is one-time document for BCP.

**Brief:**

Tyger Capital Pvt. Ltd. and Tyger Home Finance Pvt. Ltd. have <xyz> application as SaaS offering from <partner name>. Partner has hosted this application on <xyz cloud> where primary site is at <central india> and DR site is at <south india>. <Partner name> is providing the managed service support for the application, infrastructure, covering OS, Database, Webservers, Network and Security, and Backup and the disaster recovery management.

1. Objective of document

This document describes and provides details of DR setup, Standard Operational Procedure, failover and failback steps to be taken when the disruptive DR drill is invoked for the LMS application.

This is a guide for DR teams (Crego tools team, Database team, OS team and for the application teams, as a reference Technical guide)

1. List of Primary and DR site
    1. Primary: AWS Mumbai (ap-south-1)
    2. DR Site: AWS Hyderabad (ap-south-2)
2. Network diagram including DR site details and IT DR Architecture
    1. @Abhishek Sharma 
3. DR technology details
    
    VM’s, Type of DB, Replication method etc.
    
4. Application details/summary
5. Application/ Infrastructure sizing
    
    Resource sizes
    
6. DR Pre-Requisites
    
    Application, Server, DB details (hostname, Public and Private IP Address, OS, DB etc.)
    
7. Disaster Recovery (DR) Plan – DC to DR (fail-over)
    
    Detailed run-book with list of task, Type (pre-check, Drill activity, post-check), Responsibility, Planned Duration (Mins), Date, Start time, End time, Actual duration (mins), Remarks
    
8. Disaster Recovery (DR) Plan – DR to DC (fail-back)
    
    Detailed run-book with list of task, Type (pre-check, Drill activity, post-check), Responsibility, Planned Duration (Mins), Date, Start time, End time, Actual duration (mins), Remarks
    
9. DR Team structure
    
    BCP owner (Tyger), DR Lead (Partner), DR technical support team details (partner)
    
10. Roles and responsibilities for DR program
11. DR measures defined - Recovery Time Objective (RTO), Recovery Point Objective (RPO) etc.
12. DR testing schedule – Half-yearly basis
13. DR Infrastructure Health-check report
14. DR Testing Reports
15. DR replication logs for the audit period (Status, Time and date, name of the tool)
16. **Crisis management plan**
17. **Crisis management team structure**
18. **Incident management policy and procedure**
19. **Incident management logs for the audit period (should include at minimum the fields incident id, status , severity, assigned to, date etc)**
20. Data Backup Policy and Procedure
21. Backup restoration procedure document and periodicity
22. Backup restoration logs for the audit period
23. DR training program details
24. List of administrative accesses to the DR setup

**DR Drill report should cover below points:**

Brief:

1. Objective of document
2. DR Drill schedule (Date and Time of drill)
3. DR team contact details (Tyger and <partner name>) with email id and phone number.
4. Bridge details (if any)
5. DC and DR application details:
    
    Application, Server, DB etc. details along with hostname, DC private and public IP, DR private and public IP, OS, Application URL.
    
    1. Pre-requisites
    2. DC to DR fail-over steps
    
    Fill the runbook with actual details.
    
    1. DR to DC fail-back steps
    
    Fill the runbook with actual details.
    
    1. DC to DR - Failover evidence’s screen shot (from each team involved in DR drill according to DR Run book)
    2. DR to DC - Failback evidence’s screen shot (from each team involved in DR drill according to DR Run book)
    3. UAT team sign-off
    4. End user sign-off