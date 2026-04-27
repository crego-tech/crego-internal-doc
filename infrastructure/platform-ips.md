## Dev

Egress (Outbound - our pods calling vendor APIs):

- `34.93.169.151` (NAT IP)

Ingress (Inbound - If vendors need to call your services):

- `34.111.207.61` (Main app)

## Preprod

Egress (Outbound - our pods calling vendor APIs):

- `34.47.153.186` (NAT IP)
- `35.244.57.192` (NAT IP)

Ingress (Inbound - If vendors need to call your services):

- `35.190.126.196` (Main app)

## Prod

Egress (Outbound - our pods calling vendor APIs):

- `34.100.213.44` (NAT IP)
- `34.47.139.78` (NAT IP)

Ingress (Inbound - If vendors need to call your services):

- `34.54.253.214` (Main app)

> These are the egress IPs used by our shared-environment applications when calling third-party APIs. Share these with vendors who need to whitelist our outbound traffic.
