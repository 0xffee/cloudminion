cloudminion
===========

DESCRIPTION

CloudMinion is a set of tools for identifying unused OpenStack VMs, setting and managing expiration dates, shutting down and deleting expired VMs.

It consists of the following components:
  - cm_agent.pl  - Tool which runs on the OpenStack compute nodes and collects info from the VMs by guestmounting them in RO mode.
  - cm_manager.pl . Tool for managing the VMs by setting expiration date, shutting down and deleting expired VMS, sending notifications, etc.
  - cm_em.cgi  - GUI for managing the expiration date of the OpenStack VMs.
  - Supporting scripts and tools for emailing, running OpenStack commands, etc.



REQUIREMENTS

Packages:
perl-DBD-MySQL needs to be installed on all compute nodes and the management node.
perl-Mail-Sendmail needs to be installed on the management node

DB:
  - A cloud_minion database needs to be created, preferably on the same db host where nova and keystone databases are located.
  - An account with create, insert, delete, update, select privileges needs to be created for the above database.
  - The account above or another readonly user (with select privileges) needs to have access to nova and keystone databases




LICENSE

Copyright 2013 PayPal, Inc.

Licensed under the Apache License, Version 2.0 (the .License.); you may not use this file except in compliance with the License.

You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0 Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an .AS IS. BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
