# mlflow-gcp-setup

Setup of mlflow in google cloud platform for remote tracking.

Notice that some default values used in the scripts could make this setup vulnerable to attacks.

One example of this is allowing all IP ranges to access the external IP of the machine.

Instructions:
```shell 
sh setup.sh CLOUD_SQL_PASSWORD
```


Source: https://medium.com/@Sushil_Kumar/setting-up-mlflow-on-google-cloud-for-remote-tracking-of-machine-learning-experiments-b48e0122de04