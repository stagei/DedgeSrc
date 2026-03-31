# Azure Container Registry Assignment Guide

## Overview
This guide walks you through completing the Azure Container Registry assignment using the Azure Portal.

---

## Prerequisites
- Azure subscription access
- Access to Azure Portal (https://portal.azure.com)
- Basic understanding of containers and Docker

---

## Task 1: Create a New Container Registry in Azure

### Steps:

1. **Navigate to Container Registries**
   - Go to Azure Portal: https://portal.azure.com
   - Search for "Container registries" in the top search bar
   - Click **"Container registries"**

2. **Create New Registry**
   - Click **"+ Create"** button
   - Fill in the following details:

   **Basics Tab:**
   - **Subscription:** Select your subscription (e.g., "Azure subscription 1")
   - **Resource group:** Select "(New) rg-assignment" or create new
   - **Registry name:** `assignmentcontainer` (must be unique, will get `.azurecr.io` suffix)
   - **Location:** `Norway East` (or your preferred region)
   - **Pricing plan:** `Standard`
   - **Domain name label scope:** `Unsecure`

   **Networking Tab:**
   - Leave defaults (Public access enabled)

   **Encryption Tab:**
   - Leave defaults

   **Tags Tab:**
   - (Optional) Add tags for organization

3. **Review + Create**
   - Click **"Review + create"**
   - Verify all settings
   - Click **"Create"**
   - Wait for deployment to complete (1-2 minutes)

4. **Take Screenshot**
   - Take a full desktop screenshot showing the successfully created Container Registry

---

## Task 2: Enable and Retrieve Access Keys

### Steps:

1. **Navigate to Your Container Registry**
   - Go to the newly created container registry: `assignmentcontainer`
   - In the left menu, find **"Settings"** section
   - Click **"Access keys"**

2. **Enable Admin User**
   - Toggle **"Admin user"** to **Enabled**
   - This will generate username and passwords

3. **Copy Access Credentials**
   - **Login server:** `assignmentcontainer.azurecr.io`
   - **Username:** `assignmentcontainer`
   - **Password:** (copy password or password2)
   - **Save these credentials** - you'll need them later

4. **Take Screenshot**
   - Screenshot showing the Access keys page with Admin user enabled

---

## Task 3: Deploy aci-helloworld Container

### Option A: Using Azure Container Instances (Recommended)

1. **Navigate to Container Instances**
   - Search for "Container instances" in Azure Portal
   - Click **"+ Create"**

2. **Configure Container Instance**

   **Basics Tab:**
   - **Subscription:** Your subscription
   - **Resource group:** `rg-assignment`
   - **Container name:** `aci-helloworld-instance`
   - **Region:** `Norway East`
   - **Image source:** `Other registry`
   - **Image type:** `Public`
   - **Image:** `mcr.microsoft.com/azuredocs/aci-helloworld:latest`
   - **OS type:** `Linux`
   - **Size:** `1 vcpu, 1.5 GiB memory` (default)

   **Networking Tab:**
   - **Networking type:** `Public`
   - **DNS name label:** `aci-helloworld-[yourname]` (must be unique)
   - **Ports:** 
     - Port: `80`
     - Protocol: `TCP`

3. **Create and Deploy**
   - Click **"Review + create"**
   - Click **"Create"**
   - Wait for deployment (2-3 minutes)

4. **Access the Container**
   - Once deployed, go to the container instance
   - Copy the **FQDN** (Fully Qualified Domain Name)
   - Open the FQDN in a web browser
   - You should see the "Welcome to Azure Container Instances!" page

5. **Take Screenshot**
   - Screenshot of the running aci-helloworld web interface

---

## Task 4: List Container Contents via Cloud Shell

### Steps:

1. **Open Cloud Shell**
   - Click the **Cloud Shell icon** (>_) in the top-right of Azure Portal
   - Select **Bash** or **PowerShell**
   - Wait for it to initialize

2. **Login to Container Registry (if needed)**
   ```bash
   # If using your own registry
   az acr login --name assignmentcontainer
   ```

3. **List Running Containers**
   ```bash
   # Get resource group and container name
   az container show --resource-group rg-assignment --name aci-helloworld-instance --query "{FQDN:ipAddress.fqdn,State:instanceView.state}" --output table
   ```

4. **Execute Commands Inside Container**
   ```bash
   # Connect to the container and list contents
   az container exec --resource-group rg-assignment --name aci-helloworld-instance --exec-command "/bin/sh"
   
   # Once inside, run:
   ls -la /
   ls -la /usr/src/app
   cat /etc/os-release
   exit
   ```

5. **Alternative: Use Container Logs**
   ```bash
   # View container logs
   az container logs --resource-group rg-assignment --name aci-helloworld-instance
   ```

6. **Take Screenshot**
   - **Full screenshot** showing:
     - The Cloud Shell terminal
     - The commands you executed
     - The output from the commands
     - The full desktop (not just a region)

---

## Task 5: Modify the Container - Change Title

To change the title to **"This is the Maltese Azure Window that collapsed in 2017"**, you need to modify the container image source code.

### Steps:

1. **Pull the Original Image Source**
   
   In Cloud Shell (Bash):
   ```bash
   # Create working directory
   mkdir ~/aci-custom
   cd ~/aci-custom
   
   # Pull the base image reference from Microsoft's repo
   # We'll create our own Dockerfile
   ```

2. **Create Custom Dockerfile**
   ```bash
   # Create a new Dockerfile
   cat > Dockerfile << 'EOF'
   FROM mcr.microsoft.com/azuredocs/aci-helloworld:latest
   
   # Copy custom HTML with modified title
   COPY index.html /usr/src/app/index.html
   EOF
   ```

3. **Create Modified index.html**
   ```bash
   cat > index.html << 'EOF'
   <!DOCTYPE html>
   <html>
   <head>
       <title>Azure Container Instances - Modified</title>
       <style>
           body { font-family: Arial, sans-serif; text-align: center; margin: 50px; }
           h1 { color: #0078d4; }
           img { max-width: 800px; width: 100%; height: auto; }
       </style>
   </head>
   <body>
       <h1>This is the Maltese Azure Window that collapsed in 2017</h1>
       <p>Running on Azure Container Instances</p>
       <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/e/ec/Azure_Window_2009.JPG/800px-Azure_Window_2009.JPG" alt="Maltese Azure Window">
   </body>
   </html>
   EOF
   ```

4. **Build and Push to Your Registry**
   ```bash
   # Login to your ACR
   az acr login --name assignmentcontainer
   
   # Build the image
   az acr build --registry assignmentcontainer --image aci-helloworld-custom:v1 .
   ```

5. **Take Screenshot**
   - Screenshot of Cloud Shell showing successful build

---

## Task 6: Deploy Modified Container

### Steps:

1. **Create New Container Instance**
   - Go to **Container instances** → **+ Create**

   **Basics Tab:**
   - **Container name:** `aci-helloworld-custom`
   - **Region:** `Norway East`
   - **Image source:** `Azure Container Registry`
   - **Registry:** `assignmentcontainer`
   - **Image:** `aci-helloworld-custom`
   - **Image tag:** `v1`
   - **Authentication type:** `Admin user` (uses the credentials from earlier)

   **Networking Tab:**
   - **DNS name label:** `aci-custom-[yourname]`
   - **Port:** `80`

2. **Deploy**
   - Click **"Review + create"**
   - Click **"Create"**
   - Wait for deployment

3. **Verify the Changes**
   - Navigate to the container instance
   - Copy the FQDN
   - Open in browser
   - **Verify:**
     - Title shows: "This is the Maltese Azure Window that collapsed in 2017"
     - Image shows the Azure Window from the URL

4. **Take Screenshot**
   - **Full desktop screenshot** showing:
     - The modified web page with new title
     - The Azure Window image
     - The URL in the browser

---

## Task 7: Check Costs and Forecast

### Steps:

1. **Navigate to Cost Management**
   - In Azure Portal, search for **"Cost Management + Billing"**
   - Or go to your **Resource Group** → **Cost analysis**

2. **View Current Costs**
   - Click **"Cost analysis"** in the left menu
   - Set the scope to your resource group: `rg-assignment`
   - View the current accumulated costs
   - Change time range to see daily/weekly costs

3. **View Forecast**
   - In Cost analysis, change view to **"Forecast"**
   - Set time range to **next quarter** (3 months)
   - Azure will show predicted costs based on current usage

4. **Export Cost Report**
   - Click **"Download"** to export cost data
   - Or click **"Share"** to save a screenshot

5. **Take Screenshot**
   - **Full desktop screenshot** showing:
     - Cost Management dashboard
     - Current costs for the solution
     - Forecast for the next quarter
     - Include time range and amounts clearly visible

---

## Alternative Method: Deploy via Azure CLI (Advanced)

If you prefer command-line approach:

```bash
# Create resource group
az group create --name rg-assignment --location norwayeast

# Create container registry
az acr create --resource-group rg-assignment \
  --name assignmentcontainer --sku Standard

# Enable admin user
az acr update -n assignmentcontainer --admin-enabled true

# Get credentials
az acr credential show --name assignmentcontainer

# Deploy container instance
az container create \
  --resource-group rg-assignment \
  --name aci-helloworld-instance \
  --image mcr.microsoft.com/azuredocs/aci-helloworld:latest \
  --dns-name-label aci-helloworld-yourname \
  --ports 80

# Deploy custom container
az container create \
  --resource-group rg-assignment \
  --name aci-helloworld-custom \
  --image assignmentcontainer.azurecr.io/aci-helloworld-custom:v1 \
  --registry-login-server assignmentcontainer.azurecr.io \
  --registry-username assignmentcontainer \
  --registry-password <password-from-access-keys> \
  --dns-name-label aci-custom-yourname \
  --ports 80
```

---

## Submission Checklist

Before submitting, ensure you have:

- ✅ **Screenshot 1:** Azure Container Registry creation page (fully deployed)
- ✅ **Screenshot 2:** Access keys page with admin user enabled
- ✅ **Screenshot 3:** Original aci-helloworld running (web interface)
- ✅ **Screenshot 4:** Cloud Shell showing container contents (full commands + output)
- ✅ **Screenshot 5:** Modified web interface with new title and Azure Window image
- ✅ **Screenshot 6:** Cost Management showing current costs and forecast

**Important Reminders:**
- ✅ All screenshots must show **full desktop** (not just a region)
- ✅ Screenshots must be clear and readable
- ✅ You have **one attempt only** - prepare all screenshots before starting the quiz
- ✅ No late submissions or missed assignments will be accepted

---

## Troubleshooting

### Issue: Container registry name already taken
**Solution:** Add your name or random numbers: `assignmentcontainer[yourname]` or `assignmentcontainer123`

### Issue: Can't access the container web interface
**Solution:** 
- Verify DNS name label is unique
- Check that port 80 is opened
- Wait 2-3 minutes for DNS to propagate
- Try accessing via IP address instead of FQDN

### Issue: Can't push image to ACR
**Solution:**
- Verify admin user is enabled
- Run `az acr login --name assignmentcontainer`
- Check credentials with `az acr credential show --name assignmentcontainer`

### Issue: Container fails to start
**Solution:**
- Check container logs: `az container logs --resource-group rg-assignment --name [container-name]`
- Verify image name and tag are correct
- Check if authentication credentials are correct

### Issue: Can't see costs in Cost Management
**Solution:**
- Wait 24-48 hours for cost data to populate
- Check that billing is enabled for your subscription
- View at subscription level instead of resource group level

---

## Additional Resources

- [Azure Container Instances Documentation](https://docs.microsoft.com/azure/container-instances/)
- [Azure Container Registry Documentation](https://docs.microsoft.com/azure/container-registry/)
- [Azure CLI Container Commands](https://docs.microsoft.com/cli/azure/container)
- [Dockerfile Reference](https://docs.docker.com/engine/reference/builder/)

---

## Tips for Success

1. **Plan ahead:** Read all instructions before starting
2. **Take screenshots as you go:** Don't wait until the end
3. **Test everything:** Verify each step works before proceeding
4. **Use Cloud Shell:** It's already authenticated and has all tools installed
5. **Name resources clearly:** Use consistent naming to avoid confusion
6. **Monitor costs:** Start with Standard pricing tier to control costs
7. **Clean up after:** Delete resources after submission to avoid ongoing charges

---

Good luck with your assignment! 🚀

