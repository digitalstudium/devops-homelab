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
# create directory for SSL certificates
mkdir -p /etc/gitlab/ssl
chmod 755 /etc/gitlab/ssl
exit
```

6. Copy SSL certificate issued earlier from local machine:

```bash
scp {gitlab.homelab.internal.crt,gitlab.homelab.internal.key} root@<ip_address>:/etc/gitlab/ssl/
```

7. Update configuration:

```bash
ssh root@<ip_address>
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

Ensure that the IP address is resolved correctly from k8s:

```bash
kubectl run busybox --image=mirror.gcr.io/library/busybox --rm  --attach --restart=Never -- nslookup gitlab.homelab.internal
```

Step completed!

### Gitlab removal

```bash
sudo virsh destroy gitlab
sudo virsh undefine gitlab
sudo rm /var/lib/libvirt/images/debian-13-generic-amd64.qcow2
```
