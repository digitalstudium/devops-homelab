Download Debian image:

```bash
wget https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2
sudo cp debian-13-generic-amd64.qcow2 /var/lib/libvirt/images/
sudo qemu-img resize /var/lib/libvirt/images/debian-13-generic-amd64.qcow2 20G
```

Check if ssh key exists, if not, create it with

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
```

Install virtual machine:

```bash
sudo virt-install --name gitlab \
                  --ram 4096 \
                  --vcpus 4 \
                  --disk /var/lib/libvirt/images/debian-13-generic-amd64.qcow2 \
                  --os-variant debian13 \
                  --network network=talos-net \
                  --import \
                  --noautoconsole \
                  --cloud-init root-ssh-key=$HOME/.ssh/id_ed25519.pub
```

Check its ip address:

```bash
sudo virsh domifaddr gitlab
```

Then you can connect to the VM using SSH:

```bash
ssh root@<ip_address>
```

Install gitlab via instructions:

https://docs.gitlab.com/install/package/debian/

```bash
apt update
curl --location "https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh" | sudo bash
sudo apt install gitlab-ce
echo "letsencrypt['enable'] = false" >> /etc/gitlab/gitlab.rb
sed -i "s|external_url 'http://gitlab.example.com'|external_url 'https://gitlab.homelab.local'|" /etc/gitlab/gitlab.rb
sudo mkdir -p /etc/gitlab/ssl
sudo chmod 755 /etc/gitlab/ssl
openssl req -x509 -newkey rsa:4096 -keyout /etc/gitlab/ssl/gitlab.homelab.local.key -out /etc/gitlab/ssl/gitlab.homelab.local.crt -days 365 -nodes -subj "/CN=gitlab.homelab.local"
sudo chmod 644 /etc/gitlab/ssl/gitlab.homelab.local.crt
sudo chmod 600 /etc/gitlab/ssl/gitlab.homelab.local.key
gitlab-ctl reconfigure
cat /etc/gitlab/initial_root_password
exit
sudo bash -c 'echo "<ip_address> gitlab.homelab.local" >> /etc/hosts'
```

Gitlab also can be optimized for lower resources consumption:

https://docs.gitlab.com/omnibus/settings/memory_constrained_envs/

Patch talos VMs hosts in order to resolve gitlab.homelab.local:

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

Check if ip address is resolved correctly:

```bash
kubectl run busybox --image=mirror.gcr.io/busybox --rm --attach --command -- nslookup gitlab.homelab.local
```

Remove VM when you are done:

```bash
sudo virsh destroy gitlab
sudo virsh undefine gitlab
sudo rm /var/lib/libvirt/images/debian-13-generic-amd64.qcow2
```
