#! /bin/bash
set -euo pipefail

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
export PGPASSWORD=$(aws rds generate-db-auth-token --hostname ${POSTGRES_HOST} --port ${POSTGRES_PORT} --username ${POSTGRES_USER} --region ${REGION})

echo "Printing Volume Information"
df -h .

FILENAME=${POSTGRES_DATABASE}_$(date +"%Y-%m-%dT%H:%M:%SZ")
echo "Using Filename: ${FILENAME}"


# Generate encryption keys
echo "Generating encryption keys..."
openssl version
echo "${OPENSSL_PUBLIC_KEY}" > pub.pem
openssl rand -base64 128 > key.txt
openssl rsautl -encrypt -inkey pub.pem -pubin -in key.txt -out key.txt.enc

# Upload key.
echo "Uploading encrypted key..."
aws s3 cp key.txt.enc "s3://$S3_BUCKET/$S3_PREFIX/${FILENAME}.key.txt.enc"

# Backup, compress, encrypt, upload on the fly.
echo "Fetching, compressing, encrypting, uploading DB dump..."
pg_dump -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U ${POSTGRES_USER} "dbname=${POSTGRES_DATABASE} sslmode=verify-full sslrootcert=rds_root.pem" |\
bzip2 |\
openssl enc -aes-256-cbc -salt -md sha256 -pass file:./key.txt |\
aws s3 cp - "s3://$S3_BUCKET/$S3_PREFIX/${FILENAME}.sql.bz.enc"

# Note: For a backup larger than 50GB, we would need to use the --expected-size parameter.

echo "Done."
