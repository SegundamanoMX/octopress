---
layout: post
title: "Continuous Delivery"
date: 2015-07-01 16:08:49 -0500
comments: true
categories: 
- Continous Delivery
- Versioning
- Blue/Green/Canary
- Canary deployment
- AB testing
- Nginx load balancer
- HA Proxy
---
Continuous Delivery is a software development approach in which teams keep producing code in short cycles and ensure that the software can be reliably and released at any time.

What's Blue/Green deploy strategy? There's a lot of different opinions and definitions, for us we see it as a way to avoid being offline if something goes wrong with a new deploy of functionality (and being shouted at, or fired).

The basic premise is to duplicate your production stack in order to have one with the most recent software installed and the other with the last stable version (and proved in production). This way if something happens with the new deploy you can always perform a rollback as fast as you can switch traffic to the old stack.

About the "blue" and "green" concepts, sometimes the new version is called blue while green is the fallback; for some people is the other way around. That's why we'll use **fallback** to describe the "old, stable" version of the system while we'll use **canary** to describe a new, shining and hopefully better version of it.

This brings another concept: canary.

It's simply to use a chunk of stack for deploying new versions. This way you'll have a canary in your stack in which validation over production will be performed. It's refered as canary for the real-live canaries used in mines to "supervise" the quality of the air, if the canary dies (because the air is rare) the miners could have time to be saved.

The canary part of the stack gradually becomes bigger and bigger and at some point your whole stack is canary. This way you tested progressively in production a new feature without the risk of putting your site offline.

**Current Situation**
---------------------

Currently we are working with a development methodology in which new features are delivered to production twice a month and usually with a lot of features. This practice increased the complexity to resolve a problem: as many features you develop is as many components you have to troubleshoot in case of a problem and you don't know which one caused the problem.

When a new feature is developed it has to wait until the next release (two weeks) to be in production, this makes our delivery process very slow.

In the past we had to install all the new developed packages manually at our infrastructure, this means enter in every single server involved for the release process, now we are using a super cool tool which is called SaltStack as a configuration and orchestration management system, this tool allows us to install automatically and quickly new version of packages.

If you are familiar with Puppet or Chef you would know a little bit more about what we are talking about, if not, you can search by your own the configuration and remote execution management tool that suites your needs. 

The Segundamano infrastructure seeing from the point of view of the interaction between Front Servers (www, php, nginx, varnish, etc) and the End-User's request, begins with the firewalls as a first level that includes security for layer 3 and 4 and which redirect (via DNAT) to a second level composed for Load Balancers with High Availability (HA) capabilities, in other words these load balancers in our case Keepalived can create a virtual IP Address (VRRP) and they have the task besides the HA to balance at layer 3 and 4 the user's request for the next level composed by the Front platform, currently there are two more lower levels which are the backend, and finally the Data Layer (Database.- PostgreSQL),  but they are not touched by the load balancing layer  as we can see in the next Diagram:

![Infrastructure as is](/images/as_is_infrastructure.jpg)

**Goals**
---------

Now, there are many ways to conceptualize the Blue/Green/Canary paradigm.  Depending on your needs, current situation and obviously  your infrastructure architecture. 

Based on the idea presented in the introduction of this article and having in mind our current situation and the infrastructure that Segundamano has, we decided to represent and therefore to implement Blue/Green/Canary *under the concept that all frontals servers can be a potential candidate to have the role or belong to one of the Stacks mention before, this is to be a  Blue, Green or Canary server*.

Yea you are right !!, this sounds so simple, but there are some key points to have in mind in order to pass through correctly from the concept to the implementation:

1. When we want to release a new potential version,  we just want to redirect a small percentage of the user's request in order to test functionality (**Canary Stack**).

2. Then if everything is going well, we are going to redirect the 100% of the user's request to the new potential release version of our platform.(**Blue Stack**)

3. But not always life is good, what if for any reason, and there are tons of them, we realized that some feature or functionality it's broken after we have been redirected users request to the new potential release version !!, Well, we need to redirect them back to the Stable Version we use to have (**Fallback Stack**) 

4. We need to ensure that in the process of redirecting users request from one stack to another, the user's sessions are not going to be lost or closed.

**Implementation **
-------------------

1. As we mentioned before, we must create one more stack of servers, for the new potential releases, in this case will be the Blue Stack, we already have the Green Stack  for the current release stable version, which in fact  is the only one we have today.

2. Hey wait a minute, but you have just  said  that all servers can be a candidate to be or belong for any Stack no matter if we are talking about Blue, Green or Canary, Yes you are right !!, but we need resources in order to support at least two different versions alive at same time of the platform (web, msite, etc).

