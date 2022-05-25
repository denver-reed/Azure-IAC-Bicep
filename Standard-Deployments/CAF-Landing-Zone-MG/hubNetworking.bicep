param name string
param vnetAddressSpace string
param dnsServers array = []
param disableBgpRoutePropagation bool
param location string
param nsgRules array
param routes array
param subnets array
param gateways array
param tags object = {}

/*
virtualNetworks Object = 
{
  name: 'vnetName'
  subId: 'subid'
  vnetAddressSpace: '10.0.0.0/22'
  dnsServers: []
  type: 'Hub or Spoke'
  location: 'azure Region'
  resourceGroupName: 'rgName'
  nsgRules: []
  routes: []
  gateways: [
    {
      name: 'gatewayName'
      location: 'region'
      subnetId: 'subnetId'
      activeActive: 'bool'
      size: 'VpnGw1'
      generation: '1 or 2'
      type: 'VPN or ER'
    }
  ]
  disableBgpRoutePropagation: 'bool'
  subnets: [
    {
      name: 'subname'
      addressPrefix: '10.0.0.0/24'
      nsg: 'bool'
      routeTable: 'bool'
    }
  ]
}*/

resource nsg 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: '${name}-${location}-nsg'
  location: location
  properties: {
    securityRules: nsgRules 
  }
  tags: tags 
}

resource rt 'Microsoft.Network/routeTables@2021-05-01' = {
  name: '${name}-${location}-rt'
  location: location
  properties: {
    disableBgpRoutePropagation: disableBgpRoutePropagation
    routes: routes 
  }
  tags: tags  
}

var subnetbase = [for subnet in subnets: {
  addressPrefix: subnet.addressPrefix
}]

var subnetNsg = [for subnet in subnets: subnet.nsg == true ? {
  networkSecurityGroup: {
    id: nsg.id
  }
}: {}]

var subnetRt = [for subnet in subnets: subnet.routeTable == true ? {
  routeTable: {
    id: rt.id
  }
}: {}]

var subnetsConfig = [for (subnet,i) in subnets: union(subnetbase[i],subnetNsg[i],subnetRt[i])]

var subnetCreate = [for (subnet,i) in subnets: {
  name: subnet.name
  properties: subnetsConfig[i]   
}]

var vnetPropertiesBase = {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ] 
    }
    dhcpOptions: {
      dnsServers: dnsServers 
    }
    subnets: subnetCreate 
}

resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: name 
  location: location
  properties: vnetPropertiesBase
  tags: tags
}
//Basic Standard
resource publicIps 'Microsoft.Network/publicIPAddresses@2021-05-01' = [for pip in gateways: {
 name: '${pip.name}-pip'
 location: location
 sku: {
   name: contains(pip.size,'Az') ? 'Standard' : 'Basic'
   tier: 'Regional'  
 } 
 properties: {
   publicIPAllocationMethod: contains(pip.size,'Az') ? 'Static' : 'Dynamic'  
 } 
 tags: tags   
}]

resource publicActiveIps 'Microsoft.Network/publicIPAddresses@2021-05-01' = [for pip in gateways: if(pip.activeActive == true){
  name: '${pip.name}-2-pip'
  location: location
  sku: {
   name: contains(pip.size,'Az') ? 'Standard' : 'Basic'
   tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: contains(pip.size,'Az') ? 'Static' : 'Dynamic'  
  } 
  tags: tags
}]

resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2021-05-01' = [for gateway in gateways: if(toLower(gateway.type) == 'vpn') {
  name: gateway.name
  location: location
  properties: {
    gatewayType: gateway.type
    sku: {
      name: gateway.size
      tier: gateway.size 
    } 
    vpnType: 'RouteBased'
    activeActive: gateway.activeActive == true ? true : false
    ipConfigurations: gateway.activeActive == false ? [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/GatewaySubnet'
          } 
          publicIPAddress: {
            id: resourceId('Microsoft.Network/publicIPAddresses', '${gateway.name}-pip') 
          } 
        }  
      } 
    ] : [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/GatewaySubnet'
          } 
          publicIPAddress: {
            id: resourceId('Microsoft.Network/publicIPAddresses', '${gateway.name}-pip')  
          } 
        }  
      }
      {
        name: 'ipconfig2'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/GatewaySubnet'
          } 
          publicIPAddress: {
            id: resourceId('Microsoft.Network/publicIPAddresses', '${gateway.name}-2-pip') 
          } 
        }  
      }  
    ]  
  } 
  tags: tags      
}]

resource erGateway 'Microsoft.Network/virtualNetworkGateways@2021-05-01' = [for gateway in gateways: if(toLower(gateway.type) == 'expressroute') {
  name: gateway.name
  location: location
  properties: {
    gatewayType: gateway.type
    sku: {
      name: gateway.size
      tier: gateway.size 
    } 
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/GatewaySubnet'
          } 
          publicIPAddress: {
            id: resourceId('Microsoft.Network/publicIPAddresses', '${gateway.name}-pip') 
          } 
        }  
      } 
    ]
  } 
  tags: tags      
}]

output vnetId string = vnet.id
