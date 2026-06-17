# !/bin/bash

region=${1:-dev}

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  aws sso login 
fi
export AWS_PROFILE=admin
script_dir="$(dirname "$(realpath "$0")")"



# grab current state
aws s3 cp s3://demo-public-notsecure/environments.yaml $script_dir/environments.yaml 


#grab current freight from Kargo API for the region primary stage
# based on https://docs.kargo.io/api-docs#tag/core/GET/v1beta1/projects/{project}/stages/{stage}



current_freight=$(curl -s 'https://kargo.akpdemoapps.link/v1beta1/projects/team-eddie/stages/'$region'-primary' \
  --header 'Authorization: Bearer '"$KARGO_API_TOKEN" \
  --header 'Content-Type: application/json' \
  | jq -r '.status.freightSummary')

echo current freight for $region-primary: $current_freight



# flip the primary and secondary clusters for the specified region in the environments.yaml file where top level keys are region names and each region has a primary and secondary cluster defined.
#  This is a simple swap of the values for the primary and secondary clusters for the specified region.
# Other regions should remain unchanged. This allows us to simulate a region flip where the secondary cluster becomes the primary and the primary becomes the secondary for the specified region.
yq e -i ".\"$region\".primary.cluster as \$p | .\"$region\".secondary.cluster as \$s | .\"$region\".primary.cluster = \$s | .\"$region\".secondary.cluster = \$p" $script_dir/environments.yaml

# send back to AWS
aws s3 cp $script_dir/environments.yaml s3://demo-public-notsecure/environments.yaml --acl public-read --content-type application/yaml


prior_freight=$(curl -s 'https://kargo.akpdemoapps.link/v1beta1/projects/team-eddie/stages/'$region'-primary' \
  --header 'Authorization: Bearer '"$KARGO_API_TOKEN" \
  --header 'Content-Type: application/json' \
  | jq -r '.status.freightSummary')

echo prior freight for $region-primary: $prior_freight

if [ "$current_freight" == "$prior_freight" ]; then
  echo "Freight did not change, regions in sync"
 
else
  echo "Freight in new Primay is $prior_freight , but should be $current_freight , triggering Kargo promotion"

  curl 'https://kargo.akpdemoapps.link/v1beta1/projects/team-eddie/stages/$region-primary/promotions' \
    --request POST \
    --header 'Content-Type: application/json' \
    --header 'Authorization: Bearer '"$KARGO_API_TOKEN" \
    --data '{
    "freight": "'$current_freight'"
  }'
fi
