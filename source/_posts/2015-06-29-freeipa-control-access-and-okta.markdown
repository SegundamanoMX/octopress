---
layout: post
title: "FreeIPA Control Access (and OKTA)"
date: 2015-06-29 15:42:23 -0500
comments: true
categories: 
- FreeIPA
- OKTA
- LDAP
- Access Control
- Authentication
---
FreeIPA for your Infrastructure Daily Operations
================================================

When you manage lots of servers (Unix and Linux like), dozens or hundreds of them, one thing for sure that you must take in account is the Access Control, and there are many many tools to help us to that specific task, but let's be realists!  In a minimal decent infrastructure implementation you don?t need to have only Access Control, you need as well policies depending on the user's profile. For example, you are not going to provide root permissions to a sales guy in a linux server for making queries to the main database or if you just want certain developers can execute a critical script (bash or python or whatever).

And we can say, come on! I have a tool that allows me to define Access Control as well as robust policies rules (*all mention before know as Identity and Policies*), for example LDAP or the well known MS Active Directory. But the Access Control is the only thing we have to take care about in our daily minimal server's operation?, obviously No! What about synchronization? this is to have all our server in the correct time for having accurate logs or naming resolution, if we want a friendly way to identify our servers, you know, things that are essentials in order to ensure that the basic communication and security its guaranteed.

Let's stop to talk about needs that aren?t new for us and let's talk about the solutions or in this case Segundamano's solution.

**FreeIPA**
-----------

We are not going to provide or copy/paste an explanation about what FreeIPA is from Wikipedia o Freeipa.org, in that case, please feel free to do it by yourself. We prefer to tell you in our experience what FreeIPA is doing for us. In Segundamano we use FreeIPA for the following approaches:

* **DNS Resolution**

FreeIPA offers an integration of many open source components like Bind DNS Server, so we decided to use it as our main DNS Platform, In this way we can have multiple Bind slaves servers from it. 

And why is this useful? Well It is useful because we want to have an instance for FreeIPA in each environment or Data Center in order to accelerate the DNS resolution and offer high availability. 

Maybe you are wondering about what is a FreeIPA instance? Ok this topic will be explained on a next section on this document when we talk about replication which is a super nice feature. 

* **DNS Master / Slave Deployment**

The communication servers infrastructure in Segundamano is done thought DNS, we do not pretend to explain what a DNS service is, let's just say that if you only use for communication IP addressing and for any reason you have to change the database IP, you will have to change the IP in every single server that has communication with that servers and your memory factor is an issue, because you can forget a server that you never touch but it is crucial and yeap! Your platform becomes unstable or with abnormal behavior.

One of our main directives in Segundamano is to have (at least in production) High Availability in the main services that provides support to our platform. We are not going to enter in detail about what BCP and DRP are (Business Continuity Plan and Disaster Recovery Plan respectively), but as you may know we need to be prepared in case of a server failure or Data Center crash, that's why naming resolution service is critical to have it up & running *7x24x365*.

So when we create a virtual machine (via kickstart) this is enrolled automatically to FreeIPA server and at the same time its DNS name is created (Record A and PTR). FreeIPA acts as the master DNS server and we create separate DNS Bind instances or servers (as you want to call them) which acts as the slaves and they receive the configuration from its master (FreeIPA) automatically. 

Hey wait a minute, you have just said before in this article that this is a centralized architecture about Authentication, NTP, DNS Tool Integration! The answer is yes, in Segundamano we centralize these services in FreeIPA to do it only once and not hundreds of times, but we also believe in Distributed Systems and Automation, so we centralize many of our main services in FreeIPA and this "guy" distribute its own configuration to others in order to have High Availability, that is what becomes super cool FreeIPA.

Let's see the next diagram to have a better idea about DNS Master/Slave Replication:

![DNS master/slave](/images/dns_master_slave.jpg)

* **Network Time Protocol (NTP) Synchronization**

Talking about Network Time Protocol, we are using the one that FreeIPA includes, so maybe you are wondering about why the NTP protocol is very important? And the answer is that NTP allows to synchronize the date of all your infrastructure in order to have more accurate logs and processes (and some systems depend on time).

If you want to have a reliable and synchronized infrastructure maybe you have to consider pointing all your infrastructure to a NTP Server. And the main advantage that FreeIPA's NTP offers is the possibility to audit every system you manage, having accurate information about them. 

* **User Management** 

We have a centralized user database, so we create a user only once in FreeIPA and we are able to log in across all different systems in the company. This have multiple benefits for us as systems administrators, such as:

