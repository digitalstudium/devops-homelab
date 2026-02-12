### Gitlab installation

1. Download Debian image and resize it:

```bash
wget https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2
sudo cp debian-13-generic-amd64.qcow2 /var/lib/libvirt/images/
sudo qemu-img resize /var/lib/libvirt/images/debian-13-generic-amd64.qcow2 20G
```

2. Check if ssh key exists, if not, create it with:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
```

3. Install virtual machine:

```bash
sudo virt-install --name gitlab \
                  --ram 4096 \
                  --vcpus 4 \
                  --disk /var/lib/libvirt/images/debian-13-generic-amd64.qcow2 \
                  --os-variant debian13 \
                  --network network=vmkube-net \
                  --import \
                  --noautoconsole \
                  --cloud-init root-ssh-key=$HOME/.ssh/id_ed25519.pub \
                  --autostart
```

Wait until ip address created:

```bash
sudo watch virsh domifaddr gitlab
```

4. Connect to the VM using SSH and enable swap:

```bash
ssh root@<ip_address>
fallocate -l 2G /swapfile.
chmod 600 /swapfile.
mkswap /swapfile.
swapon /swapfile.
echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab.
```

5. Install gitlab via instructions [https://docs.gitlab.com/install/package/debian](https://docs.gitlab.com/install/package/debian) :

```bash
apt update
curl --location "https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh" | bash
apt install gitlab-ce -y
```

6. Generate SSL certificate:

```bash
# switch to home directory
cd
# Create directory for SSL certificates
mkdir -p /etc/gitlab/ssl

# Generate CA private key
openssl genrsa -out ca.key 4096

# Generate CA certificate (10 years, for example)
openssl req -x509 -new -nodes \
  -key ca.key \
  -days 3650 \
  -out ca.crt \
  -subj "/CN=My Homelab CA" \
  -addext "basicConstraints=critical,CA:TRUE"

# Generate CSR
openssl req -new -newkey rsa:4096 -nodes \
  -keyout /etc/gitlab/ssl/gitlab.homelab.internal.key \
  -out gitlab.homelab.internal.csr \
  -subj "/CN=gitlab.homelab.internal" \
  -addext "subjectAltName = DNS:gitlab.homelab.internal"

# Generate certificate
openssl x509 -req -in gitlab.homelab.internal.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out /etc/gitlab/ssl/gitlab.homelab.internal.crt \
  -days 3650 \
  -extfile <(printf "subjectAltName=DNS:gitlab.homelab.internal")


# set permissions
chmod 755 /etc/gitlab/ssl
chmod 644 /etc/gitlab/ssl/gitlab.homelab.internal.crt
chmod 600 /etc/gitlab/ssl/gitlab.homelab.internal.key

exit
```

Copy ca.key/ca.crt to your local machine and create secrets for cert-manager and vmagent:

```bash
scp root@<ip_address>:/root/{ca.key,ca.crt}
kubectl config use-context admin@vmkube-1
kubectl create ns cert-manager
kubectl -n cert-manager create secret tls root-secret --cert=ca.crt --key=ca.key
kubectl create ns victoria-metrics-k8s-stack
kubectl -n victoria-metrics-k8s-stack create secret generic root-secret-cacert --from-file=cacert=ca.crt
kubectl config use-context admin@vmkube-2
kubectl create ns cert-manager
kubectl -n cert-manager create secret tls root-secret --cert=ca.crt --key=ca.key
kubectl create ns victoria-metrics-k8s-stack
kubectl -n victoria-metrics-k8s-stack create secret generic root-secret-cacert --from-file=cacert=ca.crt
```

7. Update configuration:

```bash
echo "letsencrypt['enable'] = false" >> /etc/gitlab/gitlab.rb
sed -i "s|external_url 'http://gitlab.example.com'|external_url 'https://gitlab.homelab.internal'|" /etc/gitlab/gitlab.rb
```

If lack of resources, append [this config](https://docs.gitlab.com/omnibus/settings/memory_constrained_envs/#configuration-with-all-the-changes) as well (but remove `memory_bytes: 500000,` for gitaly because it's too low (OOM!))

Then run:

```bash
gitlab-ctl reconfigure
```

It takes ~5 minutes. At the end of the reconfigure process, you can retrieve the initial root password by running:

```bash
cat /etc/gitlab/initial_root_password
```

8. Add gitlab hostname to your local hosts file (change ip placeholder):

```bash
sudo bash -c 'echo "<ip_address> gitlab.homelab.internal" >> /etc/hosts'
```

9. Patch talos VMs hosts in order to resolve gitlab.homelab.internal (change ip placeholder):

```bash
for cluster in vmkube-1 vmkube-2; do
  export TALOSCONFIG=/var/lib/vmkube/$cluster/configs/talosconfig
  talosctl patch machineconfig --mode=auto -p '{
    "machine": {
      "network": {
        "extraHostEntries": [
          {
            "ip": "<ip_address>",
            "aliases": ["gitlab.homelab.internal"]
          }
        ]
      }
    }
  }'
done
```

Ensure that ip address is resolved correctly from k8s:

```bash
kubectl run busybox --image=mirror.gcr.io/library/busybox --rm  --attach --restart=Never -- nslookup gitlab.homelab.internal
```

10. Import ca.crt to local system:

```bash
sudo cp ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

Then import to browser. Check `gitlab.homelab.internal` from both curl and browser - there should be no certificate errors.

Step completed!

### Gitlab removal

```bash
sudo virsh destroy gitlab
sudo virsh undefine gitlab
sudo rm /var/lib/libvirt/images/debian-13-generic-amd64.qcow2
```
