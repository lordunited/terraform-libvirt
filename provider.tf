terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      version = "0.7.6"
    }
  

  external = {
      source  = "hashicorp/external"
      version = "~> 2.3.1"
    }
  }
}
# Configure the Libvirt Provider
provider "libvirt" {
  # Connection URI - defaults to qemu:///system if not specified
  uri = "qemu:///system"

  # For user session:
  #uri = "qemu:///session"

  # For remote connections (not yet implemented):
 # uri = "qemu+ssh://root@127.0.0.1/system"
}
