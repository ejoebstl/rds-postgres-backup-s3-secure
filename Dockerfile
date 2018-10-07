FROM alpine:3.7
LABEL maintainer="Emanuel Jöbstl <emanuel.joebstl@gmail.com"

RUN apk update
# Install pg_dump
RUN apk add postgresql-client

# Install aws cli
RUN apk add python py2-pip
RUN pip install awscli
RUN apk del py2-pip

# Add bzip2 for a compressed backup
RUN apk add bzip2

# Add openssl for encrypted backup
RUN apk add openssl

# Finally add a bash for running our script
RUN apk add bash

# Fetch RDS root cert, then remove curl again
RUN apk add curl
RUN curl -s https://s3.amazonaws.com/rds-downloads/rds-ca-2015-root.pem --output rds_root.pem 
RUN apk del curl

# Clear APK cache for a small image
RUN rm -rf /var/cache/apk?*

ENV POSTGRES_DATABASE=
ENV POSTGRES_HOST=
ENV POSTGRES_PORT=5432
ENV POSTGRES_USER=
ENV S3_BUCKET=
ENV S3_PREFIX=backups
ENV OPENSSL_PUBLIC_KEY=

ADD backup.sh backup.sh

CMD ["bash", "backup.sh"]
