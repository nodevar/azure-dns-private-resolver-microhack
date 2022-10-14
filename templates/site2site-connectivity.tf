#########################################################
# Azure hub VPN Gateway
#########################################################

resource "azurerm_public_ip" "hub-vpngw-ip" {
  name                = "hub-vpngw-ip"
  location            = azurerm_resource_group.hub-rg.location
  resource_group_name = azurerm_resource_group.hub-rg.name
  sku                 = "Standard"
  allocation_method = "Static"

  tags = {
    environment = "cloud"
    deployment  = "terraform"
    microhack   = "dns-private-resolver"
  }
}

resource "azurerm_virtual_network_gateway" "hub-vpngw" {
  name                              = "hub-vpngw"
  location                          = azurerm_resource_group.hub-rg.location
  resource_group_name               = azurerm_resource_group.hub-rg.name

  type                              = "Vpn"
  vpn_type                          = "RouteBased"

  active_active                     = false
  enable_bgp                        = true
  sku                               = "VpnGw1"
  generation                        = "Generation1"

  bgp_settings {
      asn = var.azure_bgp_asn
      peering_addresses {
        ip_configuration_name = "vnetGatewayIpConfig"
      }
  }

  ip_configuration {
    public_ip_address_id            = azurerm_public_ip.hub-vpngw-ip.id
    private_ip_address_allocation   = "Dynamic"
    subnet_id                       = azurerm_subnet.hub-gateway-subnet.id
  }
  depends_on = [
    azurerm_public_ip.hub-vpngw-ip
  ]
  tags = {
    environment = "cloud"
    deployment  = "terraform"
    microhack   = "dns-private-resolver"
  }
}

#########################################################
# On-premise VPN Gateway
#########################################################

resource "azurerm_public_ip" "onpremise-vpngw-ip" {
  name                = "onpremise-vpngw-ip"
  location            = azurerm_resource_group.onpremise-rg.location
  resource_group_name = azurerm_resource_group.onpremise-rg.name
  sku                 = "Standard"
  allocation_method   = "Static"

  tags = {
    environment = "cloud"
    deployment  = "terraform"
    microhack   = "dns-private-resolver"
  }
}

resource "azurerm_virtual_network_gateway" "onpremise-vpngw" {
  name                              = "onpremise-vpngw"
  location                          = azurerm_resource_group.onpremise-rg.location
  resource_group_name               = azurerm_resource_group.onpremise-rg.name

  type                              = "Vpn"
  vpn_type                          = "RouteBased"

  active_active                     = false
  enable_bgp                        = true
  sku                               = "VpnGw1"
  generation                        = "Generation1"

  bgp_settings {
      asn = var.onpremise_bgp_asn

      peering_addresses {
        ip_configuration_name       = "vnetGatewayIpConfig"
      } 
  }

  ip_configuration {
    name                            = "vnetGatewayIpConfig"
    public_ip_address_id            = azurerm_public_ip.onpremise-vpngw-ip.id
    private_ip_address_allocation   = "Dynamic"
    subnet_id                       = azurerm_subnet.onpremise-gateway-subnet.id
  }

  depends_on = [
    azurerm_public_ip.onpremise-vpngw-ip
  ]

  tags = {
    environment = "cloud"
    deployment  = "terraform"
    microhack   = "dns-private-resolver"
  }
}

#########################################################
# On-premise Local Network Gateway
#########################################################

resource "azurerm_local_network_gateway" "onpremise-lng" {
  name                  = "onpremise-lng"
  resource_group_name   = azurerm_resource_group.onpremise-rg.name
  location              = azurerm_resource_group.onpremise-rg.location
  gateway_address       = azurerm_public_ip.hub-vpngw-ip.ip_address
  address_space         = ["10.221.0.0/21"]
  
  bgp_settings  {
      asn                    = var.azure_bgp_asn
      bgp_peering_address    = "10.221.0.62"
      peer_weight            = 0
  }
  depends_on = [
    azurerm_virtual_network_gateway.hub-vpngw
  ]

  tags = {
    environment = "cloud"
    deployment  = "terraform"
    microhack   = "dns-private-resolver"
  }

}

#########################################################
# Azure hub Local Network Gateway
#########################################################

resource "azurerm_local_network_gateway" "hub-lng" {
  name                  = "hub-lng"
  resource_group_name   = azurerm_resource_group.hub-rg.name
  location              = azurerm_resource_group.hub-rg.location
  gateway_address       = azurerm_public_ip.onpremise-vpngw-ip.ip_address
  address_space         = ["10.233.0.0/21"]
  
  bgp_settings  {
      asn                    = var.onpremise_bgp_asn
      bgp_peering_address    = "10.233.0.62"
  }

depends_on = [
  azurerm_virtual_network_gateway.onpremise-vpngw
]

  tags = {
    environment = "onprem"
    deployment  = "terraform"
    microhack   = "dns-private-resolver"
  }

}


#########################################################
# Connection Azure hub => On-premise
#########################################################
resource "azurerm_virtual_network_gateway_connection" "hub-to-onpremise" {
  name                = "${azurerm_virtual_network_gateway.hub-vpngw.name}-To-${azurerm_virtual_network_gateway.onpremise-vpngw.name}"
  resource_group_name   = azurerm_resource_group.hub-rg.name
  location              = azurerm_resource_group.hub-rg.location

  type                       = "IPsec"
  enable_bgp                 = true
  virtual_network_gateway_id = azurerm_virtual_network_gateway.hub-vpngw.id
  local_network_gateway_id   = azurerm_local_network_gateway.hub-lng.id
  dpd_timeout_seconds        = 45 
  shared_key = local.shared-key

  depends_on = [azurerm_virtual_network_gateway.hub-vpngw, azurerm_local_network_gateway.hub-lng]
}

#########################################################
# Connection On-premise => Azure hub 
#########################################################
resource "azurerm_virtual_network_gateway_connection" "onpremise-to-hub" {
  name                = "${azurerm_virtual_network_gateway.onpremise-vpngw.name}-To-${azurerm_virtual_network_gateway.hub-vpngw.name}"
  resource_group_name   = azurerm_resource_group.onpremise-rg.name
  location              = azurerm_resource_group.onpremise-rg.location

  type                       = "IPsec"
  enable_bgp                 = true
  virtual_network_gateway_id = azurerm_virtual_network_gateway.onpremise-vpngw.id
  local_network_gateway_id   = azurerm_local_network_gateway.onpremise-lng.id
  dpd_timeout_seconds        = 45 
  shared_key = local.shared-key

  depends_on = [azurerm_virtual_network_gateway.onpremise-vpngw, azurerm_local_network_gateway.onpremise-lng]
}