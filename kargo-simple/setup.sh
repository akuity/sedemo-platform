source ../argodemo-infra-iac/.env

export GITHUB_USER="eddiewebb"
export GITHUB_PAT=$TF_VAR_gh_pat_kargo
export KARGO_PASSWORD=$TF_VAR_argo_admin_password


projects=$(kargo get projects|tail -n+2|cut -d' ' -f1)

for project in $projects; do
    echo "Publishing git credentials for project: $project"

    # Get repo URL for project
    repo_url=$(kargo get warehouses -p $project -o json | jq -r '.spec.subscriptions[] | select(.git !=null).git.repoURL')
    image_url=$(kargo get warehouses -p $project -o json | jq -r '.spec.subscriptions[] | select(.image !=null).image.repoURL')
    
    echo "Using repo URL: $repo_url, image URL ${image_url}"
    #echo "Using GH PAT var name: $gh_pat_var_name"
    # Publish git credentials to Kargo secrets
    kargo create credentials github-creds \
    --project $project --git \
    --username ${GITHUB_USER} --password ${GITHUB_PAT} \
    --repo-url $repo_url

    kargo create credentials ghcr-creds \
    --project $project --image \
    --username ${GITHUB_USER} --password ${GITHUB_PAT} \
    --repo-url $image_url


done
