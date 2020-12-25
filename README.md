# az-devops-k8s-agent
Self-Hosted Azure Devops Agent for kubernetes

## Setup via pre-built image
Docker Image : shubhamranjan/az-devops-k8s-agent:latest

1. Modify samples/create_secret.sh with the required Azure Devops Organisation URL, PAT and Agent Pool Name.

2. Run the script or the command directly in the required namespace.

     `sh ./samples/create_secret.sh`

3. Apply samples/deployment.yml after making any required changes like namespace (if modified in the previous step).

    `kubectl apply -f samples/deployment.yml`