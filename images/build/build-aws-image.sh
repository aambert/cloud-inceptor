#!/bin/bash

LOG_DIR=$(pwd)
BUILD_DIR=$(cd $(dirname $BASH_SOURCE)/.. && pwd)

UBUNTU_RELEASE=bionic
IMAGE_NAME="appbricks-inceptor-bastion"

which aws >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    "ERROR! The AWS CLI needs to be installed and configured. (https://aws.amazon.com/cli/)"
    exit 1
fi

which jq >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    "ERROR! The JQ CLI needs to be available in the system path. (https://stedolan.github.io/jq/download/)"
    exit 1
fi

set -euo pipefail

function aws::build_ami() {

    local image_name=$1
    local region=$2
    local base_amis=$3
    local packer_manifest=$4

    echo -e "\nDeleting images with name '$image_name' in region $region..."
    local images=$(aws ec2 describe-images --output json \
        --region $region --owner self --filters "Name=name,Values=$image_name")

    for i in $(echo "$images" | jq -r '.Images[].ImageId'); do
    
        s=$(echo -e "$images" | jq -r  '.Images[] 
            | select(.ImageId=="'$i'") 
            | .BlockDeviceMappings[0].Ebs.SnapshotId')

        echo -ne "- Deleting $i with snapshot $s"
        aws ec2 deregister-image --region $region --image-id $i
        aws ec2 delete-snapshot --region $region --snapshot-id $s

        while [[ -n "$(aws ec2 describe-images --region $region --owner self | jq -r '.Images[] | select(.ImageId=="'$i'") | .ImageId')" ]]; do
            echo -ne "."
            sleep 2
        done
        echo "done"
    done

    local ami=$(echo "$base_amis" | grep "|$region|" | sort -r | head -1 | awk -F'|' '{ print $3 }')

    echo -e "\nBuilding AMI image '$image_name' in region $region using base AMI $ami..."
    cd $(dirname $packer_manifest)
    packer build \
        -var "build_dir=$BUILD_DIR" \
        -var "region=$region" \
        -var "ami=$ami" \
        -var "name=$image_name" \
        $(basename $packer_manifest)
    cd -
}

regions=${1:-$(aws ec2 describe-regions --output text | cut -f4)}
base_amis=$(curl -sL https://cloud-images.ubuntu.com/query/$UBUNTU_RELEASE/server/released.txt \
    | awk '/release/&&/ebs-ssd/&&/amd64/&&/hvm/{ print $4 "|" $7 "|" $8 }')

for r in $(echo "$regions"); do
    echo "Building AMI for region $r."
    aws::build_ami "$IMAGE_NAME" \
        "$r" "$base_amis" "$BUILD_DIR/packer/build-aws.json" 2>&1 \
        | tee $LOG_DIR/build-aws-$r.log &
done

# Wait for all parallel jobs to finish
wait