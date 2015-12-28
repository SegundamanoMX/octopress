---
layout: post
title: "Static Assets Cache Busting"
author: José Ríos
date: 2015-12-28 09:00:00 +0000
comments: true
categories: [Browser Cache, Build System, Static Assets]
---

So, you're worried about the performance of your site and have leveraged cache
headers, or even better, you're using a CDN for all your static assets: images,
CSS and JavaScript files.

Then, during the next release of your site you realize something is wrong, there
is a bug and you have already spent some time looking for the cause, only to
discover that a JavaScript file seems not to have the last changes introduced by
the last deploy, so you empty your browser cache, reload, and voilá, issue solved.

When using a CDN it's a little bit harder to debug this kind of problems, you will
have to check whether the asset is being served by your upstream server or by your
CDN, if so, you will have to purge your CDN caching, too.

How to avoid cache issues with your static assets? Enter cache busting: preventing
a browser to reuse a resource it has already retrieved and cached.

## Cache busting using query strings

This technique uses a query string appended to the resource link, it could be
whatever you want, but timestamps and version numbers are suggested.

``` html
<link rel="stylesheet" type="text/css" href="css/example.css?v1.0" />
```

One downside for this approach is that sometimes query strings are ignored, that
means for the browser the file hasn't changed, and the cache busting doesn't happen.

## Cache busting by fingerprinting your assets

### Do it automatically
