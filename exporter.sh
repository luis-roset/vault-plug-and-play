#!/bin/bash
expiry=$(date -d "2025-06-15T10:00:00Z" +%s)
echo "vault_issued_cert_expiry_seconds{common_name=\"www.my-website.com\"} $expiry" > /var/lib/node_exporter/textfile_collector/vault_certs.prom

