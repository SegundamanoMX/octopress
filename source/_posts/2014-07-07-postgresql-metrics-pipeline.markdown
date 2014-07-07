---
layout: post
title: "Postgresql Metrics with Logstash"
date: 2014-07-07 08:00:59 -0500
comments: true
categories: 
---
*by Ian Delahorne*

I thought I'd share our setup at [SegundaMano.mx](http://www.segundamano.mx)
for extracting PostgreSQL metrics with [Logstash](http://www.logstash.net) to
push to graphs. We're planning on upgrading our database cluster from an older
PostgreSQL version, and we want to know what potential performance bottlenecks
we have before and after upgrading 

Goals
-----

Our goals here are to answer the questions: 

* Which of our queries are slow?
* What's the ratio of slow queries to non-slow queries? 
* What's the average query time?

We want these in place before we do a major overhaul of our databases,
so we can see how our upgrades perform. Graphs are always better than
"well it feels a lot better"

Our choice of tooling landed on [Logstash](http://logstash.net)
parsing the CSV log, extracting data to push to Statsd/Graphite and to
Elasticsearch/Kibana via RabbitMQ. In addition to Logstash, 
other tools can extract data from the CSV log, for example
[pgBadger](http://dalibo.github.io/pgbadger) and PostgreSQL
itself.

From the CSV log, we extract the query duration of all queries and
push this to statsd. We also fire off a counter for each query, and a
separate for each slow query. 

Parts involved
------------

We broke this down into 4 different roles - this might change at some
later point but it's a start. I drew a little picture with the various
components - the dotted lines denote host boundaries

{% img /images/logstash_pipeline.png %}

### Database servers

* Postgres with CSV logging
* Logstash
* Statsd

### RabbitMQ servers

* RabbitMQ in a cluster

### Graphite server

* Graphite (carbon-cache, whisper, graphite-web)

### Elasticsearch server:

* Logstash indexer
* Elasticsearch
* Kibana
* Nginx


The pipeline components
----------------------

## Logstash 

[Logstash](http://logstash.net) is basically a Unix pipe on steroids.
It's a JRuby project with a lot of input, filter, and output plugins
hosted by Elasticsearch. It really shines when connected with
ElasticSearch and Kibana.

Usually what's done is a logstash "agent" instance runs on each server
that parses the logs, mangles them into your correct format, and push
them to a central broker. Then an "indexer" instance pulls them off
the broker and indexes them into ElasticSearch. This decouples the
instances a bit, allowing you to firewall off the ES instance from the
servers, or use a lightweight shipper agent lacking ES support (such
as [Beaver](http://beaver.readthedocs.org/en/latest/)) to ship
entries.

As for brokers, the most common are Redis and RabbitMQ. The easiest to
use is Redis, using a queue or a channel. Unfortunately this doesn't
offer the routing possibilites of RabbitMQ, or the ability to see
events coming over in real time with a script performing `tail -f`
duties - with Redis you can see the firehose with `MONITOR` and that's it.

## RabbitMQ

[RabbitMQ](http://www.rabbitmq.org) is an open source AMQP broker. We
have a separate Vhost for logstash, and separate users for indexer and
publisher.

In the vhost there's a persistent `topic` exchange. This means that we
can shut down either the producer or consumer without losing events on
the floor - they get queued up until the indexer comes alive again.
For availability we run a cluster over several hosts using a virtual
IP with keepalived for the clients to connect to.

## Statsd

[Statsd](https://github.com/etsy/statsd/) is a project from Etsy. You
shove metrics to it (types available
[here](https://github.com/etsy/statsd/blob/master/docs/metric_types.md)),
and it handles the per-timeunit bucketing, mean/std/upper90 of timers
et c and ships data to Graphite. Logstash has this as well in the
[metrics](http://logstash.net/docs/1.4.1/filters/metrics) filter, but
it doesn't behave as well as I'd like.

We use Vimeo's
[go implementation](https://github.com/vimeo/statsdaemon) instead of
Etsy's NodeJS version. The main reasoning being go projects compile to
a static binary, simplifying deploys (since we don't use NodeJS in
production). I built a
[RPM specfile](https://gist.github.com/lflux/934eff42924e276c8673) to
build an RPM of this.

## Graphite

[Graphite](http://graphite.readthedocs.org/) is a graphing system
comprising several parts. Carbon-cache receives the metrics and stores
them in Whisper. Whisper is a timeseries database that doesn't lose resolution,
like RRD does. Graphite-web is a Django project that handles the user
interface and rendering.

We use PostgreSQL as the storage backend instead of
sqlite after reading [this blog post](http://obfuscurity.com/2013/12/Why-You-Shouldnt-use-SQLite-with-Graphite)

## Elasticsearch / kibana

Logstash publishes the events into
[ElasticSearch](http://www.elasticsearch.org), with one index per
day. [Kibana](http://www.elasticsearch.org/overview/kibana/) is a
HTML/JS frontend to Elasticsearch for viewing the log data. The nice
thing about Kibana is that it's really easy to search in the data and
randomly play around with different queries - it starts off with all
events and has nice breakdowns of the values of each. At my home
company, we use Kibana to make sense of the errors coming off our app
servers and have caught a lot of interesting bugs from randomly
playing around with the queries.

Results
------

A few hours after we enabled the whole pipeline, we already could use
the Kibana interface to spot slow queries, specifically two major
offenders that we could clear up with one index on a table.

Kibana slow query count:
{% img /images/kibana_slows.png %}

Graphite queries vs slow queries
{% img /images/query_count.png %}

Graphite query time
{% img /images/query_time.png %}

<!-- more -->
Configuration Details
------------------

## On the PostgreSQL server

### postgresql.conf

```
# Log both to syslog and CSV. A .log file will be created, but it will
be empty.
log_destination = 'syslog,csvlog'
log_filename = 'postgresql-%Y-%m-%d.log'
# Log duration of all statements. 
# Log full statement of any that takes  more than 2 seconds.
log_duration = on
log_min_duration_statement = 2000
log_statement = 'none'
# If you log in a locale such as es_MX, logstash might not parse the CSV correctly
lc_messages = 'C'
```

### Logstash shipper

``` plain logstash-postgresql-shipper.conf
input {
        file {
                "path" => "/path/to/pg_log/*.csv"
                "sincedb_path" => "/path/to/pg_log/sincedb_pgsql"
# fix up multiple lines in log output into one entry				
           codec => multiline {
                   pattern => "^%{TIMESTAMP_ISO8601}.*"
                   what => previous
                   negate => true
           }
        }
}

filter {
# See http://www.postgresql.org/docs/9.3/interactive/runtime-config-logging.html#RUNTIME-CONFIG-LOGGING-CSVLOG
        csv {
 columns => [  "log_time", "user_name", "database_name", "process_id", "connection_from", "session_id", "session_line_num", "command_tag", "session_start_time", "virtual_transaction_id", "transaction_id", "error_severity", "sql_state_code", "sql_message", "detail", "hint", "internal_query", "internal_query_pos", "context", "query", "query_pos", "location"]
        }
  mutate {
         gsub => [ "sql_message", "[\n\t]+", " "]
  }
# use timestamp from log file	 
  date {
        #2014-05-22 17:02:35.069 CDT
        match => ["log_time", "YYYY-MM-dd HH:mm:ss.SSS z"]
}
  grok {
    match => ["sql_message", "duration: %{DATA:duration:int} ms"]
    tag_on_failure => []
        add_tag => "sql_message"
  }
# See postgres configuration - a message with 'statement: ' is a slow query
  grok  {
        match =>["sql_message", "statement: %{GREEDYDATA:statement}"]
        tag_on_failure => []
        add_tag => "slow_statement"
  }

output {
# Increase hitcounter when we see a slow statement
  if "slow_statement" in [tags] {
        statsd {
                increment => "postgresql.slow_queries"
        }
  }
  # increase hitcounter for all queries
  # send timing metrics for queries
  if "sql_message" in [tags] {
          statsd {
                timing => {"query_duration" => "%{duration}"}
                increment => "postgresql.queries"
          }
  }
  # Ship off all to rabbitmq
  rabbitmq {
    'durable' => true
    'exchange' => 'logstash'
    'exchange_type' => 'topic'
    'host' =>  "server"
	#note - replace type and host manually since as of writing this isn't replaced like it should be
    'key' => 'logstash.%{type}.%{host}'
    'password' => "password"
    'persistent' => true
    'user' => 'shipper'
    'vhost' => 'logstash'
    'workers' => 4
  }
}
```

### Statsdaemon
Not much to this here - just run statsdaemon and edit the configuration file `/etc/statsdaemon.ini` and set the correct graphite host.


RabbitMQ
--------

Set up rabbitmq with a Vhost for logstash, create users indexer and
shipper that can read and write to the logstash vhost. Before starting
the shipper, start the indexer which will automatically create the
binding from the exchange to the queue.

ElasticSearch/Indexers
-----------

### ElasticSearch
Install elasticsearch with a fair bit of storage. 

``` yaml /etc/elasticsearch/elasticsearch.yml
cluster.name: elasticsearch
path.conf: /etc/elasticsearch
path.data: /opt/logs/elasticsearch/data
path.logs: /opt/logs/elasticsearch/logs
discovery.zen.minimum_master_nodes: 1
discovery.zen.ping.multicast.enabled: true
```

### Logstash Indexer

Configure to pull events off RabbitMQ and index them into Elasticsearch

``` plain /opt/logstash/server/etc/conf.d/logstash.conf
input {

      rabbitmq {
        'auto_delete' => 'false'
        'codec' => 'json'
        'debug' => true
        'durable' => true
        'exchange' => 'logstash'
        'exclusive' => false
        'host' => 'host'
        'key' => 'logstash.#'
        'password' => 'passwd'
        'queue' => 'logstash-indexer'
        'user' => 'indexer'
        'vhost' => 'logstash'
      }
}

output {
  elasticsearch { host => "host"
        cluster => "logstash"
        protocol => "http"
  }
}
```


### Kibana

Install kibana from [git master](https://github.com/elasticsearch/kibana) into the directory
where you want it served from.

### Nginx

Set up Nginx to show kibana HTML and to proxy requests to Elasticsearch

``` nginx /etc/nginx/sites-enabled/kibana
server {
  listen                host:80;

  server_name           host;
  access_log            /var/log/nginx/kibana.log;

  location / {
    root  /opt/kibana/current/src;
    index  index.html  index.htm;
  }

location ~ ^/_aliases$ {
    proxy_pass http://127.0.0.1:9200;
    proxy_read_timeout 90;
  }
  location ~ ^/.*/_aliases$ {
    proxy_pass http://127.0.0.1:9200;
    proxy_read_timeout 90;
  }
  location ~ ^/_nodes$ {
    proxy_pass http://127.0.0.1:9200;
    proxy_read_timeout 90;
  }
  location ~ ^/.*/_search$ {
    proxy_pass http://127.0.0.1:9200;
    proxy_read_timeout 90;
  }
  location ~ ^/.*/_mapping$ {
    proxy_pass http://127.0.0.1:9200;
    proxy_read_timeout 90;
  }
  location ~ ^/_cluster/health$ {
    proxy_pass http://127.0.0.1:9200;
    proxy_read_timeout 90;
  }

  # password protected end points
  location ~ ^/kibana-int/dashboard/.*$ {
    proxy_pass http://127.0.0.1:9200;
    proxy_read_timeout 90;
  }
  location ~ ^/kibana-int/temp.*$ {
    proxy_pass http://127.0.0.1:9200;
    proxy_read_timeout 90;
  }
}
```
