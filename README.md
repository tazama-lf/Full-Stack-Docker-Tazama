# PREREQUISITES
- Docker Installed
- Docker Compose Installed (bundled with many docker installations)
# SETUP
Populate `.env` GH_TOKEN variable with github token that has read access to public packages

# RECOMMENDED USAGE
Start the following services first from the directory where docker-compose.yaml is located 
`docker compose up -d arango redis nats`  
Wait till all running and arango migration scripts are done before going to the next command  
then run  
`docker compose up -d tms cadp crsp tadp tp rule-901`  

# TROUBLESHOOTING TIPS
Start/Restart individual services with
`docker compose up -d --force-recreate <service>`    
Try running following if changes are not reflecting  
`docker compose up -d --build --force-recreate`  
You can trash your container followed by deleting the image in docker if none of the above works.  

List of \<services\>
- arango  
- redis  
- nats  
- tms   
- cadp  
- crsp  
- tadp  
- tp  
- rule-901  