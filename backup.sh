#! /bin/bash
set -euxo pipefail

# Check environment
if [ -z "${POSTGRES_DATABASE:-}" ]; then
  echo "POSTGRES_DATABASE was not set"
fi

if [ -z "${POSTGRES_HOST:-}" ]; then
  echo "POSTGRES_HOST was not set"
fi

if [ -z "${POSTGRES_PORT:-}" ]; then
  echo "POSTGRES_HOST was not set"
fi

if [ -z "${POSTGRES_USER:-}" ]; then
  echo "POSTGRES_HOST was not set"
fi

if [ -z "${S3_BUCKET:-}" ]; then
  echo "S3_BUCKET was not set"
fi

if [ -z "${S3_BUCKET:-}" ]; then
  echo "S3_BUCKET was not set"
fi

if [ -z "${S3_PREFIX:-}" ]; then
  echo "S3_BUCKET was not set"
fi

if [ -z "${OPENSSL_PUBLIC_KEY:-}" ]; then
  echo "OPENSSL_PUBLIC_KEY was not set"
fi

# Fetch access token for a database we have access to, configured via IAM
echo aws rds generate-db-auth-token --hostname ${POSTGRES_HOST} --port ${POSTGRES_PORT} --username ${POSTGRES_USER} --region ${REGION}
export PGPASSWORD=$(aws rds generate-db-auth-token --hostname ${POSTGRES_HOST} --port ${POSTGRES_PORT} --username ${POSTGRES_USER} --region ${REGION})

FILENAME=${POSTGRES_DATABASE}_$(date +"%Y-%m-%dT%H:%M:%SZ")
echo "Using Filename: ${FILENAME}"

# Backup, compress,
echo "Fetching DB dump..."
pg_dump -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U ${POSTGRES_USER} "dbname=${POSTGRES_DATABASE} sslmode=verify-full sslrootcert=rds_root.pem" | bzip2 > dump.sql.bz

# Encrypt
echo "Encrypting backup..."
echo "${OPENSSL_PUBLIC_KEY}" > pub.pem
openssl rand 196 > key.bin
openssl enc -aes-256-cbc -salt -in dump.sql.bz -out dump.sql.bz.enc -pbkdf2 --pass file:./key.bin 
openssl rsautl -encrypt -inkey pub.pem  -pubin -in key.bin -out key.bin.enc

# Upload
SIZE=$(du -h dump.sql.bz.enc| cut -f1)
echo "Backup size: ${SIZE}"
echo "Uploading backup..."

# Upload, expected size param used for large backup (>5G), according to AWS docs. 
aws s3 cp dump.sql.bz.enc --expected-size "${SIZE}" "s3://$S3_BUCKET/$S3_PREFIX/${FILENAME}.sql.bz.enc"
aws s3 cp key.bin.enc --expected-size "${SIZE}" "s3://$S3_BUCKET/$S3_PREFIX/${FILENAME}.key.bin.enc"

echo "Done."
