HashiCorp Vault is a secure data platform that provides secrets management, encryption as service, and identity based access. Vault centrally stores, accesses, and distributes dynamic secrets such as tokens, passwords, certificates, and encryption keys. Vault also keeps application data secure with centralized key management and simple APIs for data encryption.

Vault Enterprise users can take advantage of this Splunk® app to understand Vault from an operational and security perspective, and build their own visualizations based on the provided examples.

Vault operators will find key performance metrics highlighted, both from Vault itself, and from the hosts Vault is running on.

DevOps teams will be able to see usage metrics, broken down by namespace, that tell them how different applications and teams are  using Vault. They can identify hotspots where many tokens or leases are being created, or identify unusual patterns of usage.

Security teams can use this app to explore Vault's security footprint. Reports show what methods are used to authenticate to Vault, the duration of Vault tokens, and the number of tokens with sensitive policies. The app shows the number of key-value secrets stored within Vault, which can be broken down by mount point or namespace.  Other visualizations help identify the source of long-lived authentication tokens, or the number of existing tokens with sensitive policies.

Vault Enterprise users can complete the [Splunk app request form](https://www.hashicorp.com/get/vault-splunk-application) to request access to the app.

## App contents

The app consists of seven pre-built dashboards, and four saved reports.

**Cluster Health Summary** provides an overall summary of the cluster's health and behavior, with links to other dashboards that provide more details. Show host health, token and entity creation rates, token usage statistics, and storage metrics.

**Vault Operations Metrics from Telemetry** includes the most important metrics that provide information on Vault’s operational health. Example metrics include ‘percent of memory in use’, ‘network IO’, and ‘duration of time taken by requests handled by Vault core’.

**Vault Usage from Telemetry** shows how to use the new usage metrics introduced in Vault 1.5 to understand token creation, lease creation, secret usage, and frequently-performed operations. This usage data can be filtered by a variety of criteria, including namespace, auth method, mount point, or time-to-live.

![](a06f0b16-c85b-11ea-9f63-020f2155e396.png)

**Vault Usage from Audit Logs** shows summaries derived from Vault audit logs, such as the number of requests by path, entity, or IP address. We highlight the number of distinct errors, and provide specialized visualizations for accesses to key-value stores.

**Vault Storage Metrics:** This dashboard includes the most important storage backend metrics to monitor, when using Vault Integrated Storage or Consul.

**Quota Monitoring** plots metrics that were introduced in Vault 1.5 as part of the Resource Quotas feature, showing when rate-limiting quotas have been exceeded or the number of leases allowed has reached its maximum.

**High TTL Explorer**: This is a workflow-oriented dashboard for exploring the origins of high time-to-live tokens.

The saved reports available in the app show operation count (by mount point), operation latency, a timeline of errors, and details of the number of tokens per namespace and policy.

## More information

The sources of data for the dashboards include: 
  * [Vault telemetry](https://www.vaultproject.io/docs/internals/telemetry)
  * [Vault audit logs](https://www.vaultproject.io/docs/audit)
  * [Telegraf](https://www.influxdata.com/time-series-platform/telegraf/); used to capture and forward Vault telemetry metrics and system level metrics.
  
For more information on the Splunk app, please refer to the Vault [Monitor Telemetry & Audit Device Log Data with Splunk](https://learn.hashicorp.com/vault/monitoring/monitor-telemetry-audit-splunk#splunk-app) guide.

## Getting Help

If you have any questions about the app, please reach out to the [HashiCorp Support Team](https://support.hashicorp.com/hc/en-us/requests/new)
