<!-- SPDX-License-Identifier: Apache-2.0 -->

## INTRODUCTION

This appendix will show you how to optionally load the configuration and environment files in the Tazama full stack docker installation

## Configure Tazama

Tazama is configured by loading the network map, rules and typology configurations required to evaluate a transaction via the ArangoDB API. We need to clone the Tazama Postman repository so that we can utilize the Postman environment file that is hosted there. 

In a Windows Command Prompt, navigate to the source code root folder. Then clone the following repository with the following command:
```
git clone https://github.com/frmscoe/postman -b main
```

**Output:**

![clone-config](/images/full-stack-docker-tazama-clone-postman.png)

Perform the following Newman command to load the configuration into the ArangoDB databases and collections:

```
newman run collection-file -e environment-file --timeout-request 10200
```

 - The `collection-file` is the full path to the location on your local machine where the `postman\Configuration - Rule 901.postman_collection.json` file is located.
 - The `environment-file` is the full path to the location on your local machine where the `postman\environments\Tazama-Docker-Compose-LOCAL.postman_environment.json` file is located.
 - If the path contains spaces, wrap the string in double-quotes.

**Output:**

![execute-config](/images/full-stack-docker-tazama-load-config.png) 

