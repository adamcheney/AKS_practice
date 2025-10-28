variable "vnet_address_space" {
  description = "The address space that is used by the virtual network."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}  

variable "node_subnet_cidr" {
  description = "The address prefix that is used by the node subnet."
  type        = list(string)
  default     = ["10.0.16.0/24"]
}

variable "pod_subnet_cidr" {
  description = "The address prefix that is used by the pod subnet."
  type        = list(string)
  default     = ["10.0.0.0/20"]
}

variable "ingress_subnet_cidr" {
  description = "The address prefix that is used by the ingress subnet."
  type        = list(string)
  default     = ["10.0.17.0/27"]
}

variable "endpoints_subnet_cidr" {
  description = "The address prefix that is used by the private endpoints subnet."
  type        = list(string)
  default     = ["10.0.17.32/27"]
}
