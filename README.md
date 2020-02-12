# rds-postgres-backup-s3-secure
This docker image is designed to be used on AWS ECS. It creates a dump of a postgres database on RDS, compresses it, encrypts it using assymetric crypto, and uploads it to s3. All permissions are managed via IAM.

#### Why should I use it?

This image was made to fullfil use cases where data is sensitive and security is of concern: 
* No hardcoded access keys are used. Even if the container logs or the container configuration are leaked, the database can not be acessed. 
* The backup is encrypted using a public key, while the private key does not need to be exposed, ever. Not even and administrative AWS user could decrypt the backup if the private key is kept secure. 

This approach is a bit more complicated than just using access keys and relying on the encryption of S3. If that would be sufficient, consider using [another image](https://github.com/schickling/dockerfiles/tree/master/postgres-backup-s3). 

#### How it works in detail

This container performs the following steps when executed: 
* Authenticate with a postgres database via IAM
* Create a dump of the database using `pg_dump`
* Compress the dump with `bzip2`
* Generate a secret key using `openssl`
* Encrypt the dump using the secret key
* Encrypt the secret key using a given public key
* Upload the encrypted key and dump to s3

## Usage

You can find an ECS task definition [here](./backup_task_definition.json). 

The container can be executed manually using

```
docker pull ejoebstl/rds-postgres-backup-s3-secure
```

Please mind the configuration below. 

### Generating a key pair

Optionally generate a new private key or use an existing one. The private key will be needed to decrypt the backups:

`openssl genrsa -des3 -out private_key.pem 2048`

To derive a public key from the private key:

`openssl rsa -in private_key.pem -outform PEM -pubout -out public_key.pem`

### Execution role policy

* IAM authentication needs to be [explicitely enabled](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.Enabling.html) on RDS
* A database user needs to be created with [appropriate permissions](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.DBAccounts.html)
* The execution role needs an [permission for RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.IAMPolicy.html) and S3

The following is a minimal example of a useable role policy: 

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "ssm:DescribeParameters"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Stmt1482841904003",
      "Effect": "Allow",
      "Action": [
          "s3:Put*",
      ],
      "Resource": [
        "${s3_bucket_arn}"
      ]
    },
    {
        "Effect": "Allow",
        "Action": [
            "rds-db:connect"
        ],
        "Resource": [
            "arn:aws:rds-db:${db_region}:${aws_account}:dbuser:${db_rid}/${db_user}"
        ]
    }
  ]
}
```

`s3_bucket_arn`, the ARN of the bucket to upload the backup to  
`db_region`, the region in which the RDS instance resides  
`aws_account`, the AWS account identifier  
`db_rid`, the resource identifier of the RDS instance  
`db_user`, the database user  

### Environment

The container requires the following environment variables to be set: 

`POSTGRES_DATABASE`, name of the database  
`POSTGRES_HOST`, the name of the RDS instance  
`POSTGRES_PORT`, the port of the RDS instance (default: 5432)   
`POSTGRES_USER`, the database user with [permissions for pg_dump](https://serverfault.com/questions/249172/what-grants-are-required-to-run-pg-dump) and IAM authentication enabled  
`S3_BUCKET`, the name of the S3 bucket to upload the backup to  
`S3_PREFIX`, prefix which will be prepended to the upload path (default: `backups`)  
`ENV OPENSSL_PUBLIC_KEY`, the public key
`RATE_LMIT`, rate limiting of data transfer out of `pg_dump`. This can be used to avoid runing out of IOPS in RDS. A `t2.medium` instance dumpy about 6MB/s of data at maximum speed. For details of the format, please refer the documentation of [pv](http://www.ivarch.com/programs/quickref/pv.shtml).

### Decrypting

*These commands were tested on OpenSSL 1.1.1*

To decrypt a backup, decrypt the encrypted key fist, *using your private key*:

```bash
openssl rsautl -decrypt -inkey private_key.pem -in key.bin.enc -out key.bin.dec
```

Then, decrypt the backup *using the encrypted key*:

```bash
openssl enc -d -aes-256-cbc -salt -in backup.sql.gz.enc -out backup.sql.gz --pass file:./key.bin.dec
```

Finally, decompress the decrypted file:

```bash
bzip2 -d backup.sql.gz 
```

## Two words of caution
Please test your backups regularly.   
If the private key is lost, all backups encrypted with it are lost as well.

## Planned todos
* A terraform module to schedule backups on an ECS cluster.
* Move to OpenSSL 1.1 with secure key derivation, as soon as alpine supports it. 
