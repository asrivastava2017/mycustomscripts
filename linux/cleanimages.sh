# Cretae ami_list.txt file with list of AMIs
while read -r ami_id
do
    if [[ -n "$ami_id" ]]; then
        echo "describing the image : $ami_id"
        describe_image=$(aws ec2 describe-images --image-ids "$ami_id") 
        response=$(echo "$describe_image"| jq  .Images[].BlockDeviceMappings[].Ebs.SnapshotId | jq . -r)
        aws ec2 deregister-image --image-id "$ami_id"
        for snapshot in $response; do 
            echo "$snapshot"
            aws ec2 delete-snapshot --snapshot-id "$snapshot"
        done
        unset describe_image
    fi
done  < ami_list.txt
