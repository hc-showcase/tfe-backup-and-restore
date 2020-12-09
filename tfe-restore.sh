#!/bin/sh
# Format: "%m-%d-%Y-%H-%M"
DATE_TO_RESTORE=$1

TMP_RESTORE_DIR=$(mktemp -d)
MINIO_CLIENT_SOURCE=https://dl.min.io/client/mc/release/linux-amd64/mc
cd $TMP_RESTORE_DIR
curl $MINIO_CLIENT_SOURCE -o mc
MCLI_BINARY=$TMP_RESTORE_DIR/mc
chmod +x $MCLI_BINARY

MINIO_CLIENT_CONFIG=$TMP_RESTORE_DIR/minio-restore-config
mkdir -p $MINIO_CLIENT_CONFIG

SOURCE_S3_URL='https://s3.eu-central-1.wasabisys.com'
SOURCE_S3_ACCESS_KEY=''
SOURCE_S3_SECRET_Key=''
SOURCE_S3_BUCKET='tfe-backup'

TARGET_S3_URL='https://storage.googleapis.com'
TARGET_S3_ACCESS_KEY=''
TARGET_S3_SECRET_Key=''
TARGET_S3_BUCKET='mkaesz-tfe'

replicatedctl app stop

while [[ "stopped" != $(replicatedctl app status | jq -r .[].State | tr -d '\r') ]]; do sleep 5 ; done;

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

cat $MINIO_CLIENT_CONFIG/config.json

#docker run -v $MINIO_CLIENT_CONFIG:/minio-client-config -v $TMP_RESTORE_DIR:/tmp minio/mc --config-dir '/minio-client-config' cp --recursive source/$SOURCE_S3_BUCKET/$DATE_TO_RESTORE/tfe-config/ /tmp
$MCLI_BINARY --config-dir $MINIO_CLIENT_CONFIG cp --recursive source/$SOURCE_S3_BUCKET/$DATE_TO_RESTORE/tfe-config/ $TMP_RESTORE_DIR

TFE_SETTINGS=$TMP_RESTORE_DIR/tfe-settings-$DATE_TO_RESTORE.json
TFE_HOSTNAME=$(cat $TFE_SETTINGS | jq -r .hostname.value)

POSTGRES_HOST=$(cat $TFE_SETTINGS | jq -r .pg_netloc.value)
POSTGRES_DB=$(cat $TFE_SETTINGS | jq -r .pg_dbname.value)
POSTGRES_USER=$(cat $TFE_SETTINGS | jq -r .pg_user.value)
POSTGRES_PW=$(cat $TFE_SETTINGS | jq -r .pg_password.value)

#docker run -v $MINIO_CLIENT_CONFIG:/minio-client-config minio/mc --config-dir '/minio-client-config' rb target/$target/$TARGET_S3_BUCKET/
#docker run -v $MINIO_CLIENT_CONFIG:/minio-client-config minio/mc --config-dir '/minio-client-config' mb target/$target/$TARGET_S3_BUCKET/
#docker run -v $MINIO_CLIENT_CONFIG:/minio-client-config minio/mc --config-dir '/minio-client-config' mirror source/$SOURCE_S3_BUCKET/$DATE_TO_RESTORE/tfe-bucket-contents/ target/$TARGET_S3_BUCKET/

#docker run -v $MINIO_CLIENT_CONFIG:/minio-client-config minio/mc --config-dir '/minio-client-config' mirror --overwrite source/$SOURCE_S3_BUCKET/$DATE_TO_RESTORE/tfe-bucket-contents/ target/$TARGET_S3_BUCKET/
$MCLI_BINARY --config-dir $MINIO_CLIENT_CONFIG mirror --overwrite source/$SOURCE_S3_BUCKET/$DATE_TO_RESTORE/tfe-bucket-contents/ target/$TARGET_S3_BUCKET/

BACKUP_FILE=tfe-postgres-$DATE_TO_RESTORE.bak
echo "Restoring from $BACKUP_FILE"

docker run -v $TMP_RESTORE_DIR:/tmp postgres bash -c "exec psql \"sslmode=disable dbname=$POSTGRES_DB user=$POSTGRES_USER hostaddr=$POSTGRES_HOST password=$POSTGRES_PW\" < /tmp/$BACKUP_FILE"

replicatedctl app start

while ! curl -ksfS --connect-timeout 5 https://$TFE_HOSTNAME/_health_check; do
    sleep 5;
done;

sudo rm -rf $TMP_BACKUP_DIR
