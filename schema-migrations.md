# Schema migrations

Tuning PostgreSQL performance might mean tuning individual table or even column scheames

- Hand tuning and microo ptimising are hard to keep up with schma tools like [Alembic](https://alembic.sqlalchemy.org/en/latest/)

# Schema migrations

Do manually managed schema comparisons using [migra](https://github.com/djrobstep/migra)

## Install migra

[Install locally on your laptop](https://databaseci.com/docs/migra/installing-and-connecting).

- Python based, can be installed to the existing Python developer tool chain

## Diff between production optimisations and latest known managed state

- Create a new database with all Alembic migrations applied
- Compare this to the production database

Example that compares between SSH-tunneled production database a local development database.
Note that other PostgreSQL needs to be in non-standard port to not cause TCP/IP port conflicts. 

```shell
PROD_USER=
PROD_PASSWORD=
PROD_DATABASE=oracle_v2
PROD_PORT=5555
LOCAL_USER=dex_ohlcv
LOCAL_PASSWORD=dex_ohlcv
LOCAL_DATABASE=dex_ohlcv
LOCAL_PORT=5556
migra \
  "postgresql:///$PROD_USER:$PROD_PASSWORD@localhost:$PROD_PORT/$PROD_DATABASE" \
  "postgresql:///$LOCAL_USER:$LOCAL_PASSWORD@localhost:$LOCAL_PORT/LOCAL_DATABASE"
```

