#!/bin/sh
NOW=$(date +"%m-%d-%Y-%H-%M")

TMP_BACKUP_DIR=$(mktemp -d)
MINIO_CLIENT_CONFIG=$TMP_BACKUP_DIR/minio-backup-config/
mkdir -p $MINIO_CLIENT_CONFIG

SOURCE_S3_URL='https://storage.googleapis.com'
SOURCE_S3_ACCESS_KEY=''
SOURCE_S3_SECRET_Key=''
SOURCE_S3_BUCKET='mkaesz-tfe'

TARGET_S3_URL='https://s3.eu-central-1.wasabisys.com'
TARGET_S3_ACCESS_KEY=''
TARGET_S3_SECRET_Key=''
TARGET_S3_BUCKET='tfe-backup'

replicatedctl app-config export > $TMP_BACKUP_DIR/tfe-settings-$NOW.json
replicatedctl app status > $TMP_BACKUP_DIR/tfe-status-$NOW.json
replicatedctl console-auth export --type ldap > $TMP_BACKUP_DIR/tfe-replicated-console-auth-$NOW.json

replicatedctl app stop

TFE_SETTINGS=$TMP_BACKUP_DIR/tfe-settings-$NOW.json
TFE_HOSTNAME=$(cat $TFE_SETTINGS | jq -r .hostname.value)

POSTGRES_HOST=$(cat $TFE_SETTINGS | jq -r .pg_netloc.value)
POSTGRES_DB=$(cat $TFE_SETTINGS | jq -r .pg_dbname.value)
POSTGRES_USER=$(cat $TFE_SETTINGS | jq -r .pg_user.value)
POSTGRES_PW=$(cat $TFE_SETTINGS | jq -r .pg_password.value)

while [[ "stopped" != $(replicatedctl app status | jq -r .[].State | tr -d '\r') ]]; do sleep 5 ; done;

docker run postgres pg_dump --clean "sslmode=disable dbname=$POSTGRES_DB user=$POSTGRES_USER hostaddr=$POSTGRES_HOST password=$POSTGRES_PW" > $TMP_BACKUP_DIR/tfe-postgres-$NOW.bak

cat <<EOF > $MINIO_CLIENT_CONFIG/config.json
{
	"version": "10",
	"aliases": {
		"source": {
			"url": "$SOURCE_S3_URL",
			"accessKey": "$SOURCE_S3_ACCESS_KEY",
			"secretKey": "$SOURCE_S3_SECRET_Key",
			"api": "s3v4",
			"path": "auto"
		},
		"target": {
			"url": "$TARGET_S3_URL",
			"accessKey": "$TARGET_S3_ACCESS_KEY",
			"secretKey": "$TARGET_S3_SECRET_Key",
			"api": "s3v4",
			"path": "auto"
		}
	}
}
EOF

docker run -v $MINIO_CLIENT_CONFIG:/minio-client-config -v $TMP_BACKUP_DIR:/tmp minio/mc --config-dir '/minio-client-config' cp --recursive tmp/ target/$TARGET_S3_BUCKET/$NOW/tfe-config/
docker run -v $MINIO_CLIENT_CONFIG:/minio-client-config -v $TMP_BACKUP_DIR:/tmp minio/mc --config-dir '/minio-client-config' mirror source/$SOURCE_S3_BUCKET/ target/$TARGET_S3_BUCKET/$NOW/tfe-bucket-contents/

replicatedctl app start

while ! curl -ksfS --connect-timeout 5 https://$TFE_HOSTNAME/_health_check; do
    sleep 5;
done;

sudo rm -rf $TMP_BACKUP_DIR