**Modularity:** FreeIPA allow us to create user and system groups. This give us the flexibility to create Access Policies at user or system level, going from general to specific. Also give us the ability to set up policies accordingly to the real roles in the company.

**Reuse of Policies:** once we create a policy it can be applied to multiple scenarios, avoiding the manual replication and possible human errors by doing that.

* **Free IPA Master / Replica Deployment**

This probably one of the most super cool features about FreeIPA: the capability to create as many FreeIPA instances as we need. Why do I have to create another replica? Well there are tons of reasons, we think that the main reason is... yes you guest right! High Availability.

At this point you maybe wondering based on the point where we discuss earlier in this article about DNS, if I can create many replicas, why to create Bind DNS instances if with the replicas should be enough? For sure you can use replicas to support with DNS, NTP, Authentication, etc. in a HA schema in a distributed way, that is fine if you want to do it that way. For Segundamano we want to have a Centralized Manager which gathers and command all the services mentioned and at the same time have independent services which receives the information they need from its master, in this case FreeIPA, because if, in some case we need to restart or reload a service, we only need to to do it in the service involved and not restart or reload the entire stack of FreeIPA services!

Going back to FreeIPA replica, let?s say that the hard part was to create from zero the first FreeIPA server, create a replica is super simple and after some minutes automagically you will have a clone of your master and could be promoted itself as a master (you can only have one master at the time), all replicas can be promoted as master whenever you need it, ain't that cool!

These are the steps to create a replica:

 1. In the master just enter the next line:
	 
	 *ipa-replica-prepare your_ipa_server_name*

	it creates a file named replica-info-your_ipa_server_name
	 
 2.  In the slave:
	
	*ipa-replica-install replica-info-your_ipa_server_name --setup-ca --setup-dns --no-forwarders --skip-conncheck*

	**--setup-ca.-** put this parameter in order to promote your replica as master when you need it. This parameter is optional, but take into account that when you want to promote your replica, you will need to install the CA information at that moment.

	**--setup-dns.-** this parameter is to clone your DNS configuration to your replica as well as replicate DNS information.

And that?s it!

In the next diagram we show you a brief overview about schema replication in Segundamano:

![FreeIPA replication](/images/freeipa_replication.jpg)

**Integration with OKTA**
-------------------------

OKTA is a tool that once is integrated with an LDAP Directory allows us to have a centralized access and management of a predefined set of commercial applications such as Gmail, Google Apps, Slack, Github, Sales Force, etc. In Segundamano we had integrated FreeIPA as our LDAP Server with OKTA. After this we can login in all internal and external systems handled by OKTA with the same login information (user and password).

With this implementation we are able to manage our user database more efficiently and we can create policies which will rule the permissions to access the applications and systems based on the profiles of every person in the company.

**Advantages**

* A single access with the same password (SSO Single Sign ON)

* Automatic Updates App of Web Apps (OKTA is responsible for updating all)

* Integration of new tools (OKTA is continually developing new applications compatibility)

![OKTA apps](/images/okta_apps.png)

**Implementation**

Our experience implementing LDAP OKTA made us realize we must know beforehand the main parameters of our LDAP deployment 

 - orgUrl
 - ldaphost
 - LDAPPort
 - ldapAdminDN
 - ldapAdminPassword
 - baseDN

It is essential to have a basic knowledge about LDAP (FreeIPA) for reliable deployment. Also we need to install an agent in FreeIPA server so you can have communication with OKTA (cloud), once the configuration is done in OKTA you have to log in at portal as an administrator.

The OKTA configuration is managed from FreeIPA (OKTA uses and agent to check everything is setup correctly), this is a simple way to describe the implementation of OKTA with LDAP.

Once the OKTA agent is configured in our LDAP it was necessary to enable part of SSO in Google Apps to access all our applications in Google, this will instruct Google to use the OKTA credentials instead of their own.

With this technique we avoid having several accesses and passwords for different tools.

![OKTA architecture](/images/okta_architecture.png)

**Expected Results**
--------------------

With this solution we should be able to manage easily and without waste of time the everyday applications by having a central point of control and giving the users a portal where they can access the apps.

This needs applications supporting OKTA integration, at the moment we're handling through this system the following apps:

 - Google Aps
 - Gmail
 - Google Drive
 - Google Calendar
 - Slack
 - Yammer
 - Box
 - Github
 - Jira
 - Confluence
 - Sales Force (In process)

![OKTA supported apps](/images/okta_supported_apps.png)
