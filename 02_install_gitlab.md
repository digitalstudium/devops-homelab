```bash
wget https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2
sudo cp debian-13-generic-amd64.qcow2 /var/lib/libvirt/images/
sudo qemu-img resize /var/lib/libvirt/images/debian-13-generic-amd64.qcow2 20G
```

Check if ssh key exists, if not, create it with

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
```

```bash
sudo virt-install --name gitlab \
                  --ram 2048 \
                  --vcpus 1 \
                  --disk /var/lib/libvirt/images/debian-13-generic-amd64.qcow2 \
                  --os-variant debian13 \
                  --network network=talos-net \
                  --import \
                  --noautoconsole \
                  --cloud-init root-ssh-key=$HOME/.ssh/id_ed25519.pub
```

Check ip address:

```bash
sudo virsh domifaddr gitlab
```

Then you can connect to the VM using SSH:

```bash
ssh root@<ip_address>
```

Install gitlab via instructions:
https://docs.gitlab.com/install/package/debian/
https://docs.gitlab.com/omnibus/settings/memory_constrained_envs/

```bash
curl --location "https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh" | sudo bash
sudo EXTERNAL_URL="https://gitlab.example.com" apt install gitlab-ce
```
