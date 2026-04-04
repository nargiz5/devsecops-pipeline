This project provides a fully automated, containerized environment for a modern DevSecOps lifecycle. 

It orchestrates HashiCorp Vault for secret management, GitLab for SCM/CI, and DefectDojo for vulnerability aggregation.


To run it in your environment:

1. Clone the Repository:

git clone https://github.com/nargiz5/devsecops-pipeline.git

cd devsecops-pipeline

2. Configure Environment:

in .env change:

HOST_IP and VAULT_URL

( I know that we should use .gitignore when pushing .env, and everyone should write its own env configuration.
But in this lab for simplicity I used .env for injecting the data predefined for lab to hashicorp)

4. Execute Deployment:

chmod +x run_all.sh

./run_all.sh
