# TFE Backup and restore

## Pre-requisites
1. Internet access required as minio cli is being downloaded.

## Backup

1. Set variables in tfe-backup.sh for S3 source and target.
2. Execute the following on the TFE instance.

```
bash tfe-backup.sh 
```
The script will create a folder in the target S3 bucket as timestamp in the following format: 12-09-2020-08-53

## Restore

1. Set variables in tfe-restore.sh for S3 source and target.
2. Execute the following on the TFE instance.

```
bash tfe-restore.sh 12-09-2020-08-53
```