3. We also need to create an extra layer of load balancers, *but Why another one!? if we already have the super powerful Keepalived load balancers*. Well, as we described earlier in this article, those  load balancers ensures HA and 3 and 4 layer load balancing (IP/TCP), but ... and this is a Big But !!, we are not ensuring the users sessions layer, for tech guys this is the OSI layer 7, this means that we need to ensure that the user's sessions will not be lost or closed if we move them from one Stack to another.

4. So, based on the point above, we selected after some studies on the performance and usability benchmarking as well as our own know how in some tools a proxy tool which has  two main advantages:

    1. Layer 7 support load balancing, this is the persistence based on cookies (sessions).

    2. A proxy server which can be programmable (dynamic behavior).

We describe in the next diagram the idea explained in the points discussed before:

![Infrastructure to be](/images/infrastructure_to_be.jpg)

And talking about Load Balancing levels and layers, why not just remove the keepalived level which are the load balancers for layer 3 and 4 and just leave the new Layer 7 proxy load balancers. Well, if we want a full redundant architecture, let's remember that for example HAProxy or Nginx or Pen or Pound they do not support the creation of a Virtual IP Address which ensures the HA feature, and if in Segundamano already have the keepalived which has this feature, the question would be, Why not combine the features from one Load Balancer (HA and 3 and 4 layer support) and the other Load Balancer (Programmable and layer 7 cookies session support)?. 

And ... that's it !!, Is that all?, well, the answer is NO, let's remember that almost all things in life or at least in projects are about PPT.- People, Process and Tools.

We need a tool to help us to distribute to a big amount of servers the proper configuration that enable us to change the behavior on the fly (orchestration), for example to move a certain % of users from one stack to another and vice versa.

But all tools and People involved are useless if we do not define the correct processes that must be reflected on the tools we use. 

In the next section we will talk a little bit more about the technologies we decided to use in order to achieve the Blue/Green/Canary paradigm. 

One note, we always got confused when we tried to identify what's blue or what's green? that's why we stopped thinking like that and use the canary and fallback concepts; after this blue and green are only names of the stack, but as that is really, really boring we came to name it "Topo" and "Gigio" after an inside joke in the team as one of our colleagues is a lookalike of the TV program.

So, **topo** or **gigio** can be at anytime **canary** or **fallback** stack per service basis (but not the two at the same time).

 ![Topo Gigio](/images/topogigio.jpg)

**Tools**
---------

In order to implement this solution, we had to choose the right tools that help us to achieve our goals. So we choose the following tools:

* **Salt Stack **

Salt Stack is a python based open source configuration management and remote execution application which handle the infrastructure as code.

We used this tool as the server's brain, so we can handle our entire infrastructure from a single point, allowing us to standardize our servers configuration and to automate tasks.

For automation we used salt stack with jinja, that is a python templating extension that enable us to make dynamic and on the fly configuration files for the servers.

* **Keepalived**

Keepalived is an open source Layer 3 and 4 Load Balancer Application for incoming requests between servers. The main goal of this component is to provide high availability to Linux system based Infrastructures.

We use Keepalived in order to provide high availability to our Proxy Load Balancers (Nginx), because of Nginx can't do it by itself.

* **Nginx**

Nginx is a Free, Open Source and high performance Http server and proxy.In our experience, it has been considered the best option for handling large amount of requests.

We use Nginx as load balancer and as SSL Proxy. Basically all the requests that come from our end users are handled by Nginx in order to secure them via the SSL protocol.

* **Python**

Python is a high-level programming language that has been created to emphasize the code readability and its syntax allows programmers to express concepts in fewer lines of code.

We use Python to create the script which orchestrate dynamically the load balancer's configuration (with help of SaltStack-Jinja) in order to follow with the continuous delivery process.

**Configuration Details**
-------------------------

**HA Proxy**:

We start our project with HA Proxy in mind. It's simple, reliable and fast. Three key points we needed for balancing our traffic between stacks in order to have our "virtual canary".

The configuration is really simple, with something like

    frontend  main *:443
	    acl	canary		cook(site_id) canary
	    acl	fallback	cook(site_id) fallback
	    
	    use_backend		canary		if canary
	    use_backend		fallback	if fallback
	    default_backend newuser
    
    backend newuser
	    balance roundrobin
	    cookie	site_id		insert indirect maxlife 72h preserve
	    server	fallback1	10.39.0.92:443 check inter 1000 cookie fallback weight 95
	    server	fallback2	10.39.0.93:443 check inter 1000 cookie fallback weight 95
	    server	canary1 	10.39.1.90:443 check inter 1000 cookie canary weight 5
	    server	canary2 	10.39.1.90:443 check inter 1000 cookie canary weight 5
    
    backend canary
	    balance roundrobin
	    cookie	site_id		insert indirect maxlife 72h preserve
	    server	canary1 	10.39.1.90:443 check inter 1000 cookie canary weight 1
	    server	canary2 	10.39.1.91:443 check inter 1000 cookie canary weight 1

    backend fallback
	    balance roundrobin
	    cookie	site_id		insert indirect maxlife 72h preserve
	    server	fallback1	10.39.0.92:443 check inter 1000 cookie canary weight 1
	    server	fallback2	10.39.0.93:443 check inter 1000 cookie canary weight 1

