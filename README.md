# DNS-driven failover for Application Load Balancers on Google Cloud

This repository contains infrastructure-as-code for my deep dive on Google's new(ish), Envoy-based, Application Load Balancers &ndash; global and regional.

I also published an [article explaining the architecture](https://medium.com/@olliefr/global-load-balancer-failover-62e98a0f1253) for this deployment.

In my opinion, you'd enjoy studying the article and the code in this repo if you are interested in learning more about one of the following topics on Google Cloud:

* Application Load Balancers (HTTP and HTTPS) on Google Cloud, and their limitations.
* Multi-Cloud architecture (Google Cloud + AWS).
* High Availability (HA) systems.
* Serverless architecture.
* TLS certificates (vendor and self managed) and TLS configuration for maximum security.
* Best practices in modern Terraform infrastructure-as-code.

Please bear in mind that a work of this scale is never *truly* finished. Questions, comments, and suggestions are welcome!

## Deployment

Pre-deployment configuration:

* Set up your credentials for Google Cloud SDK (`gcloud`)
* Set up your credentials for AWS. There is a section on this later in this document.
* Decide what Terraform backend you'd like to use and adjust the configuration in `versions.tf`

Deployment is a three-step process:

1. Apply Terraform configuration! This should deploy enough infra to enable the next step.
2. Provision your Let's Encrypt certificates by following the relevant section in this document.
3. Apply Terraform configuration *again*! This time it will pick up the certificate and private key files and finish setting up the infrastructure for this project.

At this point you should have the service responding to requests via the global external ALB. You can verify that by checking the CA on the TLS certificate returned by the server.

* Global external ALB is configured with a managed TLS certificate issued by Google CA.
* Regional external ALB serves a user-managed TLS certificate issued by Let's Encrypt.

To simulate global external ALB failure, rerun Terraform configuration with the `simulate_failure` flag set to `true`:

```bash
terraform apply -var "simulate_failure=true"
```

After having done this, you should be able to see the DNS health probes failing in your AWS Route 53 console. After the predefined number of failures, the DNS entries will switch, and new requests are going to be served by the regional external ALB.

To reverse the effect, run the Terraform `apply` command again, with `simulate_failure` set to  `false`:

```bash
terraform apply -var "simulate_failure=false"
```

The following sections provide more details on different aspects of this deployment. Also don't forget to check out the [article] for which this infrastructure-as-code was written.

[article]: https://medium.com/@olliefr/global-load-balancer-failover-62e98a0f1253

## DNS records

The DNS zone is hosted with Route 53.

This project makes the following DNS configuration:

* Creates records for DNS authorisation for use with Google-managed SSL certificates.
* Creates a primary record for the global HTTPS load balancer's IP.
* Creates a secondary record for the regional HTTPS load balancer's IP.
* Creates a DNS health-check to enable failover from the primary to the secondary record.

## AWS credentials

AWS is my weakest spot at the moment. So, the following is a record of how I muddled through to set up access to Route 53 API for my Terraform.

I installed [AWS CLI], the next step I suppose would be to log in somehow to generate some kind of access token, like with `gcloud auth login`. But AWS appear to have a wide range of [authentication and access credentials], which is all new to me. Guided by inexperience and intuition, I chose what I think is an acceptable, though not ideal, solution:

I created an IAM group `Administrators-DNS` and attached a managed IAM policy `AmazonRoute53FullAccess` to the group. I then created an IAM user `terraform-manage-dns` and added it to the group. Console access is disabled for the user. Finally, I created the access keys credentials for the user.

To use the access key credentials with this module, set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` environment variables. Then the AWS provider will pick up the credentials from the environment.

I will review this setup once I learn more about IAM roles in AWS.

[AWS CLI]: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
[authentication and access credentials]: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-authentication.html
[short-term credentials]: https://docs.aws.amazon.com/cli/latest/userguide/cli-authentication-short-term.html

## Let's Encrypt

To create a user-managed Compute Engine SSL certificate resource, we need the actual certificate and the private key for it.

I went with Let's Encrypt for this proof-of-concept deployment. I used [gcsfuse] to mount a Cloud Storage bucket to my local file system, and then I run [Step CLI] to provision the certificate.

[Step CLI]: https://smallstep.com/docs/step-cli/basic-crypto-operations/#get-a-tls-certificate-from-lets-encrypt
[gcsfuse]: https://cloud.google.com/storage/docs/gcs-fuse

```bash
# Domain name for Hello Service. This value goes into the TLS certificate we provision from Let's Encrypt.
FQDN="hello-service.dev.devilmicelabs.com"

# Host part of Hello Service FQDN
HOST="hello-service"

# The value of 'acme_bucket' output from the Terraform root module.
BUCKET=$(terraform output -no-color -raw acme_bucket)

# Let's Encrypt Staging server - use this for experiments. Unlike Production, it's not throttled.
ACME_TEST="https://acme-staging-v02.api.letsencrypt.org/directory"

# Let's Encrypt Production server - only use this when ready. Don't overload it. It's rate throttled.
ACME_PROD="https://acme-v02.api.letsencrypt.org/directory"

# Create an empty directory to serve as a mount point for the Cloud Storage $BUCKET.
mkdir -p ${HOME}/mnt/gcs/.well-known/acme-challenge

# Mount the Cloud Storage $BUCKET under the local file system path.
gcsfuse $BUCKET ${HOME}/mnt/gcs/.well-known/acme-challenge/

# Request the TLS certificate from Let's Encrypt. If OK, .crt file is the certificate, and .key file is the private key.
# This command will use the Staging server, adjust for Production accordingly.
step ca certificate $FQDN ${HOST}.crt ${HOST}.key --acme $ACME_TEST --webroot ${HOME}/mnt/gcs

# (Optional) Inspect the certificate.
openssl x509 -in ${HOST}.crt -text -noout

# (Optional) Unmount the Cloud Storage bucket from the local filesystem.
umount ${HOME}/mnt/gcs/.well-known/acme-challenge/
```

With the certificate and the private key files in hand, I am ready to create a user-managed Compute Engine SSL certificate resource and to deploy the regional ALB.

## Mapping between Google Cloud and Terraform resources

This section is a ready reckoner for a set of Terraform Google provider resources that have to do with Network Endpoint Groups (NEG) resources on Google Cloud.

`google_compute_global_network_endpoint_group` contains endpoints that reside *outside* of Google Cloud.

* [Terraform docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_network_endpoint_group)

  Endpoint type: `INTERNET_IP_PORT` or `INTERNET_FQDN_PORT` only.

* [Google REST API docs](https://cloud.google.com/compute/docs/reference/rest/v1/globalNetworkEndpointGroups)

`google_compute_region_network_endpoint_group` supports serverless products. This is what you use for regional *and* global load balancers' backends.

* [Terraform docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_region_network_endpoint_group)

  Endpoint type: `SERVERLESS` or `PRIVATE_SERVICE_CONNECT` only.

* [Google REST API docs](https://cloud.google.com/compute/docs/reference/rest/v1/regionNetworkEndpointGroups)

`google_compute_network_endpoint_group` are *zonal* resources.

* [Terraform docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network_endpoint_group)

  Endpoint type: `GCE_VM_IP`, `GCE_VM_IP_PORT`, or `NON_GCP_PRIVATE_IP_PORT` only.

* [Google REST API docs](https://cloud.google.com/compute/docs/reference/rest/v1/networkEndpointGroups)


## Limitations

* Regional external ALBs have a severe limit on QPS for Cloud Run backends: [docs](https://cloud.google.com/load-balancing/docs/negs/serverless-neg-concepts#limitations-reg)
