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
