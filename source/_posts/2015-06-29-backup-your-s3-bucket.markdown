---
layout: post
title: "How we backed our Amazon S3 bucket within S3"
date: 2015-06-29 11:24:50 -0500
comments: true
author: Ruslan Ledesma-Garza
categories:
- Backup and restore
- AWS S3
- Golang
---

__TL;DR:__
Here at [segundamano.mx](http://www.segundamano.mx/) we store a fair amount of our content in [Amazon S3](http://aws.amazon.com/s3/).
Backup and restore of our S3 content is a must.
We did not find a system that does the job.
We tried [cross-region replication](http://docs.aws.amazon.com/AmazonS3/latest/dev/crr.html) and [versioning](http://docs.aws.amazon.com/AmazonS3/latest/dev/ObjectVersioning.html), and although neither is proper backup and restore system, they are building blocks for a proper system.
Thus, we developed [backup-my-bucket](https://github.schibsted.io/smmx/backup-my-bucket), an open source tool that complements cross-region replication and versioning to form a backup and restore system for S3 buckets.

You should backup your bucket
-----------------------------

When you run a site with a huge amount of content, delegating administration of storage to a cloud service is something you should consider.
Here at [segundamano.mx](http://www.segundamano.mx/) we choose [Amazon S3](http://aws.amazon.com/s3/).

Once you start storing content on Amazon S3 (but really, hopefully before), you will start worrying about reliability of your site.
My colleages and I are commited to designing and developing systems that are highly-available and fault tolerant.
But despite your efforts, it is always a good idea to have a disaster recovery plan for your S3 buckets.

We consider that a good disaster recovery plan for Amazon S3 considers system and human errors.
A system error is the loss of a file due to data corruption or the deletion of a set of files due to a bug in our code.
A human error is the deletion of a set of files, for example due to `aws s3 rm s3://master-bucket/my-precious.jpg`
For data corruption, you could argue that [*Amazon's 99.999999999%* durability](http://aws.amazon.com/s3/faqs/#data-protection_anchor) is enough and [forget about that](http://stackoverflow.com/a/17839589).
For the accidental deletion of files due to system or human error, you could consider that copying by cross-region replication or glacier storage [is enough](https://aws.amazon.com/blogs/aws/archive-s3-to-glacier/).
But truth is that, when you go into production, you won't feel very confident.

Backup is an essential part of an effective disaster recovery plan.
We consider that a system that does the job, let's you:

1. Backup your master bucket.
2. Restore your master bucket to a given point in time.
3. Manage your backups.

Backup approaches
-----------------

A first approach to backup is to store backups in your local data center.
This is not what we want because it defeats the purpose of using S3.
We want to store our master bucket in another S3 bucket.

For backing up master bucket in a slave bucket, you can [copy the contents from master to slave](http://serverfault.com/a/239722).
This however takes a lot of time and managing versions by hand is difficult.

One could be tempted to use avoid copy to a master slave altogether by using versioning.

> __[Versioning](http://docs.aws.amazon.com/AmazonS3/latest/dev/Versioning.html):__ for a given key and key operation, preserve the current
  content of the key after the operation is applied on key. Example:
  preserve the content of key s3://master-bucket/cozumel.jpg after
  deleting the key.

However, versioning alone does not offer a way to manage backups.
Moreover, versioning does not isolate versions from operations applied to master bucket and it is perfectly possible to delete [all versions of a set of files](http://boulderapps.co/post/remove-all-versions-from-s3-bucket-using-aws-tools):
```bash
echo '#!/bin/bash' > deleteBucketScript.sh

aws --output text s3api list-object-versions --bucket master-bucket | \
grep -E "^VERSIONS" | \
awk '{print "aws s3api delete-object --bucket master-bucket --key "$4" --version-id "$8";"}' >> deleteBucketScript.sh

. deleteBucketScript.sh
```

Cross-region replication sounds more like what we need.

> __[Cross-region replication](http://docs.aws.amazon.com/AmazonS3/latest/dev/crr.html):__ for given buckets master & slave, and
   given key operation, apply operation to bucket slave after
   operation is applied to master. Example: upload file cozumel.jpg
   to bucket slave after I upload file cozumel.jpg to bucket master.

Cross-region replication has two advantages: (1) replicates creation and deletion of files, and
(2) restricts the location of the master and the slave so that they are in different locations.
However, restoration and management of versions is still difficult and unpractical

Our solution
------------

We approached problem by complementing cross-region replication and versioning with backup management and a restore operation.
We implemented managemenent and restore in the command line tool [`backup-my-bucket`](https://github.schibsted.io/smmx/backup-my-bucket).
We wrote `backup-my-bucket` in [Go](http://golang.org/) and take advantage of it's facilities for writting concurrent code.
With `backup-my-bucket` you backup and restore master into slave by means of a control machine.
There is no restriction on where your control machine is located, e.g. your data center or Amazon EC2.

Backup
------

When we backup we create a restoration point.
A restoration point is a copy of the contents of master at a given point in time.
We create restoration points in two steps:
(1) copy contents of master to slave, and
(2) snapshot contents of slave.
Each restoration point consists of a snapshot and a set of files.

For the copy, we apply cross-region replication.
Cross-region replication continually copies contents of master to slave.
With this approach we can make backups faster in the sense that we do not wait several hours for a copy operation to bring all data from master to slave
Instead, by copying keys as soon as they are modified we obtain the latest version of slave in master at any given time.
Moreover, [cross-region replication does not replicate version deletes](http://docs.aws.amazon.com/AmazonS3/latest/dev/crr-what-is-isnot-replicated.html), thus protects from malicious deletion.

Cross-region replication requires enabling versioning on the slave bucket.
Thus, every time we operate on a key in the slave bucket, versioning takes care of creating a version of that key.
Versioning releases you from implementing a repository of versions.
You only have to care about removing versions when they become obsolete.

The snapshot of the slave bucket consists in creating an index of the contents of slave.
Creation of the index happens when you run command `backup-my-bucket snapshot`.
The command saves the snapshot in the snapshot machine.
The snapshot may be compressed.
The implementation distributes the work of exploring and querying S3 versions amongst a number of workers.
A particular challenge to exploration of S3 buckets is that for each directory, S3 API will list files in batches of 1000.

Restore
-------

Restore is your traditional copy operation.
Restore happens when you run command `backup-my-bucket restore`.
Figure 4: illustrate run of command restore.
The implementation distributes the work of copying amongst several workers.

Manage
------

Management of restoration points consists in periodically running command `backup-my-bucket gc`.
The command will remove all obsolete restoration points.
That includes the snapshot file and all corresponding versions in the slave bucket.
A restoration point is obsolete when it is older than the retention policy.
If there are not enough restoration points to meet the minimum redundancy policy, the command will not remove any restoration point.

Refine
------

The tool is in beta stage.
We are currently testing the tool.
In particular, our tool has the following limitations:

1. Copy files from master to slave during creation of restoration
   points. Instead, we rely on cross region replication to copy
   contents in advance.
2. Compress contents of restoration points.
3. Delete any given restoration point.
4. We cannot do recovery by fall back.

We like pull requests and, of course, we are [hiring](http://backstage.segundamano.mx/work-with-us/), so write a comment or drop me a line at ruslan.ledesma@schibsted.com.mx.

