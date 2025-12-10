variable "os_images" {
  type = map(string)
  default = {
    "ubuntu_24.04" = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
  }
}
