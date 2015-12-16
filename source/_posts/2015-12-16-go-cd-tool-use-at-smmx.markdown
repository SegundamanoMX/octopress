---
layout: post
title: "GO Continuous Delivery Tool Experience at Segundamano.mx"
date: 2015-12-16 08:41:13 -0600
comments: true
categories: 
---

At Segundamano.mx we had our first try at following/implementing continuous delivery. In order to do that we needed to consider selecting the right tool. In this article, I intend to share our experience related to the selection and use of the tool: Thoughtworks GO CD. However I will also explain the change in culture that we needed in order to make this project succesful. I don't intend to provide a user guide of the tool that is already provided in their page, rather just to explain what was our approach.

**Initial Discussions and Investigation** 
---------------------------------------------------------
We started having meetings to start dicussing the concepts and dividing responsabilities. It is very important that all the technical people involved in the delivery of the product are involved, that includes Developer, Testers, DevOps. Each of them is responsible for the different phases of a delivery pipeline.
 
Be ready to do a lot of reading on the subject, there is plenty of information about the subject of Continuous Delivery. You can find material as simple as [four very simple visualizations](http://continuousdelivery.com/2014/02/visualizations-of-continuous-delivery/) or something more complete as the following book that I hihghly recommend: [Continous Delivery](http://martinfowler.com/books/continuousDelivery.html) by Jez Humble and David Farley. In our case, this book was very useful for the whole team who implemented a project using continuous delivery. 

We quickly identified that no matter which tools we were going to use it was very important to understand the basic concepts of continuous delivery and in doing so it was necessary to improve our culture (processes, communication.. our way of working). We did not change everything we did, since there were things that were working fine we left them alone, but things as working on the master branch only, modifying slightly the role of a QA, developing shorter fragments of code were new to our team and we definetely had to make some adjustments. 
 

**Time To Try The Tool**
----------------------------------
So after our initial investigation, we decided to give it a try to GO CD by Thoughtworks. We went for it because it was open source, its documentation was very clear and had a very good match with the information provided in the Continuous Delivery book and it was easy to start playing with it right away.  

Once installed, you can easily start creating agents, environments and pipelines with your existing repos/projects. Once you read about the basic concepts provided in the [GO CD User Documentation](https://www.go.cd/documentation/user/15.2.0/) it is very easy to start creating your pipelines with existing projects/repos. You can play with it using a branch of an existing project(if possible master directly). We have been using Jenkins for a while as our continuous integration tool so as first steps we tried to replicate the actions taken in Jenkins for any repos/projects, i.e. build, test, create packages and send them to a repo. For example, in the image below, the first three stages were done in Jenkins: unit_test, create_rpm and push_to_pkg_repo_qa.
![Database stages](/images/databasestages.png)

**TIPS when trying the tool:** 

1. Read and learn how to configure a pipeline and its phases, an agent and an environment (you will need them)
2. Learn the organization of the directories related to GO CD, mainly the location of the content stored by the go cd server and go cd agent( it will help you for debugging).
3. Create your first go agent in the same server where GO CD sever is installed (for a test phase an agent is enough) 
4. Use the same commands that you use in your continuous integration tool, in our case jenkins. For example, if you have a make target to test: make test

**The Actual Project**
-----------------------
So the opportunity rose and we took advantange of it. A new project came to create a new functionality in our site: shops. Our "jefecito" (CTO) saw it as our chance to try continuous delivery and so we did. 
During the initial design it was desided to have 5 separate components. 1 DB, 1 Batch to collect certain information from other components, 1 Search Engine, 1 API and the UI. The first two were identified as components that were rarely going to be modified and there was no need to do a blue/green deploy, so for DB and Batch we decided to create two separate pipelines from beginning (initial commit) to end (the deploy). The advantage of this was that these two components were deployed ONLY when there were changes on each one of them instead of deploying everytime any of the other components(search, api, UI) changed. Also, it is easier to identify issues/bugs specific to these two components this way. 
For DB we had the phases described in the first image above, which included: unit_test, create_rpm, push_to_pkg_repo_qa, deploy_qa, push_to_pkg_repo_prod and deploy_prod.
For batch, we had the following stages, as seen in the image below: build, create_rpm, push_to_pkg_repo_qa, deploy_qa, push_to_pkg_repo_prod and deploy_prod. 
![Batch](/images/batch.png)

The remaing components (Search, API, UI) also had its individual pipelines but were combined from the initial QA instalation onwards. 
At a high level view in the image below, you can see the flow of these three components and how the three pipelines do a fan in during the deploy to QA. This gives you a general idea on the flow needed for each component and its dependencies (how they can affect each other).
![Full Solution](/images/shopsfullpipelines.png)

**Tips when organizing your project**

1. Use separate pipelines for components that will not be regurlarly deployed (in our case once a month or so)
2. Use the fan in and fan out functionality of the tool. We used fan in only but plan to use fan for our testing phases in the near future.
3. Try to use the tools you already use for the processto deliver to production, you will find it is easy to adapt many of them to GO CD. For instance, we continued using git, dockers, salt-stack.



**Detailed Description of each of the stages**
--------------------------------------------
In order to see the details of the pipelines, I intend to explain in this section the stages needed for one of the components we used: UI

For each of the stages there were many people involved, from developers and testers to devops. The GO CD tool does provide a nice way to manage the diferent stages but and the end there was a lot work needed by the whole team to make all the stages work. The nice thing about the tool is that it gives you the freedom to fit it to you needs. 

**UI Pipeline**

![UI Pipeline](/images/uipipeline.png)

The build stage: Stage to verify that you can actually build the code. It is worth mentioning that for most stages we used make targets defined in the correspondiging repo. In this case: "make build" 

The test stage: Stage to execute a set of test case and include code coverage. For the UI part we actually raised a complete environment using dockers since we have our expert on docker technology.

The create_rpm stage: Stage to create the rpms used in the deploy to QA and Production. 

The push_to_pkg_repo_qa stage:  Stage to send the packages to our local repo to used them later during the deploy to QA.


**QA Deploy Pipeline**

To have a better understanding of the implementation done for deploy of continuous delivery at Segundamano.mx, I suggest you read a previous article on the subject: [Continuous Delivery](http://backstage.segundamano.mx/blog/2015/07/01/continuous-delivery/)

![QA Deploy Pipeline](/images/qainstallpipeline.png)

The install_qa_50 stage: Stage to deploy to QA, initiated once any of the pipelines for UI, Search or API are completed. It installs in one of the stacks and directs traffic to that stack to 50% 

The inc_canary_qa_100 stage: It directs 100% of the traffic to the stack where the initial instalation occured in the previous stage. This stage is initiated manually once a QA member verifies the new functionality is free of bugs. The manual aproval is done by the QA member.


**Promote QA to Production Pipeline**

![QA to Prod Pipeline](/images/qatoprodpipeline.png)

The promote_pkgs_to_prod stage: Stage to move rpms in our repo to the right place so they can be installed in production.

**Production Deploy Pipeline**

![Prod Deploy Pipeline](/images/prodpipeline.png)

The install_prod_XX stages: Very similar to the QA deploy stages but in prouduction we decided to have more stages to move the traffic incrementally at smaller percentage invervals: 5, 25, 50, 75 and 100. Rollback can occur at any of these stages except when it goes to 100%.

**Tips for Pipeline Stages**

1. Add as many stages as you need, it is easier to identofy the problems if you have simple short tasks in each stage. 
2. Don't be afraid to have a single stage in one pipeline if it makes sense.
3. Have a backup of our configuration of go cd. You don't want to loose the configuration of all the stages/pipelines you have.
4. Identify which stages need manual activation and who is responsible for it from the beginning. In our case the deploy to QA and Production.

**Conclusion**
--------------------------------------------
Overall we are very happy to have selected this tool for our continuous delivery approach. There is good documentation on it and it is relatively intuitive at the time of use. It did adapt to our needs since it gives you the freedom to use any tools for version control, deploy, packages, languages,  etc. It's main goal is to organize the different pipelines and stages and it works perfectly. It is just the tool that helped us implemente/practice continuous delivery but we're glad we schose it and recommend it to anyone interested in conituos delivery.


