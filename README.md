# PREREQUISITES
- Docker Installed
- Docker Compose Installed (bundled with many docker installations)
# SETUP
Populate `.env` GH_TOKEN variable with github token that has read access to public packages

# RECOMMENDED USAGE
Start the following services first from the directory where docker-compose.yaml is located  
`docker compose up -d arango redis nats`  
Wait till all running and arango migration scripts are done then run  
(Arango will output 'it's ready for business' in docker logs when you can proceed)  
`docker compose up -d tms crsp tadp tp rule-901`  
That's it. You can now submit to TMS running on default port 5000

# ONE LINER STARTUP
`docker compose up -d`  
Note that it will log errors and stabilize eventually due to the arango migration scripts.  Unless something goes wrong during the build.

# TROUBLESHOOTING TIPS
Start/Restart individual services with  
`docker compose up -d --force-recreate <service>`    
Try running following if changes are not reflecting  
`docker compose up -d --build --force-recreate`  
You can trash your container followed by deleting the image in docker if none of the above works.  

Stopping individual (or multiple) services  
`docker compose down <service> <service2> <service3>`

List of \<services\>  
- arango  
- redis  
- nats  
- tms   
- crsp  
- tadp  
- tp  
- rule-901  