What this does is to check if the user have a cookie site_id with values canary or fallback, if so it use the proper backend for each value of the cookie, if not we redirect it to the backend newuser and then we set the different weights of the stack directly in each server.

Anyway, we'll not get deeper into HA Proxy, as we soon found it only support session cookies. It can modify a cookie already set elsewhere, but if that cookie is missing (for example, a fresh user which have never visited our site) it will depend on the application to handle most of the logic.

We prefered to move to Nginx, as it can handle cookies with expiration date. It's not "as simple" as HA Proxy, but it give us a little of room to "script" the cookie part.

**Nginx**:

 - **Load balancing part:**

We're using the load balancing features of Nginx, this is as "simple" as:

    upstream fallback {
	    server          10.39.1.90 max_fails=5 fail_timeout=20;
	    server          10.39.1.91 max_fails=5 fail_timeout=20;
    }
	
	upstream canary {
		server          10.39.0.93 max_fails=5 fail_timeout=20;
		server          10.39.0.92 max_fails=5 fail_timeout=20;
	}

That give us the basic round-robin balancing of the servers in each upstream with the same weight. We set up the two stacks and then we can send traffic to them with

	location / {
		proxy_pass http://fallback$request_uri;
	}

That force us to change configuration once we want to switch from stack (the blue/green paradigm we discuss before) and it doesn't allow to apply to it the concept of canary, since our way of seeing it is to make it work through balancing a portion of traffic to the new stack.

But in order to really replicate the features of HA Proxy we need to check if the cookie to handle the balancing between stacks is present, if not assign the new user to a stack and then proxy the connection to the right stack.

 - **Cookie part:**

For the cookie part we can use a map. As Nginx create a variable for each cookie received we only need to map it to a result. We came with the following code

	map $cookie_site_id $selected_upstream {
		default newuser;
		canary canary;
		fallback fallback;
	}

That way, if the cookie does not exist or the value of the cookie is not "canary" or "fallback" it will return the default value of "newuser" in the "selected_upstream" variable, otherwise it will return 'canary' or 'fallback'.

After doing this we need to send the cookie to the user, for when he or she returns, it will use the same stack. For doing this the code is

	add_header Set-Cookie "site_id=$selected_upstream;Domain=.test.me;Path=/;Max-Age=99000";

Actually, after doing this, we have solved how to select "on the fly" the stack the user will use, now we can change the line to proxy the connection

	location / {
		proxy_pass http://$selected_upstream$request_uri;
	}

We still need to have a way to balance the traffic between stacks. For that reason the default value of the map described above returns "newuser" when the cookie is not set.

 - **Split Clients:**

