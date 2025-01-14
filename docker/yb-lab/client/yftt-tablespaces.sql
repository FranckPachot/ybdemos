-- Here is what I've run in https://www.youtube.com/watch?v=a0b37XOh4ZM&list=PL8Z3vt4qJTkLTIqB9eTLuqOdpzghX8H40&index=33
-- Postgres TABLESPACE in a Cloud Native World | YugabyteDB Friday Tech Talks | Episode 33

/* 
ssh -L 5433:localhost:5433 -L 7000:localhost:7000 root@docker
[ -f ybdemo ] || git clone git@github.com:FranckPachot/ybdemo.git
cd ybdemo/docker/yb-lab 
git pull
sh gen-yb-docker-compose.sh geo

df -h /
psql -h localhost -p 5433 -d yugabyte -U yugabyte 
\pset pager off
create extension pgcrypto;
*/

-- clean all
select format('drop table if exists %I.%I cascade;',schemaname,tablename) from pg_tables where tableowner='yugabyte' and tablename like 'demo%';
\gexec
select format('drop tablespace if exists %I;',spcname) from pg_tablespace where spcoptions is not null;
\gexec
drop table ybwr_snapshots cascade;
\! clear
\c - - - 5433

---# list all servers: 
select host, cloud, region, zone from yb_servers() order by 2,3,4;

---# create a table
create table demo(id bigint primary key) split into 4 tablets;

---# create a tablespace to place RF=3 on one region (eu-west)
create tablespace "eu-west" with ( replica_placement= $$
{
    "num_replicas": 3,
    "placement_blocks": [
{ "cloud": "cloud", "region": "eu-west", "zone": "az1"   , "min_num_replicas": 1 },
{ "cloud": "cloud", "region": "eu-west", "zone": "az2"   , "min_num_replicas": 1 },
{ "cloud": "cloud", "region": "eu-west", "zone": "az3"   , "min_num_replicas": 1 }
    ]
} $$) ;

---# alter table tablespace
alter table demo set tablespace "eu-west";

---# same in us-east
create tablespace "us-east" with ( replica_placement= $$
{
    "num_replicas": 3,
    "placement_blocks": [
{ "cloud": "cloud", "region": "us-east", "zone": "az1"   , "min_num_replicas": 1 },
{ "cloud": "cloud", "region": "us-east", "zone": "az2"   , "min_num_replicas": 1 },
{ "cloud": "cloud", "region": "us-east", "zone": "az3"   , "min_num_replicas": 1 }
    ]
} $$) ;

---# same in us-west
create tablespace "us-west" with ( replica_placement= $$
{
    "num_replicas": 3,
    "placement_blocks": [
{ "cloud": "cloud", "region": "us-west", "zone": "az1"   , "min_num_replicas": 1 },
{ "cloud": "cloud", "region": "us-west", "zone": "az2"   , "min_num_replicas": 1 },
{ "cloud": "cloud", "region": "us-west", "zone": "az3"   , "min_num_replicas": 1 }
    ]
} $$) ;

---# create a partitioned table
create table demo_gdpr ( 
  user_country char(2),
  user_uuid uuid default gen_random_uuid(),
  user_counter int default 0,
  primary key (user_country, user_uuid)
) partition by list(user_country);

create table demo_gdpr_eu partition of demo_gdpr
 for values in ('FR','DE','IT') tablespace "eu-west"
 split into 4 tablets
;

create table demo_gdpr_uk partition of demo_gdpr
 for values in ('UK') 
 split into 4 tablets
;

create table demo_gdpr_ch partition of demo_gdpr
 for values in ('CH') tablespace "eu-west"
 split into 4 tablets
;

create table demo_gdpr_us partition of demo_gdpr
 for values in ('US') tablespace "us-west"
 split into 4 tablets
;

---# the replication factor can be changed
create tablespace "rf3" with ( replica_placement= $$
{
    "num_replicas": 3,
    "placement_blocks": [
{ "cloud": "cloud", "region": "eu-west", "zone": "az1"   , "min_num_replicas": 1 },
{ "cloud": "cloud", "region": "us-east", "zone": "az1"   , "min_num_replicas": 1 },
{ "cloud": "cloud", "region": "us-west", "zone": "az1"   , "min_num_replicas": 1 }
    ]
} $$) ;

alter table demo_gdpr_uk set tablespace "rf3";

create tablespace "rf5" with ( replica_placement= $$
{
    "num_replicas": 5,
    "placement_blocks": [
{ "cloud": "cloud", "region": "eu-west", "zone": "az1"   , "min_num_replicas": 1 },
{ "cloud": "cloud", "region": "us-east", "zone": "az1"   , "min_num_replicas": 1 },
{ "cloud": "cloud", "region": "us-west", "zone": "az1"   , "min_num_replicas": 1 }
    ]
} $$) ;

