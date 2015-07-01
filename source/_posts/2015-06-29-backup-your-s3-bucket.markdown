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

{% img /images/backup-your-s3-bucket/fig1.png %}
___Figure 1:__ Our site writes and reads some content from a master bucket._

Once you start storing content on Amazon S3 (but really, hopefully before), you will start worrying about reliability of your site.
My colleages and I are commited to designing and developing systems that are highly-available and fault tolerant.
But despite your efforts, it is always a good idea to have a disaster recovery plan for your S3 buckets.

We consider that a good disaster recovery plan for Amazon S3 considers system and human errors.
A system error is the loss of a file due to data corruption or the deletion of a set of files due to a bug in our code.
A human error is the deletion of a set of files, for example due to [aws s3 rm s3://master-bucket/cozumel.jpg](http://docs.aws.amazon.com/cli/latest/reference/s3/rm.html).
For data corruption, you could argue that [*Amazon's 99.999999999%* durability](http://aws.amazon.com/s3/faqs/#data-protection_anchor) is enough and [forget about that](http://stackoverflow.com/a/17839589).
For the accidental deletion of files due to system or human error, you could consider that copying by cross-region replication or [glacier storage](https://aws.amazon.com/blogs/aws/archive-s3-to-glacier/) is enough.
But truth is that, when you go into production, you won't feel very confident.

Backup is an essential part of an effective disaster recovery plan.
We consider that a system that does the job let's you:

1. Backup your master bucket.
2. Restore your master bucket to a given point in time.
3. Manage your backups.

{% img /images/backup-your-s3-bucket/fig2.png %}
___Figure 2:__ Abstract architecture of a backup and restore system. Backup and restore operate on the master and slave buckets. The system should offer a management console, run from a control machine._

Approaches to backup
--------------------

A first approach to backup is to store backups in your local data center.
This is not what we want because it defeats the purpose of using S3.
We want to store our master bucket in another S3 bucket.

For backing up master bucket in a slave bucket, you can [copy the contents from master to slave](http://serverfault.com/a/239722).
This however takes a lot of time and managing versions by hand is difficult.

One could be tempted to avoid copying altogether by versioning.

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

Cross-region replication has two advantages:
(1) replicates creation and deletion of files, and
(2) restricts the location of the master and the slave so that they are in different locations.
However, restoration and management of versions is still difficult and unpractical

Our solution
------------

We approached problem by complementing cross-region replication and versioning with backup management and a restore operation.
We implemented managemenent and restore in the command line tool `backup-my-bucket`.
We wrote `backup-my-bucket` in [Go](http://golang.org/) and made it [open source](https://github.schibsted.io/smmx/backup-my-bucket).
We take advantage of it's facilities for writting concurrent code, in particular [goroutines](https://gobyexample.com/goroutines) and [channels](https://gobyexample.com/channels).
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

{% img /images/backup-your-s3-bucket/fig3.png %}
___Figure 3:__ We use cross-Region replication to continually replicate onto slave bucket each operation applied to master bucket._

With this approach we can make backups faster in the sense that we do not wait several hours for a copy operation to bring all data from master to slave
Instead, by copying keys as soon as they are modified we obtain the latest version of slave in master at any given time.
Moreover, [cross-region replication does not replicate version deletes](http://docs.aws.amazon.com/AmazonS3/latest/dev/crr-what-is-isnot-replicated.html), thus protects from malicious deletion.

Cross-region replication requires enabling versioning on the slave bucket.
Thus, every time we operate on a key in the slave bucket, versioning takes care of creating a version of that key.

{% img /images/backup-your-s3-bucket/fig4.png %}
___Figure 4:__ Every time cross-region replication applies a change to slave bucket, versioning stores corresponding versions in slave bucket. The write to file `A` creates version `A3`, the delete of file `C` creates delete marker `DEL`._

Versioning releases you from implementing a repository of versions.
You only have to care about removing versions when they become obsolete.

The snapshot of the slave bucket is an index of the contents of slave.
Creation of the snapshot happens when you run command `backup-my-bucket snapshot`.

{% img /images/backup-your-s3-bucket/fig5.png %}
___Figure 5:__ Snapshot of the slave bucket proceeds by creating an index of the current versions of the keys in slave._

The command saves the snapshot in the control machine.
The snapshot may be compressed.
A particular challenge to taking snapshots of S3 buckets is that for each directory, S3 API will list files in batches of 1000.
We approach the problem by [exploring the slave bucket breadth-first](https://github.schibsted.io/smmx/backup-my-bucket/blob/2deb83fc44eb278aeed8752c87624321ae591eff/snapshot/snapshot.go).
For each new directory found we spawn a new worker goroutine, thus distributing queries to S3 API and making a more efficient use of resources than a depth-first approach.
The number of workers is configurable.
We usually take less than an hour to process c.a. 15 million keys in a flat directory tree.
Of course asking for more workers than the count of directories in your directory tree will bring no gain in speed.

Restore
-------

For a given snapshot, restore is the copy of the corresponding versions from slave bucket to master bucket.
Restore happens when you run command `backup-my-bucket restore`.

{% img /images/backup-your-s3-bucket/fig6.png %}
__Figure 6:__ A run of restore from slave into master is executed from the control machine. Restore proceeds by copying versions corresponding to a given snapshot.

Given the snapshot, the [tool](https://github.schibsted.io/smmx/backup-my-bucket/blob/2deb83fc44eb278aeed8752c87624321ae591eff/restore/restore.go) distributes the copy of corresponding versions amongst a configurable number of worker goroutines.
The limit to the number of workers is dictated by your system limits, resources, and your upload speed.
We usually take several hours to restore a terabyte of data.

{% img /images/backup-your-s3-bucket/fig7.png %}
___Figure 7:_ We distribute restore operation amongst several workers, each copies a version key from slave to master at a time._

Manage
------

Management of restoration points consists in periodically running command `backup-my-bucket gc`.
The command will remove all obsolete restoration points.
That includes the snapshot file and all corresponding versions in the slave bucket.
A restoration point is obsolete when it is older than the retention policy.
If there are not enough restoration points to meet the minimum redundancy policy, the command will not remove any restoration point.

{% img /images/backup-your-s3-bucket/fig8.png %}
___Figure 8:__ A run of `gc` removes all the versions corresponding to an obsolete restoration point._

Future work
-----------

Currently, `backup-my-bucket` is in beta stage.
For future versions, we would love to have the following features that we may or may not develop.

1. Copy files from master to slave during creation of restoration
   points. Instead, we currently rely on cross region replication to copy
   contents in advance.
2. Compress contents of restoration points. We already compress snapshot files, so nothing to do there.
3. Do recovery by fall back. That is, promote slave to master and move restoration points to new slave.

We encourage people to try `backup-my-bucket` out and submit pull requests.
And, of course, we are [hiring](http://backstage.segundamano.mx/work-with-us/), so drop us a line.