There are different ways of "randomize" the selected stack when a new user enters the site. We use a simple module of Nginx named [split clients](http://nginx.org/en/docs/http/ngx_http_split_clients_module.html), what it does basically is to hash an input string to a defined range of numbers and then check if the result of the hash is between a subrange in the predefined "universe" of the possible results. We use it because it is simple, but also using the perl module in Nginx to do calculation was considered; we don't need "that much power".

As this gives always the same output and we wanted to get some more randomness, we send as the input string the local time (when the request was made), the IP and the User Agent. Only using IPs for some could solve the whole problem, but in our site a lot of users share the same IP and sometimes we want to deliver between them different versions of the site (hence, different stacks).

	split_clients "${remote_addr}${http_user_agent}${time_local}" $stack_version {
		1.0%    canary;
		*       fallback;
	}

And we only need to use the output of the module (in the variable "stack_version") to assign a first time user.

	if ($selected_upstream = "newuser") {
		set $selected_upstream $stack_version;
	}

At this point we have an almost functional configuration, and the new users can be balanced between stacks by modifying the nginx configuration. For the logic we set up so far, moving users between stacks when they already have the cookie we need a flag to check what version of configuration they have.

	set $rollout_stage 1;
	add_header Set-Cookie "site_rs=$rollout_stage;Domain=.test.me;Path=/;Max-Age=99000";

For moving users from the fallback stack (as we don't want to move the users from the canary, they already are in the new version) we can check if they belong to that stack and then again select a new one (probably).

    split_clients "${remote_addr}${http_user_agent}${time_local}" $stack_version_renew {
	    1.0%    canary;
		*       fallback;
    }
    
    ...
	
	if ($cookie_site_rs != $rollout_stage) {
		set $candidate_split_clients "D";
	}
	if ($selected_upstream = "fallback"){
		set $candidate_split_clients "${candidate_split_clients}C";
	}
	if ($candidate_split_clients = "DC"){
		set $selected_upstream $stack_version_renew;
	}

There are two peculiarities here, as Nginx is not capable of having "OR" or "AND" logic in the if statements, we need to check them separately (if the user is in "fallback" and if the user is in another rollout stage) and then check if both conditions are true.

The other is the need to use a separately split_modules to calculate the percentage of users which will move from "fallback" to "canary". The percentage should be different (with the exceptions of 0% and 100%) for new users and existing ones.

Let's say we in the first stage want to deliver canary to 5% of the users. At this point all the users are new, so everybody will fall into the split for new users. Then, in the second stage of rollout we want to increase the percentage to 10%. For new users, setting 10% in the split is all that we need, but 95% of our existing users should be in the "fallback" stack. We only need to move 5.2631% of those users to canary in stage 2.

Talking with numbers (and some assumptions to understand this: 100 new users enter in each stage and all the previous users enter again); if in the first stage we have 100 users, 5 will go to "canary", 95 will go to "fallback". In the second stage, of the new users 10 will go to "canary" and 90 will go to "fallback"; for the old users of the first stage we only need to move 5 out of 95 from "fallback" to "canary", that's or 5.2631% of fallback users.

| Stage/Percentage 	| New users "C" 	| New users "F" 	| Old users "C"     	| Old users "F" 	|
|------------------	|---------------	|---------------	|-------------------	|---------------	|
| 1 - 5%           	| 5             	| 95            	|                   	|               	|
| 2 - 10%          	| 10            	| 90            	| 5 + 5 (5.2631%)   	| 95 - 5        	|
| 3 - 15%          	| 15            	| 85            	| 20 + 10 (5.5555%) 	| 180 - 10      	|
| 4 - 20%          	| 20            	| 80            	| 45 + 15 (5.8823%) 	| 255 - 15      	|
| 5 - 25%          	| 25            	| 75            	| 80 + 20 (6.25%)   	|               	|


The table shows us the following of the previous example. When we are in the third stage, we have 180 users in fallback and 20 in canary. We should have 170 in fallback and 30 in canary, so we need to move 10 users from fallback to canary, that's the 5.5555% of the 180 users.

In the fourth stage we have 255 users in fallback and 45 in canary, we should have 240 users in fallback and 60 in canary, so we need to move 15 users from fallback to canary, that's 5.8823% of the 255 users.

Finally, we have a configuration ready, which is:

    map $cookie_site_id $selected_upstream {
	    default newuser;
	    canary canary;
	    fallback fallback;
	}
	
	split_clients "${remote_addr}${http_user_agent}${time_local}" $stack_version {
		1.0%    canary;
		*       fallback;
	}
	
	split_clients "${remote_addr}${http_user_agent}${time_local}" $stack_version_renew {
		1.0%    canary;
		*       fallback;
	}
	
	server {
		server_name                     m.test.me;
		listen 443 ssl;
		set $rollout_stage 1;
		if ($cookie_site_rs != $rollout_stage) {
			set $candidate_split_clients "D";
		}
		if ($selected_upstream = "fallback"){
			set $candidate_split_clients "${candidate_split_clients}C";
		}
		if ($candidate_split_clients = "DC"){
			set $selected_upstream $stack_version_renew;
		}
		if ($selected_upstream = "newuser") {
			set $selected_upstream $stack_version;
		}
		add_header Set-Cookie "site_id=$selected_upstream;Domain=.test.me;Path=/;Max-Age=99000";
		add_header Set-Cookie "site_rs=$rollout_stage;Domain=.test.me;Path=/;Max-Age=99000";
		
		location / {
			proxy_pass http://$selected_upstream$request_uri;
		}
	}
	
	upstream fallback {
		server          10.39.1.90 max_fails=5 fail_timeout=20;
		server          10.39.1.91 max_fails=5 fail_timeout=20;
	}
	
	upstream canary {
		server          10.39.0.93 max_fails=5 fail_timeout=20;
		server          10.39.0.92 max_fails=5 fail_timeout=20;
	}

**Expected Results**
--------------------

With the Continuous Delivery Implementation, we want to improve some important points in the company:

**Speed:** We can deliver faster important improvements, fixes and features to our end users at any time, because we will be able to release some changes in hours or days. When we achieve this velocity our product may have fewer bugs and user experience will increase.

**Quality:** This approach helps us learning faster about our errors so we can improve the thing we do and release products with more quality.

**Focus:** All the team members can focus on finish and release a task before moving to another task. They don't need to switch their brains between tasks.

**Clarity:** The team should experience less stress, because we have to fix small problems (if any) quickly so this conducts to a lower pressure work.