alter table demo_gdpr_us set tablespace "rf5";


---# we can define the leader placement

create tablespace "rf5-pref-eu" with ( replica_placement= $$
{
    "num_replicas": 5,
    "placement_blocks": [
{ "cloud": "cloud", "region": "eu-west", "zone": "az1"   , "min_num_replicas": 2 
  , "leader_preference": 1 },
{ "cloud": "cloud", "region": "us-east", "zone": "az1"   , "min_num_replicas": 2 
  , "leader_preference": 2 },
{ "cloud": "cloud", "region": "us-west", "zone": "az1"   , "min_num_replicas": 1 
  , "leader_preference": 3 }
    ]
} $$) ;

alter table demo_gdpr_ch set tablespace "rf5-pref-eu";

---# region failure
select host, cloud, region, zone from yb_servers() order by 2,3,4;

\! docker pause yb-tserver-0  
\! docker pause yb-tserver-9  


---with countries(country) as (
 ---values ('CH'),('FR'),('DE'),('IT'),('UK'),('US')
---) insert into demo_gdpr(user_country)
 ---select country from countries, generate_series(1,1000);

select *  from demo_gdpr order by user_uuid;

\! docker unpause yb-tserver-0  
\! docker unpause yb-tserver-9  

\c

--  yb_is_local_table

\d+ demo_gdpr;
insert into demo_gdpr values  ('US'),('CH'),('FR'),( 'DE'),( 'IT'),('UK') ;
insert into demo_gdpr values  ('US'),('CH'),('FR'),( 'DE'),( 'IT'),('UK') ;
insert into demo_gdpr values  ('US'),('CH'),('FR'),( 'DE'),( 'IT'),('UK') ;
insert into demo_gdpr values  ('US'),('CH'),('FR'),( 'DE'),( 'IT'),('UK') ;

\pset pager off
explain 
select * from demo_gdpr;
select * from demo_gdpr;

show listen_addresses ;

select * from demo_gdpr where yb_is_local_table(tableoid);

explain 
select * from demo_gdpr where yb_is_local_table(tableoid);

--- end







---# duplicate index
alter table demo add column answer int;
insert into demo select n, n from generate_series(1,100) n;
explain select * from demo where answer=42;
create index demo_answer_covering_eu on demo (answer) include (id) tablespace "eu-west";
create index demo_answer_covering_us on demo (answer) include (id) tablespace "us-west";
explain select * from demo where answer=42;
show listen_addresses;
\c - - - 5450
show listen_addresses;
yftt-tablespaces.sqlexplain select * from demo where answer=42;
drop index demo_answer_covering_us;
explain select * from demo where answer=42;

show yb_enable_geolocation_costing;
\q


---# END

sh gen-yb-docker-compose.sh geo
psql -h localhost -p 5433 -d yugabyte -U yugabyte 
\pset pager off

create tablespace "rf3-pref-us" with ( replica_placement= $$
{
    "num_replicas": 3,
    "placement_blocks": [
{ "cloud": "cloud", "region": "eu-west", "zone": "az1"   , "min_num_replicas": 1 
  , "leader_preference": 2 },
{ "cloud": "cloud", "region": "us-east", "zone": "az1"   , "min_num_replicas": 1 
  , "leader_preference": 1 },
{ "cloud": "cloud", "region": "us-west", "zone": "az1"   , "min_num_replicas": 1 
  , "leader_preference": 1 }
    ]
} $$) ;

create table demo(id bigint primary key, val int) tablespace "rf3-pref-us" split into 4 tablets;
insert into demo select generate_series(1,1000),0;

update demo set val=val+1;
select sum(val) from demo;

\c - - - 5433
show listen_addresses;
select host,region,zone from yb_servers() where region='us-west' and zone='az1';
select host,region,zone from yb_servers() where region='us-east' and zone='az1';
select host,region,zone from yb_servers() where region='eu-west' and zone='az1';

create tablespace "xxx" with ( replica_placement= $$
{
    "num_replicas": 3,
    "placement_blocks": [
{ "cloud": "cloud", "region": "eu-west", "zone": "az1"   , "min_num_replicas": 1 
  , "leader_preference": 2 },
{ "cloud": "cloud", "region": "us-east", "zone": "az1"   , "min_num_replicas": 1 
  , "leader_preference": 1 },
{ "cloud": "cloud", "region": "us-west", "zone": "az1"   , "min_num_replicas": 1 
  , "leader_preference": 1 }
    ]
} $$) ;

