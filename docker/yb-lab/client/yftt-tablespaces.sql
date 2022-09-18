/*
ssh -L 5433:localhost:5433 -L 7000:localhost:7000 root@docker
[ -f ybdemo ] || git clone git@github.com:FranckPachot/ybdemo.git
cd ybdemo/docker/yb-lab 
git pull
sh gen-yb-docker-compose.sh geo

df -h /
psql -h localhost -p 5433 -d yugabyte -U yugabyte 
--\i client/yftt-tablespaces.sql
\pset pager off
create extension pgcrypto;
*/

-- clean all
select format('drop table if exists %I.%I cascade;',schemaname,tablename) from pg_tables where tableowner='yugabyte' and tablename like 'demo%';
\gexec
select format('drop tablespace if exists %I;',spcname) from pg_tablespace where spcoptions is not null;
\gexec
\! clear
\c

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



---# region failure
select host, cloud, region, zone from yb_servers() order by 2,3,4;

\! docker pause yb-tserver-0  
\! docker pause yb-tserver-9  

\c - - - 5450
show listen_addresses ;

with countries(country) as (
 values ('CH'),('FR'),('DE'),('IT'),('UK'),('US')
) insert into demo_gdpr(user_country)
 select country from countries, generate_series(1,1000);

select * from demo_gdpr order by user_uuid;

\! docker unpause yb-tserver-0  
\! docker unpause yb-tserver-9  

--  yb_is_local_table

\d+ demo_gdpr;
insert into demo_gdpr values  ('US'),('CH'),('FR'),( 'DE'),( 'IT'),('UK') ;
insert into demo_gdpr values  ('US'),('CH'),('FR'),( 'DE'),( 'IT'),('UK') ;
insert into demo_gdpr values  ('US'),('CH'),('FR'),( 'DE'),( 'IT'),('UK') ;
insert into demo_gdpr values  ('US'),('CH'),('FR'),( 'DE'),( 'IT'),('UK') ;

\pset pager off
explain 
select * from demo_gdpr;
select * from demo_gdpr where yb_is_local_table(tableoid);
explain 
select * from demo_gdpr where yb_is_local_table(tableoid);
show listen_addresses;
\c - - - 5433
show listen_addresses;
select * from demo_gdpr where yb_is_local_table(tableoid) order by 2;
explain 
select * from demo_gdpr where yb_is_local_table(tableoid) order by 2;

---# duplicate index
alter table demo add column answer int;
insert into demo select n, n from generate_series(1,100) n;
explain select * from demo where answer=42;
create index demo_answer_covering_eu on demo (answer) include (id) tablespace "eu-west";
create index demo_answer_covering_us on demo (answer) include (id) tablespace "us-west";
explain select * from demo where answer=42;
\c - - - 5450
show listen_addresses;
yftt-tablespaces.sqlexplain select * from demo where answer=42;
drop index demo_answer_covering_us;
explain select * from demo where answer=42;

show yb_enable_geolocation_costing;
\q


---# END



-- Security features (RLS, column-level encryption)

-- RLS - example multitenant
-- CLS instead of view, grant per column
-- CLE 

create extension if not exists pgcrypto;
drop table if exists demo;
create table demo (
 id uuid default gen_random_uuid() primary key
 , password text
);

insert into demo(password) select PGP_SYM_ENCRYPT(format('Welcome%s',generate_series(123,1000)),'xxx');
select * from demo;
select id,PGP_SYM_DECRYPT(password::bytea,'xxx') from demo;


create index demoi on demo(substr(password,1,10));
set yb_enable_expression_pushdown = on;
explain /*+ IndexScan(demo) */ select * from demo where substr(PGP_SYM_ENCRYPT('Welcome123','xxx')::text,1,10)=substr(password,1,10);

select PGP_SYM_ENCRYPT('Welcome123','xxx')::text;
select password from demo;


PGP_SYM_ENCRYPT
PGP_SYM_DECRYPT -> symetric (need password)
text or bytea



create table demo_gdpr ( 
 user_country char(2),
  user_uuid uuid default gen_random_uuid(),
  primary key (user_country, user_uuid)
) partition by list(user_country);









\! docker exec -it yb-tserver-12 ysqlsh -h yb-tserver-12
select * from demo_gdpr where yb_is_local_table(tableoid);
\q

\! docker exec -it yb-tserver-13 ysqlsh -h yb-tserver-13
select * from demo_gdpr where yb_is_local_table(tableoid);
\q

\! docker exec -it yb-tserver-16 ysqlsh -h yb-tserver-16
select * from demo_gdpr where yb_is_local_table(tableoid);



create table demo(id bigint primary key) split into 4 tablets;

\! sleep 60 ;  bin/yb-admin --init_master_addrs yb-master-0:7100 list_tablets ysql.yugabyte demo include_followers | awk '/^[0-9a-f]{8}/{gsub(/,/,"\n\tfollower: ",$NF);printf "Tablet %s [%6s - %6s]\n\tleader:   %s\t\n\tfollower: %s\n",$1,$3,$5,$(NF-2),$NF}' | grep --color=auto -P "^|leader|(?<=[.])[^.:]*"

alter table demo set tablespace "us-west";
\! sleep 60 ;  bin/yb-admin --init_master_addrs yb-master-0:7100 list_tablets ysql.yugabyte demo include_followers | awk '/^[0-9a-f]{8}/{gsub(/,/,"\n\tfollower: ",$NF);printf "Tablet %s [%6s - %6s]\n\tleader:   %s\t\n\tfollower: %s\n",$1,$3,$5,$(NF-2),$NF}' | grep --color=auto -P "^|leader|(?<=[.])[^.:]*"


alter table demo set tablespace "rf5";
\! sleep 60 ;  bin/yb-admin --init_master_addrs yb-master-0:7100 list_tablets ysql.yugabyte demo include_followers | awk '/^[0-9a-f]{8}/{gsub(/,/,"\n\tfollower: ",$NF);printf "Tablet %s [%6s - %6s]\n\tleader:   %s\t\n\tfollower: %s\n",$1,$3,$5,$(NF-2),$NF}' | grep --color=auto -P "^|leader|(?<=[.])[^.:]*"

alter table demo set tablespace "rf3";
\! sleep 60 ;  bin/yb-admin --init_master_addrs yb-master-0:7100 list_tablets ysql.yugabyte demo include_followers | awk '/^[0-9a-f]{8}/{gsub(/,/,"\n\tfollower: ",$NF);printf "Tablet %s [%6s - %6s]\n\tleader:   %s\t\n\tfollower: %s\n",$1,$3,$5,$(NF-2),$NF}' | grep --color=auto -P "^|leader|(?<=[.])[^.:]*"

alter table demo set tablespace "rf3-pref-eu";
\! sleep 60 ;  bin/yb-admin --init_master_addrs yb-master-0:7100 list_tablets ysql.yugabyte demo include_followers | awk '/^[0-9a-f]{8}/{gsub(/,/,"\n\tfollower: ",$NF);printf "Tablet %s [%6s - %6s]\n\tleader:   %s\t\n\tfollower: %s\n",$1,$3,$5,$(NF-2),$NF}' | grep --color=auto -P "^|leader|(?<=[.])[^.:]*"


select format('drop table if exists %I.%I cascade;',schemaname,tablename) from pg_tables where tableowner='yugabyte' and tablename like 'demo%';
\gexec

select format('drop tablespace if exists %I;',spcname) from pg_tablespace where spcoptions is not null;
\gexec