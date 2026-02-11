### Gitlab installation

1. Download Debian image and resize it:

```bash
wget https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2
cp debian-13-generic-amd64.qcow2 /var/lib/libvirt/images/
qemu-img resize /var/lib/libvirt/images/debian-13-generic-amd64.qcow2 20G
```

2. Check if ssh key exists, if not, create it with:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
```

3. Install virtual machine:

```bash
virt-install --name gitlab \
                  --ram 4096 \
                  --vcpus 4 \
                  --disk /var/lib/libvirt/images/debian-13-generic-amd64.qcow2 \
                  --os-variant debian13 \
                  --network network=vmkube-net \
                  --import \
                  --noautoconsole \
                  --cloud-init root-ssh-key=$HOME/.ssh/id_ed25519.pub
```

Wait until ip address created:

```bash
watch virsh domifaddr gitlab
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
mkdir -p /etc/gitlab/ssl
openssl req -x509 -newkey rsa:4096 -keyout /etc/gitlab/ssl/gitlab.homelab.local.key -out /etc/gitlab/ssl/gitlab.homelab.local.crt -days 365 -nodes -subj "/CN=gitlab.homelab.local"
chmod 755 /etc/gitlab/ssl
chmod 644 /etc/gitlab/ssl/gitlab.homelab.local.crt
chmod 600 /etc/gitlab/ssl/gitlab.homelab.local.key
```

6. Configure gitlab. If lack of resources, use these instructions (don't use 500000 memory_bytes for gitaly!): [https://docs.gitlab.com/omnibus/settings/memory_constrained_envs](https://docs.gitlab.com/omnibus/settings/memory_constrained_envs) in addition to below:

```bash
echo "letsencrypt['enable'] = false" >> /etc/gitlab/gitlab.rb
sed -i "s|external_url 'http://gitlab.example.com'|external_url 'https://gitlab.homelab.local'|" /etc/gitlab/gitlab.rb
gitlab-ctl reconfigure
cat /etc/gitlab/initial_root_password
exit
```

7. Add gitlab hostname to your local hosts file:

```bash
sudo bash -c 'echo "<ip_address> gitlab.homelab.local" >> /etc/hosts'
```

8. Patch talos VMs hosts in order to resolve gitlab.homelab.local:

```bash
for cluster in vmkube-1 vmkube-2; do
  export TALOSCONFIG=/var/lib/vmkube/$cluster/configs/talosconfig
  talosctl patch machineconfig --mode=auto -p '{
    "machine": {
      "network": {
        "extraHostEntries": [
          {
            "ip": "<ip_address>",
            "aliases": ["gitlab.homelab.local"]
          }
        ]
      }
    }
  }'
done
```

Check if ip address is resolved correctly from k8s:

```bash
kubectl run busybox --image=busybox --rm --attach --command -- nslookup gitlab.homelab.local
```

### Gitlab removal

```bash
sudo virsh destroy gitlab
sudo virsh undefine gitlab
sudo rm /var/lib/libvirt/images/debian-13-generic-amd64.qcow2
```
