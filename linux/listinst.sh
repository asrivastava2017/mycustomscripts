#!/bin/bash

# Loop through AWS accounts
for account in $(aws organizations list-accounts --output text --query 'Accounts[*].Id'); do
    # Loop through AWS regions
    for region in $(aws ec2 describe-regions --output text --query 'Regions[*].RegionName'); do
        echo "Listing Instances in account: $account, region: $region"
        aws ec2 describe-instances --region $region --profile $account
    done
done


