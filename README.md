*Automated DevSecOps Pipeline Suite*

This repository contains a fully automated, containerized DevSecOps laboratory. It orchestrates the deployment and integration of HashiCorp Vault, GitLab, and DefectDojo into a unified security pipeline.

Project Architecture

The suite is designed with modularity and idempotency in mind. Each component is isolated into dedicated scripts, allowing for both individual execution and full-orchestration via a master script.

Key Components:

Secret Management: HashiCorp Vault acts as the central "Secret Store" for all API tokens and root passwords.

SCM & CI/CD: GitLab 17.x (Self-hosted) configured for automated project imports from external training sources.

Vulnerability Management: DefectDojo integrated with automated Product and Engagement creation via REST API.This project provides a fully automated, containerized environment for a modern DevSecOps lifecycle. 

It orchestrates HashiCorp Vault for secret management, GitLab for SCM/CI, and DefectDojo for vulnerability aggregation.


To run it in your environment:

1.Clone the Repository:

git clone https://github.com/nargiz5/devsecops-pipeline.git

cd devsecops-pipeline

2.Configure Environment:

in .env change:

HOST_IP and VAULT_URL

( I know that we should use .gitignore when pushing .env, and everyone should write its own env configuration.
But in this lab for simplicity I used .env for injecting the data predefined for lab to hashicorp)

3.Execute Deployment:

chmod +x run_all.sh

./run_all.sh
