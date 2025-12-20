
variable "ssh_public_key" {
  description = "Path to your public SSH key"
  default     = "~/.ssh/id_rsa.pub"
}

locals {
  vms = yamldecode(file("${path.module}/server_inventory.yml"))
}


variable "isolated_subnet_cidr" { 
  description = "The name of the pre-configured Linux bridge on the host (e.g., br0)"
  default     = "172.16.1.0/24"
}


resource "libvirt_network" "isolated_net" {
  name       = "internal-storage-net"
  
  # Setting 'mode = "nat"' ensures the bridge interface itself gets an IP
  # (e.g., 172.16.10.1) which can serve as a DHCP server.
  mode       = "nat" 
  autostart  = true

  # --- CRITICAL: ISOLATION SETTING ---
  # 'none' tells Libvirt to set up the firewall rules to block traffic 
  # from leaving the bridge to the host's external interfaces.
#  forward_mode = "none" 
  
  # Define the network range and set the bridge IP
  addresses  = [var.isolated_subnet_cidr] 

  # OPTIONAL: Configure the DHCP server for the VMs on this isolated network
}


resource "libvirt_pool" "storage" {
  name = "kvm_pool_simple"
  type = "dir"
  # This path must exist on your KVM host!
  path = "/var/lib/libvirt/kvm-storage/" 
}


resource "libvirt_volume" "base_image" {
  name   = "ubuntu-2404-minimal-cloud.qcow2"
  pool   = libvirt_pool.storage.name
  # The source is now the URL, triggering the download (PULL)
  source = "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
  format = "qcow2"
}

resource "libvirt_volume" "vm_disk" {
  for_each       = local.vms
  name           = "${each.key}"
  pool           = libvirt_pool.storage.name
  # FIX: Change 'stdout' to 'disk_path' to match the jq output
# source         = libvirt_volume.base_image.id
  format         = "qcow2" 
  base_volume_id = libvirt_volume.base_image.id
}

# --- 5. Cloud-Init Metadata (User Data & SSH Key Injection) ---
# Creates the ISO metadata disk to configure the VM on first boot.
resource "libvirt_cloudinit_disk" "config_disk" {
  for_each = local.vms
  name     = "${each.key}-init.iso"
  pool     = libvirt_pool.storage.name
user_data = <<-EOF
    #cloud-config
    ssh_pwauth: True 
    runcmd:
      - [ systemctl, enable, --now, ssh ]
    users:
      - name: adminuser
        sudo: ALL=(ALL) NOPASSWD:ALL
        groups: users, admin
        home: /home/adminuser
        shell: /bin/bash
        lock_passwd: false
    chpasswd:
      list: |
         adminuser:password
      expire: False
  EOF
  network_config = <<-EOF
    version: 2
    ethernets:
      ens3:
        dhcp4: no
        addresses:
          - ${each.value.ip_address}/${split("/", each.value.ip_subnet)[1]}
        gateway4: ${each.value.ip_gateway}
        nameservers:
          addresses: [8.8.8.8, 1.1.1.1]
  EOF
  }


resource "libvirt_domain" "kvm_vm" {
  for_each = local.vms
  name    = each.key
  memory  = each.value.memory
  vcpu    = each.value.cpu
  network_interface {
    # Reference the macvtap network
    network_name = libvirt_network.isolated_net.name 
    wait_for_lease = false

  }
  cloudinit = libvirt_cloudinit_disk.config_disk[each.key].id
  # network_interface {
  #   network_name = "default" 
  #   wait_for_lease = true
  # }
  disk {
    volume_id = libvirt_volume.vm_disk[each.key].id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
}