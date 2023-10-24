# tf-brooks

api.tf - Alerts for xOTA API Java Spring systems that support Detroit Connect Portal. The API's create operations that are sent to the Egress systems and interacts with the Hbase databse.
egress.tf - Alerts for xOTA systems that send operation messages to the CTP (truck). This is upstream of CoBa and currently uses the Flink framework.
ingress.tf - Alerts for xOTA systems that consume operation messages returning from CTP (truck). This is downstream of CoBa and currently uses the Flink framework.
