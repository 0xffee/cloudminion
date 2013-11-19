CREATE TABLE instance_lifetimes (
  uuid varchar(36) DEFAULT NULL,
  hostname varchar(255) DEFAULT NULL,
  user_id varchar(64) DEFAULT NULL,
  user_email varchar(255) DEFAULT NULL,
  project_id varchar(64) DEFAULT NULL,
  project_name varchar(64) DEFAULT NULL
  expiration_date date DEFAULT NULL,
  last_check datetime DEFAULT NULL,
  unused varchar(15) DEFAULT NULL,
  compute_host varchar(255) DEFAULT NULL,
  state varchar(25) DEFAULT NULL,
  deleted int(11) DEFAULT NULL,
);
