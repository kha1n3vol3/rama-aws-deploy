# Required variables for single-node Rama cluster (testing)
region = "us-east-2"
username = "ec2-user"
vpc_security_group_ids = ["sg-19915770"]

# Paths and URLs
rama_source_path = "~/rama.zip"
zookeeper_url = "https://www.apache.org/dyn/closer.lua/zookeeper/zookeeper-3.9.3/apache-zookeeper-3.9.3-bin.tar.gz"

# AMI and instance settings
ami_id = "ami-07d9881e6986c46f8"
instance_type = "m6g.large"

# Optional settings
license_source_path = ""
volume_size_gb = 50
use_private_ip = true
private_ssh_key = "~/rama.key"