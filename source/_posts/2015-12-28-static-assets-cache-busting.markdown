---
layout: post
title: "Static Assets Cache Busting"
author: José Ríos
date: 2015-12-28 09:00:00 +0000
comments: true
categories: [Browser Cache, Build System, Static Assets]
---

So, you're worried about the performance of your site and have leveraged cache
headers, which tell the browser to hang onto the cached files for a given amount
of time, commonly this time is as long as six months or more, or maybe you're
even using a CDN for all your static assets: images, CSS and JavaScript files.

Then, during the next release of your site you realize something is wrong, there
is a bug and you have already spent some time looking for the cause, only to
discover that a JavaScript file seems not to have the last changes introduced by
the last deploy, so you empty your browser cache, reload, and voilá, issue solved.

When using a CDN it's a little bit harder to debug this kind of problems, you will
have to check whether the asset is being served by your upstream server or by your
CDN, if so, you will have to purge your CDN caching, too.

You need a way for breaking the cache and force the browser to download a new copy
of the JavaScript file every time it has changes, without having to empty the browser
cache or purging your CDN. Enter cache busting.

## Cache busting using query strings

This technique uses a query string appended to the resource link, it could be
whatever you want, but timestamps and version numbers are suggested.

``` html
<link rel="stylesheet" type="text/css" href="css/example.css?v1.0" />
```

One downside for this approach is that sometimes query strings are ignored as a part
of the filename, for the browser that means the file hasn't changed, and the cache
busting doesn't happen.

## Cache busting by file fingerprinting

``` html
<link rel="stylesheet" type="text/css" href="css/example.bc67fbd9.css" />
```

### Do it automatically
