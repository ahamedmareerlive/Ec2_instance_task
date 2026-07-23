# EC2 Provisioning System: Terraform, GitHub Actions, & ServiceNow Integration

This beginner-friendly guide explains how our automated EC2 virtual machine provisioning system works from start to end, how the code is structured, and how to configure **ServiceNow** to securely trigger deployments using **Business Rules**, **System Properties**, and **System Logs**.

---

## 1. How the System Works (Overview)

The system allows users to request a Virtual Machine (VM) from a service portal (like ServiceNow), approve the request, and have the VM automatically created in AWS without any manual work.

Here is the flow of events:
1. **Request**: A user requests a VM in ServiceNow, providing the **AMI ID** (Operating System image) and the **VM Count**.
2. **Trigger**: Once approved, a ServiceNow **Business Rule** executes a Javascript script.
3. **Authentication**: The script securely fetches a GitHub Personal Access Token (PAT) stored in ServiceNow's **System Properties**.
4. **API Call**: ServiceNow sends an HTTP POST request to the GitHub Actions API.
5. **Execution**: GitHub Actions runs **Terraform**, which connects to AWS and provisions the EC2 instance, security group, and SSH key.
6. **Isolation**: Every run is assigned a unique `deployment_id` (GitHub Run ID) so that new deployments never modify or terminate previously running instances.

---

## 2. Infrastructure Code Breakdown

The code is divided into two parts in your project:

