#login to azure
az login --username "abc@email.com" --password "password" --allow-no-subscriptions --output none
az extension add --name subscription

#set subscription
#you can set it using both subscription and subscription ID
az account set --subscription "Subscription name"
az account show

#Create managed identity(Cause we are creating private cluster(You can give any name to the unique managed identity I prefer aks name in it as a good practice).
az identity create --name umi-"$(aksname)" --resource-group "$(Resourcegroup)"

#It needs contributor rights over resource group level and reader role over subscription level.
umi=$(az identity show --name umi-"$(aksname)" --resource-group "$(Resourcegroup)" --query principalId --output tsv)
az role assignment create --assignee "$umi" --role "Reader" --scope "//subscriptions/"$(SubscriptionID)""
az role assignment create --assignee "$umi" --role "Contributor" --scope "//subscriptions/"$(SubscriptionID)"/resourceGroups/"$(Resourcegroup)""

# Note : Sometimes role name might not work, in such cases you can use role ID which you can get from portal

# Create key Vault to store and manage
az keyvault create --location "$(Location)" --name kv-$(aksname) --resource-group "$(Resourcegroup)" --enable-rbac-authorization 'false'
#RBAC is set to false cause I am using vault policies to give access to umi and myself

#Aks creation
az aks create --name $(aksname) --resource-group $(Resourcegroup) --outbound-type userDefinedRouting --enable-managed-identity --assign-identity "/subscriptions/$(SubscriptionID)/resourceGroups/$(Resourcegroup)/providers/Microsoft.ManagedIdentity/userAssignedIdentities/umi-$(aksname)" --generate-ssh-keys --vnet-subnet-id "/subscriptions/$(SubscriptionID)/resourceGroups/$(Resourcegroup)/providers/Microsoft.Network/virtualNetworks/$(vnet)/subnets/$(subnet)" --node-count 2 --node-vm-size Standard_DS11_v2 --enable-private-cluster

#If you are using hub and spoke model then only follow next step
#Add private links to DNS zone of aks created in master cluster resource group.
#Get the list of DNS zones in the resource group
$privateDnsZones = (az network private-dns zone list --resource-group "MC_$(Resourcegroup)_$(aksname)_$(Location)" --query "[].name" -o tsv)
#adding link to zone
az network private-dns link vnet create -g MC_$(Resourcegroup)_$(aksname)_$(Location) -n dns_forwarding -z $privateDnsZones -v "/subscriptions/subscriptionId/resourceGroups/Rgname/providers/Microsoft.Network/virtualNetworks/vnetname" -e False

#Updating aks and enable add on as we need secret provider to provide secrets from key vault to cluster.
az aks update -n "$(aksname)" -g "$(Resourcegroup)"
az aks enable-addons --addons azure-keyvault-secrets-provider --name "$(aksname)" --resource-group "$(Resourcegroup)"

#Provide rights to user managed indentity created by you in key vault so it can get details
az keyvault set-policy -n kv-$(aksname) --key-permissions get list --secret-permissions get list --certificate-permissions get list getissuers listissuers manageissuers setissuers --object-id (az identity show --name umi-$(aksname) --resource-group $(Resourcegroup) --query principalId --output tsv)

#Now final step is to add user managed identity to VMSS under security -> Identity.
az vmss identity assign --resource-group MC_$(Resourcegroup)_$(aksname)_$(Location) --name (az vmss list --resource-group MC_$(Resourcegroup)_$(aksname)_$(Location) --query '[].name' --output tsv) --identities "/subscriptions/$(SubscriptionID)/resourcegroups/$(Resourcegroup)/providers/Microsoft.ManagedIdentity/userAssignedIdentities/umi-$(aksname)"

#This will create a private aks cluster with managed identity and secure.