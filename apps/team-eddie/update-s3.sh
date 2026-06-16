#! /bin/bash
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  aws sso login 
fi
export AWS_PROFILE=admin
script_dir="$(dirname "$(realpath "$0")")"
aws s3 cp $script_dir/environments.yaml s3://demo-public-notsecure/environments.yaml --acl public-read --content-type application/yaml