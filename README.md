# SETUP
populate .env GH_TOKEN variable with github token that has read access to public packages

# TIPS
Start/Restart individual with  
`docker compose up -d --force-recreate <service>`   
Try running following if changes are not reflecting  
`docker compose up -d --build --force-recreate`  
You can trash your container followed by deleting the image in docker if none of the above works.  

# RECOMMENDED USAGE
Run the following services first  
`docker compose up -d arango redis nats`  
Wait till all running and arango migration scripts are done before going to the next command  
then run  
`docker compose up -d tms cadp crsp tadp tp rule-901`  