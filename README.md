# "On-prem" kubernetes demo for FortiCNAPP

This repo hosts code to create a demo Kuberenetes cluster to be integrated with FortiCNAPP. The goal is to demonstrate all the integrations available for K8s running without leveraging any public cloud integrations.

## Demo components

This demo includes:

- terraform deploying a tiny demo cluster in public cloud (GCP)
- argocd
- code building a demo workload
- CI/CD for building demo workload
- image repository

## Scanners

The following controls are available when securing this demo setup:

- k8s agent
- image repository scanner
- IaC code security scanner
- workload source code security scanner against git repo
- workload source code scanner in CI/CD

## Deployment steps

1. Get a real DNS domain if you want real certificates.
1. Provide your domain name and email as `dns_root` and `acme_email` variables
1. Deploy terraform (note: terraform will try to pull GCP authentication from environment, if you want to provide a key instead you have to modify provider block in main.tf): `cd tf-infra; terraform init && terraform apply`
1. After deployment wait few minutes, you can monitor progress in instance serial log (you're good once all you see is 'apparmor="AUDIT"')
1. In the meantime set a wildcard DNS record for *.\<your domain\> pointing to the IP address of load balancer (`output.lb_ip`)
1. login to your node using ssh in browser (or `gcloud compute ssh`)
1. get your argocd admin password using command `microk8s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`
1. you can login to your argo at https://argocd.\<your domain\> as admin and password from the step above
1. once argo shows nginx application as green the initial deployment is complete
