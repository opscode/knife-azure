# Configuration

## ARM mode

ARM mode requires setting up a service principal for authentication and permissioning. For setting up a service principal from the command line please refer
[Create service principal with PowerShell / Azure CLI 2.0](http://aka.ms/cli-service-principal) (preferred approach) or
[Unattended Authentication](http://aka.ms/auth-unattended). For detailed explanation of authentication in Azure,
see [Developer’s guide to auth with Azure Resource Manager API](http://aka.ms/arm-auth-dev-guide).

After creating the service principal, you should have these 3 values, a client id (GUID), client secret(string) and tenant id (GUID).

Be sure when you are creating the above user you change the example from `-o Reader` to `-o Contributor` otherwise you will not be able
to spin up or delete machines.

Put the following in your `knife.rb`

```ruby
knife[:azure_tenant_id] # found via: tenantId=$(azure account show -s <subscriptionId> --json | jq -r '.[0].tenantId')
knife[:azure_subscription_id] # found via: <subscriptionId>
knife[:azure_client_id] # appId=$(azure ad app show --search <principleappcreated> --json | jq -r '.[0].appId')
knife[:azure_client_secret] # password you set at initially
```

*Microsoft Azure encourages the use of Azure CLI 2.0. If you are still using [azure-xplat-cli](https://github.com/Azure/azure-xplat-cli) then you may simply run ```azure login``` and skip creating the service principal entirely.*

## Alternative Management Certificate Specification

In addition to specifying the management certificate using the publishsettings
file, you can also specify it in PEM format. Follow these steps to generate the certificate in the PEM format:

1. Download the settings file from https://manage.windowsazure.com/publishsettings/index?client=xplat
1. Extract the data from the ManagementCertificate field into a separate file named - cert.pfx
1. Decode the certificate file:

    ### On Linux/Mac(Homebrew)

        base64 -d cert.pfx > cert_decoded.pfx

    ### On Windows

    You can decode and extract the PFX file using     powershell or a free windows base 64 decoder     such as     http://www.fourmilab.ch/webtools/base64/base64.    zip,

        base64.exe -d cert.pfx -> cert_decoded.pfx

1. Convert the decoded PFX file to a PEM file

    #### On Linux/Mac(Homebrew)

        openssl pkcs12 -in cert_decoded.pfx -out     managementCertificate.pem -nodes

    #### On Windows
     Use powershell & run following command. If     openssl.exe is not already installed it can be     downloaded from     http://www.openssl.org/related/binaries.html     (Note: openssl depends on Microsoft Visual C++     Redistributable package (x86) which must be     installed for openssl to function properly).

        openssl base64 -d -A -in cert_decoded.pfx -out cert_decode.der

        openssl pkcs12 -in cert_decoded.der -out managementCertificate.pem -nodes

    You might be asked to enter a password which is     usually blank.
    You might be also asked to enter a passphrase.     Please enter the phrase of your choice.

It is possible to generate your own certificates and upload them. More Detailed Documentation about the Management Certificates is available : https://www.windowsazure.com/en-us/manage/linux/common-tasks/manage-certificates/
