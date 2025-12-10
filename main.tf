# ... (provider block remains the same) ...

# --- 1. Variables ---

variable "ssh_public_key" {
  description = "Path to your public SSH key"
  default     = "~/.ssh/id_rsa.pub"
}

locals {
  vms = yamldecode(file("${path.module}/server_inventory.yml"))
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
  source         = libvirt_volume.base_image.id
  format         = "qcow2" 
}


# --- 5. Cloud-Init Metadata (User Data & SSH Key Injection) ---
# Creates the ISO metadata disk to configure the VM on first boot.
resource "libvirt_cloudinit_disk" "config_disk" {
  for_each = local.vms
  name     = "${each.key}-init.iso"
  user_data = <<-EOF
    #cloud-config
    users:
      - name: adminuser
        sudo: ALL=(ALL) NOPASSWD:ALL
        groups: users, admin
        home: /home/adminuser
        shell: /bin/bash
    chpasswd:
      list: |
         adminuser:password
      expire: False
  EOF
}
#

resource "libvirt_domain" "kvm_vm" {
  for_each = local.vms
  name    = each.key
  memory  = each.value.memory
  vcpu    = each.value.cpu
  cloudinit = libvirt_cloudinit_disk.config_disk[each.key].id
  network_interface {
    network_name = "default" 
    wait_for_lease = true
  }
  disk {
    volume_id = libvirt_volume.vm_disk[each.key].id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
}