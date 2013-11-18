## DESCRIPTION

CloudMinion is a set of tools for identifying unused OpenStack VMs, setting and managing expiration dates, shutting down and deleting expired VMs.

It consists of the following components:
  - cm_agent.pl  - Tool which runs on the OpenStack compute nodes and collects info from the VMs by guestmounting them in RO mode.
  - cm_manager.pl - Tool for managing the VMs by setting expiration date, shutting down and deleting expired VMS, sending notifications, etc.
  - vmem.cgi - GUI for managing the expiration date of the OpenStack VMs.
  - Supporting scripts and tools for emailing, running OpenStack commands, etc.



## REQUIREMENTS

Packages:
 - perl-DBD-MySQL needs to be installed on all compute nodes and the management node.
 - perl-Mail-Sendmail needs to be installed on the management node

DB:
 - A cloud_minion database needs to be created, preferably on the same db host where nova and keystone databases are located.
 - An account with create, insert, delete, update, select privileges needs to be created for the above database.
 - The account above or another readonly user (with select privileges) needs to have access to nova and keystone databases



## Installation
CloudMinion Management tools need to be installed on a management node and the agent on all compute nodes.

### Preparation
 1. Create a cloud-minion database for this project with user and password, or you can use another existing DB
 The user needs to have select, insert, update, delete, create privileges
 2. Create a read-only user, grant  select privileges only to nova and keystone DBs.
 3. Pull the CM project 
    https://github.com/paypal/cloudminion.git
 4. Update cloudminion/conf/cm.cfg and  cloudminion/conf/cm_agent.cfg with values for your cloud
 5. Open each file under cloudminion/bin/ and change the base_dir  to your installation path
 6. Create instance_lifetimes table in the cloud-minion db  by running 
    mysql .h <db host> .u <cm username> -p  <cloud-minion db>  < cloudminion/install/instance_lifetimes.sql

 
### Installing CM on a management node
 1. Create a base directory for CM, example /opt/cloud_minion, and copy all updated directories and files
 2. Install perl-DBD-MySQL and perl-Mail-Sendmail (yum install perl-DBD-MySQL perl-Mail-Sendmail)


### Installing CM on the compute nodes
 1. Create a base directory for CM, example /opt/cloud_minion
 2. Copy  bin/cm_agent.pl  and conf/cm_agent.conf to all nodes under the base_dir
 3. Install perl-DBD-MySQL   (yum install perl-DBD-MySQL)




## LICENSE

Copyright 2013 PayPal, Inc.

Licensed under the Apache License, Version 2.0 (the .License.); you may not use this file except in compliance with the License.

You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0 Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an .AS IS. BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
