print(""" 

##############################################################################
### start the containers for the demo with the following
##############################################################################

# Start YugabyteDB (single node for dev)

docker network create -d bridge yb

docker run -d --rm --name yb0 --hostname yb0 --net=yb -p5433:5433 -p7000:7000 \
yugabytedb/yugabyte:latest yugabyted start --daemon=false --listen yb0

# Start two more nodes

docker run -d --rm --name yb1 --hostname yb1 --net=yb \
yugabytedb/yugabyte:latest yugabyted start --daemon=false --listen yb1 --join yb0

docker exec -it yb0 yb-admin -init_master_addrs=yb0:7100 list_all_masters

docker run -d --rm --name yb2 --hostname yb2 --net=yb \
yugabytedb/yugabyte:latest yugabyted start --daemon=false --listen yb2 --join yb0

docker exec -it yb0 yb-admin -init_master_addrs=yb0:7100 list_all_masters

# Start Python with libpq environment variables set

docker run -d --rm --name py --net yb python sleep infinity

docker exec -i py pip install sqlalchemy pandas psycopg2-yugabytedb 

docker exec -it py python

""")

import threading
import sqlalchemy
import pandas
pandas.set_option('display.max_colwidth', None)

yb=sqlalchemy.create_engine('postgresql+psycopg2://yb0:5433/yugabyte?load_balance=true',pool_size=5,max_overflow=5)

print(pandas.read_sql_query('select * from yb_servers()',yb.connect()))

yb.connect().execute("""
drop table if exists DEMO;
create table DEMO (id int generated always as identity (start 1000000) primary key
 , val text, ts text default now())
""")

def mythread():
 for i in range(1,10):
  print(pandas.read_sql_query(f"""
   insert into DEMO(val) values
   ('client: {threading.current_thread().name} server:'||host(inet_server_addr())) 
   returning pg_sleep(5),*
  """,yb.connect()).to_string(index=False,header=False))


threading.Thread(target=mythread).start()

for i in range(5):
 threading.Thread(target=mythread).start()

##############################################################################
### check with psql
##############################################################################

docker exec -it yb0 ysqlsh -h yb0
select * from demo limit 5;

""")
