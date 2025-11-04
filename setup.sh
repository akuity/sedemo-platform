source ../argodemo-infra-iac/.env


export GITHUB_USER="eddiewebb"
export GITHUB_PAT=$TF_VAR_gh_pat_kargo
export KARGO_PASSWORD=$TF_VAR_argo_admin_password

kargo login https://yz0qxt8l0dixl8rc.kargo.akuity.cloud/ --admin --password $KARGO_PASSWORD

projects=$(kargo get projects|tail -n+2|cut -d' ' -f1)

gh auth login --hostname github.com --with-token <<< "$GITHUB_PAT"

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
    --repo-url $repo_url 2>/dev/null || \
    kargo update credentials github-creds \
    --project $project --git \
    --username ${GITHUB_USER} --password ${GITHUB_PAT} \
    --repo-url $repo_url


    kargo create credentials ghcr-creds \
    --project $project --image \
    --username ${GITHUB_USER} --password ${GITHUB_PAT} \
    --repo-url $image_url 2>/dev/null || \
    kargo update credentials ghcr-creds \
    --project $project --image \
    --username ${GITHUB_USER} --password ${GITHUB_PAT} \
    --repo-url $image_url

    echo "Creating GH Webhook"
    wh_url=`kargo get projectconfig --project $project -ojson | jq -r '.status.webhookReceivers[] | select(.name == "gh-wh-receiver").url'`
    echo "URL: $wh_url"
    echo '
        {
        "name":"web",
        "active":true,
        "events":["push","pull_request"],
            "config":{"url":"'$wh_url'",
            "content_type":"application/json",
            "insecure_ssl":"0",
            "secret":"thisisverysecret"
            }
        }' | tr -d '\n' | gh api repos/$GITHUB_USER/argodemo-rollouts-app/hooks --input - -X POST
done
