variable "resource_group_name" {
  default = "devops-vm-rg"
}

variable "location" {
  default = "Switzerland North"
}

variable "vm_name" {
  default = "devops-vm"
}

variable "admin_username" {
  default = "devops"
}

variable "ssh_public_key" {
  description = "SSH public key used to access the virtual machine"
  type        = string
}

variable "vm_size" {
  default = "Standard_B2ats_v2"
}