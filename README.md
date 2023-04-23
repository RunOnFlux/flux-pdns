# Flux DNS

Flux DNS is a custom DNS server implementation using PowerDNS with a Python-based Pipe backend. This repository contains all the necessary components to deploy and manage the custom DNS server.

Flux DNS is responsibe for handling DNS queries for any applications deployed on the Flux Network. 

Each application gets a CNAME `appName.app.runonflux.io`. Flux DNS gets the DNS query for all these CNAMEs and returns the corresponding IP of Flux-domain-manager, which is actually responsible for responding with the correct Flux Node IP.

## Features

- PowerDNS with a Pipe backend for simple and efficient handling of DNS queries
- Custom Python script for processing DNS queries based on subdomain names
- Easy deployment and management using Ansible

## Repository Structure

```
.
├── powerdns_setup.yml            # Ansible configuration file
├── pdns.conf                     # PowerDNS configuration file
├── scripts/pdns_pipe_backed.py   # Custom Python script for handling DNS queries
├── pdns_logrotate.conf           # Log rotate config for PDNS logs
└── hosts.ini                     # Hosts to deploy the configs
```

## Prerequisites

- A target server with Ubuntu 18.04 or later
- SSH access to the target server
- Ansible installed on the control machine
- Python 3.6 or later installed on the target server

## Local Deployment

1. Clone this repository on your control machine:

   ```
   git clone https://github.com/RunOnFlux/flux-pdns.git
   cd flux-pdns
   ```

2. Update the Ansible inventory file (`hosts.ini`) with the target server's IP address, SSH user, and SSH key:

   ```
   [dns-server]
   target_ip ansible_user=your_ssh_user ansible_ssh_private_key_file=path/to/your/private_key
   ```

3. Update `powerdns_setup.yml` file with the correct hosts selector:

   ```
    - name: Install and configure PowerDNS
      hosts: "YOUR HOST SETTING HERE"
      become: yes
   ```

4. Run the Ansible playbook to deploy Flux DNS on the target server:

   ```
   ansible-playbook -i hosts.ini powerdns_setup.yml
   ```

5. After the deployment is successful, the custom DNS server will be up and running on the target server.

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## License

[MIT](https://choosealicense.com/licenses/mit/)