### Root Folder (Bootstrap S3 Backend)
* [main.tf](file:///d:/Ec2_instance_task/Ec2_instance_task/main.tf): Deploys an S3 bucket (`mareer-tf-state-prod-001`) with versioning, encryption, and public access blocks. This S3 bucket stores the "State" (memory) of Terraform.
* [variables.tf](file:///d:/Ec2_instance_task/Ec2_instance_task/variables.tf) & [providers.tf](file:///d:/Ec2_instance_task/Ec2_instance_task/providers.tf): Configure the bucket name and AWS provider details.

### EC2 Folder (`ec2-deployment/`)
* [backend.tf](file:///d:/Ec2_instance_task/Ec2_instance_task/ec2-deployment/backend.tf): Tells Terraform to store its state in the S3 bucket created above.
* [main.tf](file:///d:/Ec2_instance_task/Ec2_instance_task/ec2-deployment/main.tf): Defines the AWS resources to create:
  * `aws_instance.vm`: The virtual machines (e.g. `t3.micro`).
  * `aws_security_group.web_sg`: Firewalls letting SSH (22), RDP (3389), and HTTP (80) traffic in. Suffixes the name with the `deployment_id` to make it unique per run.
  * `aws_key_pair.generated`: Associates your existing SSH Key Pair with the VM.
* [variables.tf](file:///d:/Ec2_instance_task/Ec2_instance_task/ec2-deployment/variables.tf): Declares default configurations (like default Ubuntu AMI `ami-0b6d9d3d33ba97d99` and `deployment_id`).
* [userdata.sh](file:///d:/Ec2_instance_task/Ec2_instance_task/ec2-deployment/userdata.sh): Run-once startup script that automatically installs and starts the Apache Web Server on Linux instances.

---

## 3. GitHub Actions Workflows

We use two automated pipelines inside [.github/workflows/](file:///d:/Ec2_instance_task/Ec2_instance_task/.github/workflows/):

### A. Deploy EC2 Instances (`deploy.yml`)
* **When it runs**: When triggered by ServiceNow (via API) or manually via GitHub.
* **What it does**:
  1. Configures AWS access credentials.
  2. Runs `terraform init` with a dynamic state key: `-backend-config="key=ec2/dev/terraform-${{ github.run_id }}.tfstate"`. This gives each run its own state file so they do not overlap.
  3. Runs `terraform apply` to deploy the new resources.

### B. Destroy EC2 Instance Run (`destroy.yml`)
* **When it runs**: Triggered manually from ServiceNow or GitHub Actions when you want to decommission a specific VM.
* **What it does**:
  1. Initializes Terraform with the target run's state key.
  2. Runs `terraform destroy` to cleanly terminate the EC2 VM, delete its security groups, and clean up resources for that run.

---

## 4. ServiceNow Configurations (Step-by-Step)

Here is exactly how to configure ServiceNow to connect to this setup.

### Step A: Configure System Properties (Storing the GitHub Token Securely)
Never hardcode your GitHub Personal Access Token (PAT) inside scripts. Instead, store it in ServiceNow's System Properties:

1. In the ServiceNow filter navigator, type `sys_properties.list` and press Enter.
2. Click **New** at the top left.
3. Fill in the following fields:
   * **Name**: `github.pat.token`
   * **Description**: `GitHub Personal Access Token (PAT) for triggering EC2 deployment workflow`
   * **Type**: `string`
   * **Value**: *Paste your GitHub PAT token here* (e.g. `ghp_xxxx...`)
4. Click **Submit**.

*In the script, this property is securely fetched using:* `gs.getProperty('github.pat.token');`

---

### Step B: Create the Catalog Item Variables
In your Service Catalog item (e.g., "Request EC2 Instance"), make sure you define the variables that map to our script inputs:
* Create a Single Line Text variable named: `ami_id` (this holds the AMI ID for the OS).
* Create a Single Line Text variable named: `vm_count` (this holds the number of VMs to deploy).

---

### Step C: Create the ServiceNow Business Rule
A Business Rule runs Javascript code when a catalog request record changes state.

1. Navigate to **System Definition** -> **Business Rules** and click **New**.
2. Fill in the fields:
   * **Name**: `Trigger VM Deployment`
   * **Table**: `Requested Item [sc_req_item]`
   * **Active**: Checked
   * **Advanced**: Checked
3. Under **When to run**:
   * **When**: `after`
   * **Insert / Update**: Checked (both)
   * **Filter Conditions**: Set `Stage` `is` `Request Approved` (or whichever state fits your lifecycle workflow).
4. Under the **Advanced** tab, paste the following script into the `executeRule` function block:

```javascript
(function executeRule(current, previous /*null when async*/) {
    gs.info("Trigger VM Deployment BR started for request: " + current.number);
    try {
        // 1. Safely extract variables to prevent "Cannot read property toString of null" errors
        var amiId = current.variables.ami_id ? current.variables.ami_id.toString() : "";
        var vmCount = current.variables.vm_count ? current.variables.vm_count.toString() : "";
        
        gs.info("Extracted values - ami_id: '" + amiId + "', vm_count: '" + vmCount + "'");
        
        if (!amiId) {
            gs.error("Trigger VM Deployment: 'ami_id' variable is empty. Did you name the variable correctly in the Catalog Item?");
            return;
        }

        // 2. Prepare HTTP REST Connection
        var r = new sn_ws.RESTMessageV2();
        r.setEndpoint('https://api.github.com/repos/ahamedmareerlive/Ec2_instance_task/actions/workflows/deploy.yml/dispatches');
        r.setHttpMethod('POST');
        
        // 3. Fetch the secure token from System Properties
        var patToken = gs.getProperty('github.pat.token'); 
        if (!patToken) {
            gs.error("Trigger VM Deployment: System Property 'github.pat.token' is empty or missing.");
            return;
        }
        
        // 4. Set Headers
        r.setRequestHeader('Authorization', 'Bearer ' + patToken.trim());
        r.setRequestHeader('Accept', 'application/vnd.github+json');
        r.setRequestHeader('User-Agent', 'ServiceNow-Integration');
        
        // 5. Define Request Payload
        var body = {
            "ref": "main",
            "inputs": {
                "ami_id": amiId,
                "vm_count": vmCount ? vmCount : "1"
            }
        };
        r.setRequestBody(JSON.stringify(body));
        
        // 6. Execute API Call & Log response
        var response = r.execute();
        var responseBody = response.getBody();
        var httpStatus = response.getStatusCode();
        
        gs.info("GitHub API Response Status: " + httpStatus + ", Response Body: " + responseBody);
    } catch (ex) {
        gs.error("Exception caught in Trigger VM Deployment: " + ex.toString());
    }
})(current, previous);
```

5. Click **Submit**.

---

### Step D: Monitoring Logs in ServiceNow (Troubleshooting)
If the API call fails or resources are not created, you can debug it using ServiceNow System Logs:

1. Navigate to **System Logs** -> **System Log** -> **All** in the filter navigator.
2. Filter the messages by setting:
   * **Message** `contains` `Trigger VM Deployment`
3. Click **Run**.
4. You will see detailed logs such as:
   * `Trigger VM Deployment BR started...` (confirms the script ran).
   * `Extracted values - ami_id: 'ami-0b6d9d3d33ba97d99'...` (confirms parameters were parsed correctly).
   * `GitHub API Response Status: 204` (confirms GitHub successfully received the trigger. Note: 204 No Content is the expected successful HTTP response code from GitHub Workflows Dispatch API).
   * Any errors like `github.pat.token is empty` or connection timeouts.
