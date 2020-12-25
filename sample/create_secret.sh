 kubectl create secret generic azdevops \
 --from-literal=AZP_URL=https://dev.azure.com/yourOrg \
 --from-literal=AZP_TOKEN=YourPAT \
 --from-literal=AZP_POOL=NameOfYourPool