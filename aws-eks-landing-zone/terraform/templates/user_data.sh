#!/bin/bash

# EKS Worker Node User Data Script
# This script prepares the node for joining the EKS cluster

set -o xtrace

# Bootstrap the node to the EKS cluster
/etc/eks/bootstrap.sh ${cluster_name}

# Install additional packages
yum update -y
yum install -y amazon-cloudwatch-agent htop iotop

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/messages",
                        "log_group_name": "/aws/eks/${cluster_name}/system",
                        "log_stream_name": "{instance_id}/messages",
                        "timestamp_format": "%b %d %H:%M:%S"
                    },
                    {
                        "file_path": "/var/log/secure",
                        "log_group_name": "/aws/eks/${cluster_name}/system",
                        "log_stream_name": "{instance_id}/secure",
                        "timestamp_format": "%b %d %H:%M:%S"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "AWS/EKS/${cluster_name}",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60,
                "totalcpu": false
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "diskio": {
                "measurement": [
                    "io_time",
                    "read_bytes",
                    "write_bytes",
                    "reads",
                    "writes"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            },
            "netstat": {
                "measurement": [
                    "tcp_established",
                    "tcp_time_wait"
                ],
                "metrics_collection_interval": 60
            },
            "swap": {
                "measurement": [
                    "swap_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s

# Configure system settings based on node type
%{ if node_type == "system" ~}
# System node optimizations
echo 'net.core.somaxconn = 32768' >> /etc/sysctl.conf
echo 'vm.max_map_count = 262144' >> /etc/sysctl.conf

# Set kernel parameters for system workloads
echo 'kernel.pid_max = 4194304' >> /etc/sysctl.conf
echo 'fs.file-max = 1000000' >> /etc/sysctl.conf

%{ else ~}
# User node optimizations
echo 'net.core.somaxconn = 65536' >> /etc/sysctl.conf
echo 'vm.max_map_count = 262144' >> /etc/sysctl.conf
echo 'fs.file-max = 1000000' >> /etc/sysctl.conf

# Application workload optimizations
echo 'net.ipv4.ip_local_port_range = 1024 65535' >> /etc/sysctl.conf
echo 'net.core.rmem_default = 262144' >> /etc/sysctl.conf
echo 'net.core.rmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.core.wmem_default = 262144' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 16777216' >> /etc/sysctl.conf

%{ endif ~}

# Apply sysctl settings
sysctl -p

# Configure Docker settings for better performance
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ]
}
EOF

# Configure kubelet settings
mkdir -p /etc/kubernetes/kubelet
cat > /etc/kubernetes/kubelet/kubelet-config.json << 'EOF'
{
    "kind": "KubeletConfiguration",
    "apiVersion": "kubelet.config.k8s.io/v1beta1",
    "address": "0.0.0.0",
    "authentication": {
        "anonymous": {
            "enabled": false
        },
        "webhook": {
            "cacheTTL": "2m0s",
            "enabled": true
        },
        "x509": {
            "clientCAFile": "/etc/kubernetes/pki/ca.crt"
        }
    },
    "authorization": {
        "mode": "Webhook",
        "webhook": {
            "cacheAuthorizedTTL": "5m0s",
            "cacheUnauthorizedTTL": "30s"
        }
    },
    "cgroupDriver": "systemd",
    "clusterDNS": [
        "10.100.0.10"
    ],
    "clusterDomain": "cluster.local",
    "containerLogMaxFiles": 5,
    "containerLogMaxSize": "10Mi",
    "cpuManagerPolicy": "none",
    "enableServer": true,
    "eventRecordQPS": 0,
    "evictionHard": {
        "imagefs.available": "15%",
        "memory.available": "300Mi",
        "nodefs.available": "10%",
        "nodefs.inodesFree": "5%"
    },
    "featureGates": {
        "RotateKubeletServerCertificate": true
    },
    "healthzBindAddress": "127.0.0.1",
    "healthzPort": 10248,
    "httpCheckFrequency": "20s",
    "imageMinimumGCAge": "2m0s",
    "kubeAPIQPS": 10,
    "kubeAPIBurst": 10,
    "makeIPTablesUtilChains": true,
    "maxOpenFiles": 1000000,
    "maxPods": 110,
    "nodeStatusReportFrequency": "10s",
    "nodeStatusUpdateFrequency": "10s",
    "protectKernelDefaults": true,
    "readOnlyPort": 0,
    "registryPullQPS": 10,
    "registryBurst": 10,
    "rotateCertificates": true,
    "runtimeRequestTimeout": "2m0s",
    "serializeImagePulls": false,
    "serverTLSBootstrap": true,
    "streamingConnectionIdleTimeout": "4h0m0s",
    "syncFrequency": "1m0s",
    "volumeStatsAggPeriod": "1m0s"
}
EOF

# Set up log rotation for system logs
cat > /etc/logrotate.d/kubernetes << 'EOF'
/var/log/pods/*/*.log {
    daily
    missingok
    rotate 5
    compress
    notifempty
    create 644 root root
}
EOF

# Configure system security
# Disable unnecessary services
systemctl disable postfix || true
systemctl disable rpcbind || true

# Configure SSH hardening
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd

# Install and configure fail2ban for SSH protection
yum install -y epel-release
yum install -y fail2ban

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF

systemctl enable fail2ban
systemctl start fail2ban

# Configure automatic security updates
yum install -y yum-cron
sed -i 's/apply_updates = no/apply_updates = yes/' /etc/yum/yum-cron.conf
systemctl enable yum-cron
systemctl start yum-cron

# Signal completion
/opt/aws/bin/cfn-signal -e $? --stack ${cluster_name} --resource AutoScalingGroup --region $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//')

echo "Node initialization completed successfully"