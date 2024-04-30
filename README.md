# Let's Encrypt Certificate in OCI

## Objective

Script aimed at comparing local Let's Encrypt certificates with the certificates published in OCI and keeping them updated.

## Procedure

Configure the ```conf.ini file```;<br>
Add the domains to be analyzed and configured by the script in ```domains/*.conf```;<br>
Add the ```script.sh``` to be executed via ```bash``` in the operating system's CRON.

## Requirements

- The digital Let's Encrypt certificate must already exist in the directory specified in the ```conf.ini``` (```LETSENCRYPT_PATH```).<br>
- Manual creation of the Load Balancer, listeners, backend-set, and backend in OCI is required. Subsequently, the script will keep the digital certificate updated.<br>
- This script does not create or update (renew) the Let's Encrypt certificates; it only compares the local certificate with the certificates published at the URL (domain) and publishes the certificate on the Load Balancer in OCI.
