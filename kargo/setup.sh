
export GITHUB_USER="eddiewebb"
export KARGO_QUICKSTART_PAT=$GH_AKUITY_DEMO_PAT # Replace with your actual



kargo create credentials github-creds \
--project $PROJECT_NAME --git \
--username ${GITHUB_USER} --password ${KARGO_QUICKSTART_PAT} \
--repo-url https://github.com/${GITHUB_USER}/${GITHUB_REPOSITORY}


kargo create credentials ghcr-creds \
--project $PROJECT_NAME --image \
--username ${GITHUB_USER} --password ${KARGO_QUICKSTART_PAT} \
--repo-url ghcr.io/${GITHUB_USER}/rollouts


export PROJECT_NAME="rollouts-app"
kargo create credentials ghcr-creds \
--project oom-demo --image \
--username ${GITHUB_USER} --password ${KARGO_QUICKSTART_PAT} \
--repo-url ghcr.io/${GITHUB_USER}/oom



kargo create credentials github-creds \
--project $PROJECT_NAME --git \
--username ${GITHUB_USER} --password ${KARGO_QUICKSTART_PAT} \
--repo-url https://github.com/akuity/sedemo-app-monorepo
