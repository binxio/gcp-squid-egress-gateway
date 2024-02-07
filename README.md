# Squid Proxy Egress Gateway

This example repositories deploys an [intercepting Squid Proxy](https://wiki.squid-cache.org/ConfigExamples/Intercept/LinuxRedirect#linux-traffic-interception-using-redirect) as an internet gateway. As a result, you can whitelist traffic based on host names.

## How does it work?

The default internet route directs internet traffic through the Squid Proxy. Squid Proxy intercepts the traffic to allow and/or deny requests to certain host names.

1. Internet route override
    ```hcl
    resource "google_compute_route" "example_gateway_internet" {
        project    = var.project_id
        name       = "${google_compute_network.example.name}-gateway-internet"
        dest_range = "0.0.0.0/0"

        network      = google_compute_network.example.id
        next_hop_ilb = google_compute_forwarding_rule.gateway.id
        priority     = 900
    }
    ```

2. HTTP/S traffic interception

    Allow traffic forwarding by Squid Proxy:

    ```hcl  
    resource "google_compute_instance_template" "gateway" {
        project     = var.project_id
        region      = "europe-west1"
        name_prefix = "gateway-${random_id.id.hex}-"

        # NOTE: IpForwarding is required to intercept traffic
        can_ip_forward = true

        ...
    }
    ```

    Redirect traffic to Squid Proxy:

    ```bash
    iptables -t nat -A PREROUTING -s ${load_balancer_ip} -p tcp --dport 80 -j ACCEPT
    iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 3129
    iptables -t nat -A POSTROUTING -j MASQUERADE
    iptables -t mangle -A PREROUTING -p tcp --dport 3129 -j DROP

    iptables -t nat -A PREROUTING -s ${load_balancer_ip} -p tcp --dport 443 -j ACCEPT
    iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 3130
    iptables -t nat -A POSTROUTING -j MASQUERADE
    iptables -t mangle -A PREROUTING -p tcp --dport 3130 -j DROP
    ```


3. Whitelist specification

    ```bash
    xebia.com
    .google.com
    ```

4. Whitelist enforcement

    ```ini
    acl http_proxy myportname 3129
    acl http_allow dstdomain "/etc/squid/allowlist.txt"

    acl https_proxy myportname 3129
    acl step3 at_step SslBump3
    acl ssl_allow ssl::server_name "/etc/squid/allowlist.txt"

    http_access deny http_proxy !http_allow
    http_access deny step3 https_proxy !ssl_allow 
    ```


## Deployment

Use Terraform to deploy the example setup.

1. Set the required Terraform variables

    [variables.tf](terraform/variables.tf)

2. Deploy the example infrastructure

    ```bash
    cd terraform
    terraform init
    terraform apply
    ```

3. Try it for yourself

    Log in to the client VM:

    ```bash
    gcloud compute ssh client --tunnel-through-iap --project <project_id>
    ```

    Browse a whitelisted web page:

    ```bash
    curl https://xebia.com/
    ```

    Browse a blacklisted web page:

    ```bash
    curl https://example.com/
    ```

## Clean up

Use Terraform to destroy the example setup.

1. Set the required Terraform variables

    [variables.tf](terraform/variables.tf)

2. Destroy the example infrastructure

    ```bash
    cd terraform
    terraform init
    terraform destroy
    ```
