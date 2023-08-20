#!/bin/bash
for i in {1..50}
do
  ssh-keygen -f keys/id"$i" -P ""
  gcloud compute os-login ssh-keys add --key-file=keys/id"$i".pub
done
