
GITHUB_USER="eddiewebb"
KARGO_QUICKSTART_PAT=$GH_AKUITY_DEMO_PAT # Replace with your actual
GITHUB_REPOSITORY="argodemo-rollouts-app"
PROJECT_NAME="rollouts-app"


kargo create project $PROJECT_NAME
kargo apply -f project.yaml. #safe to re-run vs command above

kargo create credentials github-creds \
--project $PROJECT_NAME --git \
--username ${GITHUB_USER} --password ${KARGO_QUICKSTART_PAT} \
--repo-url https://github.com/${GITHUB_USER}/${GITHUB_REPOSITORY}


kargo create credentials ghcr-creds \
--project $PROJECT_NAME --image \
--username ${GITHUB_USER} --password ${KARGO_QUICKSTART_PAT} \
--repo-url ghcr.io/${GITHUB_USER}/rollouts

kargo apply -f warehouse.yaml 

kargo apply -f stages.yaml