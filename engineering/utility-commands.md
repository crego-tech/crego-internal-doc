# Utility Commands

Author: Abhishek Sharma
Status: Published
Category: PRD
Last edited time: December 4, 2025 1:16 PM

### Copy dev-gcp DB to local

```bash
PGPASSWORD=postgres dropdb -h localhost -p 5432 -U postgres --if-exists omni_dev_db_migrated
PGPASSWORD=postgres createdb -h localhost -p 5432 -U postgres omni_dev_db_migrated
PGPASSWORD=newPassword123 pg_dump -h localhost -p 15432 -U app_user omni_dev_db | PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres omni_dev_db_migrated
```