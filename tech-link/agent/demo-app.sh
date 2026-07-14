#!/bin/bash
echo "App started with secrets:"
echo "From file:"
cat ./secrets.txt
echo "From environment:"
echo "VAULT_USERNAME=$VAULT_USERNAME"
echo "VAULT_PASSWORD=$VAULT_PASSWORD"
sleep 60  # Simulate a running app