# DR Drill Setup (1)

Below are the steps for DR.

(a) Prepare all the infra in Hyderabad region - done

(b) Once we get a go ahead from you, then we will promote the Hyderabad RDS and DocumentDB read replicas to the master

(c) Validate all the ECS services and make them running in the Hyderabad region

(d) Once the parallel url like

[prod-dr.crego.io](http://prod-dr.crego.io/)

is validated then reduce the replica size to 0 and terminate the RDS and document DB instance.

(e) Once we choose the date as for eg 18th March for the DR, then we will replicate the RDS and DocumentDB again in Hyderabad region on 17th March

Steps execution during DR on 18th March at 2pm from Mumbai to Hyderabad

(a) Shutdown the Mumbai region

(b) Promote the read replica to the master in Hyderabad region

(c) Increase the replica of the Hyderabad region and make sure that everything is working in Hyderabad region

(d) Switch the DNS mapping to the Hyderabad region

(e) Validate everything is working fine and prod is ready

Switch back from Hyderabad to the Mumbai region

(a) Create the read replica of the RDS and DocumentDB from Hyderabad to the Mumbai region and promote them to the master

(b) Spin up the Mumbai region

(c) Increase the replicas in Mumbai region

(d) Switch over the Cname to Mumbai.

Note down the RTO and RPO time during this activity.